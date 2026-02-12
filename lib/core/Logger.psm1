# Logger.psm1 - Win-Ops Logging Module
# Provides structured logging with rotation, ANSI colors, and thread-safe operations

#region Module Variables

$script:LoggerConfig = @{
    LogLevel = 'INFO'
    LogPath = $null
    MaxLogSizeBytes = 5MB
    MaxLogFiles = 7
    Initialized = $false
    LogBuffer = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    BufferFlushSize = 10
    LogLock = [System.Threading.Mutex]::new()
    ColorEnabled = $true
}

$script:LogLevels = @{
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3
}

$script:LogColors = @{
    DEBUG = "`e[36m"     # Cyan
    INFO = "`e[32m"      # Green
    WARN = "`e[33m"      # Yellow
    ERROR = "`e[31m"     # Red
    RESET = "`e[0m"      # Reset
}

#endregion

#region Private Functions

function Test-LogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Level
    )

    $currentLevel = $script:LogLevels[$script:LoggerConfig.LogLevel]
    $messageLevel = $script:LogLevels[$Level]

    return $messageLevel -ge $currentLevel
}

function Get-LogFileName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Index = 0
    )

    $basePath = $script:LoggerConfig.LogPath
    if ($Index -eq 0) {
        return $basePath
    }

    $directory = Split-Path -Path $basePath -Parent
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($basePath)
    $extension = [System.IO.Path]::GetExtension($basePath)

    return Join-Path -Path $directory -ChildPath "${fileName}.${Index}${extension}"
}

function Invoke-LogRotation {
    [CmdletBinding()]
    param()

    $logPath = $script:LoggerConfig.LogPath

    if (-not (Test-Path -Path $logPath)) {
        return
    }

    $fileInfo = Get-Item -Path $logPath
    if ($fileInfo.Length -lt $script:LoggerConfig.MaxLogSizeBytes) {
        return
    }

    # Rotate existing log files
    for ($i = $script:LoggerConfig.MaxLogFiles - 1; $i -ge 1; $i--) {
        $oldFile = Get-LogFileName -Index $i
        $newFile = Get-LogFileName -Index ($i + 1)

        if (Test-Path -Path $oldFile) {
            if ($i -eq ($script:LoggerConfig.MaxLogFiles - 1)) {
                Remove-Item -Path $oldFile -Force -ErrorAction SilentlyContinue
            } else {
                Move-Item -Path $oldFile -Destination $newFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Rotate current log file
    $rotatedFile = Get-LogFileName -Index 1
    Move-Item -Path $logPath -Destination $rotatedFile -Force -ErrorAction SilentlyContinue
}

function Write-LogToFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:LoggerConfig.Initialized) {
        return
    }

    try {
        $script:LoggerConfig.LogLock.WaitOne() | Out-Null

        # Check for rotation
        Invoke-LogRotation

        # Write to file
        $logPath = $script:LoggerConfig.LogPath
        $directory = Split-Path -Path $logPath -Parent

        if (-not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        Add-Content -Path $logPath -Value $Message -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    finally {
        $script:LoggerConfig.LogLock.ReleaseMutex()
    }
}

function Write-LogToConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Level
    )

    if ($script:LoggerConfig.ColorEnabled -and $PSVersionTable.PSVersion.Major -ge 7) {
        $color = $script:LogColors[$Level]
        $reset = $script:LogColors.RESET
        Write-Host "${color}${Message}${reset}"
    } else {
        Write-Host $Message
    }
}

function Flush-LogBuffer {
    [CmdletBinding()]
    param()

    while ($script:LoggerConfig.LogBuffer.Count -gt 0) {
        $logEntry = $null
        if ($script:LoggerConfig.LogBuffer.TryDequeue([ref]$logEntry)) {
            Write-LogToFile -Message $logEntry
        }
    }
}

function Format-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Context
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    if ($Context -and $Context.Count -gt 0) {
        $contextJson = $Context | ConvertTo-Json -Compress -Depth 3
        $logMessage += " | Context: $contextJson"
    }

    return $logMessage
}

#endregion

#region Public Functions

function Initialize-WinOpsLogger {
    <#
    .SYNOPSIS
    Initializes the Win-Ops logger.

    .DESCRIPTION
    Sets up the logging infrastructure including log path, rotation settings, and buffer.

    .PARAMETER LogPath
    Path to the log file. Defaults to $env:LOCALAPPDATA\win-ops\logs\win-ops.log

    .PARAMETER LogLevel
    Minimum log level to record. Valid values: DEBUG, INFO, WARN, ERROR

    .PARAMETER MaxLogSizeBytes
    Maximum size of a log file before rotation (default: 5MB)

    .PARAMETER MaxLogFiles
    Maximum number of rotated log files to keep (default: 7)

    .PARAMETER DisableColor
    Disable ANSI color output to console

    .EXAMPLE
    Initialize-WinOpsLogger

    .EXAMPLE
    Initialize-WinOpsLogger -LogLevel DEBUG -MaxLogSizeBytes 10MB
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogPath = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'win-ops\logs\win-ops.log'),

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$LogLevel = 'INFO',

        [Parameter()]
        [int64]$MaxLogSizeBytes = 5MB,

        [Parameter()]
        [int]$MaxLogFiles = 7,

        [Parameter()]
        [switch]$DisableColor
    )

    $script:LoggerConfig.LogPath = $LogPath
    $script:LoggerConfig.LogLevel = $LogLevel
    $script:LoggerConfig.MaxLogSizeBytes = $MaxLogSizeBytes
    $script:LoggerConfig.MaxLogFiles = $MaxLogFiles
    $script:LoggerConfig.ColorEnabled = -not $DisableColor
    $script:LoggerConfig.Initialized = $true

    # Ensure log directory exists
    $logDirectory = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    # Import I18n if available
    $i18nModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core\I18n.psm1'
    if ((Test-Path $i18nModule) -and -not (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue)) {
        Import-Module $i18nModule -Force -ErrorAction SilentlyContinue
        Initialize-WinOpsI18n -ErrorAction SilentlyContinue
    }

    $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
        Get-WinOpsMessage -Key 'Logger_Initialized' -Args $LogPath, $LogLevel
    } else {
        "Logger initialized at $LogPath with level $LogLevel"
    }
    Write-WinOpsLog -Level INFO -Message $msg
}

function Write-WinOpsLog {
    <#
    .SYNOPSIS
    Writes a log message.

    .DESCRIPTION
    Writes a structured log message to both console and file with automatic rotation.

    .PARAMETER Level
    Log level (DEBUG, INFO, WARN, ERROR)

    .PARAMETER Message
    Log message content

    .PARAMETER Context
    Optional hashtable containing structured context data

    .PARAMETER Exception
    Optional exception object to log

    .EXAMPLE
    Write-WinOpsLog -Level INFO -Message "Operation completed"

    .EXAMPLE
    Write-WinOpsLog -Level ERROR -Message "Failed to connect" -Context @{Host='server1'; Port=443}

    .EXAMPLE
    try { ... } catch { Write-WinOpsLog -Level ERROR -Message "Error occurred" -Exception $_ }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Context,

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$Exception
    )

    # Initialize if not done
    if (-not $script:LoggerConfig.Initialized) {
        Initialize-WinOpsLogger
    }

    # Check log level
    if (-not (Test-LogLevel -Level $Level)) {
        return
    }

    # Add exception details to context
    if ($Exception) {
        if (-not $Context) {
            $Context = @{}
        }
        $Context['Exception'] = $Exception.Exception.Message
        $Context['ScriptStackTrace'] = $Exception.ScriptStackTrace
        $Message += " | Error: $($Exception.Exception.Message)"
    }

    # Format message
    $formattedMessage = Format-LogMessage -Level $Level -Message $Message -Context $Context

    # Write to console
    Write-LogToConsole -Message $formattedMessage -Level $Level

    # Buffer for file writing
    $script:LoggerConfig.LogBuffer.Enqueue($formattedMessage)

    # Flush buffer if threshold reached or ERROR level
    if ($script:LoggerConfig.LogBuffer.Count -ge $script:LoggerConfig.BufferFlushSize -or $Level -eq 'ERROR') {
        Flush-LogBuffer
    }
}

function Set-WinOpsLogLevel {
    <#
    .SYNOPSIS
    Sets the current log level.

    .DESCRIPTION
    Changes the minimum log level for messages to be recorded.

    .PARAMETER Level
    New log level (DEBUG, INFO, WARN, ERROR)

    .EXAMPLE
    Set-WinOpsLogLevel -Level DEBUG
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level
    )

    $oldLevel = $script:LoggerConfig.LogLevel
    $script:LoggerConfig.LogLevel = $Level

    $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
        Get-WinOpsMessage -Key 'Logger_LevelChanged' -Args $oldLevel, $Level
    } else {
        "Log level changed from $oldLevel to $Level"
    }
    Write-WinOpsLog -Level INFO -Message $msg
}

function Get-WinOpsLogPath {
    <#
    .SYNOPSIS
    Returns the current log file path.

    .DESCRIPTION
    Gets the path where log files are being written.

    .EXAMPLE
    Get-WinOpsLogPath
    #>
    [CmdletBinding()]
    param()

    if (-not $script:LoggerConfig.Initialized) {
        return (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'win-ops\logs\win-ops.log')
    }

    return $script:LoggerConfig.LogPath
}

function Get-WinOpsLogLevel {
    <#
    .SYNOPSIS
    Returns the current log level.

    .DESCRIPTION
    Gets the current minimum log level setting.

    .EXAMPLE
    Get-WinOpsLogLevel
    #>
    [CmdletBinding()]
    param()

    return $script:LoggerConfig.LogLevel
}

function Clear-WinOpsLogs {
    <#
    .SYNOPSIS
    Clears all log files.

    .DESCRIPTION
    Removes all current and rotated log files.

    .PARAMETER Confirm
    Prompts for confirmation before clearing logs

    .EXAMPLE
    Clear-WinOpsLogs -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    if (-not $script:LoggerConfig.Initialized) {
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Logger_NotInitialized'
        } else {
            "Logger not initialized"
        }
        Write-Warning $msg
        return
    }

    if ($PSCmdlet.ShouldProcess("All log files", "Delete")) {
        Flush-LogBuffer

        for ($i = 0; $i -lt $script:LoggerConfig.MaxLogFiles; $i++) {
            $logFile = Get-LogFileName -Index $i
            if (Test-Path -Path $logFile) {
                Remove-Item -Path $logFile -Force -ErrorAction SilentlyContinue
                Write-Verbose "Removed $logFile"
            }
        }

        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Logger_Cleared'
        } else {
            "All log files cleared"
        }
        Write-WinOpsLog -Level INFO -Message $msg
    }
}

#endregion

#region Module Cleanup

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Flush any remaining buffered logs
    Flush-LogBuffer

    # Release mutex
    if ($script:LoggerConfig.LogLock) {
        $script:LoggerConfig.LogLock.Dispose()
    }
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Initialize-WinOpsLogger',
    'Write-WinOpsLog',
    'Set-WinOpsLogLevel',
    'Get-WinOpsLogPath',
    'Get-WinOpsLogLevel',
    'Clear-WinOpsLogs'
)

#endregion
