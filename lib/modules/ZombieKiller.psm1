#Requires -Version 5.1

<#
.SYNOPSIS
    Zombie process detection and termination module.

.DESCRIPTION
    Identifies and terminates problematic processes:
    - Hung/non-responsive processes
    - High CPU usage processes
    - High memory usage processes
    - Processes with no window (leaked)
    - Duplicate instances

.NOTES
    Module: WinOps.Modules.ZombieKiller
    Requires: Core modules (Config, Logger, Safety)
#>

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force

#region Private Functions

function Test-ProcessResponding {
    <#
    .SYNOPSIS
        Checks if a process is responding.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    try {
        # For processes with main window
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.Responding
        }

        # For processes without main window, check if it's accessible
        $null = $Process.Handle
        return $true
    }
    catch {
        return $false
    }
}

function Get-ProcessCPUUsage {
    <#
    .SYNOPSIS
        Calculates process CPU usage percentage.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    try {
        # Get initial CPU time
        $startCpuTime = $Process.TotalProcessorTime
        $startTime = Get-Date

        # Wait a bit
        Start-Sleep -Milliseconds 500

        # Refresh process info
        $Process.Refresh()

        # Get final CPU time
        $endCpuTime = $Process.TotalProcessorTime
        $endTime = Get-Date

        # Calculate CPU usage
        $cpuUsedTime = ($endCpuTime - $startCpuTime).TotalMilliseconds
        $totalTime = ($endTime - $startTime).TotalMilliseconds

        if ($totalTime -eq 0) {
            return 0
        }

        $cpuUsage = ($cpuUsedTime / ($totalTime * [Environment]::ProcessorCount)) * 100

        return [math]::Round($cpuUsage, 2)
    }
    catch {
        return 0
    }
}

function Get-ProcessMemoryUsageMB {
    <#
    .SYNOPSIS
        Gets process memory usage in MB.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    try {
        return [long]($Process.WorkingSet64 / 1MB)
    }
    catch {
        return 0
    }
}

#endregion

#region Public Functions

function Find-WinOpsZombieProcess {
    <#
    .SYNOPSIS
        Finds zombie/hung processes on the system.

    .DESCRIPTION
        Identifies problematic processes based on criteria:
        - Non-responding processes (with 30-second reconfirmation)
        - High CPU usage (sustained)
        - High memory usage
        - Processes without windows (potential leaks)

    .PARAMETER CPUThreshold
        CPU usage percentage threshold (default: 90%).

    .PARAMETER MemoryThresholdMB
        Memory usage threshold in MB (default: 2048).

    .PARAMETER IncludeNonResponding
        Include non-responding processes.

    .PARAMETER IncludeHighCPU
        Include processes with high CPU usage.

    .PARAMETER IncludeHighMemory
        Include processes with high memory usage.

    .PARAMETER ExcludeProcessNames
        Process names to exclude from detection.

    .PARAMETER SkipReconfirmation
        Skip the 30-second reconfirmation check for non-responding processes.

    .EXAMPLE
        Find-WinOpsZombieProcess -IncludeNonResponding
        # Finds all non-responding processes (with 30-second reconfirmation)

    .EXAMPLE
        Find-WinOpsZombieProcess -IncludeHighCPU -CPUThreshold 80
        # Finds processes using more than 80% CPU
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$CPUThreshold = 90,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$MemoryThresholdMB = 2048,

        [Parameter()]
        [switch]$IncludeNonResponding,

        [Parameter()]
        [switch]$IncludeHighCPU,

        [Parameter()]
        [switch]$IncludeHighMemory,

        [Parameter()]
        [string[]]$ExcludeProcessNames = @(),

        [Parameter()]
        [switch]$SkipReconfirmation
    )

    Write-WinOpsLog -Level INFO -Message "Scanning for zombie processes..."

    # If no filters specified, enable non-responding by default
    if (-not ($IncludeNonResponding -or $IncludeHighCPU -or $IncludeHighMemory)) {
        $IncludeNonResponding = $true
    }

    $zombieProcesses = @()
    $candidateProcesses = @()
    $allProcesses = Get-Process -ErrorAction SilentlyContinue

    # First pass: identify candidates
    foreach ($process in $allProcesses) {
        try {
            # Skip excluded processes
            if ($ExcludeProcessNames -contains $process.ProcessName) {
                continue
            }

            # Skip protected processes
            $isProtected = Test-WinOpsProcessProtected -ProcessName $process.ProcessName -ErrorAction SilentlyContinue
            if ($isProtected) {
                Write-Verbose "Skipping protected process: $($process.ProcessName)"
                continue
            }

            $reasons = @()
            $isZombie = $false

            # Check if non-responding
            if ($IncludeNonResponding) {
                $isResponding = Test-ProcessResponding -Process $process

                if (-not $isResponding) {
                    $reasons += "Not responding"
                    $isZombie = $true
                }
            }

            # Check CPU usage
            if ($IncludeHighCPU) {
                $cpuUsage = Get-ProcessCPUUsage -Process $process

                if ($cpuUsage -ge $CPUThreshold) {
                    $reasons += "High CPU ($cpuUsage%)"
                    $isZombie = $true
                }
            }

            # Check memory usage
            if ($IncludeHighMemory) {
                $memoryMB = Get-ProcessMemoryUsageMB -Process $process

                if ($memoryMB -ge $MemoryThresholdMB) {
                    $reasons += "High memory ($memoryMB MB)"
                    $isZombie = $true
                }
            }

            if ($isZombie) {
                $candidateProcesses += [PSCustomObject]@{
                    ProcessId = $process.Id
                    ProcessName = $process.ProcessName
                    Reasons = $reasons
                    NeedsReconfirmation = ($IncludeNonResponding -and ($reasons -contains "Not responding"))
                }

                Write-Verbose "Found zombie candidate: $($process.ProcessName) (PID: $($process.Id)) - $($reasons -join ', ')"
            }
        }
        catch {
            Write-Verbose "Error checking process $($process.ProcessName): $_"
        }
    }

    # Second pass: reconfirm non-responding processes after 30 seconds
    if ($IncludeNonResponding -and -not $SkipReconfirmation) {
        $needReconfirm = $candidateProcesses | Where-Object { $_.NeedsReconfirmation }

        if ($needReconfirm.Count -gt 0) {
            Write-WinOpsLog -Level INFO -Message "Waiting 30 seconds to reconfirm $($needReconfirm.Count) non-responding processes..."
            Start-Sleep -Seconds 30

            foreach ($candidate in $needReconfirm) {
                try {
                    $process = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
                    if (-not $process) {
                        Write-Verbose "Process $($candidate.ProcessName) (PID: $($candidate.ProcessId)) no longer exists"
                        continue
                    }

                    # Recheck if still not responding
                    $isResponding = Test-ProcessResponding -Process $process
                    if ($isResponding) {
                        Write-Verbose "Process $($candidate.ProcessName) (PID: $($candidate.ProcessId)) is now responding - removed from zombie list"
                        # Remove from candidates
                        $candidateProcesses = $candidateProcesses | Where-Object { $_.ProcessId -ne $candidate.ProcessId }
                    }
                    else {
                        Write-Verbose "Process $($candidate.ProcessName) (PID: $($candidate.ProcessId)) still not responding after 30 seconds"
                    }
                }
                catch {
                    Write-Verbose "Error reconfirming process $($candidate.ProcessName): $_"
                }
            }
        }
    }

    # Final pass: build result objects for confirmed zombies
    foreach ($candidate in $candidateProcesses) {
        try {
            $process = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
            if (-not $process) {
                continue
            }

            $zombieProcesses += [PSCustomObject]@{
                ProcessId = $process.Id
                ProcessName = $process.ProcessName
                MainWindowTitle = $process.MainWindowTitle
                StartTime = try { $process.StartTime } catch { $null }
                CPUPercent = if ($IncludeHighCPU) { Get-ProcessCPUUsage -Process $process } else { 0 }
                MemoryMB = Get-ProcessMemoryUsageMB -Process $process
                Responding = Test-ProcessResponding -Process $process
                Reasons = $candidate.Reasons -join ", "
            }
        }
        catch {
            Write-Verbose "Error building zombie info for $($candidate.ProcessName): $_"
        }
    }

    Write-WinOpsLog -Level INFO -Message "Found $($zombieProcesses.Count) confirmed zombie processes"

    return $zombieProcesses | Sort-Object MemoryMB -Descending
}

function Stop-WinOpsZombieProcess {
    <#
    .SYNOPSIS
        Terminates zombie processes.

    .DESCRIPTION
        Kills identified zombie processes with safety checks.

    .PARAMETER ProcessId
        Process ID(s) to terminate.

    .PARAMETER ProcessName
        Process name(s) to terminate.

    .PARAMETER Force
        Force termination without confirmation.

    .PARAMETER GracefulFirst
        Try graceful shutdown before force kill.

    .EXAMPLE
        Stop-WinOpsZombieProcess -ProcessId 1234 -Force
        # Kills process 1234

    .EXAMPLE
        Find-WinOpsZombieProcess -IncludeNonResponding | Stop-WinOpsZombieProcess -GracefulFirst
        # Finds and terminates non-responding processes gracefully
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [int[]]$ProcessId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$ProcessName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$GracefulFirst
    )

    begin {
        $results = @()
    }

    process {
        # Get processes to terminate
        $processesToKill = @()

        if ($ProcessId) {
            foreach ($pid in $ProcessId) {
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc) {
                    $processesToKill += $proc
                }
            }
        }

        if ($ProcessName) {
            foreach ($name in $ProcessName) {
                $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
                if ($procs) {
                    $processesToKill += $procs
                }
            }
        }

        foreach ($process in $processesToKill) {
            try {
                # Safety check
                $isProtected = Test-WinOpsProcessProtected -ProcessName $process.ProcessName -ErrorAction SilentlyContinue

                if ($isProtected) {
                    Write-Warning "Cannot kill protected process: $($process.ProcessName) (PID: $($process.Id))"
                    $results += [PSCustomObject]@{
                        ProcessId = $process.Id
                        ProcessName = $process.ProcessName
                        Success = $false
                        Message = "Protected process"
                    }
                    continue
                }

                if (-not $Force -and -not $PSCmdlet.ShouldProcess(
                    "$($process.ProcessName) (PID: $($process.Id))",
                    "Terminate process"
                )) {
                    $results += [PSCustomObject]@{
                        ProcessId = $process.Id
                        ProcessName = $process.ProcessName
                        Success = $false
                        Message = "Cancelled by user"
                    }
                    continue
                }

                $killed = $false
                $method = "Force"

                # Try graceful shutdown first
                if ($GracefulFirst) {
                    Write-Verbose "Attempting graceful shutdown: $($process.ProcessName)"
                    try {
                        $process.CloseMainWindow() | Out-Null
                        Start-Sleep -Seconds 2

                        # Check if still running
                        $stillRunning = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
                        if (-not $stillRunning) {
                            $killed = $true
                            $method = "Graceful"
                        }
                    }
                    catch {
                        Write-Verbose "Graceful shutdown failed: $_"
                    }
                }

                # Force kill if still running
                if (-not $killed) {
                    Write-Verbose "Force killing: $($process.ProcessName) (PID: $($process.Id))"
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    $killed = $true
                }

                Write-WinOpsLog -Level INFO -Message "Killed zombie process: $($process.ProcessName) (PID: $($process.Id)) - Method: $method"

                $results += [PSCustomObject]@{
                    ProcessId = $process.Id
                    ProcessName = $process.ProcessName
                    Success = $true
                    Method = $method
                    Message = "Process terminated"
                }
            }
            catch {
                Write-WinOpsLog -Level ERROR -Message "Failed to kill process: $($process.ProcessName) (PID: $($process.Id))" -Exception $_

                $results += [PSCustomObject]@{
                    ProcessId = $process.Id
                    ProcessName = $process.ProcessName
                    Success = $false
                    Message = $_.Exception.Message
                }
            }
        }
    }

    end {
        return $results
    }
}

function Find-WinOpsDuplicateProcess {
    <#
    .SYNOPSIS
        Finds duplicate instances of processes.

    .DESCRIPTION
        Identifies processes with multiple instances running, which may indicate leaks or issues.

    .PARAMETER MinimumInstances
        Minimum number of instances to consider as duplicate (default: 3).

    .PARAMETER ExcludeProcessNames
        Process names to exclude from detection.

    .EXAMPLE
        Find-WinOpsDuplicateProcess -MinimumInstances 5
        # Finds processes with 5 or more instances

    .EXAMPLE
        Find-WinOpsDuplicateProcess | Where-Object { $_.InstanceCount -gt 10 }
        # Finds processes with more than 10 instances
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(2, 1000)]
        [int]$MinimumInstances = 3,

        [Parameter()]
        [string[]]$ExcludeProcessNames = @('svchost', 'conhost', 'chrome', 'msedge')
    )

    Write-Verbose "Scanning for duplicate processes..."

    $allProcesses = Get-Process -ErrorAction SilentlyContinue

    # Group by process name
    $grouped = $allProcesses | Group-Object -Property ProcessName

    $duplicates = @()

    foreach ($group in $grouped) {
        # Skip if below threshold
        if ($group.Count -lt $MinimumInstances) {
            continue
        }

        # Skip excluded processes
        if ($ExcludeProcessNames -contains $group.Name) {
            continue
        }

        # Skip protected processes
        $isProtected = Test-WinOpsProcessProtected -ProcessName $group.Name -ErrorAction SilentlyContinue
        if ($isProtected) {
            continue
        }

        $totalMemoryMB = ($group.Group | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB
        $processIds = $group.Group | ForEach-Object { $_.Id }

        $duplicates += [PSCustomObject]@{
            ProcessName = $group.Name
            InstanceCount = $group.Count
            TotalMemoryMB = [math]::Round($totalMemoryMB, 2)
            ProcessIds = $processIds
            FirstStartTime = ($group.Group | Sort-Object StartTime | Select-Object -First 1).StartTime
        }
    }

    return $duplicates | Sort-Object InstanceCount -Descending
}

function Invoke-WinOpsZombieCleanup {
    <#
    .SYNOPSIS
        Automated zombie process cleanup.

    .DESCRIPTION
        Scans for and terminates zombie processes in one operation.

    .PARAMETER CPUThreshold
        CPU usage threshold percentage.

    .PARAMETER MemoryThresholdMB
        Memory usage threshold in MB.

    .PARAMETER IncludeNonResponding
        Include non-responding processes.

    .PARAMETER IncludeHighCPU
        Include high CPU usage processes.

    .PARAMETER IncludeHighMemory
        Include high memory usage processes.

    .PARAMETER Force
        Force termination without confirmation.

    .PARAMETER DryRun
        Show what would be terminated without actually doing it.

    .EXAMPLE
        Invoke-WinOpsZombieCleanup -IncludeNonResponding -DryRun
        # Shows non-responding processes without killing them

    .EXAMPLE
        Invoke-WinOpsZombieCleanup -IncludeHighMemory -MemoryThresholdMB 4096 -Force
        # Kills processes using more than 4GB memory
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$CPUThreshold = 90,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$MemoryThresholdMB = 2048,

        [Parameter()]
        [switch]$IncludeNonResponding,

        [Parameter()]
        [switch]$IncludeHighCPU,

        [Parameter()]
        [switch]$IncludeHighMemory,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DryRun
    )

    Write-WinOpsLog -Level INFO -Message "Starting zombie process cleanup"

    # Find zombies
    $zombies = Find-WinOpsZombieProcess `
        -CPUThreshold $CPUThreshold `
        -MemoryThresholdMB $MemoryThresholdMB `
        -IncludeNonResponding:$IncludeNonResponding `
        -IncludeHighCPU:$IncludeHighCPU `
        -IncludeHighMemory:$IncludeHighMemory

    if ($zombies.Count -eq 0) {
        Write-WinOpsLog -Level INFO -Message "No zombie processes found"
        return [PSCustomObject]@{
            ZombiesFound = 0
            ZombiesKilled = 0
            Results = @()
        }
    }

    Write-Host "Found $($zombies.Count) zombie processes:"
    $zombies | Format-Table ProcessName, ProcessId, MemoryMB, Reasons -AutoSize | Out-Host

    if ($DryRun) {
        return [PSCustomObject]@{
            ZombiesFound = $zombies.Count
            ZombiesKilled = 0
            Results = $zombies
            DryRun = $true
        }
    }

    # Kill zombies
    $killResults = $zombies | Stop-WinOpsZombieProcess -Force:$Force -GracefulFirst

    $successCount = ($killResults | Where-Object { $_.Success }).Count

    Write-WinOpsLog -Level INFO -Message "Zombie cleanup complete: Killed $successCount of $($zombies.Count) processes"

    return [PSCustomObject]@{
        ZombiesFound = $zombies.Count
        ZombiesKilled = $successCount
        Results = $killResults
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Find-WinOpsZombieProcess',
    'Stop-WinOpsZombieProcess',
    'Find-WinOpsDuplicateProcess',
    'Invoke-WinOpsZombieCleanup'
)
