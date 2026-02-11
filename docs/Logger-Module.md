# Logger Module Documentation

## Overview

The Logger module (`lib/core/Logger.psm1`) provides comprehensive logging capabilities for the Win-Ops framework with features including:

- **Multiple log levels**: DEBUG, INFO, WARN, ERROR
- **Dual output**: Console (with ANSI colors) and file
- **Automatic log rotation**: Size-based with configurable limits
- **Structured logging**: JSON context support
- **Thread-safe operations**: Concurrent write protection
- **Performance optimized**: Buffered writes
- **Exception handling**: Built-in exception logging

## Installation

```powershell
Import-Module .\lib\core\Logger.psm1
```

## Quick Start

```powershell
# Initialize the logger
Initialize-WinOpsLogger

# Write log messages
Write-WinOpsLog -Level INFO -Message "Application started"
Write-WinOpsLog -Level ERROR -Message "Connection failed"
```

## Functions

### Initialize-WinOpsLogger

Initializes the logging system with custom configuration.

**Syntax**

```powershell
Initialize-WinOpsLogger
    [-LogPath <string>]
    [-LogLevel <string>]
    [-MaxLogSizeBytes <int64>]
    [-MaxLogFiles <int>]
    [-DisableColor]
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| LogPath | string | `$env:LOCALAPPDATA\win-ops\logs\win-ops.log` | Path to the log file |
| LogLevel | string | INFO | Minimum log level (DEBUG, INFO, WARN, ERROR) |
| MaxLogSizeBytes | int64 | 5MB | Maximum size before rotation |
| MaxLogFiles | int | 7 | Maximum number of rotated files to keep |
| DisableColor | switch | false | Disable ANSI color output |

**Examples**

```powershell
# Default initialization
Initialize-WinOpsLogger

# Custom configuration
Initialize-WinOpsLogger -LogPath "C:\Logs\myapp.log" -LogLevel DEBUG -MaxLogSizeBytes 10MB

# Disable colors for non-terminal output
Initialize-WinOpsLogger -DisableColor
```

### Write-WinOpsLog

Writes a log message to console and file.

**Syntax**

```powershell
Write-WinOpsLog
    -Level <string>
    -Message <string>
    [-Context <hashtable>]
    [-Exception <ErrorRecord>]
```

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Level | string | Yes | Log level: DEBUG, INFO, WARN, ERROR |
| Message | string | Yes | Log message content |
| Context | hashtable | No | Structured context data |
| Exception | ErrorRecord | No | Exception object to log |

**Examples**

```powershell
# Simple log
Write-WinOpsLog -Level INFO -Message "User logged in"

# With context
Write-WinOpsLog -Level INFO -Message "API request" -Context @{
    Endpoint = '/api/users'
    Method = 'GET'
    StatusCode = 200
}

# With exception
try {
    Get-Content -Path "missing.txt" -ErrorAction Stop
} catch {
    Write-WinOpsLog -Level ERROR -Message "File read failed" -Exception $_
}
```

### Set-WinOpsLogLevel

Changes the current log level dynamically.

**Syntax**

```powershell
Set-WinOpsLogLevel -Level <string>
```

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Level | string | Yes | New log level (DEBUG, INFO, WARN, ERROR) |

**Examples**

```powershell
# Enable debug logging
Set-WinOpsLogLevel -Level DEBUG

# Set to error only
Set-WinOpsLogLevel -Level ERROR
```

### Get-WinOpsLogPath

Returns the current log file path.

**Syntax**

```powershell
Get-WinOpsLogPath
```

**Examples**

```powershell
$logPath = Get-WinOpsLogPath
Write-Host "Logs are stored at: $logPath"
```

### Get-WinOpsLogLevel

Returns the current log level setting.

**Syntax**

```powershell
Get-WinOpsLogLevel
```

**Examples**

```powershell
$currentLevel = Get-WinOpsLogLevel
Write-Host "Current log level: $currentLevel"
```

### Clear-WinOpsLogs

Removes all log files (current and rotated).

**Syntax**

```powershell
Clear-WinOpsLogs [-Confirm]
```

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Confirm | switch | No | Prompts for confirmation (default: true) |

**Examples**

```powershell
# Clear with confirmation
Clear-WinOpsLogs

# Clear without confirmation
Clear-WinOpsLogs -Confirm:$false
```

## Log Levels

Log levels control which messages are written. Each level includes all higher severity levels.

| Level | Value | Description | Use Case |
|-------|-------|-------------|----------|
| DEBUG | 0 | Detailed diagnostic information | Development, troubleshooting |
| INFO | 1 | General informational messages | Normal operations |
| WARN | 2 | Warning messages | Potential issues |
| ERROR | 3 | Error events | Failures, exceptions |

**Log Level Hierarchy**

- **ERROR**: Only errors
- **WARN**: Warnings + Errors
- **INFO**: Info + Warnings + Errors
- **DEBUG**: Everything

## Log Format

### Console Output (with ANSI colors)

```
[2026-02-12 10:30:45] [INFO] Application started
[2026-02-12 10:30:46] [ERROR] Connection failed
```

### File Output

```
[2026-02-12 10:30:45] [INFO] Application started
[2026-02-12 10:30:46] [ERROR] Connection failed | Error: Unable to connect
```

### With Context

```
[2026-02-12 10:30:47] [INFO] API request | Context: {"Endpoint":"/api/users","Method":"GET","StatusCode":200}
```

## Log Rotation

Log rotation happens automatically when the current log file exceeds the configured size.

**Rotation Behavior**

1. When `win-ops.log` reaches 5MB (default):
   - `win-ops.log` → `win-ops.1.log`
   - `win-ops.1.log` → `win-ops.2.log`
   - ... and so on
   - Oldest file beyond max count is deleted

**Configuration**

```powershell
Initialize-WinOpsLogger -MaxLogSizeBytes 10MB -MaxLogFiles 10
```

**File Naming**

- Current: `win-ops.log`
- Rotated: `win-ops.1.log`, `win-ops.2.log`, ..., `win-ops.7.log`

## ANSI Color Support

Console output uses ANSI colors for better readability (PowerShell 7+ recommended).

**Color Scheme**

- **DEBUG**: Cyan
- **INFO**: Green
- **WARN**: Yellow
- **ERROR**: Red

**Disabling Colors**

```powershell
# For terminals without ANSI support
Initialize-WinOpsLogger -DisableColor

# Or redirect output
Write-WinOpsLog ... | Out-File log.txt
```

## Structured Logging

Add context data as hashtables for structured logging.

**Example**

```powershell
$context = @{
    UserId = 'admin@example.com'
    Action = 'DeleteUser'
    TargetUserId = 'user123'
    IPAddress = '192.168.1.100'
    Timestamp = Get-Date -Format 'o'
}

Write-WinOpsLog -Level WARN -Message "User deletion attempted" -Context $context
```

**Output**

```
[2026-02-12 10:30:48] [WARN] User deletion attempted | Context: {"UserId":"admin@example.com","Action":"DeleteUser","TargetUserId":"user123","IPAddress":"192.168.1.100","Timestamp":"2026-02-12T10:30:48.1234567+09:00"}
```

## Exception Logging

Automatically capture exception details including stack traces.

**Example**

```powershell
try {
    # Some operation that might fail
    Invoke-RestMethod -Uri "https://api.example.com/data" -ErrorAction Stop
} catch {
    Write-WinOpsLog -Level ERROR -Message "API call failed" -Exception $_ -Context @{
        Endpoint = "https://api.example.com/data"
        Retry = 1
    }
}
```

**Output**

```
[2026-02-12 10:30:49] [ERROR] API call failed | Error: The remote server returned an error: (404) Not Found. | Context: {"Endpoint":"https://api.example.com/data","Retry":1,"Exception":"The remote server returned an error: (404) Not Found.","ScriptStackTrace":"..."}
```

## Performance Optimization

### Buffering

Logs are buffered in memory and flushed to disk when:
- Buffer reaches 10 entries (default)
- ERROR level message is logged
- Module is unloaded

**Benefits**
- Reduced disk I/O
- Better performance for high-volume logging
- Immediate flushing for critical errors

### Thread Safety

The logger uses mutex locks to ensure thread-safe operations:
- Multiple threads can log simultaneously
- Log rotation is atomic
- No file corruption under concurrent access

**Example**

```powershell
# Parallel logging from multiple threads
$jobs = 1..10 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($Index)
        Import-Module .\lib\core\Logger.psm1
        Initialize-WinOpsLogger
        for ($i = 0; $i -lt 100; $i++) {
            Write-WinOpsLog -Level INFO -Message "Thread $Index Message $i"
        }
    } -ArgumentList $_
}

$jobs | Wait-Job | Remove-Job
```

## Best Practices

### 1. Initialize Early

```powershell
# At the start of your script
Initialize-WinOpsLogger -LogLevel INFO
Write-WinOpsLog -Level INFO -Message "Script started"
```

### 2. Use Appropriate Log Levels

```powershell
# DEBUG: Detailed diagnostics
Write-WinOpsLog -Level DEBUG -Message "Processing item $i of $total"

# INFO: Normal operations
Write-WinOpsLog -Level INFO -Message "User login successful"

# WARN: Potential issues
Write-WinOpsLog -Level WARN -Message "Disk space low: 10% remaining"

# ERROR: Failures
Write-WinOpsLog -Level ERROR -Message "Database connection failed"
```

### 3. Add Context for Important Events

```powershell
Write-WinOpsLog -Level INFO -Message "Order processed" -Context @{
    OrderId = $orderId
    Amount = $amount
    CustomerId = $customerId
    ProcessingTime = $duration
}
```

### 4. Always Log Exceptions

```powershell
try {
    # Critical operation
} catch {
    Write-WinOpsLog -Level ERROR -Message "Operation failed" -Exception $_
    throw
}
```

### 5. Use Verbose Logging in Development

```powershell
if ($env:ENVIRONMENT -eq 'Development') {
    Set-WinOpsLogLevel -Level DEBUG
}
```

### 6. Clean Up in Production

```powershell
# Scheduled task to clean old logs
if ((Get-Date).Day -eq 1) {
    Clear-WinOpsLogs -Confirm:$false
}
```

## Integration Examples

### With Error Handling

```powershell
function Invoke-DatabaseQuery {
    param([string]$Query)

    Write-WinOpsLog -Level DEBUG -Message "Executing query" -Context @{ Query = $Query }

    try {
        $result = Invoke-SqlCmd -Query $Query
        Write-WinOpsLog -Level INFO -Message "Query executed successfully" -Context @{
            RowCount = $result.Count
        }
        return $result
    }
    catch {
        Write-WinOpsLog -Level ERROR -Message "Query execution failed" -Exception $_ -Context @{
            Query = $Query
        }
        throw
    }
}
```

### With Progress Tracking

```powershell
function Process-Files {
    param([string[]]$Files)

    Write-WinOpsLog -Level INFO -Message "Starting file processing" -Context @{
        FileCount = $Files.Count
    }

    $processed = 0
    foreach ($file in $Files) {
        try {
            # Process file
            $processed++
            Write-WinOpsLog -Level DEBUG -Message "Processed file: $file"
        }
        catch {
            Write-WinOpsLog -Level ERROR -Message "Failed to process file" -Exception $_ -Context @{
                File = $file
            }
        }
    }

    Write-WinOpsLog -Level INFO -Message "File processing complete" -Context @{
        Total = $Files.Count
        Processed = $processed
        Failed = $Files.Count - $processed
    }
}
```

### With Configuration

```powershell
# Load configuration
$config = Get-Content config.json | ConvertFrom-Json

Initialize-WinOpsLogger `
    -LogPath $config.Logging.Path `
    -LogLevel $config.Logging.Level `
    -MaxLogSizeBytes $config.Logging.MaxSizeBytes `
    -MaxLogFiles $config.Logging.MaxFiles
```

## Troubleshooting

### Logs Not Appearing

1. Check log level setting
```powershell
Get-WinOpsLogLevel
```

2. Verify log path is writable
```powershell
$logPath = Get-WinOpsLogPath
Test-Path -Path (Split-Path $logPath -Parent)
```

3. Check for initialization
```powershell
# Re-initialize if needed
Initialize-WinOpsLogger
```

### Performance Issues

1. Increase buffer size (modify `$script:LoggerConfig.BufferFlushSize`)
2. Reduce log level in production
3. Use asynchronous logging for high-volume scenarios

### File Permission Errors

1. Ensure directory exists and is writable
2. Run PowerShell with appropriate permissions
3. Check antivirus/security software interference

## See Also

- [Win-Ops Architecture](./Architecture.md)
- [Error Handling Guide](./Error-Handling.md)
- [Testing Guide](./Testing.md)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-12 | Initial release |
