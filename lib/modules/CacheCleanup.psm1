#Requires -Version 5.1

<#
.SYNOPSIS
    Cache cleanup module for Windows applications and system caches.

.DESCRIPTION
    Cleans various Windows and application caches including:
    - Windows Temp folders (system and user)
    - Browser caches (Chrome, Edge, Firefox)
    - Windows Store cache
    - Windows Update cache
    - Font cache
    - Icon cache
    - Thumbnail cache
    - Prefetch cache

.NOTES
    Module: WinOps.Modules.CacheCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force -Global }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force -Global }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force -Global }
if (-not (Get-Module -Name Trash)) { Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force -Global }

# Import I18n module
$i18nModulePath = Join-Path $coreModulePath 'I18n.psm1'
if ((Test-Path $i18nModulePath) -and -not (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue)) {
    Import-Module $i18nModulePath -Force -Global -ErrorAction SilentlyContinue
    Initialize-WinOpsI18n -ErrorAction SilentlyContinue
}

#region Cache Locations

$script:CacheLocations = @{
    WindowsTemp = @{
        Paths = @(
            "$env:SystemRoot\Temp",
            "$env:TEMP",
            "$env:TMP"
        )
        Description = "Windows temporary files"
        SafetyLevel = "Normal"
    }

    ChromeCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
        )
        Description = "Google Chrome cache"
        SafetyLevel = "Normal"
    }

    EdgeCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
        )
        Description = "Microsoft Edge cache"
        SafetyLevel = "Normal"
    }

    FirefoxCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\startupCache"
        )
        Description = "Mozilla Firefox cache"
        SafetyLevel = "Normal"
    }

    WindowsStoreCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Packages\*\LocalCache",
            "$env:LOCALAPPDATA\Packages\*\AC\INetCache",
            "$env:LOCALAPPDATA\Packages\*\AC\INetCookies"
        )
        Description = "Windows Store app cache"
        SafetyLevel = "Normal"
    }

    ThumbnailCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
        )
        Description = "Windows thumbnail cache"
        SafetyLevel = "Normal"
    }

    IconCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\IconCache.db",
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
        )
        Description = "Windows icon cache"
        SafetyLevel = "Normal"
    }

    FontCache = @{
        Paths = @(
            "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache"
        )
        Description = "Windows font cache"
        SafetyLevel = "Strict"
    }

    Prefetch = @{
        Paths = @(
            "$env:SystemRoot\Prefetch\*.pf"
        )
        Description = "Windows prefetch files"
        SafetyLevel = "Normal"
    }

    DeliveryOptimization = @{
        Paths = @(
            "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
        )
        Description = "Windows Update delivery optimization cache"
        SafetyLevel = "Normal"
    }
}

#endregion

#region Private Functions

function Get-CacheSize {
    <#
    .SYNOPSIS
        Calculates total size of files in cache locations.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$AgeInDays = 0
    )

    $totalSize = 0
    $cutoffDate = if ($AgeInDays -gt 0) {
        (Get-Date).AddDays(-$AgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        if ($expandedPath -like '*`**') {
            # Handle wildcard paths
            $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
        } else {
            # Handle direct paths
            if (Test-Path $expandedPath -ErrorAction SilentlyContinue) {
                $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                continue
            }
        }

        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                continue
            }

            if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                continue
            }

            $totalSize += $item.Length
        }
    }

    return $totalSize
}

function Remove-CacheFiles {
    <#
    .SYNOPSIS
        Removes cache files from specified paths.
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
        [string]$CacheName
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
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
                # Handle wildcard paths (files)
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction Stop
            } else {
                # Handle direct paths (directories)
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
                        continue
                    }

                    $itemSize = if ($item.PSIsContainer) {
                        (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                    } else {
                        $item.Length
                    }

                    # Safety check: verify path is safe to delete
                    if (-not (Test-WinOpsPathSafe -Path $item.FullName)) {
                        Write-Verbose "Skipping protected path: $($item.FullName)"
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove cache item")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module $CacheName -ErrorAction Stop | Out-Null
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
                    $errors += "Failed to remove $($item.FullName): $_"
                    Write-Warning "Failed to remove $($item.FullName): $_"
                }
            }
        }
        catch {
            Write-Warning "Failed to access path $expandedPath`: $_"
        }
    }

    return [PSCustomObject]@{
        RemovedCount = $removedCount
        RemovedSize = $removedSize
        FailedCount = $failedCount
        Errors = $errors
    }
}

#endregion

#region Public Functions

function Clear-WinOpsCache {
    <#
    .SYNOPSIS
        Clears specified Windows and application caches.

    .DESCRIPTION
        Removes cache files from specified cache locations with safety checks and optional trash recovery.

    .PARAMETER CacheType
        Type of cache to clear. Valid values:
        - WindowsTemp, ChromeCache, EdgeCache, FirefoxCache, WindowsStoreCache,
          ThumbnailCache, IconCache, FontCache, Prefetch, DeliveryOptimization, All

    .PARAMETER AgeInDays
        Only remove cache files older than specified days (0 = all files).

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion (allows 72-hour recovery).

    .PARAMETER DryRun
        Show what would be removed without actually removing files.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsCache -CacheType WindowsTemp
        # Clears Windows temp folders

    .EXAMPLE
        Clear-WinOpsCache -CacheType All -AgeInDays 30 -UseTrash
        # Clears all caches older than 30 days with trash recovery

    .EXAMPLE
        Clear-WinOpsCache -CacheType ChromeCache -DryRun
        # Shows what Chrome cache files would be removed
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet(
            'WindowsTemp', 'ChromeCache', 'EdgeCache', 'FirefoxCache',
            'WindowsStoreCache', 'ThumbnailCache', 'IconCache', 'FontCache',
            'Prefetch', 'DeliveryOptimization', 'All'
        )]
        [string]$CacheType = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
        Get-WinOpsMessage -Key 'Cache_Starting' -Args $CacheType, $AgeInDays
    } else {
        "Starting cache cleanup: $CacheType (Age: $AgeInDays days)"
    }
    Write-WinOpsLog -Level INFO -Message $msg

    # Determine which caches to clean
    $cachesToClean = if ($CacheType -eq 'All') {
        $script:CacheLocations.Keys
    } else {
        @($CacheType)
    }

    $results = @()

    foreach ($cacheKey in $cachesToClean) {
        $cacheInfo = $script:CacheLocations[$cacheKey]

        Write-Verbose "Processing cache: $cacheKey - $($cacheInfo.Description)"

        # Calculate current size
        $currentSize = Get-CacheSize -Paths $cacheInfo.Paths -AgeInDays $AgeInDays

        if ($currentSize -eq 0) {
            Write-Verbose "No cache files found for: $cacheKey"
            continue
        }

        Write-Verbose "Cache size: $cacheKey = $([math]::Round($currentSize / 1MB, 2)) MB"

        if ($DryRun) {
            $results += [PSCustomObject]@{
                CacheType = $cacheKey
                Description = $cacheInfo.Description
                CurrentSize = $currentSize
                WouldRemove = $true
                RemovedCount = 0
                RemovedSize = 0
                FailedCount = 0
            }
            continue
        }

        # Confirmation for interactive mode
        if (-not $Force -and -not $PSCmdlet.ShouldProcess(
            "$cacheKey ($([math]::Round($currentSize / 1MB, 2)) MB)",
            "Clear cache"
        )) {
            Write-Verbose "Skipped by user: $cacheKey"
            continue
        }

        # Remove cache files
        $removeResult = Remove-CacheFiles `
            -Paths $cacheInfo.Paths `
            -AgeInDays $AgeInDays `
            -UseTrash:$UseTrash `
            -CacheName $cacheKey

        $results += [PSCustomObject]@{
            CacheType = $cacheKey
            Description = $cacheInfo.Description
            CurrentSize = $currentSize
            RemovedCount = $removeResult.RemovedCount
            RemovedSize = $removeResult.RemovedSize
            FailedCount = $removeResult.FailedCount
            Errors = $removeResult.Errors
        }

        $cleanedMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Cache_Cleaned' -Args $cacheKey, $removeResult.RemovedCount, ([math]::Round($removeResult.RemovedSize / 1MB, 2))
        } else {
            "Cleaned $cacheKey`: Removed $($removeResult.RemovedCount) items ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
        }
        Write-WinOpsLog -Level INFO -Message $cleanedMsg
    }

    # Summary
    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    $completeMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
        Get-WinOpsMessage -Key 'Cache_Complete' -Args $totalCount, ([math]::Round($totalRemoved / 1MB, 2))
    } else {
        "Cache cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1MB, 2)) MB)"
    }
    Write-WinOpsLog -Level INFO -Message $completeMsg

    return $results
}

function Get-WinOpsCacheInfo {
    <#
    .SYNOPSIS
        Gets information about cache sizes without removing them.

    .DESCRIPTION
        Retrieves size and file count information for specified cache locations.

    .PARAMETER CacheType
        Type of cache to query. Valid values: WindowsTemp, ChromeCache, etc., or All.

    .PARAMETER AgeInDays
        Only count cache files older than specified days.

    .EXAMPLE
        Get-WinOpsCacheInfo -CacheType All
        # Shows size of all cache locations

    .EXAMPLE
        Get-WinOpsCacheInfo -CacheType WindowsTemp -AgeInDays 30
        # Shows size of temp files older than 30 days
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet(
            'WindowsTemp', 'ChromeCache', 'EdgeCache', 'FirefoxCache',
            'WindowsStoreCache', 'ThumbnailCache', 'IconCache', 'FontCache',
            'Prefetch', 'DeliveryOptimization', 'All'
        )]
        [string]$CacheType = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0
    )

    $cachesToQuery = if ($CacheType -eq 'All') {
        $script:CacheLocations.Keys
    } else {
        @($CacheType)
    }

    $results = @()

    foreach ($cacheKey in $cachesToQuery) {
        $cacheInfo = $script:CacheLocations[$cacheKey]

        Write-Verbose "Querying cache: $cacheKey"

        $size = Get-CacheSize -Paths $cacheInfo.Paths -AgeInDays $AgeInDays

        $results += [PSCustomObject]@{
            CacheType = $cacheKey
            Description = $cacheInfo.Description
            TotalSize = $size
            TotalSizeMB = [math]::Round($size / 1MB, 2)
            TotalSizeGB = [math]::Round($size / 1GB, 2)
            Paths = $cacheInfo.Paths
            SafetyLevel = $cacheInfo.SafetyLevel
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

function Optimize-WinOpsIconCache {
    <#
    .SYNOPSIS
        Rebuilds Windows icon cache to fix corrupted or missing icons.

    .DESCRIPTION
        Stops Explorer, deletes icon cache files, and restarts Explorer to rebuild cache.

    .EXAMPLE
        Optimize-WinOpsIconCache
        # Rebuilds icon cache
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param()

    if (-not $PSCmdlet.ShouldProcess("Windows icon cache", "Rebuild")) {
        return $false
    }

    $rebuildMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
        Get-WinOpsMessage -Key 'Cache_IconRebuild'
    } else {
        "Rebuilding icon cache"
    }
    Write-WinOpsLog -Level INFO -Message $rebuildMsg

    try {
        # Safety check: verify Explorer is not protected (should pass for Explorer restart)
        if (Test-WinOpsProcessProtected -ProcessName explorer) {
            Write-Warning "Explorer is marked as protected, but icon cache rebuild requires restart"
        }

        # Stop Explorer
        $stoppingMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Cache_IconStopping'
        } else {
            "Stopping Explorer process..."
        }
        Write-Verbose $stoppingMsg
        Stop-Process -Name explorer -Force -ErrorAction Stop
        Start-Sleep -Seconds 2

        # Clear icon cache files
        $iconCachePaths = @(
            "$env:LOCALAPPDATA\IconCache.db",
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db"
        )

        foreach ($path in $iconCachePaths) {
            $expandedPath = [Environment]::ExpandEnvironmentVariables($path)
            $files = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue

            foreach ($file in $files) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Verbose "Removed: $($file.FullName)"
                }
                catch {
                    Write-Warning "Failed to remove $($file.FullName): $_"
                }
            }
        }

        # Restart Explorer
        $restartingMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Cache_IconRestarting'
        } else {
            "Restarting Explorer..."
        }
        Write-Verbose $restartingMsg
        Start-Process explorer.exe

        $successMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Cache_IconSuccess'
        } else {
            "Icon cache rebuilt successfully"
        }
        Write-WinOpsLog -Level INFO -Message $successMsg
        return $true
    }
    catch {
        $failedMsg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'Cache_IconFailed'
        } else {
            "Failed to rebuild icon cache"
        }
        Write-WinOpsLog -Level ERROR -Message $failedMsg -Exception $_
        return $false
    }
}

#endregion

function Invoke-WinOpsCacheCleanup {
    <#
    .SYNOPSIS
        Main execution function for cache cleanup operations.

    .DESCRIPTION
        Convenience wrapper for Clear-WinOpsCache with commonly used parameters.
        Cleans Windows and application caches based on age criteria.

    .PARAMETER AgeInDays
        Only remove cache files older than specified days (default: 7).

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion (allows 72-hour recovery).

    .PARAMETER DryRun
        Show what would be removed without actually removing files.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Invoke-WinOpsCacheCleanup
        # Cleans all caches older than 7 days

    .EXAMPLE
        Invoke-WinOpsCacheCleanup -AgeInDays 30 -UseTrash
        # Cleans caches older than 30 days with recovery option

    .EXAMPLE
        Invoke-WinOpsCacheCleanup -DryRun
        # Preview what would be cleaned
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 7,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    Write-WinOpsLog -Level INFO -Message "Starting cache cleanup operation (Age: $AgeInDays days)"

    # Clean all cache types
    $params = @{
        CacheType = 'All'
        AgeInDays = $AgeInDays
        UseTrash = $UseTrash
        DryRun = $DryRun
        Force = $Force
    }

    if ($PSCmdlet.ShouldProcess) {
        $params['Confirm'] = $false
    }

    $results = Clear-WinOpsCache @params

    # Generate summary
    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    $summary = [PSCustomObject]@{
        TotalItemsRemoved = $totalCount
        TotalSizeRemoved = $totalRemoved
        TotalSizeRemovedMB = [math]::Round($totalRemoved / 1MB, 2)
        TotalSizeRemovedGB = [math]::Round($totalRemoved / 1GB, 2)
        CacheTypesProcessed = $results.Count
        Details = $results
        Timestamp = (Get-Date)
    }

    return $summary
}

function Get-WinOpsCacheTargets {
    <#
    .SYNOPSIS
        Returns list of cache cleanup targets.

    .DESCRIPTION
        Provides detailed information about cache locations that will be targeted
        for cleanup, including paths, descriptions, and current sizes.

    .PARAMETER AgeInDays
        Filter by files older than specified days (default: 7).

    .EXAMPLE
        Get-WinOpsCacheTargets
        # Lists all cache targets with 7-day filter

    .EXAMPLE
        Get-WinOpsCacheTargets -AgeInDays 30 | Format-Table
        # Shows cache targets with 30-day filter in table format
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 7
    )

    Write-Verbose "Retrieving cache cleanup targets (Age filter: $AgeInDays days)"

    # Get cache info for all types
    $cacheInfo = Get-WinOpsCacheInfo -CacheType All -AgeInDays $AgeInDays

    # Enrich with target-specific information
    $targets = foreach ($cache in $cacheInfo) {
        [PSCustomObject]@{
            Name = $cache.CacheType
            Description = $cache.Description
            Paths = $cache.Paths
            CurrentSizeMB = $cache.TotalSizeMB
            CurrentSizeGB = $cache.TotalSizeGB
            SafetyLevel = $cache.SafetyLevel
            AgeFilter = $AgeInDays
            WillCleanup = ($cache.TotalSize -gt 0)
        }
    }

    return $targets | Sort-Object CurrentSizeMB -Descending
}

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsCache',
    'Get-WinOpsCacheInfo',
    'Optimize-WinOpsIconCache',
    'Invoke-WinOpsCacheCleanup',
    'Get-WinOpsCacheTargets'
)
