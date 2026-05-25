# Start Deployment Manager
# Starts backend API and opens frontend

Write-Host "🚀 DAB Deployment Manager" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

# Check Docker
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    $containers = docker ps --format "{{.Names}}" 2>$null
    if ($containers -contains "dab-app-local") {
        Write-Host "✅ Docker is running" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Local Docker container not running (optional)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Docker not running (needed for API_Master_AKA)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting Backend API Server..." -ForegroundColor Yellow

# Start backend API
$backendPath = Join-Path $PSScriptRoot "backend"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$backendPath'; .\api-server.ps1"

Start-Sleep -Seconds 2

Write-Host "✅ Backend API started on http://localhost:8888" -ForegroundColor Green
Write-Host ""

# Open frontend
$frontendPath = Join-Path $PSScriptRoot "frontend\index.html"
Write-Host "Opening Frontend..." -ForegroundColor Yellow
Start-Process $frontendPath

Start-Sleep -Seconds 1

Write-Host ""
Write-Host "✅ Deployment Manager is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 System Overview:" -ForegroundColor Cyan
Write-Host "  • Frontend:  index.html (opened in browser)" -ForegroundColor White
Write-Host "  • Backend:   http://localhost:8888 (PowerShell window)" -ForegroundColor White
Write-Host "  • DAB API:   http://localhost:8090 (if Docker running)" -ForegroundColor White
Write-Host ""
Write-Host "🎯 Features:" -ForegroundColor Yellow
Write-Host "  • View current entities in table format" -ForegroundColor White
Write-Host "  • Delete entities (with automatic backup)" -ForegroundColor White
Write-Host "  • Add new entities from API_Master_AKA" -ForegroundColor White
Write-Host "  • View JSON (live preview)" -ForegroundColor White
Write-Host "  • Deploy to Azure with one click" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
