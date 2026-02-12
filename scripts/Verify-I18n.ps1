#Requires -Version 5.1

<#
.SYNOPSIS
    Verification script for Win-Ops i18n implementation.

.DESCRIPTION
    Validates that the i18n implementation is complete and working correctly.

.EXAMPLE
    .\scripts\Verify-I18n.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Colors
$SuccessColor = 'Green'
$ErrorColor = 'Red'
$WarningColor = 'Yellow'
$InfoColor = 'Cyan'

function Write-Check {
    param(
        [string]$Message,
        [bool]$Success
    )

    $icon = if ($Success) { '✓' } else { '✗' }
    $color = if ($Success) { $SuccessColor } else { $ErrorColor }

    Write-Host "$icon " -ForegroundColor $color -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ " -ForegroundColor $InfoColor -NoNewline
    Write-Host $Message
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Win-Ops i18n Implementation Verification         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$projectRoot = Split-Path $PSScriptRoot -Parent
$passed = 0
$failed = 0

# Check 1: I18n module exists
Write-Info "Checking core module..."
$i18nModule = Join-Path $projectRoot 'lib\core\I18n.psm1'
$exists = Test-Path $i18nModule
Write-Check "I18n module exists" $exists
if ($exists) { $passed++ } else { $failed++ }

# Check 2: Language resource files exist
Write-Info "Checking language resource files..."
$enUsFile = Join-Path $projectRoot 'resources\en-US.psd1'
$koKrFile = Join-Path $projectRoot 'resources\ko-KR.psd1'

$enExists = Test-Path $enUsFile
$koExists = Test-Path $koKrFile

Write-Check "English (en-US) resource file exists" $enExists
Write-Check "Korean (ko-KR) resource file exists" $koExists

if ($enExists) { $passed++ } else { $failed++ }
if ($koExists) { $passed++ } else { $failed++ }

# Check 3: Resource files are valid PowerShell data files
if ($enExists -and $koExists) {
    Write-Info "Validating resource file syntax..."

    try {
        $enData = Import-PowerShellDataFile -Path $enUsFile -ErrorAction Stop
        Write-Check "English resource file is valid" $true
        $passed++
    } catch {
        Write-Check "English resource file is valid" $false
        $failed++
    }

    try {
        $koData = Import-PowerShellDataFile -Path $koKrFile -ErrorAction Stop
        Write-Check "Korean resource file is valid" $true
        $passed++
    } catch {
        Write-Check "Korean resource file is valid" $false
        $failed++
    }
}

# Check 4: Resource files have same keys
if ($enExists -and $koExists) {
    Write-Info "Checking resource file parity..."

    $enData = Import-PowerShellDataFile -Path $enUsFile
    $koData = Import-PowerShellDataFile -Path $koKrFile

    $enKeys = $enData.Keys | Sort-Object
    $koKeys = $koData.Keys | Sort-Object

    $sameCount = $enKeys.Count -eq $koKeys.Count
    Write-Check "English and Korean have same number of keys ($($enKeys.Count))" $sameCount

    if ($sameCount) { $passed++ } else { $failed++ }

    # Check for missing keys
    $missingInKo = $enKeys | Where-Object { $_ -notin $koKeys }
    $missingInEn = $koKeys | Where-Object { $_ -notin $enKeys }

    if ($missingInKo) {
        Write-Host "  Missing in Korean: $($missingInKo -join ', ')" -ForegroundColor $WarningColor
    }

    if ($missingInEn) {
        Write-Host "  Missing in English: $($missingInEn -join ', ')" -ForegroundColor $WarningColor
    }

    $allKeysMatch = -not $missingInKo -and -not $missingInEn
    Write-Check "All keys match between languages" $allKeysMatch
    if ($allKeysMatch) { $passed++ } else { $failed++ }
}

# Check 5: Module can be imported
Write-Info "Testing module import..."

try {
    Import-Module $i18nModule -Force -ErrorAction Stop
    Write-Check "I18n module imports successfully" $true
    $passed++
} catch {
    Write-Check "I18n module imports successfully" $false
    $failed++
}

# Check 6: Functions are exported
Write-Info "Checking exported functions..."

$expectedFunctions = @(
    'Initialize-WinOpsI18n',
    'Get-WinOpsMessage',
    'Set-WinOpsLanguage',
    'Get-WinOpsCurrentLanguage',
    'Test-WinOpsMessageKey'
)

foreach ($func in $expectedFunctions) {
    $exists = Get-Command $func -ErrorAction SilentlyContinue
    Write-Check "$func is exported" ($null -ne $exists)
    if ($exists) { $passed++ } else { $failed++ }
}

# Check 7: Module initialization works
Write-Info "Testing module initialization..."

try {
    Initialize-WinOpsI18n -ResourcesPath (Join-Path $projectRoot 'resources') -ErrorAction Stop
    Write-Check "Module initializes successfully" $true
    $passed++
} catch {
    Write-Check "Module initializes successfully" $false
    Write-Host "  Error: $_" -ForegroundColor $ErrorColor
    $failed++
}

# Check 8: Message retrieval works
Write-Info "Testing message retrieval..."

try {
    $msg = Get-WinOpsMessage -Key 'CLI_Help_Title'
    $works = -not [string]::IsNullOrEmpty($msg) -and $msg -ne '[CLI_Help_Title]'
    Write-Check "Message retrieval works (got: '$msg')" $works
    if ($works) { $passed++ } else { $failed++ }
} catch {
    Write-Check "Message retrieval works" $false
    $failed++
}

# Check 9: Parameter substitution works
Write-Info "Testing parameter substitution..."

try {
    $msg = Get-WinOpsMessage -Key 'Version_Title' -Args 'win-ops', '1.0.0'
    $works = $msg -match 'win-ops' -and $msg -match '1.0.0'
    Write-Check "Parameter substitution works (got: '$msg')" $works
    if ($works) { $passed++ } else { $failed++ }
} catch {
    Write-Check "Parameter substitution works" $false
    $failed++
}

# Check 10: Language switching works
Write-Info "Testing language switching..."

try {
    Set-WinOpsLanguage -Language 'en-US'
    $enMsg = Get-WinOpsMessage -Key 'CLI_Help_Title'

    Set-WinOpsLanguage -Language 'ko-KR'
    $koMsg = Get-WinOpsMessage -Key 'CLI_Help_Title'

    $works = $enMsg -ne $koMsg -and -not [string]::IsNullOrEmpty($koMsg)
    Write-Check "Language switching works (EN: '$enMsg', KO: '$koMsg')" $works
    if ($works) { $passed++ } else { $failed++ }
} catch {
    Write-Check "Language switching works" $false
    $failed++
}

# Check 11: Updated files use i18n
Write-Info "Checking file integration..."

$filesToCheck = @{
    'bin\win-ops.ps1' = 'Get-WinOpsMessage'
    'lib\modules\Analyze.psm1' = 'Get-WinOpsMessage'
    'lib\modules\CacheCleanup.psm1' = 'Get-WinOpsMessage'
    'lib\core\Logger.psm1' = 'Get-WinOpsMessage'
}

foreach ($file in $filesToCheck.Keys) {
    $fullPath = Join-Path $projectRoot $file
    if (Test-Path $fullPath) {
        $content = Get-Content $fullPath -Raw
        $pattern = $filesToCheck[$file]
        $uses = $content -match $pattern
        Write-Check "$file uses $pattern" $uses
        if ($uses) { $passed++ } else { $failed++ }
    } else {
        Write-Check "$file exists" $false
        $failed++
    }
}

# Check 12: Documentation exists
Write-Info "Checking documentation..."

$docs = @(
    'resources\README.md',
    'I18N_IMPLEMENTATION.md',
    'I18N_SUMMARY.md'
)

foreach ($doc in $docs) {
    $fullPath = Join-Path $projectRoot $doc
    $exists = Test-Path $fullPath
    Write-Check "$doc exists" $exists
    if ($exists) { $passed++ } else { $failed++ }
}

# Check 13: Tests exist
Write-Info "Checking tests..."

$testFile = Join-Path $projectRoot 'tests\I18n.Tests.ps1'
$exists = Test-Path $testFile
Write-Check "I18n tests exist" $exists
if ($exists) { $passed++ } else { $failed++ }

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$total = $passed + $failed
$percentage = [math]::Round(($passed / $total) * 100, 1)

Write-Host "Passed: " -NoNewline
Write-Host "$passed" -ForegroundColor $SuccessColor
Write-Host "Failed: " -NoNewline
Write-Host "$failed" -ForegroundColor $ErrorColor
Write-Host "Total:  $total"
Write-Host "Success Rate: " -NoNewline
Write-Host "$percentage%" -ForegroundColor $(if ($percentage -eq 100) { $SuccessColor } elseif ($percentage -gt 80) { $WarningColor } else { $ErrorColor })
Write-Host ""

if ($failed -eq 0) {
    Write-Host "✓ All checks passed! i18n implementation is complete." -ForegroundColor $SuccessColor
    exit 0
} else {
    Write-Host "✗ Some checks failed. Please review the errors above." -ForegroundColor $ErrorColor
    exit 1
}
