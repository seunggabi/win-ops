#Requires -Version 7.0

<#
.SYNOPSIS
    Test helper functions for win-ops Pester tests
.DESCRIPTION
    Provides utility functions for test setup, mocking, and cleanup
#>

using namespace System.IO

#region Test Directory Management

<#
.SYNOPSIS
    Creates a temporary test directory
.DESCRIPTION
    Creates a unique temporary directory for test isolation
.PARAMETER Prefix
    Optional prefix for the directory name
.OUTPUTS
    String - Path to the created test directory
.EXAMPLE
    $testDir = New-TestDirectory -Prefix "config-test"
#>
function New-TestDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Prefix = "test"
    )

    $uniqueId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dirName = "$Prefix-$uniqueId"
    $testPath = Join-Path $env:TEMP "win-ops-tests" $dirName

    if (-not (Test-Path $testPath)) {
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null
    }

    Write-Verbose "Created test directory: $testPath"
    return $testPath
}

<#
.SYNOPSIS
    Removes a test directory
.DESCRIPTION
    Safely removes a test directory and all its contents
.PARAMETER Path
    Path to the test directory to remove
.EXAMPLE
    Remove-TestDirectory -Path $testDir
#>
function Remove-TestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Verbose "Removed test directory: $Path"
        }
        catch {
            Write-Warning "Failed to remove test directory '$Path': $_"
            # Retry after a short delay
            Start-Sleep -Milliseconds 100
            try {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Second attempt failed to remove '$Path': $_"
            }
        }
    }
}

<#
.SYNOPSIS
    Ensures test directory is clean
.DESCRIPTION
    Removes and recreates a test directory
.PARAMETER Path
    Path to the test directory
.OUTPUTS
    String - Path to the clean test directory
.EXAMPLE
    $testDir = Reset-TestDirectory -Path $testDir
#>
function Reset-TestDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Remove-TestDirectory -Path $Path
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    return $Path
}

#endregion

#region Test File Management

<#
.SYNOPSIS
    Creates a test file with optional content
.DESCRIPTION
    Creates a file in the test directory with specified content
.PARAMETER Path
    Full path to the file to create
.PARAMETER Content
    Optional content to write to the file
.PARAMETER Size
    Optional size in bytes (creates random content)
.EXAMPLE
    New-TestFile -Path "$testDir/test.txt" -Content "test data"
.EXAMPLE
    New-TestFile -Path "$testDir/large.bin" -Size 1MB
#>
function New-TestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Content,

        [Parameter()]
        [int64]$Size
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    if ($PSBoundParameters.ContainsKey('Content')) {
        Set-Content -Path $Path -Value $Content -Encoding UTF8 -NoNewline
    }
    elseif ($PSBoundParameters.ContainsKey('Size')) {
        $fileStream = [FileStream]::new($Path, [FileMode]::Create, [FileAccess]::Write)
        try {
            $buffer = New-Object byte[] 8192
            $written = 0
            while ($written -lt $Size) {
                $toWrite = [Math]::Min($buffer.Length, $Size - $written)
                $fileStream.Write($buffer, 0, $toWrite)
                $written += $toWrite
            }
        }
        finally {
            $fileStream.Dispose()
        }
    }
    else {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    Write-Verbose "Created test file: $Path"
}

<#
.SYNOPSIS
    Creates multiple test files
.DESCRIPTION
    Creates a batch of test files with specified pattern
.PARAMETER Directory
    Directory to create files in
.PARAMETER Count
    Number of files to create
.PARAMETER Pattern
    File name pattern (use {0} for index)
.PARAMETER Size
    Size of each file in bytes
.EXAMPLE
    New-TestFiles -Directory $testDir -Count 10 -Pattern "file-{0}.txt" -Size 1KB
#>
function New-TestFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [int]$Count,

        [Parameter()]
        [string]$Pattern = "file-{0}.txt",

        [Parameter()]
        [int64]$Size = 1KB
    )

    if (-not (Test-Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    for ($i = 0; $i -lt $Count; $i++) {
        $fileName = $Pattern -f $i
        $filePath = Join-Path $Directory $fileName
        New-TestFile -Path $filePath -Size $Size
    }

    Write-Verbose "Created $Count test files in: $Directory"
}

#endregion

#region Config Mocking

<#
.SYNOPSIS
    Creates a mock win-ops configuration
.DESCRIPTION
    Returns a test configuration object with sensible defaults
.PARAMETER Overrides
    Hashtable of configuration overrides
.OUTPUTS
    PSCustomObject - Mock configuration
.EXAMPLE
    $config = New-MockWinOpsConfig -Overrides @{ dry_run = $true }
#>
function New-MockWinOpsConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable]$Overrides = @{}
    )

    $defaultConfig = @{
        dry_run = $true
        verbose = $false
        parallel_enabled = $false
        max_threads = 4
        cache_age_days = 30
        log_age_days = 90
        temp_age_days = 7

        trash = @{
            enabled = $true
            path = Join-Path $env:TEMP "win-ops-trash-test"
            retention_hours = 72
            max_size_gb = 10
        }

        cleanup = @{
            browser = @{
                enabled = $false
                browsers = @('chrome', 'edge', 'firefox')
            }
            docker = @{
                enabled = $false
                remove_stopped = $false
                remove_dangling = $false
            }
            packages = @{
                enabled = $false
                managers = @('npm', 'pip', 'cargo')
            }
        }

        safety = @{
            protected_extensions = @('.git', '.ssh', '.config')
            protected_paths = @('C:\Windows', 'C:\Program Files')
            min_free_space_gb = 10
        }
    }

    # Merge overrides
    foreach ($key in $Overrides.Keys) {
        if ($defaultConfig.ContainsKey($key) -and $defaultConfig[$key] -is [hashtable] -and $Overrides[$key] -is [hashtable]) {
            # Deep merge for nested hashtables
            foreach ($subKey in $Overrides[$key].Keys) {
                $defaultConfig[$key][$subKey] = $Overrides[$key][$subKey]
            }
        }
        else {
            $defaultConfig[$key] = $Overrides[$key]
        }
    }

    return [PSCustomObject]$defaultConfig
}

<#
.SYNOPSIS
    Mocks Get-WinOpsConfig function
.DESCRIPTION
    Sets up a mock for Get-WinOpsConfig with test configuration
.PARAMETER Config
    Configuration object to return from mock
.EXAMPLE
    Mock-WinOpsConfig -Config (New-MockWinOpsConfig)
#>
function Mock-WinOpsConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Config
    )

    if (-not $Config) {
        $Config = New-MockWinOpsConfig
    }

    Mock Get-WinOpsConfig {
        param($Key)

        if (-not $Key) {
            return $Config
        }

        # Navigate key path
        $current = $Config
        $keyParts = $Key -split '\.'

        foreach ($part in $keyParts) {
            if ($current.PSObject.Properties.Name -contains $part) {
                $current = $current.$part
            }
            else {
                return $null
            }
        }

        return $current
    } -ModuleName $TestModuleName
}

#endregion

#region Logger Mocking

<#
.SYNOPSIS
    Mocks the win-ops logger
.DESCRIPTION
    Sets up mocks for all logger functions to prevent actual logging
.PARAMETER CaptureMessages
    If specified, captures log messages in a script variable
.EXAMPLE
    Mock-WinOpsLogger
.EXAMPLE
    Mock-WinOpsLogger -CaptureMessages
    # Later access via $script:LogMessages
#>
function Mock-WinOpsLogger {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$CaptureMessages
    )

    if ($CaptureMessages) {
        $script:LogMessages = [System.Collections.Generic.List[hashtable]]::new()

        Mock Write-WinOpsLog {
            param($Level, $Message, $Context, $Exception)
            $script:LogMessages.Add(@{
                Level = $Level
                Message = $Message
                Context = $Context
                Exception = $Exception
                Timestamp = Get-Date
            })
        }
    }
    else {
        Mock Write-WinOpsLog { }
    }

    Mock Initialize-WinOpsLogger { }
    Mock Set-WinOpsLogLevel { }
    Mock Get-WinOpsLogPath { Join-Path $env:TEMP "mock-log.log" }
    Mock Get-WinOpsLogLevel { 'INFO' }
    Mock Clear-WinOpsLogs { }
}

<#
.SYNOPSIS
    Gets captured log messages
.DESCRIPTION
    Returns log messages captured by Mock-WinOpsLogger -CaptureMessages
.PARAMETER Level
    Optional filter by log level
.OUTPUTS
    Array of log message hashtables
.EXAMPLE
    $errors = Get-MockLogMessages -Level 'ERROR'
#>
function Get-MockLogMessages {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level
    )

    if (-not $script:LogMessages) {
        return @()
    }

    if ($Level) {
        return $script:LogMessages | Where-Object { $_.Level -eq $Level }
    }

    return $script:LogMessages.ToArray()
}

<#
.SYNOPSIS
    Clears captured log messages
.DESCRIPTION
    Resets the captured log messages list
.EXAMPLE
    Clear-MockLogMessages
#>
function Clear-MockLogMessages {
    [CmdletBinding()]
    param()

    if ($script:LogMessages) {
        $script:LogMessages.Clear()
    }
}

#endregion

#region Assertion Helpers

<#
.SYNOPSIS
    Asserts that a path exists
.DESCRIPTION
    Throws an error if the path doesn't exist
.PARAMETER Path
    Path to check
.PARAMETER Message
    Optional custom error message
.EXAMPLE
    Assert-PathExists -Path $testFile
#>
function Assert-PathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Message = "Path should exist: $Path"
    )

    if (-not (Test-Path $Path)) {
        throw $Message
    }
}

<#
.SYNOPSIS
    Asserts that a path does not exist
.DESCRIPTION
    Throws an error if the path exists
.PARAMETER Path
    Path to check
.PARAMETER Message
    Optional custom error message
.EXAMPLE
    Assert-PathNotExists -Path $deletedFile
#>
function Assert-PathNotExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Message = "Path should not exist: $Path"
    )

    if (Test-Path $Path) {
        throw $Message
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    # Test Directory Management
    'New-TestDirectory',
    'Remove-TestDirectory',
    'Reset-TestDirectory',

    # Test File Management
    'New-TestFile',
    'New-TestFiles',

    # Config Mocking
    'New-MockWinOpsConfig',
    'Mock-WinOpsConfig',

    # Logger Mocking
    'Mock-WinOpsLogger',
    'Get-MockLogMessages',
    'Clear-MockLogMessages',

    # Assertion Helpers
    'Assert-PathExists',
    'Assert-PathNotExists'
)

#endregion
