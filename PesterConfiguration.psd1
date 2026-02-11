@{
    Run = @{
        Path = './tests'
        Exit = $false
        PassThru = $true
        SkipRun = $false
    }

    Filter = @{
        Tag = @()
        ExcludeTag = @()
        Line = @()
        FullName = @()
    }

    CodeCoverage = @{
        Enabled = $true
        Path = @(
            './lib/core/*.psm1',
            './lib/modules/*.psm1',
            './lib/utils/*.psm1',
            './scheduler/*.psm1'
        )
        OutputFormat = 'JaCoCo'
        OutputPath = './tests/coverage.xml'
        OutputEncoding = 'UTF8'
        CoveragePercentTarget = 80
        UseBreakpoints = $false
    }

    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = './tests/test-results.xml'
        OutputEncoding = 'UTF8'
        TestSuiteName = 'win-ops Test Suite'
    }

    Should = @{
        ErrorAction = 'Stop'
    }

    Debug = @{
        ShowFullErrors = $false
        WriteDebugMessages = $false
        WriteDebugMessagesFrom = @()
        ShowNavigationMarkers = $false
        ReturnRawResultObject = $false
    }

    Output = @{
        Verbosity = 'Detailed'
        StackTraceVerbosity = 'Filtered'
        CIFormat = 'Auto'
        CILogLevel = 'Error'
    }

    TestDrive = @{
        Enabled = $true
    }

    TestRegistry = @{
        Enabled = $false
    }

    # Parallel execution settings
    # Note: Set to 1 for sequential, increase for parallel execution
    ParallelizationMode = 'Context'
    MaxParallelContainers = 4
}
