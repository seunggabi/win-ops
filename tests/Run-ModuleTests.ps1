#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Test runner for WinOps cleanup module tests.

.DESCRIPTION
    Runs Pester tests for all cleanup modules with various options.

.PARAMETER Module
    Specific module to test (e.g., 'CacheCleanup'). If not specified, runs all module tests.

.PARAMETER Tag
    Test tags to filter by (e.g., 'Unit', 'Integration').

.PARAMETER Coverage
    Generate code coverage report.

.PARAMETER OutputFormat
    Output format: Detailed, Normal, Minimal, or NUnitXml.

.PARAMETER PassThru
    Return the test results object.

.EXAMPLE
    .\Run-ModuleTests.ps1
    # Runs all module tests with normal output

.EXAMPLE
    .\Run-ModuleTests.ps1 -Module CacheCleanup -Tag Unit
    # Runs only unit tests for CacheCleanup module

.EXAMPLE
    .\Run-ModuleTests.ps1 -Coverage -OutputFormat NUnitXml
    # Runs all tests with coverage and exports NUnit XML

.EXAMPLE
    .\Run-ModuleTests.ps1 -Tag Integration
    # Runs only integration tests for all modules
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet(
        'CacheCleanup', 'TmpCleanup', 'LogCleanup', 'BrowserCleanup',
        'DevCleanup', 'PackageManagerCleanup', 'DockerCleanup',
        'ZombieKiller', 'OrphanKiller', 'OrphanAppCleanup', 'Analyze'
    )]
    [string]$Module,

    [Parameter()]
    [string[]]$Tag,

    [Parameter()]
    [switch]$Coverage,

    [Parameter()]
    [ValidateSet('Detailed', 'Normal', 'Minimal', 'NUnitXml')]
    [string]$OutputFormat = 'Detailed',

    [Parameter()]
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$scriptRoot = $PSScriptRoot
$modulesTestPath = Join-Path $scriptRoot 'Modules'
$modulesSourcePath = Join-Path (Split-Path $scriptRoot -Parent) 'lib\modules'

Write-Host "`n=== WinOps Cleanup Module Test Suite ===" -ForegroundColor Cyan
Write-Host "Test Path: $modulesTestPath`n" -ForegroundColor Gray

# Build Pester configuration
$pesterConfig = @{
    Run = @{
        PassThru = $true
    }
    Output = @{
        Verbosity = $OutputFormat
    }
    Should = @{
        ErrorAction = 'Stop'
    }
}

# Set test path
if ($Module) {
    $testFile = Join-Path $modulesTestPath "$Module.Tests.ps1"
    if (-not (Test-Path $testFile)) {
        throw "Test file not found: $testFile"
    }
    $pesterConfig.Run.Path = $testFile
    Write-Host "Running tests for module: $Module" -ForegroundColor Yellow
} else {
    $pesterConfig.Run.Path = $modulesTestPath
    Write-Host "Running tests for all modules" -ForegroundColor Yellow
}

# Set tag filter
if ($Tag) {
    $pesterConfig.Filter = @{
        Tag = $Tag
    }
    Write-Host "Filtering by tags: $($Tag -join ', ')" -ForegroundColor Yellow
}

# Set code coverage
if ($Coverage) {
    $coveragePath = if ($Module) {
        Join-Path $modulesSourcePath "$Module.psm1"
    } else {
        Join-Path $modulesSourcePath '*.psm1'
    }

    $pesterConfig.CodeCoverage = @{
        Enabled = $true
        Path = $coveragePath
        OutputFormat = 'JaCoCo'
        OutputPath = Join-Path $scriptRoot 'coverage.xml'
    }
    Write-Host "Code coverage enabled: $coveragePath" -ForegroundColor Yellow
}

# Set output file for NUnitXml
if ($OutputFormat -eq 'NUnitXml') {
    $pesterConfig.TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = Join-Path $scriptRoot 'TestResults.xml'
    }
}

Write-Host "`nStarting test execution...`n" -ForegroundColor Green

# Run tests
$configuration = New-PesterConfiguration -Hashtable $pesterConfig
$results = Invoke-Pester -Configuration $configuration

# Display summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Total Tests:  $($results.TotalCount)" -ForegroundColor White
Write-Host "Passed:       $($results.PassedCount)" -ForegroundColor Green
Write-Host "Failed:       $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped:      $($results.SkippedCount)" -ForegroundColor Yellow
Write-Host "Not Run:      $($results.NotRunCount)" -ForegroundColor Gray

if ($results.Duration) {
    Write-Host "Duration:     $($results.Duration.ToString('mm\:ss\.fff'))" -ForegroundColor White
}

# Display coverage summary
if ($Coverage -and $results.CodeCoverage) {
    Write-Host "`n=== Code Coverage ===" -ForegroundColor Cyan
    $coverage = $results.CodeCoverage
    $coveredPercent = if ($coverage.CommandsAnalyzedCount -gt 0) {
        [math]::Round(($coverage.CommandsExecutedCount / $coverage.CommandsAnalyzedCount) * 100, 2)
    } else {
        0
    }

    Write-Host "Commands Analyzed: $($coverage.CommandsAnalyzedCount)" -ForegroundColor White
    Write-Host "Commands Executed: $($coverage.CommandsExecutedCount)" -ForegroundColor White
    Write-Host "Commands Missed:   $($coverage.CommandsMissedCount)" -ForegroundColor White
    Write-Host "Coverage:          $coveredPercent%" -ForegroundColor $(
        if ($coveredPercent -ge 80) { 'Green' }
        elseif ($coveredPercent -ge 60) { 'Yellow' }
        else { 'Red' }
    )

    if ($coverage.MissedCommands) {
        Write-Host "`nTop 10 Missed Commands:" -ForegroundColor Yellow
        $coverage.MissedCommands |
            Select-Object -First 10 -Property File, Line, Function, Command |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    }
}

# Display failed tests
if ($results.FailedCount -gt 0) {
    Write-Host "`n=== Failed Tests ===" -ForegroundColor Red
    foreach ($test in $results.Failed) {
        Write-Host "`n❌ $($test.ExpandedName)" -ForegroundColor Red
        Write-Host "   Location: $($test.ScriptBlock.File):$($test.ScriptBlock.StartPosition.StartLine)" -ForegroundColor Gray
        if ($test.ErrorRecord) {
            Write-Host "   Error: $($test.ErrorRecord.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`n" -NoNewline

# Exit with appropriate code
if ($PassThru) {
    return $results
} else {
    exit $(if ($results.FailedCount -gt 0) { 1 } else { 0 })
}
