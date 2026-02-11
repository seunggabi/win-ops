# Win-Ops Logger Module

Production-ready logging module for PowerShell with automatic rotation, ANSI colors, and thread-safe operations.

## Features

- **4 Log Levels**: DEBUG, INFO, WARN, ERROR with hierarchical filtering
- **Dual Output**: Console (colored) + File (persistent)
- **Auto Rotation**: Size-based rotation with configurable limits (default: 5MB, 7 files)
- **Structured Logging**: JSON context support for rich metadata
- **Thread-Safe**: Mutex-protected concurrent writes
- **Performance**: Buffered writes with automatic flushing
- **Exception Handling**: Built-in exception logging with stack traces
- **ANSI Colors**: Color-coded console output (PowerShell 7+)

## Quick Start

```powershell
# Import module
Import-Module ./lib/core/Logger.psm1

# Initialize
Initialize-WinOpsLogger

# Log messages
Write-WinOpsLog -Level INFO -Message "Application started"
Write-WinOpsLog -Level ERROR -Message "Connection failed"
```

## Installation

No installation required. Simply import the module:

```powershell
Import-Module ./lib/core/Logger.psm1 -Force
```

## Basic Usage

### Simple Logging

```powershell
# Initialize with defaults
Initialize-WinOpsLogger

Write-WinOpsLog -Level DEBUG -Message "Detailed diagnostic info"
Write-WinOpsLog -Level INFO -Message "Normal operation"
Write-WinOpsLog -Level WARN -Message "Warning condition"
Write-WinOpsLog -Level ERROR -Message "Error occurred"
```

### With Context

```powershell
Write-WinOpsLog -Level INFO -Message "User action" -Context @{
    UserId = 'admin'
    Action = 'Login'
    IPAddress = '192.168.1.100'
}
```

### With Exceptions

```powershell
try {
    Get-Content "missing.txt" -ErrorAction Stop
} catch {
    Write-WinOpsLog -Level ERROR -Message "File read failed" -Exception $_
}
```

## Configuration

```powershell
Initialize-WinOpsLogger `
    -LogPath "C:\Logs\myapp.log" `
    -LogLevel DEBUG `
    -MaxLogSizeBytes 10MB `
    -MaxLogFiles 10 `
    -DisableColor
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| LogPath | `$env:LOCALAPPDATA\win-ops\logs\win-ops.log` | Log file location |
| LogLevel | INFO | Minimum level (DEBUG/INFO/WARN/ERROR) |
| MaxLogSizeBytes | 5MB | Size before rotation |
| MaxLogFiles | 7 | Maximum rotated files |
| DisableColor | false | Disable ANSI colors |

## Log Format

### Console Output
```
[2026-02-12 10:30:45] [INFO] Application started
[2026-02-12 10:30:46] [ERROR] Connection failed
```

### With Context
```
[2026-02-12 10:30:47] [INFO] User action | Context: {"UserId":"admin","Action":"Login"}
```

## API Reference

### Functions

#### Initialize-WinOpsLogger
Initializes the logging system.

```powershell
Initialize-WinOpsLogger [-LogPath <string>] [-LogLevel <string>] [-MaxLogSizeBytes <int64>] [-MaxLogFiles <int>] [-DisableColor]
```

#### Write-WinOpsLog
Writes a log message.

```powershell
Write-WinOpsLog -Level <string> -Message <string> [-Context <hashtable>] [-Exception <ErrorRecord>]
```

#### Set-WinOpsLogLevel
Changes the log level dynamically.

```powershell
Set-WinOpsLogLevel -Level <string>
```

#### Get-WinOpsLogPath
Returns the current log file path.

```powershell
Get-WinOpsLogPath
```

#### Get-WinOpsLogLevel
Returns the current log level.

```powershell
Get-WinOpsLogLevel
```

#### Clear-WinOpsLogs
Removes all log files.

```powershell
Clear-WinOpsLogs [-Confirm]
```

## Examples

See [examples/logger-usage.ps1](examples/logger-usage.ps1) for comprehensive examples including:
- Basic logging
- Structured logging with context
- Exception handling
- Dynamic log level changes
- Custom configuration
- Log rotation simulation
- Performance testing
- Practical application patterns

Run examples:
```powershell
./examples/logger-usage.ps1
```

## Log Rotation

Automatic rotation when file size exceeds threshold:

```
win-ops.log      (current, 5MB)
  ↓ rotation
win-ops.log      (new, empty)
win-ops.1.log    (old, 5MB)
  ↓ next rotation
win-ops.log      (new, empty)
win-ops.1.log    (previous, 5MB)
win-ops.2.log    (older, 5MB)
```

Oldest files beyond MaxLogFiles are automatically deleted.

## Thread Safety

The logger is thread-safe and can be used in parallel operations:

```powershell
$jobs = 1..10 | ForEach-Object {
    Start-Job -ScriptBlock {
        Import-Module ./lib/core/Logger.psm1
        Initialize-WinOpsLogger
        Write-WinOpsLog -Level INFO -Message "Parallel log from job $_"
    }
}

$jobs | Wait-Job | Remove-Job
```

## Performance

- **Buffered Writes**: Logs are buffered (10 entries) for efficiency
- **Auto Flush**: ERROR level logs flush immediately
- **Rotation Checks**: Performed only during writes
- **Mutex Locking**: Minimal lock contention

Benchmark: 1000 log entries in ~100-300ms (typical hardware)

## Testing

Run unit tests with Pester:

```powershell
# Install Pester if needed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run tests
Invoke-Pester ./tests/unit/Logger.Tests.ps1 -Output Detailed
```

Test coverage includes:
- Module import and exports
- Initialization
- Log writing (all levels)
- Log level filtering
- Log rotation
- Thread safety
- Utility functions

## Best Practices

1. **Initialize Early**: Call `Initialize-WinOpsLogger` at script start
2. **Use Appropriate Levels**: DEBUG for diagnostics, INFO for normal ops, WARN for potential issues, ERROR for failures
3. **Add Context**: Include relevant metadata in Context parameter
4. **Log Exceptions**: Always use `-Exception $_` in catch blocks
5. **Set Correct Level**: Use DEBUG in dev, INFO/WARN in production
6. **Monitor Size**: Adjust MaxLogSizeBytes for your log volume
7. **Clean Regularly**: Schedule periodic log cleanup in production

## Troubleshooting

### Logs Not Appearing

Check log level:
```powershell
Get-WinOpsLogLevel  # Ensure level allows your messages
Set-WinOpsLogLevel -Level DEBUG  # Lower if needed
```

### Permission Errors

Ensure directory exists and is writable:
```powershell
$logPath = Get-WinOpsLogPath
$dir = Split-Path $logPath -Parent
Test-Path $dir  # Should return True
```

### Performance Issues

Reduce log volume or increase buffer size:
```powershell
Set-WinOpsLogLevel -Level WARN  # Reduce volume
# Or modify BufferFlushSize in module (default: 10)
```

## Requirements

- PowerShell 5.1 or higher
- PowerShell 7+ recommended for ANSI color support
- Windows, Linux, or macOS

## License

Part of Win-Ops project.

## Documentation

Full documentation: [docs/Logger-Module.md](docs/Logger-Module.md)

## Contributing

This module is part of the Win-Ops framework. Contributions welcome!

## Support

For issues or questions, refer to the main Win-Ops documentation.

---

**Default Log Location**: `%LOCALAPPDATA%\win-ops\logs\win-ops.log`

**Version**: 1.0.0
