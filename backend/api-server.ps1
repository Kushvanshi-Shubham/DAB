# Deployment Manager API Server
param([int]$Port = 8888)

$ErrorActionPreference = "Continue"
$entitiesFile = ".\entities.json"
$backupFolder = ".\backups"
$maxBackups = 20

if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder | Out-Null
}

# Function to manage backups (keep only max 20)
function Manage-Backups {
    $backups = Get-ChildItem -Path $backupFolder -Filter "entities_*.json" | Sort-Object LastWriteTime -Descending
    
    if ($backups.Count -gt $maxBackups) {
        $toDelete = $backups | Select-Object -Skip $maxBackups
        foreach ($backup in $toDelete) {
            Remove-Item $backup.FullName -Force
            Write-Host "Deleted old backup: $($backup.Name)" -ForegroundColor Yellow
        }
        Write-Host "Kept $maxBackups most recent backups" -ForegroundColor Green
    }
}

Write-Host "Deployment Manager API Server" -ForegroundColor Cyan
Write-Host "Starting on port $Port..." -ForegroundColor Yellow

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()

Write-Host "Server started on all interfaces: http://*:$Port" -ForegroundColor Green

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        continue
    }
    
    $url = $request.Url.LocalPath
    $method = $request.HttpMethod
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    Write-Host "[$timestamp] $method $url" -ForegroundColor Cyan
    
    $body = ""
    if ($request.HasEntityBody) {
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()
    }
    
    $responseText = ""
    $statusCode = 200
    
    try {
        if ($url -eq "/api/version" -and $method -eq "GET") {
            $versionContent = "v18"
            if (Test-Path ".\version.txt") {
                $versionContent = (Get-Content ".\version.txt" -Raw).Trim()
            }
            $result = @{
                success = $true
                version = $versionContent
            }
            $responseText = $result | ConvertTo-Json -Compress
        }
        elseif ($url -eq "/api/entities" -and $method -eq "GET") {
            $entities = Get-Content $entitiesFile -Raw | ConvertFrom-Json
            $result = @{
                success = $true
                count = $entities.Count
                entities = $entities
            }
            $responseText = $result | ConvertTo-Json -Depth 10 -Compress
        }
        elseif ($url -eq "/api/tables" -and $method -eq "GET") {
            try {
                # Fetch all rows using pagination to avoid DAB default 100-row limit
                $allTables = @()
                $nextUrl = "http://localhost:8090/api/API_Master_AKA?`$orderby=ID asc"
                do {
                    $apiResponse = Invoke-RestMethod -Uri $nextUrl -TimeoutSec 10
                    $allTables += $apiResponse.value
                    $nextUrl = $apiResponse.'@nextLink'
                } while ($nextUrl)
                $tables = $allTables | Select-Object ID, TABLE_NAME, LOG_DATE
                $result = @{
                    success = $true
                    count = $tables.Count
                    tables = $tables
                }
                $responseText = $result | ConvertTo-Json -Depth 10 -Compress
            } catch {
                $result = @{
                    success = $false
                    message = "Failed to fetch tables. Is Docker running?"
                }
                $responseText = $result | ConvertTo-Json -Compress
                $statusCode = 500
            }
        }
        elseif ($url -eq "/api/entities/add" -and $method -eq "POST") {
            $data = $body | ConvertFrom-Json
            $tablesToAdd = $data.tables
            
            $backupFile = Join-Path $backupFolder "entities_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            Copy-Item $entitiesFile $backupFile
            
            $entities = Get-Content $entitiesFile -Raw | ConvertFrom-Json
            $entitiesArray = @($entities)
            
            $added = @()
            $skipped = @()
            
            foreach ($tableName in $tablesToAdd) {
                $exists = $entitiesArray | Where-Object { $_.name -eq $tableName }
                
                if (-not $exists) {
                    $newEntity = @{
                        name = $tableName
                        "real-name" = "[dbo].[$tableName]"
                    }
                    $entitiesArray += $newEntity
                    $added += $tableName
                } else {
                    $skipped += $tableName
                }
            }
            
            $entitiesArray | ConvertTo-Json -Depth 10 | Set-Content $entitiesFile -Encoding UTF8
            
            # Manage backups (keep only 20 most recent)
            Manage-Backups
            
            $result = @{
                success = $true
                message = "Added $($added.Count) entities"
                added = $added
                skipped = $skipped
                backup = $backupFile
                totalEntities = $entitiesArray.Count
            }
            $responseText = $result | ConvertTo-Json -Depth 10 -Compress
        }
        elseif ($url -eq "/api/entities/delete" -and $method -eq "POST") {
            $data = $body | ConvertFrom-Json
            $entityName = $data.name
            
            $backupFile = Join-Path $backupFolder "entities_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            Copy-Item $entitiesFile $backupFile
            
            $entities = Get-Content $entitiesFile -Raw | ConvertFrom-Json
            $filtered = $entities | Where-Object { $_.name -ne $entityName }
            
            $filtered | ConvertTo-Json -Depth 10 | Set-Content $entitiesFile -Encoding UTF8
            
            # Manage backups (keep only 20 most recent)
            Manage-Backups
            
            $result = @{
                success = $true
                message = "Deleted entity: $entityName"
                backup = $backupFile
                totalEntities = $filtered.Count
            }
            $responseText = $result | ConvertTo-Json -Compress
        }
        elseif ($url -eq "/api/deploy/status" -and $method -eq "GET") {
            $statusFile = ".\deploy-status.json"
            if (Test-Path $statusFile) {
                $statusContent = Get-Content $statusFile -Raw
                $response.StatusCode = 200
                $response.ContentType = "application/json"
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($statusContent)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                continue
            } else {
                $result = @{ running = $false; step = ""; progress = 0; message = "No deployment in progress" }
                $responseText = $result | ConvertTo-Json -Compress
            }
        }
        elseif ($url -eq "/api/deploy" -and $method -eq "POST") {
            $data = $body | ConvertFrom-Json
            $version = $data.version
            $statusFile = ".\deploy-status.json"

            Write-Host "Starting deployment for version: $version (background job)" -ForegroundColor Cyan

            # Write initial status immediately so the UI gets a response
            @{
                running  = $true
                success  = $false
                failed   = $false
                progress = 1
                step     = "Initializing deployment..."
                detail   = "Starting background job for version $version"
                time     = (Get-Date -Format "HH:mm:ss")
            } | ConvertTo-Json -Compress | Set-Content $statusFile -Encoding UTF8

            # Run the entire deployment in a background job so the HTTP server stays responsive
            $backendDir = (Get-Location).Path
            Start-Job -ScriptBlock {
                param($version, $statusFile, $backendDir)

                Set-Location $backendDir

                function Write-DeployStatus {
                    param([int]$Progress, [string]$Step, [string]$Detail = "", [bool]$Running = $true, [bool]$Success = $false, [bool]$Failed = $false)
                    @{
                        running  = $Running
                        success  = $Success
                        failed   = $Failed
                        progress = $Progress
                        step     = $Step
                        detail   = $Detail
                        time     = (Get-Date -Format "HH:mm:ss")
                    } | ConvertTo-Json -Compress | Set-Content $statusFile -Encoding UTF8
                }

                try {
                    Write-DeployStatus -Progress 5  -Step "Regenerating dab-config.json..." -Detail "Building config from entities.json"
                    & .\generate-dab-config.ps1 2>&1 | Out-Null

                    # Best-effort: keep the LOCAL field-loading DAB in sync (container
                    # dab-app-local on :8090, used by the UI "Load Fields" button). Without
                    # this it serves a stale config and Load Fields 404s for new entities.
                    # NON-FATAL - a failure here must never fail the Azure deploy.
                    try {
                        Write-DeployStatus -Progress 10 -Step "Refreshing local field-loader (:8090)..." -Detail "Updating dab-app-local with new config"
                        docker cp "$backendDir\dab-config.json" dab-app-local:/App/dab-config.json 2>&1 | Out-Null
                        docker restart dab-app-local 2>&1 | Out-Null
                    } catch {}

                    Write-DeployStatus -Progress 15 -Step "Copying files to build directory..." -Detail "Copying dab-config.json, .env, Dockerfile"
                    $buildDir = "d:\DAB_Project\DAB Project\_dab_build\AzureService_SRM"
                    $acrServer = "arsv2acr.azurecr.io"
                    $imageName = "dab-app"
                    $appName = "my-dab-app"
                    $resourceGroup = "dab-rg"
                    $acrName = "arsv2acr"

                    Copy-Item "dab-config.json" "$buildDir\dab-config.json" -Force
                    Copy-Item ".env.azure" "$buildDir\.env" -Force
                    Copy-Item "Dockerfile" "$buildDir\Dockerfile.linux" -Force

                    Push-Location $buildDir

                    # PERMANENT FIX (2026-06-30): build + push SERVER-SIDE in ACR.
                    # The old flow (az acr login -> docker build -> docker push) stalled the
                    # background job at "az acr login" whenever Docker Desktop wasn't running,
                    # the job's az session wasn't live, or arsv2acr's AAD token auth failed
                    # after the 2026-06-25 registry recreate. 'az acr build' has none of those
                    # dependencies: it uploads the build context and builds inside Azure.
                    Write-DeployStatus -Progress 30 -Step "Building image in Azure Container Registry..." -Detail "az acr build -r ${acrName} -t ${imageName}:${version}"
                    $buildOutput = az acr build --registry $acrName --image "${imageName}:${version}" --file Dockerfile.linux . 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "az acr build failed: $($buildOutput | Select-Object -Last 8 | Out-String)" }
                    Write-DeployStatus -Progress 65 -Step "Image built and pushed to ACR" -Detail "${acrServer}/${imageName}:${version}"

                    Write-DeployStatus -Progress 80 -Step "Updating Azure App Service..." -Detail "Setting container image to ${version}"
                    az webapp config container set `
                        --name $appName `
                        --resource-group $resourceGroup `
                        --container-image-name "${acrServer}/${imageName}:${version}" `
                        --container-registry-url "https://${acrServer}" 2>&1 | Out-Null

                    Write-DeployStatus -Progress 90 -Step "Restarting App Service..." -Detail "az webapp restart"
                    az webapp restart --name $appName --resource-group $resourceGroup 2>&1 | Out-Null

                    Pop-Location
                    $version | Set-Content "$backendDir\version.txt"

                    # Verify the NEW container is ACTUALLY serving before declaring success.
                    # 'az webapp restart' leaves the OLD container answering 200 for a few
                    # seconds, so a naive poll gets a FALSE POSITIVE off the old instance.
                    # Fix: (phase 1) wait until the app is observed DOWN - old instance torn
                    # down / new one cold - then (phase 2) wait for the new one to return 200.
                    $firstEntity = $null
                    try {
                        $cfg = Get-Content "$backendDir\dab-config.json" -Raw | ConvertFrom-Json
                        $firstEntity = ($cfg.entities.PSObject.Properties | Select-Object -First 1).Name
                    } catch {}
                    if (-not $firstEntity) { $firstEntity = "DY_SUPPLIER_MST" }
                    $verifyUrl = "https://my-dab-app.azurewebsites.net/api/$firstEntity" + '?$first=1'

                    Start-Sleep -Seconds 15   # let the restart begin taking effect

                    # Phase 1: wait until the app goes DOWN (up to ~90s). If it never does
                    # (fast/overlapping swap) we proceed anyway - a later 200 is then the new one.
                    $sawDown = $false
                    for ($d = 1; $d -le 15; $d++) {
                        Write-DeployStatus -Progress 92 -Step "Recycling container... (waiting for old instance to stop)" -Detail "check $d/15"
                        $isUp = $false
                        try { $isUp = ((Invoke-WebRequest -Uri $verifyUrl -UseBasicParsing -TimeoutSec 15).StatusCode -eq 200) } catch { $isUp = $false }
                        if (-not $isUp) { $sawDown = $true; break }
                        Start-Sleep -Seconds 6
                    }

                    # Phase 2: wait for the NEW container to come UP with HTTP 200 (up to ~180s).
                    $live = $false
                    for ($attempt = 1; $attempt -le 30; $attempt++) {
                        $pct = [math]::Min(99, 93 + $attempt)
                        Write-DeployStatus -Progress $pct -Step "Waiting for new version to go live... (check $attempt/30)" -Detail "Cold start ~60-90s. Polling $firstEntity for HTTP 200..."
                        try {
                            if ((Invoke-WebRequest -Uri $verifyUrl -UseBasicParsing -TimeoutSec 15).StatusCode -eq 200) { $live = $true; break }
                        } catch {}
                        Start-Sleep -Seconds 6
                    }
                    if ($live) {
                        $note = if ($sawDown) { "confirmed recycle + HTTP 200" } else { "HTTP 200 (no downtime observed)" }
                        Write-DeployStatus -Progress 100 -Step "LIVE & VERIFIED - deployment successful!" -Detail "Version ${version} is up and serving requests ($note)" -Running $false -Success $true
                    } else {
                        Write-DeployStatus -Progress 100 -Step "Deployed, but app not responding yet" -Detail "Image ${version} was pushed and App Service updated, but the live endpoint hasn't returned 200 after ~4-5 min. It may still be warming up - wait a moment and retest." -Running $false -Failed $true
                    }

                } catch {
                    Write-DeployStatus -Progress 0 -Step "Deployment failed" -Detail $_.Exception.Message -Running $false -Failed $true
                    try { Pop-Location } catch {}
                }

            } -ArgumentList $version, $statusFile, $backendDir | Out-Null

            $result = @{ success = $true; message = "Deployment started in background"; version = $version }
            $responseText = $result | ConvertTo-Json -Compress
        }
        else {
            $statusCode = 404
            $result = @{
                success = $false
                message = "Endpoint not found"
            }
            $responseText = $result | ConvertTo-Json -Compress
        }
    } catch {
        $statusCode = 500
        $result = @{
            success = $false
            message = $_.Exception.Message
        }
        $responseText = $result | ConvertTo-Json -Compress
    }
    
    $response.StatusCode = $statusCode
    $response.ContentType = "application/json"
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseText)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()
}

$listener.Stop()
Write-Host "Server stopped" -ForegroundColor Yellow
