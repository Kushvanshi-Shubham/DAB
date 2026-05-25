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

                    Write-DeployStatus -Progress 20 -Step "Logging into Azure Container Registry..." -Detail "az acr login"
                    Push-Location $buildDir
                    az acr login --name $acrName 2>&1 | Out-Null

                    Write-DeployStatus -Progress 25 -Step "Building Docker image..." -Detail "docker build --no-cache ${acrServer}/${imageName}:${version}"
                    $buildOutput = docker build --no-cache -f Dockerfile.linux -t "${acrServer}/${imageName}:${version}" . 2>&1
                    $buildOutput | ForEach-Object {
                        if ($_ -match "Step (\d+)/(\d+)") {
                            $stepNum = [int]$Matches[1]
                            $totalSteps = [int]$Matches[2]
                            $buildPct = 25 + [math]::Round(($stepNum / $totalSteps) * 40)
                            Write-DeployStatus -Progress $buildPct -Step "Building Docker image... (Step $stepNum/$totalSteps)" -Detail "$_"
                        }
                    }
                    if ($LASTEXITCODE -ne 0) { throw "Docker build failed: $($buildOutput | Select-Object -Last 5 | Out-String)" }

                    Write-DeployStatus -Progress 65 -Step "Pushing image to Azure Container Registry..." -Detail "docker push ${acrServer}/${imageName}:${version}"
                    $pushOutput = docker push "${acrServer}/${imageName}:${version}" 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "Docker push failed: $($pushOutput | Select-Object -Last 5 | Out-String)" }

                    Write-DeployStatus -Progress 80 -Step "Updating Azure App Service..." -Detail "Setting container image to ${version}"
                    az webapp config container set `
                        --name $appName `
                        --resource-group $resourceGroup `
                        --container-image-name "${acrServer}/${imageName}:${version}" `
                        --container-registry-url "https://${acrServer}" 2>&1 | Out-Null

                    Write-DeployStatus -Progress 90 -Step "Restarting App Service..." -Detail "az webapp restart"
                    az webapp restart --name $appName --resource-group $resourceGroup 2>&1 | Out-Null

                    Write-DeployStatus -Progress 95 -Step "Updating version tracker..." -Detail "Writing version.txt"
                    Pop-Location
                    $version | Set-Content "$backendDir\version.txt"

                    Write-DeployStatus -Progress 100 -Step "Deployment complete!" -Detail "Version ${version} is live on Azure" -Running $false -Success $true

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
