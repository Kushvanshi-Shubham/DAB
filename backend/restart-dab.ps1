<#
.SYNOPSIS
  Restarts the Azure DAB App Service so it re-reads the live SQL schema.

.DESCRIPTION
  Permanent guard for the ROI_TREND_DATA_AKA "500 DatabaseOperationFailed" issue.
  DAB caches the DB schema only at container startup. ROI_TREND_DATA_AKA is a
  rolling-month wide table whose columns change monthly, so DAB's cache goes stale
  and the entity 500s until DAB is restarted. Running this on a schedule (see
  register-restart-task.ps1) keeps DAB's schema fresh automatically.

  Must run on the deploy VM (192.168.151.45) as the user that has `az login`
  cached (VM-HRMS\Administrator) — same context the deploy scripts use.

.EXAMPLE
  .\restart-dab.ps1
#>

$ErrorActionPreference = "Stop"
$appName       = "my-dab-app"
$resourceGroup = "dab-rg"
$verifyUrl     = "https://my-dab-app.azurewebsites.net/api/ROI_TREND_DATA_AKA?`$first=1"
$logFile       = Join-Path $PSScriptRoot "restart-dab.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# Resolve az even if it isn't on the scheduled-task PATH
$az = (Get-Command az -ErrorAction SilentlyContinue).Source
if (-not $az) {
    $candidate = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
    if (Test-Path $candidate) { $az = $candidate }
}
if (-not $az) { Write-Log "Azure CLI (az) not found on this machine." "ERROR"; exit 1 }

# Confirm we still have a valid Azure login (refresh token can expire ~90 days)
$acct = & $az account show --query name -o tsv 2>$null
if (-not $acct) { Write-Log "Not logged into Azure. Run 'az login' as this user." "ERROR"; exit 1 }
Write-Log "Azure context: $acct"

Write-Log "Restarting $appName (RG $resourceGroup)..."
& $az webapp restart --name $appName --resource-group $resourceGroup 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Log "az webapp restart failed (exit $LASTEXITCODE)." "ERROR"; exit 1 }
Write-Log "Restart issued. Waiting 120s for warm-up..."
Start-Sleep -Seconds 120

# Verify the previously-broken entity now responds
try {
    $resp = Invoke-WebRequest -Uri $verifyUrl -UseBasicParsing -TimeoutSec 30
    Write-Log ("Verify ROI_TREND_DATA_AKA -> HTTP {0}" -f $resp.StatusCode) "SUCCESS"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Log ("Verify ROI_TREND_DATA_AKA -> HTTP {0} (still failing)" -f $code) "ERROR"
    exit 1
}
Write-Log "Done."
