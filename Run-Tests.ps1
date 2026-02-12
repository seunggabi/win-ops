#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Run win-ops Pester tests with coverage reporting
.DESCRIPTION
    Executes all Pester tests and generates coverage reports.
    Supports various execution modes and filtering options.
.PARAMETER Tags
    Run only tests with specified tags
.PARAMETER ExcludeTags
    Exclude tests with specified tags
.PARAMETER Path
    Specific test file or directory to run
.PARAMETER CI
    Enable CI mode with optimized output
.PARAMETER NoCoverage
    Skip code coverage analysis
.PARAMETER Parallel
    Enable parallel test execution
.PARAMETER PassThru
    Return test results object
.EXAMPLE
    .\Run-Tests.ps1
.EXAMPLE
    .\Run-Tests.ps1 -Tags Unit
.EXAMPLE
    .\Run-Tests.ps1 -Path ./tests/Core -NoCoverage
.EXAMPLE
    .\Run-Tests.ps1 -CI -Parallel
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Tags,

    [Parameter()]
    [string[]]$ExcludeTags,

    [Parameter()]
    [string]$Path = './tests',

    [Parameter()]
    [switch]$CI,

    [Parameter()]
    [switch]$NoCoverage,

    [Parameter()]
    [switch]$Parallel,

    [Parameter()]
    [switch]$PassThru
)

#region Setup

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine script directory
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Import Pester
Write-Host "🔍 Checking Pester installation..." -ForegroundColor Cyan

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pesterModule) {
    Write-Host "❌ Pester not found. Installing Pester 5.x..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
    $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
}

if ($pesterModule.Version.Major -lt 5) {
    Write-Warning "Pester $($pesterModule.Version) detected. Pester 5.x is recommended."
    Write-Host "Installing Pester 5.x..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

Write-Host "✅ Using Pester $($pesterModule.Version)" -ForegroundColor Green

#endregion

#region Build Configuration

Write-Host "📋 Building Pester configuration..." -ForegroundColor Cyan

$pesterConfig = New-PesterConfiguration

# Run settings
$pesterConfig.Run.Path = if ($Path) { $Path } else { './tests' }
$pesterConfig.Run.Exit = $CI.IsPresent
$pesterConfig.Run.PassThru = $true

# Filter settings
if ($Tags) {
    $pesterConfig.Filter.Tag = $Tags
}

if ($ExcludeTags) {
    $pesterConfig.Filter.ExcludeTag = $ExcludeTags
}

# Code coverage
if (-not $NoCoverage) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = @(
        './lib/core/*.psm1'
        # Only Core modules are tested in CI
        # './lib/modules/*.psm1',
        # './lib/utils/*.psm1',
        # './scheduler/*.psm1'
    )
    $pesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
    $pesterConfig.CodeCoverage.OutputPath = Join-Path $ScriptRoot './tests/coverage.xml'
    $pesterConfig.CodeCoverage.OutputEncoding = 'UTF8'
    $pesterConfig.CodeCoverage.CoveragePercentTarget = 80
}
else {
    $pesterConfig.CodeCoverage.Enabled = $false
}

# Test results
$pesterConfig.TestResult.Enabled = $true
$pesterConfig.TestResult.OutputFormat = 'NUnitXml'
$pesterConfig.TestResult.OutputPath = Join-Path $ScriptRoot './tests/test-results.xml'
$pesterConfig.TestResult.OutputEncoding = 'UTF8'
$pesterConfig.TestResult.TestSuiteName = 'win-ops Test Suite'

# Output settings
if ($CI) {
    $pesterConfig.Output.Verbosity = 'Minimal'
    $pesterConfig.Output.CIFormat = 'GithubActions'
}
else {
    $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.Output.StackTraceVerbosity = 'Filtered'
}

# Parallel execution
if ($Parallel) {
    $pesterConfig.Run.Container = New-PesterContainer -Path $pesterConfig.Run.Path
    Write-Host "⚡ Parallel execution enabled (experimental)" -ForegroundColor Cyan
}

# Should settings
$pesterConfig.Should.ErrorAction = 'Stop'

# TestDrive
$pesterConfig.TestDrive.Enabled = $true

#endregion

#region Execute Tests

Write-Host ""
Write-Host "🧪 Running win-ops Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Path:        $($pesterConfig.Run.Path)" -ForegroundColor White
Write-Host "  Coverage:    $(if ($pesterConfig.CodeCoverage.Enabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor White
Write-Host "  Parallel:    $(if ($Parallel) { 'Enabled' } else { 'Disabled' })" -ForegroundColor White
if ($Tags) {
    Write-Host "  Tags:        $($Tags -join ', ')" -ForegroundColor White
}
if ($ExcludeTags) {
    Write-Host "  Exclude:     $($ExcludeTags -join ', ')" -ForegroundColor White
}
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

try {
    $results = Invoke-Pester -Configuration $pesterConfig
}
catch {
    Write-Host "❌ Test execution failed: $_" -ForegroundColor Red
    exit 1
}

$duration = (Get-Date) - $startTime

#endregion

#region Report Results

Write-Host ""
Write-Host "📊 Test Results Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Test statistics
$totalTests = $results.TotalCount
$passedTests = $results.PassedCount
$failedTests = $results.FailedCount
$skippedTests = $results.SkippedCount
$notRunTests = $results.NotRunCount

Write-Host "  Total:       $totalTests tests" -ForegroundColor White
Write-Host "  Passed:      $passedTests " -ForegroundColor Green -NoNewline
Write-Host "tests" -ForegroundColor White

if ($failedTests -gt 0) {
    Write-Host "  Failed:      $failedTests " -ForegroundColor Red -NoNewline
    Write-Host "tests" -ForegroundColor White
}

if ($skippedTests -gt 0) {
    Write-Host "  Skipped:     $skippedTests " -ForegroundColor Yellow -NoNewline
    Write-Host "tests" -ForegroundColor White
}

Write-Host "  Duration:    $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White

# Code coverage
if ($pesterConfig.CodeCoverage.Enabled -and $results.CodeCoverage) {
    Write-Host ""
    Write-Host "📈 Code Coverage" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Cyan

    $coverage = $results.CodeCoverage
    $commandsAnalyzed = $coverage.NumberOfCommandsAnalyzed
    $commandsExecuted = $coverage.NumberOfCommandsExecuted
    $commandsMissed = $coverage.NumberOfCommandsMissed

    if ($commandsAnalyzed -gt 0) {
        $coveragePercent = [math]::Round(($commandsExecuted / $commandsAnalyzed) * 100, 2)

        $coverageColor = if ($coveragePercent -ge 80) { 'Green' }
                        elseif ($coveragePercent -ge 60) { 'Yellow' }
                        else { 'Red' }

        Write-Host "  Commands:    $commandsAnalyzed analyzed, $commandsExecuted executed, $commandsMissed missed" -ForegroundColor White
        Write-Host "  Coverage:    " -NoNewline -ForegroundColor White
        Write-Host "$coveragePercent%" -ForegroundColor $coverageColor

        if ($coveragePercent -lt $configData.CodeCoverage.CoveragePercentTarget) {
            Write-Host "  ⚠️  Coverage below target ($($configData.CodeCoverage.CoveragePercentTarget)%)" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "  Coverage report: $($pesterConfig.CodeCoverage.OutputPath)" -ForegroundColor Gray
    }
}

# Test results file
if ($pesterConfig.TestResult.Enabled) {
    Write-Host "  Test results:    $($pesterConfig.TestResult.OutputPath)" -ForegroundColor Gray
}

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

#endregion

#region Failed Tests Detail

if ($failedTests -gt 0) {
    Write-Host ""
    Write-Host "❌ Failed Tests" -ForegroundColor Red
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Red

    foreach ($test in $results.Failed) {
        Write-Host "  • $($test.ExpandedName)" -ForegroundColor Red
        if ($test.ErrorRecord) {
            Write-Host "    $($test.ErrorRecord.Exception.Message)" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

#endregion

#region Exit Code

if ($PassThru) {
    return $results
}

if ($failedTests -gt 0) {
    Write-Host "❌ Tests FAILED" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "✅ All tests PASSED" -ForegroundColor Green
    exit 0
}

#endregion
