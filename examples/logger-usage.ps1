# logger-usage.ps1 - Example usage of the Logger module

# Import the Logger module
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\lib\core\Logger.psm1') -Force

# Example 1: Basic initialization and logging
Write-Host "`n=== Example 1: Basic Logging ===" -ForegroundColor Cyan

# Initialize with default settings
Initialize-WinOpsLogger -LogLevel INFO

Write-WinOpsLog -Level INFO -Message "Application started"
Write-WinOpsLog -Level DEBUG -Message "This won't appear (below INFO level)"
Write-WinOpsLog -Level WARN -Message "Low disk space warning"
Write-WinOpsLog -Level ERROR -Message "Failed to connect to database"

# Example 2: Logging with context
Write-Host "`n=== Example 2: Structured Logging with Context ===" -ForegroundColor Cyan

$context = @{
    UserId = 'admin@example.com'
    Action = 'UserLogin'
    IPAddress = '192.168.1.100'
    Timestamp = Get-Date -Format 'o'
}

Write-WinOpsLog -Level INFO -Message "User logged in successfully" -Context $context

# Example 3: Exception logging
Write-Host "`n=== Example 3: Exception Logging ===" -ForegroundColor Cyan

try {
    # Simulate an error
    $result = 1 / 0
} catch {
    Write-WinOpsLog -Level ERROR -Message "Division by zero error occurred" -Exception $_
}

try {
    # Simulate file not found
    Get-Content -Path "C:\NonExistent\file.txt" -ErrorAction Stop
} catch {
    $errorContext = @{
        Operation = 'ReadFile'
        FilePath = 'C:\NonExistent\file.txt'
    }
    Write-WinOpsLog -Level ERROR -Message "File operation failed" -Exception $_ -Context $errorContext
}

# Example 4: Dynamic log level changes
Write-Host "`n=== Example 4: Dynamic Log Level ===" -ForegroundColor Cyan

Write-Host "Current log level: $(Get-WinOpsLogLevel)"

Write-WinOpsLog -Level DEBUG -Message "This DEBUG message won't appear"

Set-WinOpsLogLevel -Level DEBUG
Write-Host "Changed log level to: $(Get-WinOpsLogLevel)"

Write-WinOpsLog -Level DEBUG -Message "Now this DEBUG message will appear"

# Reset to INFO
Set-WinOpsLogLevel -Level INFO

# Example 5: Custom log path and rotation settings
Write-Host "`n=== Example 5: Custom Configuration ===" -ForegroundColor Cyan

$customLogPath = Join-Path -Path $env:TEMP -ChildPath "custom-app\logs\app.log"

Initialize-WinOpsLogger -LogPath $customLogPath `
                        -LogLevel DEBUG `
                        -MaxLogSizeBytes 2MB `
                        -MaxLogFiles 10

Write-Host "Log path: $(Get-WinOpsLogPath)"
Write-WinOpsLog -Level INFO -Message "Logging to custom location"

# Example 6: Simulating log rotation
Write-Host "`n=== Example 6: Log Rotation (Simulation) ===" -ForegroundColor Cyan

$testLogPath = Join-Path -Path $env:TEMP -ChildPath "rotation-test-$(Get-Random).log"
Initialize-WinOpsLogger -LogPath $testLogPath -MaxLogSizeBytes 5KB -MaxLogFiles 3

Write-Host "Writing logs to trigger rotation..."
for ($i = 1; $i -le 200; $i++) {
    Write-WinOpsLog -Level INFO -Message "Log entry $i - This is a test message with additional padding to increase file size faster. Lorem ipsum dolor sit amet."

    if ($i % 50 -eq 0) {
        Write-Host "Written $i log entries..."
    }
}

Write-Host "Check for rotated files at: $(Split-Path -Path $testLogPath -Parent)"

# Example 7: Performance test with buffering
Write-Host "`n=== Example 7: High-Volume Logging ===" -ForegroundColor Cyan

$perfLogPath = Join-Path -Path $env:TEMP -ChildPath "perf-test-$(Get-Random).log"
Initialize-WinOpsLogger -LogPath $perfLogPath

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 1; $i -le 1000; $i++) {
    Write-WinOpsLog -Level INFO -Message "Performance test entry $i"
}

$stopwatch.Stop()
Write-Host "Logged 1000 entries in $($stopwatch.ElapsedMilliseconds)ms"

# Example 8: Log levels demonstration
Write-Host "`n=== Example 8: All Log Levels ===" -ForegroundColor Cyan

Set-WinOpsLogLevel -Level DEBUG

Write-WinOpsLog -Level DEBUG -Message "Debug: Detailed diagnostic information"
Write-WinOpsLog -Level INFO -Message "Info: General informational messages"
Write-WinOpsLog -Level WARN -Message "Warn: Warning messages for potentially harmful situations"
Write-WinOpsLog -Level ERROR -Message "Error: Error events that might still allow the application to continue"

# Example 9: Clearing logs
Write-Host "`n=== Example 9: Log Cleanup ===" -ForegroundColor Cyan

$cleanupLogPath = Join-Path -Path $env:TEMP -ChildPath "cleanup-test-$(Get-Random).log"
Initialize-WinOpsLogger -LogPath $cleanupLogPath

Write-WinOpsLog -Level INFO -Message "Log entry before cleanup"
Write-Host "Log file exists: $(Test-Path -Path $cleanupLogPath)"

Clear-WinOpsLogs -Confirm:$false
Write-Host "Logs cleared"

# Example 10: Practical application logging
Write-Host "`n=== Example 10: Practical Application Example ===" -ForegroundColor Cyan

function Invoke-DataProcessing {
    param(
        [string]$InputFile,
        [string]$OutputFile
    )

    Write-WinOpsLog -Level INFO -Message "Starting data processing" -Context @{
        InputFile = $InputFile
        OutputFile = $OutputFile
    }

    try {
        # Simulate processing
        Write-WinOpsLog -Level DEBUG -Message "Reading input file"
        Start-Sleep -Milliseconds 100

        Write-WinOpsLog -Level DEBUG -Message "Processing 1000 records"
        Start-Sleep -Milliseconds 100

        Write-WinOpsLog -Level DEBUG -Message "Writing output file"
        Start-Sleep -Milliseconds 100

        Write-WinOpsLog -Level INFO -Message "Data processing completed successfully" -Context @{
            RecordsProcessed = 1000
            Duration = '300ms'
        }

        return $true
    }
    catch {
        Write-WinOpsLog -Level ERROR -Message "Data processing failed" -Exception $_ -Context @{
            InputFile = $InputFile
            OutputFile = $OutputFile
        }
        return $false
    }
}

# Run the example function
$result = Invoke-DataProcessing -InputFile "data.csv" -OutputFile "output.csv"
Write-Host "Processing result: $result"

Write-Host "`n=== Examples Complete ===" -ForegroundColor Green
Write-Host "Log file location: $(Get-WinOpsLogPath)" -ForegroundColor Yellow
