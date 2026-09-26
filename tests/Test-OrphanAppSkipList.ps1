<#
.SYNOPSIS
    Regression test: container folders under %LOCALAPPDATA% must never be
    treated as orphaned apps.

.DESCRIPTION
    Find-OrphanedAppDataFolders scans the top level of %LOCALAPPDATA% and
    flags any folder whose name does not match an installed application.
    'Programs' holds installed apps but is not itself an app, so without an
    explicit skip it gets flagged and the whole container is moved to trash,
    taking every app inside it with it. That happened on 2026-09-26 and cost
    an IntelliJ IDEA installation.

    Run: pwsh -File tests\Test-OrphanAppSkipList.ps1
#>

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\lib\modules\OrphanAppCleanup.psm1'
if (-not (Test-Path $modulePath)) { throw "module not found: $modulePath" }

$source = Get-Content $modulePath -Raw

# First $systemFolders literal belongs to Find-OrphanedAppDataFolders (AppData scan).
$match = [regex]::Match($source, '(?s)\$systemFolders\s*=\s*@\((.*?)\)')
if (-not $match.Success) { throw 'could not locate $systemFolders in Find-OrphanedAppDataFolders' }

$skipList = $match.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ }

$required = @('Programs', 'Apps', 'Common', 'Microsoft', 'Packages')
$missing  = $required | Where-Object { $_ -notin $skipList }

if ($missing) {
    Write-Host "FAIL: missing from skip list -> $($missing -join ', ')" -ForegroundColor Red
    Write-Host "      current: $($skipList -join ', ')"
    exit 1
}

# The config shipped with the project must also protect the container paths.
$configPath = Join-Path $PSScriptRoot '..\config\win-ops.json'
$protected  = (Get-Content $configPath -Raw | ConvertFrom-Json).safety.protectedPaths
$needPaths  = @('%LOCALAPPDATA%\Programs')
$missingCfg = $needPaths | Where-Object { $_ -notin $protected }

if ($missingCfg) {
    Write-Host "FAIL: config protectedPaths missing -> $($missingCfg -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: skip list = $($skipList -join ', ')" -ForegroundColor Green
Write-Host "PASS: protectedPaths covers $($needPaths -join ', ')" -ForegroundColor Green
exit 0
