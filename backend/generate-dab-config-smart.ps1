<#
.SYNOPSIS
  SMART dab-config generator with AUTO-DETECTION

.DESCRIPTION
  - Automatically detects tables vs views from database
  - Handles tables without primary keys
  - Finds best key fields automatically
#>

$ErrorActionPreference = "Stop"

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  SMART DAB CONFIG GENERATOR v2.0" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Database connection
$server = "192.168.151.28"
$database = "DataV2"
$user = "datalake"
$password = "lQn@t-rm#W*NG7"

# Read entities.json
if (-not (Test-Path "entities.json")) {
    Write-Host "[ERROR] entities.json not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[1/4] Reading entities.json..." -ForegroundColor Gray
$jsonContent = Get-Content "entities.json" -Raw
$jsonContent = $jsonContent -replace '//.*$', ''
$entitiesJson = $jsonContent | ConvertFrom-Json

Write-Host "[2/4] Analyzing $($entitiesJson.Count) entities from database..." -ForegroundColor Gray

# Function to get table/view metadata
function Get-EntityMetadata {
    param($tableName)
    
    # Get table type
    $typeQuery = "SELECT TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$tableName'"
    $tableType = sqlcmd -S $server -U $user -P $password -d $database -Q $typeQuery -h-1 -W -s "," 2>&1 | Select-String -Pattern "BASE TABLE|VIEW" | ForEach-Object { $_.ToString().Trim() }
    
    if (-not $tableType) {
        return @{ Exists = $false }
    }
    
    $isView = $tableType -eq "VIEW"
    
    # For tables, try to get primary key
    if (-not $isView) {
        $pkQuery = @"
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE 
WHERE OBJECTPROPERTY(OBJECT_ID(CONSTRAINT_SCHEMA + '.' + CONSTRAINT_NAME), 'IsPrimaryKey') = 1 
  AND TABLE_NAME = '$tableName'
ORDER BY ORDINAL_POSITION
"@
        $pkColumns = @(sqlcmd -S $server -U $user -P $password -d $database -Q $pkQuery -h-1 -W -s "," 2>&1 | Where-Object { $_ -notmatch 'rows affected' -and $_ -match '\S' } | ForEach-Object { $_.ToString().Trim() })
        
        if ($pkColumns.Count -gt 0 -and $pkColumns[0] -ne '') {
            return @{
                Exists = $true
                IsView = $false
                HasPK = $true
                KeyColumns = $pkColumns
            }
        }
    }
    
    # No PK found (or it's a view), find best key column
    # Strategy: Look for columns named ID, or first NOT NULL column, or first column
    $keyQuery = @"
SELECT TOP 1 COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = '$tableName' 
  AND (COLUMN_NAME LIKE '%ID%' OR COLUMN_NAME LIKE '%KEY%')
ORDER BY CASE 
    WHEN COLUMN_NAME = 'ID' THEN 1
    WHEN COLUMN_NAME LIKE '%ID' THEN 2
    WHEN COLUMN_NAME LIKE 'ID%' THEN 3
    ELSE 4
END, ORDINAL_POSITION
"@
    $keyColumn = sqlcmd -S $server -U $user -P $password -d $database -Q $keyQuery -h-1 -W -s "," 2>&1 | Select-Object -First 1 | Where-Object { $_ -match '\S' } | ForEach-Object { $_.ToString().Trim() }
    
    if (-not $keyColumn) {
        # Fallback: first NOT NULL column
        $keyQuery = "SELECT TOP 1 COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$tableName' AND IS_NULLABLE = 'NO' ORDER BY ORDINAL_POSITION"
        $keyColumn = sqlcmd -S $server -U $user -P $password -d $database -Q $keyQuery -h-1 -W -s "," 2>&1 | Select-Object -First 1 | Where-Object { $_ -match '\S' } | ForEach-Object { $_.ToString().Trim() }
    }
    
    if (-not $keyColumn) {
        # Last resort: first column
        $keyQuery = "SELECT TOP 1 COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$tableName' ORDER BY ORDINAL_POSITION"
        $keyColumn = sqlcmd -S $server -U $user -P $password -d $database -Q $keyQuery -h-1 -W -s "," 2>&1 | Select-Object -First 1 | Where-Object { $_ -match '\S' } | ForEach-Object { $_.ToString().Trim() }
    }
    
    return @{
        Exists = $true
        IsView = $isView
        HasPK = $false
        KeyColumns = @($keyColumn)
    }
}

# Build entities section
$entities = @{}
$stats = @{ Tables = 0; Views = 0; WithPK = 0; WithoutPK = 0; Skipped = 0 }

foreach ($entity in $entitiesJson) {
    $entityName = $entity.name
    $realName = $entity.'real-name'
    
    # Extract table name
    $tableName = $realName -replace '\[dbo\]\.', '' -replace '\[', '' -replace '\]', ''
    
    Write-Host "  Analyzing: $entityName ($tableName)..." -NoNewline
    
    $metadata = Get-EntityMetadata -tableName $tableName
    
    if (-not $metadata.Exists) {
        Write-Host " SKIPPED (not found in DB)" -ForegroundColor Red
        $stats.Skipped++
        continue
    }
    
    # Build source config
    $sourceConfig = @{
        object = $realName
        type = if ($metadata.IsView) { "view" } else { "table" }
    }
    
    # Add key-fields if needed
    if ($metadata.IsView -or (-not $metadata.HasPK)) {
        $sourceConfig['key-fields'] = $metadata.KeyColumns
        
        $statusColor = if ($metadata.IsView) { "Yellow" } else { "Magenta" }
        $statusText = if ($metadata.IsView) { "VIEW" } else { "TABLE (NO PK)" }
        Write-Host " $statusText [key: $($metadata.KeyColumns -join ',')]" -ForegroundColor $statusColor
        
        if ($metadata.IsView) { $stats.Views++ } else { $stats.WithoutPK++ }
    } else {
        Write-Host " TABLE [PK: $($metadata.KeyColumns -join ',')]" -ForegroundColor Green
        $stats.WithPK++
    }
    
    if (-not $metadata.IsView) { $stats.Tables++ }
    
    $entities[$entityName] = @{
        source = $sourceConfig
        graphql = @{
            enabled = $true
            type = @{
                singular = $entityName
                plural = "${entityName}s"
            }
        }
        rest = @{
            enabled = $true
            path = "/$entityName"
        }
        permissions = @(
            @{
                role = "anonymous"
                actions = @("create", "read", "update", "delete")
            }
        )
    }
}

Write-Host "`n[3/4] Building dab-config.json..." -ForegroundColor Gray

# Create full config
$dabConfig = @{
    '$schema' = "https://github.com/Azure/data-api-builder/releases/download/v1.2.10/dab.draft.schema.json"
    'data-source' = @{
        'database-type' = "mssql"
        'connection-string' = "@env('DATABASE_CONNECTION_STRING')"
        options = @{
            'set-session-context' = $false
        }
    }
    runtime = @{
        rest = @{
            enabled = $true
            path = "/api"
            'request-body-strict' = $true
            'max-response-size-mb' = 158
        }
        graphql = @{
            enabled = $true
            path = "/graphql"
            'allow-introspection' = $true
        }
        host = @{
            cors = @{
                origins = @("http://localhost:8888", "http://127.0.0.1:8888", "http://192.168.151.45:8034", "http://192.168.151.45:*")
                'allow-credentials' = $false
            }
            authentication = @{
                provider = "StaticWebApps"
            }
            mode = "development"
        }
    }
    entities = $entities
}

# Convert to JSON with proper depth
$jsonOutput = $dabConfig | ConvertTo-Json -Depth 10

# Write to file
$jsonOutput | Set-Content "dab-config.json" -Encoding UTF8

Write-Host "[4/4] Config generated successfully!`n" -ForegroundColor Green

# Show statistics
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  STATISTICS" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Total Entities:     $($entitiesJson.Count)" -ForegroundColor White
Write-Host "  Tables (with PK):   $($stats.WithPK)" -ForegroundColor Green
Write-Host "  Tables (no PK):     $($stats.WithoutPK)" -ForegroundColor Magenta
Write-Host "  Views:              $($stats.Views)" -ForegroundColor Yellow
Write-Host "  Skipped:            $($stats.Skipped)" -ForegroundColor Red
Write-Host "======================================`n" -ForegroundColor Cyan

if ($stats.Skipped -gt 0) {
    Write-Host "[WARNING] Some entities were not found in database!" -ForegroundColor Yellow
}

Write-Host "[SUCCESS] dab-config.json is ready for deployment`n" -ForegroundColor Green
