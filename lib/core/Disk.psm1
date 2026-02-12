using namespace System.Management.Automation

<#
.SYNOPSIS
    Disk management and monitoring module for Windows operations.

.DESCRIPTION
    Provides CIM-based disk operations including usage monitoring, space checking,
    large file detection, and directory size calculation.

.NOTES
    Module: WinOps.Core.Disk
    Uses: CIM (Common Information Model) for efficient disk queries
#>

# Module-level CIM session cache
$script:CimSessionCache = $null

function Get-CimSessionCached {
    <#
    .SYNOPSIS
        Gets or creates a cached CIM session for reuse.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:CimSessionCache) {
        try {
            $script:CimSessionCache = New-CimSession -ComputerName localhost -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to create CIM session: $_. Using non-cached queries."
            return $null
        }
    }

    return $script:CimSessionCache
}

function ConvertTo-HumanReadableSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable format (KB, MB, GB, TB).

    .PARAMETER Bytes
        The number of bytes to convert.

    .PARAMETER Precision
        Number of decimal places to display (default: 2).

    .EXAMPLE
        ConvertTo-HumanReadableSize -Bytes 1073741824
        # Returns "1.00 GB"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [long]$Bytes,

        [Parameter()]
        [int]$Precision = 2
    )

    process {
        if ($Bytes -eq 0) {
            return "0 B"
        }

        $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
        $index = 0
        $value = [double]$Bytes

        while ($value -ge 1024 -and $index -lt ($units.Length - 1)) {
            $value /= 1024
            $index++
        }

        # Use standard formatting with precision
        return "{0:N$Precision} {1}" -f $value, $units[$index]
    }
}

function Get-WinOpsDiskUsage {
    <#
    .SYNOPSIS
        Retrieves disk usage information for all or specified drives.

    .DESCRIPTION
        Uses CIM to query Win32_LogicalDisk for comprehensive disk information including
        total size, free space, used space, usage percentage, file system, and volume label.

    .PARAMETER DriveLetter
        Specific drive letter(s) to query (e.g., "C:", "D:"). If not specified, queries all local drives.

    .PARAMETER ExcludeNetworkDrives
        Excludes network mapped drives (DriveType 4).

    .PARAMETER ExcludeRemovableDrives
        Excludes removable drives like USB drives (DriveType 2).

    .PARAMETER AsHumanReadable
        Returns sizes in human-readable format (GB, TB) instead of bytes.

    .EXAMPLE
        Get-WinOpsDiskUsage
        # Returns usage for all local drives

    .EXAMPLE
        Get-WinOpsDiskUsage -DriveLetter "C:" -AsHumanReadable
        # Returns C: drive usage in human-readable format

    .EXAMPLE
        Get-WinOpsDiskUsage -ExcludeNetworkDrives -ExcludeRemovableDrives
        # Returns only fixed local drives
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$DriveLetter,

        [Parameter()]
        [switch]$ExcludeNetworkDrives,

        [Parameter()]
        [switch]$ExcludeRemovableDrives,

        [Parameter()]
        [switch]$AsHumanReadable
    )

    begin {
        $cimSession = Get-CimSessionCached
        $driveTypeFilter = @()

        # DriveType: 2=Removable, 3=Local Disk, 4=Network, 5=CD-ROM, 6=RAM Disk
        $driveTypeFilter += 3  # Always include local disks

        if (-not $ExcludeRemovableDrives) {
            $driveTypeFilter += 2
        }

        if (-not $ExcludeNetworkDrives) {
            $driveTypeFilter += 4
        }
    }

    process {
        try {
            # Build CIM query
            $queryParams = @{
                ClassName = 'Win32_LogicalDisk'
            }

            if ($cimSession) {
                $queryParams['CimSession'] = $cimSession
            }

            # Get all disks, then filter
            $disks = Get-CimInstance @queryParams -ErrorAction Stop

            # Apply filters
            $disks = $disks | Where-Object { $_.DriveType -in $driveTypeFilter }

            if ($DriveLetter) {
                $normalizedLetters = $DriveLetter | ForEach-Object {
                    if ($_ -match '^[A-Za-z]:?$') {
                        ($_ -replace ':', '') + ':'
                    }
                    else {
                        $_
                    }
                }
                $disks = $disks | Where-Object { $_.DeviceID -in $normalizedLetters }
            }

            foreach ($disk in $disks) {
                # Skip disks with no size (e.g., empty CD drives)
                if ($null -eq $disk.Size -or $disk.Size -eq 0) {
                    Write-Verbose "Skipping $($disk.DeviceID) - no media or zero size"
                    continue
                }

                $totalSize = [long]$disk.Size
                $freeSpace = [long]$disk.FreeSpace
                $usedSpace = $totalSize - $freeSpace
                $usagePercent = if ($totalSize -gt 0) {
                    [math]::Round(($usedSpace / $totalSize) * 100, 2)
                } else {
                    0
                }

                $driveType = switch ($disk.DriveType) {
                    2 { 'Removable' }
                    3 { 'Local' }
                    4 { 'Network' }
                    5 { 'CD-ROM' }
                    6 { 'RAM Disk' }
                    default { 'Unknown' }
                }

                $result = [PSCustomObject]@{
                    Drive          = $disk.DeviceID
                    VolumeLabel    = $disk.VolumeName
                    FileSystem     = $disk.FileSystem
                    DriveType      = $driveType
                    TotalSize      = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $totalSize } else { $totalSize }
                    UsedSpace      = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $usedSpace } else { $usedSpace }
                    FreeSpace      = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $freeSpace } else { $freeSpace }
                    UsagePercent   = $usagePercent
                    TotalSizeBytes = $totalSize
                    UsedSizeBytes  = $usedSpace
                    FreeSizeBytes  = $freeSpace
                }

                $result.PSObject.TypeNames.Insert(0, 'WinOps.DiskUsage')
                Write-Output $result
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Test-WinOpsDiskSpace {
    <#
    .SYNOPSIS
        Tests if sufficient disk space is available on a drive.

    .DESCRIPTION
        Checks if a drive has enough free space based on either absolute size or percentage.
        Useful for pre-flight checks before operations requiring disk space.

    .PARAMETER DriveLetter
        The drive letter to check (e.g., "C:", "D:").

    .PARAMETER RequiredBytes
        Minimum required free space in bytes.

    .PARAMETER RequiredGB
        Minimum required free space in gigabytes.

    .PARAMETER RequiredPercent
        Minimum required free space as a percentage of total disk size.

    .EXAMPLE
        Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredGB 10
        # Returns $true if C: has at least 10GB free

    .EXAMPLE
        Test-WinOpsDiskSpace -DriveLetter "D:" -RequiredPercent 20
        # Returns $true if D: has at least 20% free space

    .EXAMPLE
        Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredBytes 5368709120
        # Returns $true if C: has at least 5GB (in bytes) free
    #>
    [CmdletBinding(DefaultParameterSetName = 'Bytes')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$DriveLetter,

        [Parameter(ParameterSetName = 'Bytes')]
        [long]$RequiredBytes,

        [Parameter(ParameterSetName = 'GB')]
        [double]$RequiredGB,

        [Parameter(ParameterSetName = 'Percent')]
        [ValidateRange(0, 100)]
        [double]$RequiredPercent
    )

    process {
        try {
            $diskInfo = Get-WinOpsDiskUsage -DriveLetter $DriveLetter -ErrorAction Stop

            if (-not $diskInfo) {
                Write-Error "Drive $DriveLetter not found or inaccessible."
                return $false
            }

            $freeSpace = $diskInfo.FreeSizeBytes

            switch ($PSCmdlet.ParameterSetName) {
                'Bytes' {
                    if ($RequiredBytes -eq 0) { $RequiredBytes = 1GB }  # Default to 1GB
                    $result = $freeSpace -ge $RequiredBytes
                    Write-Verbose "Free: $(ConvertTo-HumanReadableSize $freeSpace), Required: $(ConvertTo-HumanReadableSize $RequiredBytes), Result: $result"
                    return $result
                }
                'GB' {
                    $requiredBytes = [long]($RequiredGB * 1GB)
                    $result = $freeSpace -ge $requiredBytes
                    Write-Verbose "Free: $(ConvertTo-HumanReadableSize $freeSpace), Required: $($RequiredGB)GB, Result: $result"
                    return $result
                }
                'Percent' {
                    $totalSize = $diskInfo.TotalSizeBytes
                    $currentPercent = ($freeSpace / $totalSize) * 100
                    $result = $currentPercent -ge $RequiredPercent
                    Write-Verbose "Free: $([math]::Round($currentPercent, 2))%, Required: $RequiredPercent%, Result: $result"
                    return $result
                }
            }
        }
        catch {
            Write-Error "Failed to check disk space: $_"
            return $false
        }
    }
}

function Get-WinOpsLargestFiles {
    <#
    .SYNOPSIS
        Finds the largest files in a directory tree.

    .DESCRIPTION
        Recursively scans a directory and returns the largest files, useful for disk cleanup
        and identifying space consumers.

    .PARAMETER Path
        The root path to scan.

    .PARAMETER Top
        Number of largest files to return (default: 10).

    .PARAMETER MinimumSizeGB
        Only include files larger than this size in GB.

    .PARAMETER MinimumSizeMB
        Only include files larger than this size in MB.

    .PARAMETER ExcludeSystemFiles
        Exclude system and hidden files.

    .PARAMETER AsHumanReadable
        Return file sizes in human-readable format.

    .EXAMPLE
        Get-WinOpsLargestFiles -Path "C:\Users" -Top 20 -AsHumanReadable
        # Returns top 20 largest files in C:\Users

    .EXAMPLE
        Get-WinOpsLargestFiles -Path "D:\Data" -MinimumSizeGB 1 -ExcludeSystemFiles
        # Returns files larger than 1GB, excluding system files
    #>
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,

        [Parameter()]
        [int]$Top = 10,

        [Parameter(ParameterSetName = 'FilterGB')]
        [double]$MinimumSizeGB,

        [Parameter(ParameterSetName = 'FilterMB')]
        [double]$MinimumSizeMB,

        [Parameter()]
        [switch]$ExcludeSystemFiles,

        [Parameter()]
        [switch]$AsHumanReadable
    )

    process {
        try {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Write-Error "Path '$Path' does not exist or is not a directory."
                return
            }

            Write-Verbose "Scanning $Path for largest files..."

            # Calculate minimum size filter
            $minSize = 0
            if ($PSCmdlet.ParameterSetName -eq 'FilterGB') {
                $minSize = [long]($MinimumSizeGB * 1GB)
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'FilterMB') {
                $minSize = [long]($MinimumSizeMB * 1MB)
            }

            # Get all files recursively
            $getChildItemParams = @{
                Path        = $Path
                File        = $true
                Recurse     = $true
                Force       = -not $ExcludeSystemFiles
                ErrorAction = 'SilentlyContinue'
            }

            $files = Get-ChildItem @getChildItemParams

            # Apply filters
            if ($ExcludeSystemFiles) {
                $files = $files | Where-Object { -not ($_.Attributes -match 'Hidden|System') }
            }

            if ($minSize -gt 0) {
                $files = $files | Where-Object { $_.Length -ge $minSize }
            }

            # Sort and take top N
            $largestFiles = $files |
                Sort-Object Length -Descending |
                Select-Object -First $Top

            foreach ($file in $largestFiles) {
                if ($null -eq $file) { continue }

                $result = [PSCustomObject]@{
                    FileName      = $file.Name
                    FullPath      = $file.FullName
                    Size          = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $file.Length } else { $file.Length }
                    SizeBytes     = $file.Length
                    LastModified  = $file.LastWriteTime
                    Extension     = $file.Extension
                    IsReadOnly    = $file.IsReadOnly
                    Attributes    = $file.Attributes
                }
                $result.PSObject.TypeNames.Insert(0, 'WinOps.LargeFile')
                Write-Output $result
            }

            Write-Verbose "Found $($largestFiles.Count) files matching criteria"
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-WinOpsDirectorySize {
    <#
    .SYNOPSIS
        Calculates the total size of a directory and its contents.

    .DESCRIPTION
        Recursively calculates directory size including all subdirectories and files.
        Handles access-denied errors gracefully and provides progress indication for large directories.

    .PARAMETER Path
        The directory path to measure.

    .PARAMETER AsHumanReadable
        Return size in human-readable format.

    .PARAMETER IncludeSubdirectories
        Include breakdown by subdirectory.

    .PARAMETER ExcludeSystemFiles
        Exclude system and hidden files from calculation.

    .EXAMPLE
        Get-WinOpsDirectorySize -Path "C:\Program Files" -AsHumanReadable
        # Returns total size of Program Files in readable format

    .EXAMPLE
        Get-WinOpsDirectorySize -Path "C:\Users\Documents" -IncludeSubdirectories
        # Returns total size plus breakdown by subdirectory
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter()]
        [switch]$AsHumanReadable,

        [Parameter()]
        [switch]$IncludeSubdirectories,

        [Parameter()]
        [switch]$ExcludeSystemFiles
    )

    process {
        try {
            if (-not (Test-Path -Path $Path -PathType Container)) {
                Write-Error "Path '$Path' does not exist or is not a directory."
                return
            }

            Write-Verbose "Calculating size for: $Path"

            $getChildItemParams = @{
                Path        = $Path
                Recurse     = $true
                File        = $true
                Force       = -not $ExcludeSystemFiles
                ErrorAction = 'SilentlyContinue'
            }

            $files = @(Get-ChildItem @getChildItemParams)

            if ($ExcludeSystemFiles) {
                $files = $files | Where-Object { -not ($_.Attributes -match 'Hidden|System') }
            }

            $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $totalSize) { $totalSize = 0 }

            $fileCount = $files.Count

            $result = [PSCustomObject]@{
                Path          = $Path
                TotalSize     = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $totalSize } else { $totalSize }
                TotalSizeBytes = $totalSize
                FileCount     = $fileCount
                Subdirectories = $null
            }

            if ($IncludeSubdirectories) {
                $subdirs = Get-ChildItem -Path $Path -Directory -Force:(-not $ExcludeSystemFiles) -ErrorAction SilentlyContinue
                $subdirInfo = foreach ($subdir in $subdirs) {
                    $subdirFiles = @(Get-ChildItem -Path $subdir.FullName -Recurse -File -Force:(-not $ExcludeSystemFiles) -ErrorAction SilentlyContinue)
                    if ($ExcludeSystemFiles) {
                        $subdirFiles = $subdirFiles | Where-Object { -not ($_.Attributes -match 'Hidden|System') }
                    }
                    $subdirSize = ($subdirFiles | Measure-Object -Property Length -Sum).Sum
                    if ($null -eq $subdirSize) { $subdirSize = 0 }

                    [PSCustomObject]@{
                        Name          = $subdir.Name
                        Path          = $subdir.FullName
                        Size          = if ($AsHumanReadable) { ConvertTo-HumanReadableSize $subdirSize } else { $subdirSize }
                        SizeBytes     = $subdirSize
                        FileCount     = $subdirFiles.Count
                    }
                }
                $result.Subdirectories = $subdirInfo
            }

            $result.PSObject.TypeNames.Insert(0, 'WinOps.DirectorySize')
            Write-Output $result
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-WinOpsDiskUsage',
    'Test-WinOpsDiskSpace',
    'Get-WinOpsLargestFiles',
    'Get-WinOpsDirectorySize',
    'ConvertTo-HumanReadableSize'
)

# Cleanup on module removal
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($null -ne $script:CimSessionCache) {
        Remove-CimSession -CimSession $script:CimSessionCache -ErrorAction SilentlyContinue
        $script:CimSessionCache = $null
    }
}
