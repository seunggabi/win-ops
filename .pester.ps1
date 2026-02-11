#Requires -Version 7.0

<#
.SYNOPSIS
    Alternative Pester configuration script
.DESCRIPTION
    This is an alternative to PesterConfiguration.psd1 using PowerShell script format.
    Use this if you need dynamic configuration or prefer script syntax.
#>

# Create and configure Pester settings
$config = New-PesterConfiguration

# Run configuration
$config.Run.Path = './tests'
$config.Run.Exit = $false
$config.Run.PassThru = $true

# Code coverage
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    './lib/core/*.psm1',
    './lib/modules/*.psm1',
    './lib/utils/*.psm1',
    './scheduler/*.psm1'
)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './tests/coverage.xml'
$config.CodeCoverage.OutputEncoding = 'UTF8'
$config.CodeCoverage.CoveragePercentTarget = 80

# Test results
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = './tests/test-results.xml'
$config.TestResult.OutputEncoding = 'UTF8'
$config.TestResult.TestSuiteName = 'win-ops Test Suite'

# Output configuration
$config.Output.Verbosity = 'Detailed'
$config.Output.StackTraceVerbosity = 'Filtered'

# Should configuration
$config.Should.ErrorAction = 'Stop'

# TestDrive
$config.TestDrive.Enabled = $true

# Return configuration
return $config
