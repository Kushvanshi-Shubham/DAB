<#
.SYNOPSIS
  Registers a Windows Scheduled Task that runs restart-dab.ps1 to keep DAB's
  cached SQL schema fresh (permanent fix for the ROI_TREND_DATA_AKA 500 issue).

.DESCRIPTION
  Run ONCE, on the deploy VM (192.168.151.45), in an ELEVATED PowerShell, as the
  user that has `az login` cached (VM-HRMS\Administrator).

  Default schedule: daily at 02:30. DAB boots in ~1 min and the API is internal,
  so a daily restart is harmless and guarantees DAB picks up the monthly column
  roll within 24h with no dependency on the (external) ETL job.

  Monthly-only alternative: replace the trigger below with, e.g.
    $trigger = New-ScheduledTaskTrigger -Daily -At 2:30am
    # then restrict to the first 5 days of the month via -DaysOfWeek is not enough;
    # simplest robust option is to keep it daily.

.EXAMPLE
  # Elevated PowerShell on the VM:
  cd D:\path\to\DAB\backend
  .\register-restart-task.ps1
#>

$ErrorActionPreference = "Stop"
$taskName = "DAB_Schema_Refresh_Restart"
$scriptPath = Join-Path $PSScriptRoot "restart-dab.ps1"

if (-not (Test-Path $scriptPath)) { throw "restart-dab.ps1 not found next to this script." }

$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 2:30am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
             -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# Run as the current (admin) user so az's cached login is available.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
              -LogonType S4U -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force `
    -Description "Restarts my-dab-app daily so DAB re-reads the SQL schema (fixes ROI_TREND_DATA_AKA monthly 500)."

Write-Host "Registered scheduled task '$taskName' (daily 02:30)." -ForegroundColor Green
Write-Host "Test it now with:  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
Write-Host "Check the result in: $((Join-Path $PSScriptRoot 'restart-dab.log'))" -ForegroundColor Cyan
