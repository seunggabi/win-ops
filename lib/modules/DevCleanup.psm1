#Requires -Version 5.1

<#
.SYNOPSIS
    Development environment cleanup module.

.DESCRIPTION
    Cleans development-related caches and build artifacts:
    - Node.js (node_modules, npm cache, yarn cache)
    - Python (__pycache__, pip cache)
    - .NET (NuGet packages, obj/bin folders)
    - Maven/Gradle caches
    - Docker build cache
    - Git repository cleanup
    - IDE caches (VS Code, Visual Studio, IntelliJ)

.NOTES
    Module: WinOps.Modules.DevCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force

#region Dev Tool Locations

$script:DevLocations = @{
    NodeModules = @{
        SearchPaths = @("C:\Users\*\Documents", "C:\Users\*\Projects", "C:\Projects", "D:\Projects")
        Pattern = "node_modules"
        Description = "Node.js dependencies (node_modules)"
        MinAgeInDays = 30
        SafetyLevel = "Normal"
    }

    NpmCache = @{
        Paths = @(
            "$env:APPDATA\npm-cache",
            "$env:LOCALAPPDATA\npm-cache"
        )
        Description = "npm package cache"
        MinAgeInDays = 60
        SafetyLevel = "Normal"
    }

    YarnCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Yarn\Cache",
            "$env:APPDATA\Yarn\Cache"
        )
        Description = "Yarn package cache"
        MinAgeInDays = 60
        SafetyLevel = "Normal"
    }

    PythonCache = @{
        SearchPaths = @("C:\Users\*\Documents", "C:\Users\*\Projects", "C:\Projects", "D:\Projects")
        Pattern = "__pycache__"
        Description = "Python bytecode cache"
        MinAgeInDays = 7
        SafetyLevel = "Normal"
    }

    PipCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\pip\Cache"
        )
        Description = "pip package cache"
        MinAgeInDays = 60
        SafetyLevel = "Normal"
    }

    NuGetCache = @{
        Paths = @(
            "$env:USERPROFILE\.nuget\packages",
            "$env:LOCALAPPDATA\NuGet\Cache"
        )
        Description = "NuGet package cache"
        MinAgeInDays = 90
        SafetyLevel = "Normal"
    }

    DotNetBuildOutput = @{
        SearchPaths = @("C:\Users\*\Documents", "C:\Users\*\Projects", "C:\Projects", "D:\Projects")
        Pattern = @("bin", "obj")
        Description = ".NET build output (bin/obj)"
        MinAgeInDays = 30
        SafetyLevel = "Normal"
    }

    MavenCache = @{
        Paths = @(
            "$env:USERPROFILE\.m2\repository"
        )
        Description = "Maven repository cache"
        MinAgeInDays = 90
        SafetyLevel = "Normal"
    }

    GradleCache = @{
        Paths = @(
            "$env:USERPROFILE\.gradle\caches"
        )
        Description = "Gradle build cache"
        MinAgeInDays = 90
        SafetyLevel = "Normal"
    }

    VSCodeCache = @{
        Paths = @(
            "$env:APPDATA\Code\Cache",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\CachedExtensions"
        )
        Description = "Visual Studio Code cache"
        MinAgeInDays = 30
        SafetyLevel = "Normal"
    }

    VisualStudioCache = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache",
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\Extensions"
        )
        Description = "Visual Studio cache"
        MinAgeInDays = 30
        SafetyLevel = "Strict"
    }

    GitLFS = @{
        Paths = @(
            "$env:LOCALAPPDATA\lfs"
        )
        Description = "Git LFS cache"
        MinAgeInDays = 90
        SafetyLevel = "Normal"
    }
}

#endregion

#region Private Functions

function Find-DevFolders {
    <#
    .SYNOPSIS
        Finds development folders matching pattern.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SearchPaths,

        [Parameter(Mandatory)]
        [string[]]$Pattern,

        [Parameter()]
        [int]$MinAgeInDays = 0,

        [Parameter()]
        [int]$MaxDepth = 5
    )

    $results = @()
    $cutoffDate = if ($MinAgeInDays -gt 0) {
        (Get-Date).AddDays(-$MinAgeInDays)
    } else {
        $null
    }

    foreach ($searchPath in $SearchPaths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($searchPath)

        if (-not (Test-Path $expandedPath)) {
            Write-Verbose "Search path does not exist: $expandedPath"
            continue
        }

        Write-Verbose "Searching in: $expandedPath"

        try {
            # Find matching folders
            $folders = Get-ChildItem -Path $expandedPath -Directory -Recurse -Force -ErrorAction SilentlyContinue -Depth $MaxDepth |
                Where-Object {
                    $folderName = $_.Name
                    $matchesPattern = $false

                    foreach ($p in $Pattern) {
                        if ($folderName -eq $p) {
                            $matchesPattern = $true
                            break
                        }
                    }

                    if (-not $matchesPattern) {
                        return $false
                    }

                    # Check age
                    if ($cutoffDate -and $_.LastWriteTime -gt $cutoffDate) {
                        return $false
                    }

                    return $true
                }

            $results += $folders
        }
        catch {
            Write-Verbose "Error searching $expandedPath`: $_"
        }
    }

    return $results
}

function Get-DevFolderSize {
    <#
    .SYNOPSIS
        Calculates total size of development folders.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo[]]$Folders
    )

    $totalSize = 0
    $totalCount = $Folders.Count

    foreach ($folder in $Folders) {
        try {
            $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum

            if ($null -ne $size) {
                $totalSize += $size
            }
        }
        catch {
            Write-Verbose "Failed to calculate size for $($folder.FullName): $_"
        }
    }

    return @{
        Count = $totalCount
        Size = $totalSize
    }
}

function Remove-DevFolders {
    <#
    .SYNOPSIS
        Removes development folders.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo[]]$Folders,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$LocationName
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $errors = @()

    foreach ($folder in $Folders) {
        try {
            # Calculate size before removal
            $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum

            if ($null -eq $size) {
                $size = 0
            }

            if ($PSCmdlet.ShouldProcess($folder.FullName, "Remove development folder")) {
                if ($UseTrash) {
                    Move-WinOpsToTrash -Path $folder.FullName -Module $LocationName -ErrorAction Stop | Out-Null
                } else {
                    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                }

                $removedCount++
                $removedSize += $size
                Write-Verbose "Removed: $($folder.FullName) ($size bytes)"
            }
        }
        catch {
            $failedCount++
            $errorMsg = "Failed to remove $($folder.FullName): $_"
            $errors += $errorMsg
            Write-Verbose $errorMsg
        }
    }

    return [PSCustomObject]@{
        RemovedCount = $removedCount
        RemovedSize = $removedSize
        FailedCount = $failedCount
        Errors = $errors
    }
}

function Remove-DevCacheFiles {
    <#
    .SYNOPSIS
        Removes files from development cache paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$MinAgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$LocationName
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $errors = @()

    $cutoffDate = if ($MinAgeInDays -gt 0) {
        (Get-Date).AddDays(-$MinAgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        if (-not (Test-Path $expandedPath)) {
            Write-Verbose "Path does not exist: $expandedPath"
            continue
        }

        try {
            $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction Stop

            foreach ($item in $items) {
                try {
                    if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                        continue
                    }

                    $itemSize = if ($item.PSIsContainer) {
                        $childSize = (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                        if ($null -eq $childSize) { 0 } else { $childSize }
                    } else {
                        $item.Length
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove cache item")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module $LocationName -ErrorAction Stop | Out-Null
                        } else {
                            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        }

                        $removedCount++
                        $removedSize += $itemSize
                    }
                }
                catch {
                    $failedCount++
                    $errors += "Failed to remove $($item.FullName): $_"
                }
            }
        }
        catch {
            $errors += "Failed to access $expandedPath`: $_"
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

function Clear-WinOpsDevCache {
    <#
    .SYNOPSIS
        Clears development tool caches and build artifacts.

    .DESCRIPTION
        Removes development caches, node_modules, build outputs, and package caches.

    .PARAMETER Location
        Location to clean. Valid values:
        - NodeModules, NpmCache, YarnCache, PythonCache, PipCache, NuGetCache,
          DotNetBuildOutput, MavenCache, GradleCache, VSCodeCache, VisualStudioCache, GitLFS, All

    .PARAMETER MinAgeInDays
        Only remove items older than specified days (0 = use default per location).

    .PARAMETER UseTrash
        Move items to trash instead of permanent deletion.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .PARAMETER Force
        Bypass confirmation prompts.

    .PARAMETER MaxSearchDepth
        Maximum directory depth to search for folders (default: 5).

    .EXAMPLE
        Clear-WinOpsDevCache -Location NodeModules -MinAgeInDays 60
        # Removes node_modules folders older than 60 days

    .EXAMPLE
        Clear-WinOpsDevCache -Location NpmCache -UseTrash
        # Clears npm cache with recovery option

    .EXAMPLE
        Clear-WinOpsDevCache -Location All -DryRun
        # Shows what would be removed from all dev caches
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'NodeModules', 'NpmCache', 'YarnCache', 'PythonCache', 'PipCache',
            'NuGetCache', 'DotNetBuildOutput', 'MavenCache', 'GradleCache',
            'VSCodeCache', 'VisualStudioCache', 'GitLFS', 'All'
        )]
        [string]$Location,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$MinAgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxSearchDepth = 5
    )

    Write-WinOpsLog -Level INFO -Message "Starting dev cache cleanup: $Location"

    $locationsToClean = if ($Location -eq 'All') {
        $script:DevLocations.Keys
    } else {
        @($Location)
    }

    $results = @()

    foreach ($locationKey in $locationsToClean) {
        $locationInfo = $script:DevLocations[$locationKey]

        Write-Verbose "Processing location: $locationKey - $($locationInfo.Description)"

        $effectiveAge = if ($MinAgeInDays -gt 0) {
            $MinAgeInDays
        } else {
            $locationInfo.MinAgeInDays
        }

        # Handle search-based locations (node_modules, __pycache__, bin/obj)
        if ($locationInfo.SearchPaths) {
            Write-Verbose "Searching for $($locationInfo.Pattern) folders..."

            $folders = Find-DevFolders `
                -SearchPaths $locationInfo.SearchPaths `
                -Pattern $locationInfo.Pattern `
                -MinAgeInDays $effectiveAge `
                -MaxDepth $MaxSearchDepth

            if ($folders.Count -eq 0) {
                Write-Verbose "No folders found for: $locationKey"
                continue
            }

            $folderInfo = Get-DevFolderSize -Folders $folders

            Write-Verbose "Found $($folderInfo.Count) folders ($([math]::Round($folderInfo.Size / 1GB, 2)) GB) for $locationKey"

            if ($DryRun) {
                $results += [PSCustomObject]@{
                    Location = $locationKey
                    Description = $locationInfo.Description
                    FolderCount = $folderInfo.Count
                    TotalSize = $folderInfo.Size
                    MinAgeInDays = $effectiveAge
                    WouldRemove = $true
                    RemovedCount = 0
                    RemovedSize = 0
                }
                continue
            }

            if (-not $Force -and -not $PSCmdlet.ShouldProcess(
                "$locationKey - $($folderInfo.Count) folders ($([math]::Round($folderInfo.Size / 1GB, 2)) GB)",
                "Remove development folders"
            )) {
                Write-Verbose "Skipped by user: $locationKey"
                continue
            }

            $removeResult = Remove-DevFolders `
                -Folders $folders `
                -UseTrash:$UseTrash `
                -LocationName $locationKey

            $results += [PSCustomObject]@{
                Location = $locationKey
                Description = $locationInfo.Description
                FolderCount = $folderInfo.Count
                TotalSize = $folderInfo.Size
                MinAgeInDays = $effectiveAge
                RemovedCount = $removeResult.RemovedCount
                RemovedSize = $removeResult.RemovedSize
                FailedCount = $removeResult.FailedCount
                Errors = $removeResult.Errors
            }

            Write-WinOpsLog -Level INFO -Message "Cleaned $locationKey`: Removed $($removeResult.RemovedCount) folders ($([math]::Round($removeResult.RemovedSize / 1GB, 2)) GB)"
        }
        # Handle path-based locations (npm cache, pip cache, etc.)
        else {
            $removeResult = Remove-DevCacheFiles `
                -Paths $locationInfo.Paths `
                -MinAgeInDays $effectiveAge `
                -UseTrash:$UseTrash `
                -LocationName $locationKey

            if ($removeResult.RemovedCount -eq 0 -and $removeResult.FailedCount -eq 0) {
                Write-Verbose "No cache found for: $locationKey"
                continue
            }

            $results += [PSCustomObject]@{
                Location = $locationKey
                Description = $locationInfo.Description
                MinAgeInDays = $effectiveAge
                RemovedCount = $removeResult.RemovedCount
                RemovedSize = $removeResult.RemovedSize
                FailedCount = $removeResult.FailedCount
                Errors = $removeResult.Errors
            }

            Write-WinOpsLog -Level INFO -Message "Cleaned $locationKey`: Removed $($removeResult.RemovedCount) items ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
        }
    }

    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Dev cache cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1GB, 2)) GB)"

    return $results
}

function Get-WinOpsDevCacheInfo {
    <#
    .SYNOPSIS
        Gets information about development caches without removing them.

    .DESCRIPTION
        Scans and reports on development cache sizes.

    .PARAMETER Location
        Location to query. Valid values: NodeModules, NpmCache, etc., or All.

    .PARAMETER MinAgeInDays
        Only count items older than specified days.

    .PARAMETER MaxSearchDepth
        Maximum directory depth to search.

    .EXAMPLE
        Get-WinOpsDevCacheInfo -Location All
        # Shows sizes for all dev caches

    .EXAMPLE
        Get-WinOpsDevCacheInfo -Location NodeModules -MinAgeInDays 90
        # Shows node_modules folders older than 90 days
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet(
            'NodeModules', 'NpmCache', 'YarnCache', 'PythonCache', 'PipCache',
            'NuGetCache', 'DotNetBuildOutput', 'MavenCache', 'GradleCache',
            'VSCodeCache', 'VisualStudioCache', 'GitLFS', 'All'
        )]
        [string]$Location = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$MinAgeInDays = 0,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxSearchDepth = 5
    )

    $locationsToQuery = if ($Location -eq 'All') {
        $script:DevLocations.Keys
    } else {
        @($Location)
    }

    $results = @()

    foreach ($locationKey in $locationsToQuery) {
        $locationInfo = $script:DevLocations[$locationKey]

        Write-Verbose "Querying: $locationKey"

        $effectiveAge = if ($MinAgeInDays -gt 0) { $MinAgeInDays } else { $locationInfo.MinAgeInDays }

        if ($locationInfo.SearchPaths) {
            $folders = Find-DevFolders `
                -SearchPaths $locationInfo.SearchPaths `
                -Pattern $locationInfo.Pattern `
                -MinAgeInDays $effectiveAge `
                -MaxDepth $MaxSearchDepth

            $folderInfo = Get-DevFolderSize -Folders $folders

            $results += [PSCustomObject]@{
                Location = $locationKey
                Description = $locationInfo.Description
                ItemCount = $folderInfo.Count
                TotalSize = $folderInfo.Size
                TotalSizeMB = [math]::Round($folderInfo.Size / 1MB, 2)
                TotalSizeGB = [math]::Round($folderInfo.Size / 1GB, 2)
                MinAgeInDays = $effectiveAge
            }
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsDevCache',
    'Get-WinOpsDevCacheInfo'
)
