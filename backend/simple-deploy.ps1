<#
.SYNOPSIS
  Simple deployment script that works every time

.DESCRIPTION
  Copies your local dab-config.json and deploys to Azure

.PARAMETER Version
  Version tag (e.g., v15, v16, v17...)

.EXAMPLE
  .\simple-deploy.ps1 -Version "v15"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$ErrorActionPreference = "Continue"

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "Info" = "Cyan"
        "Success" = "Green"
        "Warning" = "Yellow"
        "Error" = "Red"
    }
    
    $prefix = @{
        "Info" = "[INFO]"
        "Success" = "[OK]"
        "Warning" = "[WARN]"
        "Error" = "[ERR]"
    }
    
    Write-Host "[$timestamp] $($prefix[$Level]) $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   DEPLOYING $Version" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$deployStartTime = Get-Date

# Configuration
$buildDir = "d:\DAB_Project\DAB Project\_dab_build\AzureService_SRM"
$acrName = "dabacr123"
$acrServer = "dabacr123.azurecr.io"
$imageName = "dab-app"
$appName = "my-dab-app"
$resourceGroup = "dab-rg"

# Step 1: Regenerate dab-config.json from entities.json
Write-Log "Regenerating dab-config.json from entities.json..." -Level Info
& .\generate-dab-config.ps1
$generateSuccess = $?

if (-not $generateSuccess) {
    Write-Log "Failed to generate dab-config.json!" -Level Error
    exit 1
}

# Verify the config was created
if (-not (Test-Path "dab-config.json")) {
    Write-Log "dab-config.json was not created!" -Level Error
    exit 1
}

$configSize = (Get-Item "dab-config.json").Length
$configSizeKB = [math]::Round($configSize/1KB, 2)
Write-Log "Config generated successfully (Size: $configSizeKB KB)" -Level Success

# Step 2: Check if build directory exists
if (-not (Test-Path $buildDir)) {
    Write-Log "Build directory not found. Running initial setup..." -Level Warning
    & .\deploy-script.ps1 -Tag $Version -NoClean
    exit 0
}

# Step 3: Copy current dab-config.json
Write-Log "Copying dab-config.json to build directory..." -Level Info
Copy-Item "dab-config.json" "$buildDir\dab-config.json" -Force
Write-Log "dab-config.json copied" -Level Success

# Step 4: Copy .env.azure file for production
Write-Log "Copying .env.azure file to build directory..." -Level Info
Copy-Item ".env.azure" "$buildDir\.env" -Force
Write-Log ".env.azure copied" -Level Success

# Step 4.5: Copy Dockerfile with Swagger UI support
Write-Log "Copying Dockerfile with Swagger UI to build directory..." -Level Info
Copy-Item "Dockerfile" "$buildDir\Dockerfile.linux" -Force
Write-Log "Dockerfile copied" -Level Success

# Step 5: Build Docker image
Write-Log "Building Docker image (no cache)..." -Level Info
Write-Log "Image: ${acrServer}/${imageName}:${Version}" -Level Info
$buildStartTime = Get-Date
Push-Location $buildDir
docker build --no-cache -f Dockerfile.linux -t "${acrServer}/${imageName}:${Version}" .
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0) {
    Pop-Location
    Write-Log "Docker build failed!" -Level Error
    exit 1
}
$buildDuration = (Get-Date) - $buildStartTime
Write-Log "Docker build completed in $([math]::Round($buildDuration.TotalSeconds, 1))s" -Level Success

# Step 6: Login to ACR
Write-Log "Logging into Azure Container Registry..." -Level Info
az acr login --name $acrName 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Log "ACR login failed!" -Level Error
    exit 1
}
Write-Log "ACR login successful" -Level Success

# Step 7: Push image
Write-Log "Pushing image to ACR..." -Level Info
$pushStartTime = Get-Date
docker push "${acrServer}/${imageName}:${Version}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Log "Image push failed!" -Level Error
    exit 1
}
$pushDuration = (Get-Date) - $pushStartTime
Write-Log "Image pushed successfully in $([math]::Round($pushDuration.TotalSeconds, 1))s" -Level Success

# Step 8: Update App Service
Write-Log "Updating App Service configuration..." -Level Info
az webapp config container set `
    --name $appName `
    --resource-group $resourceGroup `
    --container-image-name "${acrServer}/${imageName}:${Version}" `
    --container-registry-url "https://${acrServer}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log "App Service configuration failed!" -Level Error
    Pop-Location
    exit 1
}
Write-Log "App Service configuration updated" -Level Success

# Step 9: Force container update using webhook
Write-Log "Triggering container pull via webhook..." -Level Info
$webhookUrl = az webapp deployment container config --name $appName --resource-group $resourceGroup --enable-cd true --query "CI_CD_URL" -o tsv 2>&1
if ($webhookUrl -and $webhookUrl -notlike "*ERROR*") {
    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -TimeoutSec 10 | Out-Null
        Write-Log "Webhook triggered successfully" -Level Success
    } catch {
        Write-Log "Webhook trigger failed, will use restart" -Level Warning
    }
} else {
    Write-Log "Webhook not available, will use restart" -Level Warning
}

# Step 10: Restart App Service
Write-Log "Restarting App Service..." -Level Info
az webapp restart --name $appName --resource-group $resourceGroup 2>&1 | Out-Null
Write-Log "App Service restart initiated" -Level Success

Pop-Location

# Step 11: Update version.txt
Write-Log "Updating version tracker..." -Level Info
$Version | Set-Content "version.txt"

# Get entity count for summary
$entitiesJson = Get-Content "entities.json" -Raw | ConvertFrom-Json
$entityCount = $entitiesJson.Count

$deployDuration = (Get-Date) - $deployStartTime

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "    DEPLOYMENT SUCCESS!                                         " -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Deployment Details:" -ForegroundColor Cyan
Write-Host "  Version:          $Version" -ForegroundColor White
Write-Host "  Image:            ${acrServer}/${imageName}:${Version}" -ForegroundColor White
Write-Host "  Entities:         $entityCount" -ForegroundColor White
Write-Host "  Total Time:       $([math]::Round($deployDuration.TotalMinutes, 1)) minutes" -ForegroundColor White
Write-Host ""
Write-Host "API Endpoints:" -ForegroundColor Cyan
Write-Host "  REST API:         https://${appName}.azurewebsites.net/api/<entity-name>" -ForegroundColor White
Write-Host "  GraphQL:          https://${appName}.azurewebsites.net/graphql" -ForegroundColor White
Write-Host "  Swagger UI:       https://${appName}.azurewebsites.net/swagger" -ForegroundColor Green
Write-Host "  OpenAPI JSON:     https://${appName}.azurewebsites.net/api/swagger" -ForegroundColor White
Write-Host ""
Write-Host "[!] Wait 2-3 minutes for App Service to fully restart!" -ForegroundColor Yellow
Write-Host ""
