# Snapshot.psm1 - Win-Ops System Snapshot Module
# Provides system state capture for disk, memory, and CPU

#region Module Variables

$script:CimSession = $null

#endregion

#region Private Functions

function Initialize-CimSession {
    <#
    .SYNOPSIS
    Initializes a reusable CIM session.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:CimSession) {
        try {
            $script:CimSession = New-CimSession -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to create CIM session: $_"
        }
    }

    return $script:CimSession
}

function Get-DiskSnapshot {
    <#
    .SYNOPSIS
    Captures disk usage snapshot.
    #>
    [CmdletBinding()]
    param()

    $cimSession = Initialize-CimSession
    if ($null -eq $cimSession) {
        throw "CIM session not available"
    }

    try {
        $disks = Get-CimInstance -CimSession $cimSession -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

        $diskData = @{}
        foreach ($disk in $disks) {
            $totalBytes = [int64]$disk.Size
            $freeBytes = [int64]$disk.FreeSpace
            $usedBytes = $totalBytes - $freeBytes

            $diskData[$disk.DeviceID] = @{
                TotalBytes = $totalBytes
                UsedBytes = $usedBytes
                FreeBytes = $freeBytes
                TotalGB = [math]::Round($totalBytes / 1GB, 2)
                UsedGB = [math]::Round($usedBytes / 1GB, 2)
                FreeGB = [math]::Round($freeBytes / 1GB, 2)
                UsedPercent = if ($totalBytes -gt 0) { [math]::Round(($usedBytes / $totalBytes) * 100, 2) } else { 0 }
                VolumeName = $disk.VolumeName
            }
        }

        return $diskData
    }
    catch {
        Write-Warning "Failed to get disk snapshot: $_"
        return @{}
    }
}

function Get-MemorySnapshot {
    <#
    .SYNOPSIS
    Captures memory usage snapshot.
    #>
    [CmdletBinding()]
    param()

    $cimSession = Initialize-CimSession
    if ($null -eq $cimSession) {
        throw "CIM session not available"
    }

    try {
        $os = Get-CimInstance -CimSession $cimSession -ClassName Win32_OperatingSystem -ErrorAction Stop

        $totalBytes = [int64]$os.TotalVisibleMemorySize * 1KB
        $freeBytes = [int64]$os.FreePhysicalMemory * 1KB
        $usedBytes = $totalBytes - $freeBytes

        return @{
            TotalBytes = $totalBytes
            UsedBytes = $usedBytes
            FreeBytes = $freeBytes
            TotalGB = [math]::Round($totalBytes / 1GB, 2)
            UsedGB = [math]::Round($usedBytes / 1GB, 2)
            FreeGB = [math]::Round($freeBytes / 1GB, 2)
            UsedPercent = if ($totalBytes -gt 0) { [math]::Round(($usedBytes / $totalBytes) * 100, 2) } else { 0 }
        }
    }
    catch {
        Write-Warning "Failed to get memory snapshot: $_"
        return @{}
    }
}

function Get-CPUSnapshot {
    <#
    .SYNOPSIS
    Captures CPU usage snapshot.
    #>
    [CmdletBinding()]
    param()

    $cimSession = Initialize-CimSession
    if ($null -eq $cimSession) {
        throw "CIM session not available"
    }

    try {
        $processors = Get-CimInstance -CimSession $cimSession -ClassName Win32_Processor -ErrorAction Stop

        $totalCores = 0
        $totalLogicalProcessors = 0
        $loadPercentages = @()

        foreach ($proc in $processors) {
            $totalCores += $proc.NumberOfCores
            $totalLogicalProcessors += $proc.NumberOfLogicalProcessors
            $loadPercentages += $proc.LoadPercentage
        }

        $avgLoad = if ($loadPercentages.Count -gt 0) {
            ($loadPercentages | Measure-Object -Average).Average
        } else {
            0
        }

        return @{
            Cores = $totalCores
            LogicalProcessors = $totalLogicalProcessors
            LoadPercent = [math]::Round($avgLoad, 2)
            ProcessorCount = $processors.Count
        }
    }
    catch {
        Write-Warning "Failed to get CPU snapshot: $_"
        return @{}
    }
}

function Format-ByteSize {
    <#
    .SYNOPSIS
    Formats byte size to human-readable format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int64]$Bytes
    )

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $unitIndex = 0
    $size = [double]$Bytes

    while ($size -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $size /= 1024
        $unitIndex++
    }

    return "{0:N2} {1}" -f $size, $units[$unitIndex]
}

function Format-SnapshotOutput {
    <#
    .SYNOPSIS
    Formats snapshot data for human-readable output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Snapshot
    )

    $output = [System.Text.StringBuilder]::new()
    [void]$output.AppendLine("=" * 60)
    [void]$output.AppendLine("System Snapshot - $($Snapshot.Timestamp)")
    [void]$output.AppendLine("=" * 60)

    # Disk information
    if ($Snapshot.Disk -and $Snapshot.Disk.Count -gt 0) {
        [void]$output.AppendLine("`nDISK USAGE:")
        [void]$output.AppendLine("-" * 60)

        foreach ($drive in ($Snapshot.Disk.Keys | Sort-Object)) {
            $disk = $Snapshot.Disk[$drive]
            [void]$output.AppendLine("  Drive ${drive}")
            if ($disk.VolumeName) {
                [void]$output.AppendLine("    Volume: $($disk.VolumeName)")
            }
            [void]$output.AppendLine("    Total:  $(Format-ByteSize -Bytes $disk.TotalBytes)")
            [void]$output.AppendLine("    Used:   $(Format-ByteSize -Bytes $disk.UsedBytes) ($($disk.UsedPercent)%)")
            [void]$output.AppendLine("    Free:   $(Format-ByteSize -Bytes $disk.FreeBytes)")
            [void]$output.AppendLine("")
        }
    }

    # Memory information
    if ($Snapshot.Memory -and $Snapshot.Memory.Count -gt 0) {
        [void]$output.AppendLine("MEMORY USAGE:")
        [void]$output.AppendLine("-" * 60)
        [void]$output.AppendLine("  Total:  $(Format-ByteSize -Bytes $Snapshot.Memory.TotalBytes)")
        [void]$output.AppendLine("  Used:   $(Format-ByteSize -Bytes $Snapshot.Memory.UsedBytes) ($($Snapshot.Memory.UsedPercent)%)")
        [void]$output.AppendLine("  Free:   $(Format-ByteSize -Bytes $Snapshot.Memory.FreeBytes)")
        [void]$output.AppendLine("")
    }

    # CPU information
    if ($Snapshot.CPU -and $Snapshot.CPU.Count -gt 0) {
        [void]$output.AppendLine("CPU USAGE:")
        [void]$output.AppendLine("-" * 60)
        [void]$output.AppendLine("  Processors:         $($Snapshot.CPU.ProcessorCount)")
        [void]$output.AppendLine("  Physical Cores:     $($Snapshot.CPU.Cores)")
        [void]$output.AppendLine("  Logical Processors: $($Snapshot.CPU.LogicalProcessors)")
        [void]$output.AppendLine("  Load:               $($Snapshot.CPU.LoadPercent)%")
        [void]$output.AppendLine("")
    }

    [void]$output.AppendLine("=" * 60)

    return $output.ToString()
}

#endregion

#region Public Functions

function Get-WinOpsSnapshot {
    <#
    .SYNOPSIS
    Captures a system state snapshot.

    .DESCRIPTION
    Captures disk, memory, and CPU usage information at a point in time.
    Uses CIM (Common Information Model) for fast, efficient queries.

    .PARAMETER IncludeDisk
    Include disk usage information in the snapshot

    .PARAMETER IncludeMemory
    Include memory usage information in the snapshot

    .PARAMETER IncludeCPU
    Include CPU usage information in the snapshot

    .PARAMETER Format
    Output format: Raw (hashtable), Formatted (human-readable text), or JSON

    .EXAMPLE
    Get-WinOpsSnapshot -IncludeDisk -IncludeMemory

    .EXAMPLE
    $before = Get-WinOpsSnapshot -IncludeDisk
    # ... perform cleanup operations ...
    $after = Get-WinOpsSnapshot -IncludeDisk
    Compare-WinOpsSnapshot -Before $before -After $after

    .EXAMPLE
    Get-WinOpsSnapshot -IncludeDisk -IncludeMemory -IncludeCPU -Format Formatted
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeDisk,

        [Parameter()]
        [switch]$IncludeMemory,

        [Parameter()]
        [switch]$IncludeCPU,

        [Parameter()]
        [ValidateSet('Raw', 'Formatted', 'JSON')]
        [string]$Format = 'Raw'
    )

    # If no specific includes, capture all
    if (-not $IncludeDisk -and -not $IncludeMemory -and -not $IncludeCPU) {
        $IncludeDisk = $true
        $IncludeMemory = $true
        $IncludeCPU = $true
    }

    $snapshot = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    }

    if ($IncludeDisk) {
        $snapshot['Disk'] = Get-DiskSnapshot
    }

    if ($IncludeMemory) {
        $snapshot['Memory'] = Get-MemorySnapshot
    }

    if ($IncludeCPU) {
        $snapshot['CPU'] = Get-CPUSnapshot
    }

    switch ($Format) {
        'Formatted' {
            return Format-SnapshotOutput -Snapshot $snapshot
        }
        'JSON' {
            return $snapshot | ConvertTo-Json -Depth 10
        }
        default {
            return $snapshot
        }
    }
}

function Compare-WinOpsSnapshot {
    <#
    .SYNOPSIS
    Compares two system snapshots.

    .DESCRIPTION
    Calculates the differences between two snapshots (before and after).
    Reports freed space, memory changes, and other metrics.

    .PARAMETER Before
    The earlier snapshot

    .PARAMETER After
    The later snapshot

    .PARAMETER Format
    Output format: Raw (hashtable), Formatted (human-readable text), or JSON

    .EXAMPLE
    $before = Get-WinOpsSnapshot -IncludeDisk
    # ... perform cleanup ...
    $after = Get-WinOpsSnapshot -IncludeDisk
    Compare-WinOpsSnapshot -Before $before -After $after -Format Formatted
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Before,

        [Parameter(Mandatory)]
        [hashtable]$After,

        [Parameter()]
        [ValidateSet('Raw', 'Formatted', 'JSON')]
        [string]$Format = 'Formatted'
    )

    $comparison = @{
        BeforeTimestamp = $Before.Timestamp
        AfterTimestamp = $After.Timestamp
        Disk = @{}
        Memory = @{}
        CPU = @{}
    }

    # Compare disk
    if ($Before.Disk -and $After.Disk) {
        foreach ($drive in $Before.Disk.Keys) {
            if ($After.Disk.ContainsKey($drive)) {
                $beforeDisk = $Before.Disk[$drive]
                $afterDisk = $After.Disk[$drive]

                $freedBytes = $afterDisk.FreeBytes - $beforeDisk.FreeBytes

                $comparison.Disk[$drive] = @{
                    FreedBytes = $freedBytes
                    FreedGB = [math]::Round($freedBytes / 1GB, 2)
                    BeforeFreeGB = $beforeDisk.FreeGB
                    AfterFreeGB = $afterDisk.FreeGB
                    BeforeUsedPercent = $beforeDisk.UsedPercent
                    AfterUsedPercent = $afterDisk.UsedPercent
                    UsedPercentChange = [math]::Round($afterDisk.UsedPercent - $beforeDisk.UsedPercent, 2)
                }
            }
        }
    }

    # Compare memory
    if ($Before.Memory -and $After.Memory) {
        $freedBytes = $After.Memory.FreeBytes - $Before.Memory.FreeBytes

        $comparison.Memory = @{
            FreedBytes = $freedBytes
            FreedGB = [math]::Round($freedBytes / 1GB, 2)
            BeforeFreeGB = $Before.Memory.FreeGB
            AfterFreeGB = $After.Memory.FreeGB
            BeforeUsedPercent = $Before.Memory.UsedPercent
            AfterUsedPercent = $After.Memory.UsedPercent
            UsedPercentChange = [math]::Round($After.Memory.UsedPercent - $Before.Memory.UsedPercent, 2)
        }
    }

    # Compare CPU
    if ($Before.CPU -and $After.CPU) {
        $comparison.CPU = @{
            BeforeLoadPercent = $Before.CPU.LoadPercent
            AfterLoadPercent = $After.CPU.LoadPercent
            LoadPercentChange = [math]::Round($After.CPU.LoadPercent - $Before.CPU.LoadPercent, 2)
        }
    }

    switch ($Format) {
        'Formatted' {
            return Format-ComparisonOutput -Comparison $comparison
        }
        'JSON' {
            return $comparison | ConvertTo-Json -Depth 10
        }
        default {
            return $comparison
        }
    }
}

function Format-ComparisonOutput {
    <#
    .SYNOPSIS
    Formats comparison data for human-readable output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Comparison
    )

    $output = [System.Text.StringBuilder]::new()
    [void]$output.AppendLine("=" * 60)
    [void]$output.AppendLine("Snapshot Comparison")
    [void]$output.AppendLine("=" * 60)
    [void]$output.AppendLine("  Before: $($Comparison.BeforeTimestamp)")
    [void]$output.AppendLine("  After:  $($Comparison.AfterTimestamp)")
    [void]$output.AppendLine("=" * 60)

    # Disk comparison
    if ($Comparison.Disk -and $Comparison.Disk.Count -gt 0) {
        [void]$output.AppendLine("`nDISK CHANGES:")
        [void]$output.AppendLine("-" * 60)

        foreach ($drive in ($Comparison.Disk.Keys | Sort-Object)) {
            $disk = $Comparison.Disk[$drive]
            $freedSign = if ($disk.FreedBytes -ge 0) { "+" } else { "" }

            [void]$output.AppendLine("  Drive ${drive}:")
            [void]$output.AppendLine("    Space Freed:  ${freedSign}$(Format-ByteSize -Bytes $disk.FreedBytes)")
            [void]$output.AppendLine("    Free Before:  $($disk.BeforeFreeGB) GB ($($disk.BeforeUsedPercent)% used)")
            [void]$output.AppendLine("    Free After:   $($disk.AfterFreeGB) GB ($($disk.AfterUsedPercent)% used)")

            if ($disk.UsedPercentChange -ne 0) {
                $changeSign = if ($disk.UsedPercentChange -gt 0) { "+" } else { "" }
                [void]$output.AppendLine("    Usage Change: ${changeSign}$($disk.UsedPercentChange)%")
            }
            [void]$output.AppendLine("")
        }
    }

    # Memory comparison
    if ($Comparison.Memory -and $Comparison.Memory.Count -gt 0) {
        [void]$output.AppendLine("MEMORY CHANGES:")
        [void]$output.AppendLine("-" * 60)
        $mem = $Comparison.Memory
        $freedSign = if ($mem.FreedBytes -ge 0) { "+" } else { "" }

        [void]$output.AppendLine("  Memory Freed:  ${freedSign}$(Format-ByteSize -Bytes $mem.FreedBytes)")
        [void]$output.AppendLine("  Free Before:   $($mem.BeforeFreeGB) GB ($($mem.BeforeUsedPercent)% used)")
        [void]$output.AppendLine("  Free After:    $($mem.AfterFreeGB) GB ($($mem.AfterUsedPercent)% used)")

        if ($mem.UsedPercentChange -ne 0) {
            $changeSign = if ($mem.UsedPercentChange -gt 0) { "+" } else { "" }
            [void]$output.AppendLine("  Usage Change:  ${changeSign}$($mem.UsedPercentChange)%")
        }
        [void]$output.AppendLine("")
    }

    # CPU comparison
    if ($Comparison.CPU -and $Comparison.CPU.Count -gt 0) {
        [void]$output.AppendLine("CPU CHANGES:")
        [void]$output.AppendLine("-" * 60)
        $cpu = $Comparison.CPU

        [void]$output.AppendLine("  Load Before:  $($cpu.BeforeLoadPercent)%")
        [void]$output.AppendLine("  Load After:   $($cpu.AfterLoadPercent)%")

        if ($cpu.LoadPercentChange -ne 0) {
            $changeSign = if ($cpu.LoadPercentChange -gt 0) { "+" } else { "" }
            [void]$output.AppendLine("  Load Change:  ${changeSign}$($cpu.LoadPercentChange)%")
        }
        [void]$output.AppendLine("")
    }

    [void]$output.AppendLine("=" * 60)

    return $output.ToString()
}

function Export-WinOpsSnapshot {
    <#
    .SYNOPSIS
    Exports a snapshot to a file.

    .DESCRIPTION
    Saves a snapshot to a JSON file for later comparison or archival.

    .PARAMETER Snapshot
    The snapshot to export

    .PARAMETER Path
    Path to the output file

    .EXAMPLE
    $snapshot = Get-WinOpsSnapshot
    Export-WinOpsSnapshot -Snapshot $snapshot -Path "C:\snapshots\before-cleanup.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable]$Snapshot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
        Write-Verbose "Snapshot exported to: $Path"
    }
    catch {
        Write-Error "Failed to export snapshot: $_"
        throw
    }
}

function Import-WinOpsSnapshot {
    <#
    .SYNOPSIS
    Imports a snapshot from a file.

    .DESCRIPTION
    Loads a previously exported snapshot from a JSON file.

    .PARAMETER Path
    Path to the snapshot file

    .EXAMPLE
    $snapshot = Import-WinOpsSnapshot -Path "C:\snapshots\before-cleanup.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            throw "Snapshot file not found: $Path"
        }

        $json = Get-Content -Path $Path -Raw -Encoding UTF8
        $snapshot = $json | ConvertFrom-Json -AsHashtable

        Write-Verbose "Snapshot imported from: $Path"
        return $snapshot
    }
    catch {
        Write-Error "Failed to import snapshot: $_"
        throw
    }
}

#endregion

#region Module Cleanup

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Clean up CIM session
    if ($null -ne $script:CimSession) {
        Remove-CimSession -CimSession $script:CimSession -ErrorAction SilentlyContinue
        $script:CimSession = $null
    }
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Get-WinOpsSnapshot',
    'Compare-WinOpsSnapshot',
    'Export-WinOpsSnapshot',
    'Import-WinOpsSnapshot'
)

#endregion
