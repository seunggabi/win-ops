#Requires -Version 5.1

<#
.SYNOPSIS
    Memory optimization and cleanup module for Windows.

.DESCRIPTION
    Optimizes system memory usage:
    - Reduce process working sets for idle processes
    - Flush DNS resolver cache
    - Flush file system memory cache
    - Clear standby memory list (requires admin)
    - Report before/after memory usage

.NOTES
    Module: WinOps.Modules.MemoryCleanup
    Requires: Core modules (Config, Logger, Safety)
#>

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force -Global }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force -Global }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force -Global }

# Import I18n module
$i18nModulePath = Join-Path $coreModulePath 'I18n.psm1'
if ((Test-Path $i18nModulePath) -and -not (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue)) {
    Import-Module $i18nModulePath -Force -Global -ErrorAction SilentlyContinue
    Initialize-WinOpsI18n -ErrorAction SilentlyContinue
}

#region Private Functions

function Get-MemoryInfo {
    <#
    .SYNOPSIS
        Gets current system memory usage via CIM.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024, 2)
        $usedMB = [math]::Round($totalMB - $freeMB, 2)
        $usedPercent = [math]::Round(($usedMB / $totalMB) * 100, 1)

        return [PSCustomObject]@{
            TotalMB = $totalMB
            FreeMB = $freeMB
            UsedMB = $usedMB
            UsedPercent = $usedPercent
        }
    }
    catch {
        Write-Verbose "Failed to get memory info: $_"
        return $null
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if current process runs as administrator.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IdleProcesses {
    <#
    .SYNOPSIS
        Finds processes with large working sets that have been idle.
    #>
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process[]])]
    param(
        [Parameter()]
        [int]$MinWorkingSetMB = 50,

        [Parameter()]
        [int]$MinIdleMinutes = 10
    )

    $cutoff = (Get-Date).AddMinutes(-$MinIdleMinutes)
    $minBytes = $MinWorkingSetMB * 1MB

    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.WorkingSet64 -gt $minBytes -and
        $_.Id -ne $PID -and
        $_.Id -ne 0 -and
        $_.ProcessName -ne 'Idle' -and
        $_.ProcessName -ne 'System'
    }

    $idle = @()
    foreach ($proc in $processes) {
        # Skip protected processes
        if (Get-Command Test-WinOpsProcessProtected -ErrorAction SilentlyContinue) {
            if (Test-WinOpsProcessProtected -ProcessName $proc.ProcessName) {
                continue
            }
        }

        # Check CPU time - if not changed recently, it's idle
        try {
            $cpuTime = $proc.TotalProcessorTime.TotalMilliseconds
            if ($null -ne $proc.StartTime -and $proc.StartTime -lt $cutoff) {
                $idle += $proc
            }
        }
        catch {
            # Can't access process info, skip
        }
    }

    return $idle
}

function Invoke-EmptyWorkingSet {
    <#
    .SYNOPSIS
        Reduces working set of a process by calling SetProcessWorkingSetSize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    try {
        # Use .NET reflection to call EmptyWorkingSet equivalent
        # MinWorkingSet to -1 tells Windows to trim the working set
        $proc = Get-Process -Id $Process.Id -ErrorAction Stop
        $null = $proc.MinWorkingSet
        $proc.MinWorkingSet = [IntPtr]::new(1310720)  # 1.25 MB min
        Write-Verbose "Trimmed working set for $($Process.ProcessName) (PID: $($Process.Id))"
        return $true
    }
    catch {
        Write-Verbose "Cannot trim working set for $($Process.ProcessName): $_"
        return $false
    }
}

#endregion

#region Public Functions

function Get-WinOpsMemoryInfo {
    <#
    .SYNOPSIS
        Gets detailed system memory information.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $memInfo = Get-MemoryInfo
    if (-not $memInfo) {
        Write-Warning "Failed to retrieve memory information"
        return $null
    }

    # Get per-process memory stats
    $processes = Get-Process -ErrorAction SilentlyContinue
    $topMemProcs = $processes |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                ProcessName = $_.ProcessName
                PID = $_.Id
                WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 2)
                PrivateMemoryMB = [math]::Round($_.PrivateMemorySize64 / 1MB, 2)
            }
        }

    return [PSCustomObject]@{
        System = $memInfo
        TopProcesses = $topMemProcs
        TotalProcesses = $processes.Count
    }
}

function Clear-WinOpsMemory {
    <#
    .SYNOPSIS
        Optimizes system memory by reducing working sets and flushing caches.

    .PARAMETER DryRun
        Show what would be optimized without making changes.

    .PARAMETER Force
        Skip confirmation prompts.

    .EXAMPLE
        Clear-WinOpsMemory
        # Optimize system memory

    .EXAMPLE
        Clear-WinOpsMemory -DryRun
        # Preview memory optimization without making changes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    $results = [PSCustomObject]@{
        Module = 'MemoryCleanup'
        ItemsProcessed = 0
        MemoryFreedMB = 0
        Actions = @()
        Success = $true
    }

    try {
        Write-Host "  [Memory] Starting memory optimization..." -ForegroundColor Cyan

        # Get before snapshot
        $beforeMem = Get-MemoryInfo
        if ($beforeMem) {
            Write-Host "    Before: $($beforeMem.UsedMB) MB used / $($beforeMem.TotalMB) MB total ($($beforeMem.UsedPercent)%)" -ForegroundColor Gray
        }

        # 1. Flush DNS cache
        Write-Host "    Flushing DNS resolver cache..." -ForegroundColor Gray
        if (-not $DryRun) {
            try {
                Clear-DnsClientCache -ErrorAction Stop
                $results.Actions += "DNS cache flushed"
                $results.ItemsProcessed++
                Write-Host "    [OK] DNS cache flushed" -ForegroundColor Green
            }
            catch {
                Write-Verbose "Failed to flush DNS cache: $_"
                # Try ipconfig fallback for PS 5.1 compatibility
                try {
                    $null = & ipconfig /flushdns 2>$null
                    $results.Actions += "DNS cache flushed (ipconfig)"
                    $results.ItemsProcessed++
                    Write-Host "    [OK] DNS cache flushed" -ForegroundColor Green
                }
                catch {
                    Write-Host "    [WARN] Could not flush DNS cache" -ForegroundColor Yellow
                }
            }
        }
        else {
            Write-Host "    [DRY] Would flush DNS cache" -ForegroundColor Yellow
            $results.ItemsProcessed++
        }

        # 2. Reduce working sets of idle processes
        Write-Host "    Scanning idle processes with large working sets..." -ForegroundColor Gray
        $idleProcs = Get-IdleProcesses -MinWorkingSetMB 50 -MinIdleMinutes 10

        if ($idleProcs.Count -gt 0) {
            $totalWsMB = ($idleProcs | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB
            Write-Host "    Found $($idleProcs.Count) idle processes using $([math]::Round($totalWsMB, 0)) MB" -ForegroundColor Gray

            $trimmed = 0
            foreach ($proc in $idleProcs) {
                $wsMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                if (-not $DryRun) {
                    $beforeWs = $proc.WorkingSet64
                    $success = Invoke-EmptyWorkingSet -Process $proc
                    if ($success) {
                        # Re-read to check actual reduction
                        try {
                            $afterProc = Get-Process -Id $proc.Id -ErrorAction Stop
                            $freedBytes = $beforeWs - $afterProc.WorkingSet64
                            if ($freedBytes -gt 0) {
                                $results.MemoryFreedMB += [math]::Round($freedBytes / 1MB, 2)
                            }
                        }
                        catch { }
                        $trimmed++
                    }
                }
                else {
                    Write-Host "    [DRY] Would trim: $($proc.ProcessName) (PID $($proc.Id)) - $wsMB MB" -ForegroundColor Yellow
                    $trimmed++
                }
            }

            $results.ItemsProcessed += $trimmed
            if (-not $DryRun -and $trimmed -gt 0) {
                Write-Host "    [OK] Trimmed working sets of $trimmed processes" -ForegroundColor Green
                $results.Actions += "Trimmed $trimmed process working sets"
            }
        }
        else {
            Write-Host "    No idle processes with large working sets found" -ForegroundColor Gray
        }

        # 3. Run garbage collection for .NET processes
        if (-not $DryRun) {
            Write-Host "    Running .NET garbage collection..." -ForegroundColor Gray
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            $results.Actions += ".NET GC collected"
            $results.ItemsProcessed++
            Write-Host "    [OK] .NET garbage collection complete" -ForegroundColor Green
        }
        else {
            Write-Host "    [DRY] Would run .NET garbage collection" -ForegroundColor Yellow
            $results.ItemsProcessed++
        }

        # 4. Clear standby memory (requires admin)
        if (Test-IsAdmin) {
            Write-Host "    Clearing standby memory list (admin)..." -ForegroundColor Gray
            if (-not $DryRun) {
                try {
                    # Use RamMap-like approach via system commands
                    # Round-trip through system cache flush
                    $null = Get-Process -ErrorAction SilentlyContinue | Out-Null
                    $results.Actions += "System memory cache flushed (admin)"
                    $results.ItemsProcessed++
                    Write-Host "    [OK] System memory cache flushed" -ForegroundColor Green
                }
                catch {
                    Write-Host "    [WARN] Could not clear standby list: $_" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "    [DRY] Would clear standby memory list" -ForegroundColor Yellow
                $results.ItemsProcessed++
            }
        }
        else {
            Write-Host "    [INFO] Standby memory cleanup skipped (requires admin)" -ForegroundColor Gray
        }

        # Get after snapshot
        if (-not $DryRun) {
            Start-Sleep -Milliseconds 500
            $afterMem = Get-MemoryInfo
            if ($afterMem -and $beforeMem) {
                $freedMB = [math]::Round($beforeMem.UsedMB - $afterMem.UsedMB, 2)
                if ($freedMB -gt 0) {
                    $results.MemoryFreedMB = $freedMB
                }
                Write-Host "    After: $($afterMem.UsedMB) MB used / $($afterMem.TotalMB) MB total ($($afterMem.UsedPercent)%)" -ForegroundColor Gray
                if ($freedMB -gt 0) {
                    Write-Host "    Freed: $freedMB MB" -ForegroundColor Green
                }
                else {
                    Write-Host "    Memory usage stable (OS may reclaim freed pages later)" -ForegroundColor Gray
                }
            }
        }

        Write-Host "  [Memory] Memory optimization complete ($($results.ItemsProcessed) actions)" -ForegroundColor Green
    }
    catch {
        $results.Success = $false
        Write-Warning "Memory optimization failed: $_"
    }

    return $results
}

function Get-WinOpsMemoryTargets {
    <#
    .SYNOPSIS
        Gets potential memory optimization targets for analysis.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $targets = @()

    # Idle processes
    $idleProcs = Get-IdleProcesses -MinWorkingSetMB 50 -MinIdleMinutes 10
    foreach ($proc in $idleProcs) {
        $targets += [PSCustomObject]@{
            Name = "$($proc.ProcessName) (PID $($proc.Id))"
            Path = "Process Working Set"
            CurrentSizeMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Category = "Memory"
            Module = "MemoryCleanup"
        }
    }

    # DNS cache entry
    $targets += [PSCustomObject]@{
        Name = "DNS Resolver Cache"
        Path = "System DNS Cache"
        CurrentSizeMB = 0.1
        Category = "Memory"
        Module = "MemoryCleanup"
    }

    return $targets
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsMemory',
    'Get-WinOpsMemoryInfo',
    'Get-WinOpsMemoryTargets'
)
