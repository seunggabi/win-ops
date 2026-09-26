<#
.SYNOPSIS
    Functional test: folders holding executables are never orphan candidates.

.DESCRIPTION
    Name matching alone cannot separate an abandoned data folder from a live
    installation. Test-FolderHasExecutables is the backstop: any folder that
    carries an .exe/.dll/.sys/.msi is an installation and must be left alone,
    whatever its name and however old it is.

    Builds a throwaway tree under TEMP, so it never touches real AppData.

    Run: pwsh -File tests\Test-OrphanAppExecutableGuard.ps1
#>

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\lib\modules\OrphanAppCleanup.psm1'
if (-not (Test-Path $modulePath)) { throw "module not found: $modulePath" }
Import-Module $modulePath -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ("winops_guard_" + [guid]::NewGuid().ToString('N'))
$failures = @()

function Assert-Guard {
    param([string]$Label, [string]$Path, [bool]$Expected)

    # Test-FolderHasExecutables is module-internal, so reach into module scope.
    $actual = & (Get-Module OrphanAppCleanup) { param($p) Test-FolderHasExecutables -Path $p } $Path

    if ($actual -eq $Expected) {
        Write-Host ("PASS: {0} -> {1}" -f $Label, $actual) -ForegroundColor Green
    } else {
        Write-Host ("FAIL: {0} -> got {1}, expected {2}" -f $Label, $actual, $Expected) -ForegroundColor Red
        $script:failures += $Label
    }
}

try {
    # app with an executable at the top level
    $app = Join-Path $root 'SomeApp'
    New-Item -ItemType Directory -Path $app -Force | Out-Null
    Set-Content -Path (Join-Path $app 'app.exe') -Value 'stub'

    # container holding an app a few levels down, like AppData\Local\Programs
    $nested = Join-Path $root 'Programs\Vendor IDE\bin'
    New-Item -ItemType Directory -Path $nested -Force | Out-Null
    Set-Content -Path (Join-Path $nested 'ide64.exe') -Value 'stub'

    # native library only, no .exe
    $libOnly = Join-Path $root 'LibOnly'
    New-Item -ItemType Directory -Path $libOnly -Force | Out-Null
    Set-Content -Path (Join-Path $libOnly 'core.dll') -Value 'stub'

    # genuine leftover data: no executable content anywhere
    $data = Join-Path $root 'LeftoverData\cache'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -Path (Join-Path $data 'settings.json') -Value '{}'
    Set-Content -Path (Join-Path $data 'notes.txt') -Value 'text'

    # executable deeper than the search depth: accepted miss, documents the limit
    $deep = Join-Path $root 'DeepApp\a\b\c\d\e'
    New-Item -ItemType Directory -Path $deep -Force | Out-Null
    Set-Content -Path (Join-Path $deep 'buried.exe') -Value 'stub'

    Assert-Guard 'exe at top level'          $app                          $true
    Assert-Guard 'exe nested in container'   (Join-Path $root 'Programs')  $true
    Assert-Guard 'dll only'                  $libOnly                      $true
    Assert-Guard 'data only (real orphan)'   (Join-Path $root 'LeftoverData') $false
    Assert-Guard 'exe below depth limit'     (Join-Path $root 'DeepApp')   $false
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    Write-Host ("{0} check(s) failed: {1}" -f $failures.Count, ($failures -join ', ')) -ForegroundColor Red
    exit 1
}

Write-Host 'All guard checks passed.' -ForegroundColor Green
exit 0
