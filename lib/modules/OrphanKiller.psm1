#Requires -Version 5.1

<#
.SYNOPSIS
    Orphaned process detection and cleanup module.

.DESCRIPTION
    Identifies and cleans up orphaned processes:
    - Processes without parent process
    - Child processes of terminated parents
    - Leaked background processes
    - Detached service processes
    - Console-less background processes

.NOTES
    Module: WinOps.Modules.OrphanKiller
    Requires: Core modules (Config, Logger, Safety)
#>

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force }

#region Private Functions

function Get-ProcessWithParent {
    <#
    .SYNOPSIS
        Gets process with parent process information using WMI.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop

        $processMap = @{}
        foreach ($proc in $processes) {
            $processMap[$proc.ProcessId] = $proc
        }

        $results = @()
        foreach ($proc in $processes) {
            $parentExists = $processMap.ContainsKey($proc.ParentProcessId)
            $parentProcess = if ($parentExists) { $processMap[$proc.ParentProcessId] } else { $null }

            $results += [PSCustomObject]@{
                ProcessId = $proc.ProcessId
                ProcessName = $proc.Name
                ParentProcessId = $proc.ParentProcessId
                ParentProcessName = if ($parentProcess) { $parentProcess.Name } else { $null }
                CommandLine = $proc.CommandLine
                CreationDate = $proc.CreationDate
                ParentExists = $parentExists
                WorkingSetSize = $proc.WorkingSetSize
                HandleCount = $proc.HandleCount
            }
        }

        return $results
    }
    catch {
        Write-Error "Failed to get process information: $_"
        return @()
    }
}

function Test-ProcessOrphaned {
    <#
    .SYNOPSIS
        Determines if a process is orphaned.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ProcessInfo,

        [Parameter()]
        [hashtable]$ProcessMap
    )

    # Process has no parent
    if ($ProcessInfo.ParentProcessId -eq 0) {
        # System processes (PID 0, 4) and session managers are not orphans
        if ($ProcessInfo.ProcessId -in @(0, 4) -or $ProcessInfo.ProcessName -in @('System', 'smss.exe', 'csrss.exe')) {
            return $false
        }
        return $true
    }

    # Parent process doesn't exist
    if (-not $ProcessInfo.ParentExists) {
        return $true
    }

    return $false
}

function Get-ProcessAgeInMinutes {
    <#
    .SYNOPSIS
        Gets process age in minutes.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [DateTime]$CreationDate
    )

    $age = (Get-Date) - $CreationDate
    return $age.TotalMinutes
}

#endregion

#region Public Functions

function Find-WinOpsOrphanedProcess {
    <#
    .SYNOPSIS
        Finds orphaned processes on the system.

    .DESCRIPTION
        Identifies processes that have lost their parent process or are leaked background processes.

    .PARAMETER MinimumAgeMinutes
        Minimum age in minutes for a process to be considered orphaned (default: 1440 = 24 hours).
        This prevents flagging recently started processes.

    .PARAMETER IncludeConsoleLess
        Include processes without console windows (background processes).

    .PARAMETER ExcludeProcessNames
        Process names to exclude from detection.

    .PARAMETER ExcludeSystemProcesses
        Exclude known system processes.

    .EXAMPLE
        Find-WinOpsOrphanedProcess
        # Finds basic orphaned processes (24+ hours old)

    .EXAMPLE
        Find-WinOpsOrphanedProcess -MinimumAgeMinutes 30 -IncludeConsoleLess
        # Finds orphaned processes older than 30 minutes including background processes
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(0, 10080)]
        [int]$MinimumAgeMinutes = 1440,

        [Parameter()]
        [switch]$IncludeConsoleLess,

        [Parameter()]
        [string[]]$ExcludeProcessNames = @(),

        [Parameter()]
        [switch]$ExcludeSystemProcesses = $true
    )

    Write-WinOpsLog -Level INFO -Message "Scanning for orphaned processes..."

    $allProcesses = Get-ProcessWithParent

    if ($allProcesses.Count -eq 0) {
        Write-Warning "Failed to retrieve process information"
        return @()
    }

    # Build process map for quick lookup
    $processMap = @{}
    foreach ($proc in $allProcesses) {
        $processMap[$proc.ProcessId] = $proc
    }

    $orphanedProcesses = @()

    foreach ($processInfo in $allProcesses) {
        try {
            # Skip excluded processes
            if ($ExcludeProcessNames -contains $processInfo.ProcessName) {
                continue
            }

            # Skip system processes if requested
            if ($ExcludeSystemProcesses) {
                $systemProcesses = @(
                    'System', 'smss.exe', 'csrss.exe', 'wininit.exe', 'services.exe',
                    'lsass.exe', 'svchost.exe', 'explorer.exe', 'dwm.exe'
                )

                if ($processInfo.ProcessName -in $systemProcesses) {
                    continue
                }
            }

            # Skip protected processes
            $processNameWithoutExt = $processInfo.ProcessName -replace '\.exe$', ''
            $isProtected = Test-WinOpsProcessProtected -ProcessName $processNameWithoutExt -ErrorAction SilentlyContinue
            if ($isProtected) {
                Write-Verbose "Skipping protected process: $($processInfo.ProcessName)"
                continue
            }

            # Check if orphaned
            $isOrphaned = Test-ProcessOrphaned -ProcessInfo $processInfo -ProcessMap $processMap

            if (-not $isOrphaned) {
                continue
            }

            # Check age
            if ($processInfo.CreationDate) {
                $ageMinutes = Get-ProcessAgeInMinutes -CreationDate $processInfo.CreationDate

                if ($ageMinutes -lt $MinimumAgeMinutes) {
                    Write-Verbose "Process too young: $($processInfo.ProcessName) (age: $([math]::Round($ageMinutes, 1)) min)"
                    continue
                }
            }

            # Check if console-less (for IncludeConsoleLess filter)
            $process = Get-Process -Id $processInfo.ProcessId -ErrorAction SilentlyContinue
            $hasMainWindow = if ($process) { $process.MainWindowHandle -ne [IntPtr]::Zero } else { $false }

            if (-not $IncludeConsoleLess -and -not $hasMainWindow) {
                # Skip console-less processes unless explicitly included
                continue
            }

            $orphanedProcesses += [PSCustomObject]@{
                ProcessId = $processInfo.ProcessId
                ProcessName = $processInfo.ProcessName
                ParentProcessId = $processInfo.ParentProcessId
                ParentProcessName = $processInfo.ParentProcessName
                ParentExists = $processInfo.ParentExists
                CommandLine = $processInfo.CommandLine
                AgeMinutes = if ($processInfo.CreationDate) {
                    [math]::Round((Get-ProcessAgeInMinutes -CreationDate $processInfo.CreationDate), 1)
                } else {
                    0
                }
                MemoryMB = [math]::Round($processInfo.WorkingSetSize / 1MB, 2)
                HandleCount = $processInfo.HandleCount
                HasMainWindow = $hasMainWindow
            }

            Write-Verbose "Found orphan: $($processInfo.ProcessName) (PID: $($processInfo.ProcessId), Parent PID: $($processInfo.ParentProcessId))"
        }
        catch {
            Write-Verbose "Error checking process $($processInfo.ProcessName): $_"
        }
    }

    Write-WinOpsLog -Level INFO -Message "Found $($orphanedProcesses.Count) orphaned processes"

    return $orphanedProcesses | Sort-Object AgeMinutes -Descending
}

function Stop-WinOpsOrphanedProcess {
    <#
    .SYNOPSIS
        Terminates orphaned processes.

    .DESCRIPTION
        Kills identified orphaned processes with safety checks.

    .PARAMETER ProcessId
        Process ID(s) to terminate.

    .PARAMETER ProcessName
        Process name(s) to terminate.

    .PARAMETER Force
        Force termination without confirmation.

    .PARAMETER GracefulFirst
        Try graceful shutdown before force kill.

    .EXAMPLE
        Stop-WinOpsOrphanedProcess -ProcessId 1234 -Force
        # Terminates orphaned process 1234

    .EXAMPLE
        Find-WinOpsOrphanedProcess | Stop-WinOpsOrphanedProcess -GracefulFirst
        # Finds and terminates orphaned processes gracefully
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
                    "Terminate orphaned process"
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

                Write-WinOpsLog -Level INFO -Message "Killed orphaned process: $($process.ProcessName) (PID: $($process.Id)) - Method: $method"

                $results += [PSCustomObject]@{
                    ProcessId = $process.Id
                    ProcessName = $process.ProcessName
                    Success = $true
                    Method = $method
                    Message = "Process terminated"
                }
            }
            catch {
                Write-WinOpsLog -Level ERROR -Message "Failed to kill orphaned process: $($process.ProcessName) (PID: $($process.Id))" -Exception $_

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

function Invoke-WinOpsOrphanCleanup {
    <#
    .SYNOPSIS
        Automated orphaned process cleanup.

    .DESCRIPTION
        Scans for and terminates orphaned processes in one operation.

    .PARAMETER MinimumAgeMinutes
        Minimum age in minutes for processes to be considered orphaned (default: 1440 = 24 hours).

    .PARAMETER IncludeConsoleLess
        Include console-less background processes.

    .PARAMETER Force
        Force termination without confirmation.

    .PARAMETER DryRun
        Show what would be terminated without actually doing it.

    .EXAMPLE
        Invoke-WinOpsOrphanCleanup -DryRun
        # Shows orphaned processes without killing them (24+ hours old)

    .EXAMPLE
        Invoke-WinOpsOrphanCleanup -MinimumAgeMinutes 60 -Force
        # Kills orphaned processes older than 1 hour
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(0, 10080)]
        [int]$MinimumAgeMinutes = 1440,

        [Parameter()]
        [switch]$IncludeConsoleLess,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DryRun
    )

    Write-WinOpsLog -Level INFO -Message "Starting orphaned process cleanup"

    # Find orphans
    $orphans = Find-WinOpsOrphanedProcess `
        -MinimumAgeMinutes $MinimumAgeMinutes `
        -IncludeConsoleLess:$IncludeConsoleLess

    if ($orphans.Count -eq 0) {
        Write-WinOpsLog -Level INFO -Message "No orphaned processes found"
        return [PSCustomObject]@{
            OrphansFound = 0
            OrphansKilled = 0
            Results = @()
        }
    }

    Write-Host "Found $($orphans.Count) orphaned processes:"
    $orphans | Format-Table ProcessName, ProcessId, ParentProcessId, AgeMinutes, MemoryMB -AutoSize | Out-Host

    if ($DryRun) {
        return [PSCustomObject]@{
            OrphansFound = $orphans.Count
            OrphansKilled = 0
            Results = $orphans
            DryRun = $true
        }
    }

    # Kill orphans
    $killResults = $orphans | Stop-WinOpsOrphanedProcess -Force:$Force -GracefulFirst

    $successCount = ($killResults | Where-Object { $_.Success }).Count

    Write-WinOpsLog -Level INFO -Message "Orphan cleanup complete: Killed $successCount of $($orphans.Count) processes"

    return [PSCustomObject]@{
        OrphansFound = $orphans.Count
        OrphansKilled = $successCount
        Results = $killResults
    }
}

function Get-WinOpsProcessTree {
    <#
    .SYNOPSIS
        Gets the process tree showing parent-child relationships.

    .DESCRIPTION
        Displays process hierarchy to help identify orphaned processes.

    .PARAMETER ProcessId
        Root process ID to start tree from (default: shows all).

    .PARAMETER MaxDepth
        Maximum depth to traverse (default: 10).

    .EXAMPLE
        Get-WinOpsProcessTree -ProcessId 1234
        # Shows process tree starting from PID 1234

    .EXAMPLE
        Get-WinOpsProcessTree | Where-Object { -not $_.ParentExists }
        # Shows processes without parents
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [int]$ProcessId,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 10
    )

    $allProcesses = Get-ProcessWithParent

    if ($ProcessId) {
        # Filter to specific tree
        $processMap = @{}
        foreach ($proc in $allProcesses) {
            $processMap[$proc.ProcessId] = $proc
        }

        $treeProcesses = @()
        $queue = @($ProcessId)
        $depth = 0

        while ($queue.Count -gt 0 -and $depth -lt $MaxDepth) {
            $currentLevel = $queue
            $queue = @()

            foreach ($pid in $currentLevel) {
                if ($processMap.ContainsKey($pid)) {
                    $proc = $processMap[$pid]
                    $treeProcesses += $proc

                    # Find children
                    $children = $allProcesses | Where-Object { $_.ParentProcessId -eq $pid }
                    $queue += $children.ProcessId
                }
            }

            $depth++
        }

        return $treeProcesses
    }

    return $allProcesses
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Find-WinOpsOrphanedProcess',
    'Stop-WinOpsOrphanedProcess',
    'Invoke-WinOpsOrphanCleanup',
    'Get-WinOpsProcessTree'
)
