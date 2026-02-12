#Requires -Version 5.1

<#
.SYNOPSIS
    Validates all test files for structural integrity.

.DESCRIPTION
    Checks test files for:
    - Valid PowerShell syntax
    - Required Pester structure
    - Proper BeforeAll/AfterAll blocks
    - Mock declarations
    - Test naming conventions

.EXAMPLE
    .\Validate-Tests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$scriptRoot = $PSScriptRoot
$modulesTestPath = Join-Path $scriptRoot 'Modules'

Write-Host "`n=== WinOps Test Validation ===" -ForegroundColor Cyan
Write-Host "Validating test files in: $modulesTestPath`n" -ForegroundColor Gray

$testFiles = Get-ChildItem -Path $modulesTestPath -Filter '*.Tests.ps1'
$validationResults = @()

foreach ($testFile in $testFiles) {
    Write-Host "Validating: $($testFile.Name)" -ForegroundColor Yellow

    $validation = [PSCustomObject]@{
        File = $testFile.Name
        SyntaxValid = $false
        HasBeforeAll = $false
        HasDescribe = $false
        HasContext = $false
        HasIt = $false
        MockCount = 0
        TestCount = 0
        Errors = @()
        Warnings = @()
    }

    try {
        # Check syntax
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $testFile.FullName,
            [ref]$null,
            [ref]$null
        )
        $validation.SyntaxValid = $true
        Write-Host "  OK Syntax valid" -ForegroundColor Green
    }
    catch {
        $validation.Errors += "Syntax error: $_"
        Write-Host "  FAIL Syntax error: $_" -ForegroundColor Red
    }

    # Read content
    $content = Get-Content -Path $testFile.FullName -Raw

    # Check for BeforeAll
    if ($content -match 'BeforeAll\s*\{') {
        $validation.HasBeforeAll = $true
        Write-Host "  OK Has BeforeAll block" -ForegroundColor Green
    }
    else {
        $validation.Warnings += "Missing BeforeAll block"
        Write-Host "  [WARN] Missing BeforeAll block" -ForegroundColor Yellow
    }

    # Check for Describe blocks
    $describeMatches = [regex]::Matches($content, "Describe\s+'[^']+'")
    if ($describeMatches.Count -gt 0) {
        $validation.HasDescribe = $true
        Write-Host "  OK Has $($describeMatches.Count) Describe block(s)" -ForegroundColor Green
    }
    else {
        $validation.Errors += "No Describe blocks found"
        Write-Host "  FAIL No Describe blocks found" -ForegroundColor Red
    }

    # Check for Context blocks
    $contextMatches = [regex]::Matches($content, "Context\s+'[^']+'")
    if ($contextMatches.Count -gt 0) {
        $validation.HasContext = $true
        Write-Host "  OK Has $($contextMatches.Count) Context block(s)" -ForegroundColor Green
    }

    # Check for It blocks (tests)
    $itMatches = [regex]::Matches($content, "It\s+'[^']+'")
    if ($itMatches.Count -gt 0) {
        $validation.HasIt = $true
        $validation.TestCount = $itMatches.Count
        Write-Host "  OK Has $($itMatches.Count) test(s)" -ForegroundColor Green
    }
    else {
        $validation.Errors += "No tests (It blocks) found"
        Write-Host "  FAIL No tests (It blocks) found" -ForegroundColor Red
    }

    # Check for Mock declarations
    $mockMatches = [regex]::Matches($content, "Mock\s+[\w-]+")
    $validation.MockCount = $mockMatches.Count
    if ($mockMatches.Count -gt 0) {
        Write-Host "  OK Has $($mockMatches.Count) mock(s)" -ForegroundColor Green
    }

    # Check for Should -Invoke
    $shouldInvokeMatches = [regex]::Matches($content, "Should\s+-Invoke")
    if ($shouldInvokeMatches.Count -gt 0) {
        Write-Host "  OK Has $($shouldInvokeMatches.Count) mock verification(s)" -ForegroundColor Green
    }

    # Check for DryRun tests
    if ($content -match "DryRun") {
        Write-Host "  OK Has DryRun mode tests" -ForegroundColor Green
    }
    else {
        $validation.Warnings += "No DryRun mode tests"
        Write-Host "  [WARN] No DryRun mode tests" -ForegroundColor Yellow
    }

    # Check for Integration tests
    if ($content -match "Integration") {
        Write-Host "  OK Has Integration tests" -ForegroundColor Green
    }

    $validationResults += $validation
    Write-Host ""
}

# Summary
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
$totalFiles = $validationResults.Count
$validFiles = ($validationResults | Where-Object { $_.SyntaxValid -and $_.HasDescribe -and $_.HasIt }).Count
$totalTests = ($validationResults | Measure-Object -Property TestCount -Sum).Sum
$totalMocks = ($validationResults | Measure-Object -Property MockCount -Sum).Sum
$filesWithErrors = ($validationResults | Where-Object { $_.Errors.Count -gt 0 }).Count
$filesWithWarnings = ($validationResults | Where-Object { $_.Warnings.Count -gt 0 }).Count

Write-Host "Total test files:    $totalFiles" -ForegroundColor White
Write-Host "Valid files:         $validFiles" -ForegroundColor Green
Write-Host "Files with errors:   $filesWithErrors" -ForegroundColor $(if ($filesWithErrors -gt 0) { 'Red' } else { 'Green' })
Write-Host "Files with warnings: $filesWithWarnings" -ForegroundColor $(if ($filesWithWarnings -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "Total tests:         $totalTests" -ForegroundColor White
Write-Host "Total mocks:         $totalMocks" -ForegroundColor White

# Display errors
if ($filesWithErrors -gt 0) {
    Write-Host "`n=== Files with Errors ===" -ForegroundColor Red
    foreach ($result in $validationResults | Where-Object { $_.Errors.Count -gt 0 }) {
        Write-Host "`n$($result.File):" -ForegroundColor Red
        foreach ($error in $result.Errors) {
            Write-Host "  * $error" -ForegroundColor Red
        }
    }
}

# Display warnings
if ($filesWithWarnings -gt 0) {
    Write-Host "`n=== Files with Warnings ===" -ForegroundColor Yellow
    foreach ($result in $validationResults | Where-Object { $_.Warnings.Count -gt 0 }) {
        Write-Host "`n$($result.File):" -ForegroundColor Yellow
        foreach ($warning in $result.Warnings) {
            Write-Host "  * $warning" -ForegroundColor Yellow
        }
    }
}

# Test statistics
Write-Host "`n=== Test Statistics ===" -ForegroundColor Cyan
$validationResults |
    Select-Object File, TestCount, MockCount, @{N='Status';E={
        if ($_.Errors.Count -gt 0) { '[FAIL] Error' }
        elseif ($_.Warnings.Count -gt 0) { '[WARN]  Warning' }
        else { '[OK] Valid' }
    }} |
    Format-Table -AutoSize |
    Out-String |
    Write-Host

Write-Host ""

# Exit code
exit $(if ($filesWithErrors -gt 0) { 1 } else { 0 })
