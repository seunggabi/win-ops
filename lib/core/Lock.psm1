using namespace System.Threading

# Lock.psm1 - Named Mutex based locking system for WinOps

# Module-level variables
$script:LockMutex = $null
$script:LockMetadataPath = Join-Path $env:LOCALAPPDATA "win-ops\.lock"
$script:MutexName = "Global\WinOps"

<#
.SYNOPSIS
    Acquires a global lock for WinOps operations.

.DESCRIPTION
    Attempts to acquire a Named Mutex lock to prevent concurrent WinOps executions.
    Stores lock metadata (PID, start time, hostname) for debugging and stale lock detection.

.PARAMETER TimeoutSeconds
    Maximum time to wait for lock acquisition. Default is 30 seconds.

.PARAMETER Force
    Force lock acquisition by clearing stale locks first.

.EXAMPLE
    Lock-WinOps
    Acquires lock with default 30-second timeout.

.EXAMPLE
    Lock-WinOps -TimeoutSeconds 60
    Acquires lock with 60-second timeout.

.EXAMPLE
    Lock-WinOps -Force
    Clears stale locks and acquires new lock.

.OUTPUTS
    [bool] True if lock acquired, False otherwise.
#>
function Lock-WinOps {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Clear stale locks if Force is specified
        if ($Force) {
            Write-Verbose "Force flag set, clearing stale locks..."
            Clear-WinOpsStaleLock
        }

        # Check if already locked by this process
        if ($script:LockMutex -ne $null) {
            Write-Warning "Lock already acquired by this process"
            return $true
        }

        Write-Verbose "Attempting to acquire lock: $script:MutexName"

        # Create or open the named mutex
        $createdNew = $false
        $mutex = [Mutex]::new($false, $script:MutexName, [ref]$createdNew)

        # Try to acquire the mutex with timeout
        $timeoutMs = $TimeoutSeconds * 1000
        $acquired = $mutex.WaitOne($timeoutMs)

        if ($acquired) {
            $script:LockMutex = $mutex

            # Store lock metadata
            $metadata = @{
                PID = $PID
                StartTime = (Get-Date).ToString("o")
                Hostname = $env:COMPUTERNAME
                Process = (Get-Process -Id $PID).ProcessName
                CommandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).CommandLine
            }

            # Ensure directory exists
            $lockDir = Split-Path -Parent $script:LockMetadataPath
            if (-not (Test-Path $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }

            # Write metadata to file
            $metadata | ConvertTo-Json -Depth 3 | Set-Content -Path $script:LockMetadataPath -Force

            Write-Verbose "Lock acquired successfully (PID: $PID, Created: $createdNew)"
            return $true
        }
        else {
            Write-Warning "Failed to acquire lock within $TimeoutSeconds seconds"
            $mutex.Dispose()

            # Show who holds the lock
            if (Test-Path $script:LockMetadataPath) {
                $existingLock = Get-Content $script:LockMetadataPath -Raw | ConvertFrom-Json
                Write-Warning "Lock held by PID $($existingLock.PID) on $($existingLock.Hostname) since $($existingLock.StartTime)"
            }

            return $false
        }
    }
    catch {
        Write-Error "Failed to acquire lock: $_"
        if ($script:LockMutex) {
            try { $script:LockMutex.Dispose() } catch { }
            $script:LockMutex = $null
        }
        return $false
    }
}

<#
.SYNOPSIS
    Releases the WinOps global lock.

.DESCRIPTION
    Releases the Named Mutex and cleans up lock metadata.
    Safe to call even if no lock is held.

.EXAMPLE
    Unlock-WinOps
    Releases the lock.

.OUTPUTS
    [void]
#>
function Unlock-WinOps {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        if ($script:LockMutex -ne $null) {
            Write-Verbose "Releasing lock (PID: $PID)"

            # Release the mutex
            $script:LockMutex.ReleaseMutex()
            $script:LockMutex.Dispose()
            $script:LockMutex = $null

            # Clean up metadata file
            if (Test-Path $script:LockMetadataPath) {
                Remove-Item -Path $script:LockMetadataPath -Force -ErrorAction SilentlyContinue
            }

            Write-Verbose "Lock released successfully"
        }
        else {
            Write-Verbose "No lock to release"
        }
    }
    catch {
        Write-Error "Failed to release lock: $_"

        # Force cleanup on error
        try {
            if ($script:LockMutex) {
                $script:LockMutex.Dispose()
            }
        }
        catch { }

        $script:LockMutex = $null

        if (Test-Path $script:LockMetadataPath) {
            Remove-Item -Path $script:LockMetadataPath -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Checks if WinOps is currently locked.

.DESCRIPTION
    Attempts to check if the WinOps mutex is currently held without acquiring it.
    Uses a zero-timeout check to avoid blocking.

.EXAMPLE
    Test-WinOpsLocked
    Returns $true if locked, $false if available.

.OUTPUTS
    [bool] True if locked, False if available.
#>
function Test-WinOpsLocked {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Try to open existing mutex with zero timeout
        $mutex = $null
        $createdNew = $false

        try {
            $mutex = [Mutex]::new($false, $script:MutexName, [ref]$createdNew)

            # Try to acquire with zero timeout (non-blocking check)
            $acquired = $mutex.WaitOne(0)

            if ($acquired) {
                # We got it, so it wasn't locked - release immediately
                $mutex.ReleaseMutex()
                return $false
            }
            else {
                # Couldn't acquire, it's locked
                return $true
            }
        }
        finally {
            if ($mutex) {
                $mutex.Dispose()
            }
        }
    }
    catch [System.Threading.AbandonedMutexException] {
        # Mutex was abandoned (process crashed), consider it available
        Write-Verbose "Mutex was abandoned by previous owner"
        return $false
    }
    catch {
        Write-Warning "Failed to check lock status: $_"
        # On error, assume locked to be safe
        return $true
    }
}

<#
.SYNOPSIS
    Clears stale WinOps locks.

.DESCRIPTION
    Removes lock metadata for processes that no longer exist.
    Useful for cleaning up locks from crashed processes.

.PARAMETER MaxAgeMinutes
    Maximum age in minutes before considering a lock stale. Default is 60 minutes.

.EXAMPLE
    Clear-WinOpsStaleLock
    Clears locks older than 60 minutes from dead processes.

.EXAMPLE
    Clear-WinOpsStaleLock -MaxAgeMinutes 30
    Clears locks older than 30 minutes from dead processes.

.OUTPUTS
    [bool] True if a stale lock was cleared, False otherwise.
#>
function Clear-WinOpsStaleLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [int]$MaxAgeMinutes = 60
    )

    try {
        if (-not (Test-Path $script:LockMetadataPath)) {
            Write-Verbose "No lock metadata file found"
            return $false
        }

        # Read existing lock metadata
        $lockData = Get-Content $script:LockMetadataPath -Raw | ConvertFrom-Json
        $lockPID = $lockData.PID
        $lockStartTime = [DateTime]::Parse($lockData.StartTime)
        $lockAge = (Get-Date) - $lockStartTime

        Write-Verbose "Found lock metadata: PID=$lockPID, Age=$($lockAge.TotalMinutes) minutes"

        # Check if process still exists
        $processExists = Get-Process -Id $lockPID -ErrorAction SilentlyContinue

        $shouldClear = $false
        $reason = ""

        if (-not $processExists) {
            $shouldClear = $true
            $reason = "Process no longer exists"
        }
        elseif ($lockAge.TotalMinutes -gt $MaxAgeMinutes) {
            $shouldClear = $true
            $reason = "Lock age ($([int]$lockAge.TotalMinutes) minutes) exceeds maximum ($MaxAgeMinutes minutes)"
        }

        if ($shouldClear) {
            Write-Warning "Clearing stale lock: $reason"

            # Remove metadata file
            Remove-Item -Path $script:LockMetadataPath -Force -ErrorAction Stop

            # Try to acquire and release the mutex to clear it
            try {
                $mutex = [Mutex]::new($false, $script:MutexName)
                $acquired = $mutex.WaitOne(0)
                if ($acquired) {
                    $mutex.ReleaseMutex()
                }
                $mutex.Dispose()
            }
            catch [System.Threading.AbandonedMutexException] {
                # Expected for abandoned mutex - this is actually good
                Write-Verbose "Cleared abandoned mutex"
            }
            catch {
                Write-Verbose "Mutex cleanup attempt: $_"
            }

            Write-Verbose "Stale lock cleared successfully"
            return $true
        }
        else {
            Write-Verbose "Lock is valid and active"
            return $false
        }
    }
    catch {
        Write-Error "Failed to clear stale lock: $_"
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Lock-WinOps',
    'Unlock-WinOps',
    'Test-WinOpsLocked',
    'Clear-WinOpsStaleLock'
)

# Register cleanup on module removal
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($script:LockMutex -ne $null) {
        Write-Verbose "Module unloading, releasing lock..."
        try {
            $script:LockMutex.ReleaseMutex()
            $script:LockMutex.Dispose()
        }
        catch { }
        $script:LockMutex = $null
    }
}
