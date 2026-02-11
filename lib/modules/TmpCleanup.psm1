#Requires -Version 5.1

<#
.SYNOPSIS
    Temporary file cleanup module for Windows.

.DESCRIPTION
    Cleans temporary files and folders from various Windows locations:
    - Windows Temp (%TEMP%, %TMP%, C:\Windows\Temp)
    - User Temp folders
    - Recent items
    - Windows Error Reporting
    - Memory dumps
    - Windows Installer cache
    - Setup log files

.NOTES
    Module: WinOps.Modules.TmpCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force

#region Temp Locations

$script:TempLocations = @{
    UserTemp = @{
        Paths = @(
            $env:TEMP,
            $env:TMP
        )
        Description = "User temporary files"
        DefaultAgeInDays = 7
        SafetyLevel = "Normal"
    }

    SystemTemp = @{
        Paths = @(
            "$env:SystemRoot\Temp"
        )
        Description = "System temporary files"
        DefaultAgeInDays = 7
        SafetyLevel = "Normal"
        RequiresElevation = $true
    }

    RecentItems = @{
        Paths = @(
            "$env:APPDATA\Microsoft\Windows\Recent\*"
        )
        Description = "Recent items list"
        DefaultAgeInDays = 30
        SafetyLevel = "Normal"
    }

    WindowsErrorReporting = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
            "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
            "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
            "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
        )
        Description = "Windows Error Reporting data"
        DefaultAgeInDays = 30
        SafetyLevel = "Normal"
    }

    MemoryDumps = @{
        Paths = @(
            "$env:SystemRoot\memory.dmp",
            "$env:SystemRoot\Minidump\*.dmp",
            "$env:LOCALAPPDATA\CrashDumps\*.dmp"
        )
        Description = "Memory dump files"
        DefaultAgeInDays = 30
        SafetyLevel = "Strict"
    }

    WindowsInstallerCache = @{
        Paths = @(
            "$env:SystemRoot\Installer\$PatchCache$\*"
        )
        Description = "Windows Installer cached files"
        DefaultAgeInDays = 90
        SafetyLevel = "Strict"
        RequiresElevation = $true
    }

    WindowsSetupLogs = @{
        Paths = @(
            "$env:SystemRoot\Panther\*",
            "$env:SystemRoot\Logs\CBS\*.log",
            "$env:SystemRoot\Logs\DISM\*.log"
        )
        Description = "Windows setup and servicing logs"
        DefaultAgeInDays = 90
        SafetyLevel = "Strict"
        RequiresElevation = $true
    }

    DownloadedInstallFiles = @{
        Paths = @(
            "$env:SystemRoot\Downloaded Program Files"
        )
        Description = "Downloaded ActiveX and Java components"
        DefaultAgeInDays = 30
        SafetyLevel = "Normal"
    }

    TempInternetFiles = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
            "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies"
        )
        Description = "Internet Explorer temporary files"
        DefaultAgeInDays = 7
        SafetyLevel = "Normal"
    }
}

#endregion

#region Private Functions

function Test-IsElevated {
    <#
    .SYNOPSIS
        Checks if current session is running with administrator privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TempFileCount {
    <#
    .SYNOPSIS
        Counts files in temp locations matching age criteria.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$AgeInDays = 0
    )

    $totalCount = 0
    $totalSize = 0
    $cutoffDate = if ($AgeInDays -gt 0) {
        (Get-Date).AddDays(-$AgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        try {
            if ($expandedPath -like '*`**') {
                # Wildcard path - get matching files
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
            } else {
                # Directory path - get all contents
                if (-not (Test-Path $expandedPath)) {
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            foreach ($item in $items) {
                if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                    continue
                }

                $totalCount++
                if (-not $item.PSIsContainer) {
                    $totalSize += $item.Length
                }
            }
        }
        catch {
            Write-Verbose "Failed to access path $expandedPath`: $_"
        }
    }

    return @{
        Count = $totalCount
        Size = $totalSize
    }
}

function Remove-TempFiles {
    <#
    .SYNOPSIS
        Removes temporary files from specified paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$AgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$LocationName,

        [Parameter()]
        [string[]]$ExcludePatterns = @()
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $skippedCount = 0
    $errors = @()

    $cutoffDate = if ($AgeInDays -gt 0) {
        (Get-Date).AddDays(-$AgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        try {
            if ($expandedPath -like '*`**') {
                # Wildcard path
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction Stop
            } else {
                if (-not (Test-Path $expandedPath)) {
                    Write-Verbose "Path does not exist: $expandedPath"
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction Stop
            }

            foreach ($item in $items) {
                try {
                    # Check age filter
                    if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                        $skippedCount++
                        continue
                    }

                    # Check exclude patterns
                    $shouldExclude = $false
                    foreach ($pattern in $ExcludePatterns) {
                        if ($item.Name -like $pattern -or $item.FullName -like $pattern) {
                            $shouldExclude = $true
                            break
                        }
                    }

                    if ($shouldExclude) {
                        Write-Verbose "Excluded by pattern: $($item.FullName)"
                        $skippedCount++
                        continue
                    }

                    # Check if file is in use
                    if (-not $item.PSIsContainer) {
                        try {
                            $stream = [File]::Open($item.FullName, [FileMode]::Open, [FileAccess]::Read, [FileShare]::None)
                            $stream.Close()
                            $stream.Dispose()
                        }
                        catch [UnauthorizedAccessException] {
                            Write-Verbose "File in use or access denied: $($item.FullName)"
                            $skippedCount++
                            continue
                        }
                        catch {
                            # Other errors - might be in use
                            Write-Verbose "Cannot access file: $($item.FullName)"
                            $skippedCount++
                            continue
                        }
                    }

                    $itemSize = if ($item.PSIsContainer) {
                        $childSize = (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                        if ($null -eq $childSize) { 0 } else { $childSize }
                    } else {
                        $item.Length
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove temporary file/folder")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module $LocationName -ErrorAction Stop | Out-Null
                        } else {
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        }

                        $removedCount++
                        $removedSize += $itemSize
                        Write-Verbose "Removed: $($item.FullName) ($itemSize bytes)"
                    }
                }
                catch {
                    $failedCount++
                    $errorMsg = "Failed to remove $($item.FullName): $_"
                    $errors += $errorMsg
                    Write-Verbose $errorMsg
                }
            }
        }
        catch {
            $errorMsg = "Failed to access path $expandedPath`: $_"
            $errors += $errorMsg
            Write-Verbose $errorMsg
        }
    }

    return [PSCustomObject]@{
        RemovedCount = $removedCount
        RemovedSize = $removedSize
        FailedCount = $failedCount
        SkippedCount = $skippedCount
        Errors = $errors
    }
}

#endregion

#region Public Functions

function Clear-WinOpsTempFiles {
    <#
    .SYNOPSIS
        Clears temporary files from Windows locations.

    .DESCRIPTION
        Removes temporary files from specified locations with age filtering and safety checks.

    .PARAMETER Location
        Location to clean. Valid values:
        - UserTemp, SystemTemp, RecentItems, WindowsErrorReporting, MemoryDumps,
          WindowsInstallerCache, WindowsSetupLogs, DownloadedInstallFiles, TempInternetFiles, All

    .PARAMETER AgeInDays
        Only remove files older than specified days (0 = use default per location).

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion.

    .PARAMETER ExcludePatterns
        File name patterns to exclude (e.g., "*.lock", "*important*").

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsTempFiles -Location UserTemp
        # Clears user temp files older than default age

    .EXAMPLE
        Clear-WinOpsTempFiles -Location All -AgeInDays 30 -UseTrash
        # Clears all temp files older than 30 days with recovery option

    .EXAMPLE
        Clear-WinOpsTempFiles -Location SystemTemp -ExcludePatterns "*.log"
        # Clears system temp except log files
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'UserTemp', 'SystemTemp', 'RecentItems', 'WindowsErrorReporting',
            'MemoryDumps', 'WindowsInstallerCache', 'WindowsSetupLogs',
            'DownloadedInstallFiles', 'TempInternetFiles', 'All'
        )]
        [string]$Location,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    Write-WinOpsLog -Level INFO -Message "Starting temp file cleanup: $Location"

    # Check elevation for locations that require it
    $isElevated = Test-IsElevated

    # Determine locations to clean
    $locationsToClean = if ($Location -eq 'All') {
        $script:TempLocations.Keys
    } else {
        @($Location)
    }

    $results = @()

    foreach ($locationKey in $locationsToClean) {
        $locationInfo = $script:TempLocations[$locationKey]

        # Check elevation requirement
        if ($locationInfo.RequiresElevation -and -not $isElevated) {
            Write-Warning "Skipping $locationKey - requires administrator privileges"
            continue
        }

        Write-Verbose "Processing location: $locationKey - $($locationInfo.Description)"

        # Determine age filter
        $effectiveAge = if ($AgeInDays -gt 0) {
            $AgeInDays
        } else {
            $locationInfo.DefaultAgeInDays
        }

        # Get current file count and size
        $fileInfo = Get-TempFileCount -Paths $locationInfo.Paths -AgeInDays $effectiveAge

        if ($fileInfo.Count -eq 0) {
            Write-Verbose "No temp files found for: $locationKey"
            continue
        }

        Write-Verbose "Found $($fileInfo.Count) items ($([math]::Round($fileInfo.Size / 1MB, 2)) MB) in $locationKey"

        if ($DryRun) {
            $results += [PSCustomObject]@{
                Location = $locationKey
                Description = $locationInfo.Description
                FileCount = $fileInfo.Count
                TotalSize = $fileInfo.Size
                AgeInDays = $effectiveAge
                WouldRemove = $true
                RemovedCount = 0
                RemovedSize = 0
            }
            continue
        }

        # Confirmation
        if (-not $Force -and -not $PSCmdlet.ShouldProcess(
            "$locationKey - $($fileInfo.Count) items ($([math]::Round($fileInfo.Size / 1MB, 2)) MB)",
            "Remove temporary files older than $effectiveAge days"
        )) {
            Write-Verbose "Skipped by user: $locationKey"
            continue
        }

        # Remove files
        $removeResult = Remove-TempFiles `
            -Paths $locationInfo.Paths `
            -AgeInDays $effectiveAge `
            -UseTrash:$UseTrash `
            -LocationName $locationKey `
            -ExcludePatterns $ExcludePatterns

        $results += [PSCustomObject]@{
            Location = $locationKey
            Description = $locationInfo.Description
            FileCount = $fileInfo.Count
            TotalSize = $fileInfo.Size
            AgeInDays = $effectiveAge
            RemovedCount = $removeResult.RemovedCount
            RemovedSize = $removeResult.RemovedSize
            FailedCount = $removeResult.FailedCount
            SkippedCount = $removeResult.SkippedCount
            Errors = $removeResult.Errors
        }

        Write-WinOpsLog -Level INFO -Message "Cleaned $locationKey`: Removed $($removeResult.RemovedCount) items ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
    }

    # Summary
    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Temp file cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1MB, 2)) MB)"

    return $results
}

function Get-WinOpsTempFileInfo {
    <#
    .SYNOPSIS
        Gets information about temporary files without removing them.

    .DESCRIPTION
        Retrieves count and size information for temp file locations.

    .PARAMETER Location
        Location to query. Valid values: UserTemp, SystemTemp, etc., or All.

    .PARAMETER AgeInDays
        Only count files older than specified days.

    .EXAMPLE
        Get-WinOpsTempFileInfo -Location All
        # Shows info for all temp locations

    .EXAMPLE
        Get-WinOpsTempFileInfo -Location UserTemp -AgeInDays 30
        # Shows info for user temp files older than 30 days
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet(
            'UserTemp', 'SystemTemp', 'RecentItems', 'WindowsErrorReporting',
            'MemoryDumps', 'WindowsInstallerCache', 'WindowsSetupLogs',
            'DownloadedInstallFiles', 'TempInternetFiles', 'All'
        )]
        [string]$Location = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0
    )

    $locationsToQuery = if ($Location -eq 'All') {
        $script:TempLocations.Keys
    } else {
        @($Location)
    }

    $results = @()

    foreach ($locationKey in $locationsToQuery) {
        $locationInfo = $script:TempLocations[$locationKey]

        Write-Verbose "Querying location: $locationKey"

        $effectiveAge = if ($AgeInDays -gt 0) { $AgeInDays } else { $locationInfo.DefaultAgeInDays }

        $fileInfo = Get-TempFileCount -Paths $locationInfo.Paths -AgeInDays $effectiveAge

        $results += [PSCustomObject]@{
            Location = $locationKey
            Description = $locationInfo.Description
            FileCount = $fileInfo.Count
            TotalSize = $fileInfo.Size
            TotalSizeMB = [math]::Round($fileInfo.Size / 1MB, 2)
            TotalSizeGB = [math]::Round($fileInfo.Size / 1GB, 2)
            DefaultAgeInDays = $locationInfo.DefaultAgeInDays
            Paths = $locationInfo.Paths
            RequiresElevation = $locationInfo.RequiresElevation
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsTempFiles',
    'Get-WinOpsTempFileInfo'
)
