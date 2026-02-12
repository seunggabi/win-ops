#Requires -Version 5.1

<#
.SYNOPSIS
    Development tools cleanup module for package managers, IDEs, and build caches.

.DESCRIPTION
    Cleans development tool caches:
    - Package managers: npm, yarn, pnpm, pip, NuGet, Maven, Gradle
    - IDEs: VS Code, Visual Studio
    - Optional: node_modules directories (can be very large)

.NOTES
    Module: WinOps.Modules.DevCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force -Global }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force -Global }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force -Global }
if (-not (Get-Module -Name Trash)) { Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force -Global }

#region Cache Target Definitions

$script:DevCacheTargets = @{
    npm = @{
        Name = "npm Cache"
        Path = "$env:APPDATA\npm-cache"
        Description = "Node Package Manager cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "npm cache clean --force"
    }

    yarn = @{
        Name = "Yarn Cache"
        Path = "$env:LOCALAPPDATA\Yarn\Cache"
        Description = "Yarn package manager cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "yarn cache clean"
    }

    pnpm = @{
        Name = "pnpm Cache"
        Path = "$env:LOCALAPPDATA\pnpm-cache"
        Description = "pnpm package manager cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "pnpm store prune"
    }

    pip = @{
        Name = "pip Cache"
        Path = "$env:LOCALAPPDATA\pip\Cache"
        Description = "Python pip package cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "pip cache purge"
    }

    nuget = @{
        Name = "NuGet Cache"
        Path = "$env:LOCALAPPDATA\NuGet\Cache"
        Description = ".NET NuGet package cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "dotnet nuget locals all --clear"
    }

    maven = @{
        Name = "Maven Repository"
        Path = "$env:USERPROFILE\.m2\repository"
        Description = "Maven local repository cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "mvn dependency:purge-local-repository"
    }

    gradle = @{
        Name = "Gradle Cache"
        Path = "$env:USERPROFILE\.gradle\caches"
        Description = "Gradle build cache"
        Category = "PackageManager"
        CanRegenerate = $true
        CommandToRegenerate = "gradle cleanBuildCache"
    }

    vscode = @{
        Name = "VS Code Cache"
        Paths = @(
            "$env:APPDATA\Code\Cache",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\CachedExtensions",
            "$env:APPDATA\Code\CachedExtensionVSIXs"
        )
        Description = "Visual Studio Code cache files"
        Category = "IDE"
        CanRegenerate = $true
        CommandToRegenerate = "Restart VS Code (cache regenerates automatically)"
    }

    visualstudio = @{
        Name = "Visual Studio Cache"
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache",
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\Extensions",
            "$env:TEMP\VCTempBuild*"
        )
        Description = "Visual Studio component and build caches"
        Category = "IDE"
        CanRegenerate = $true
        CommandToRegenerate = "Restart Visual Studio (cache regenerates automatically)"
    }
}

#endregion

#region Private Functions

function Get-CacheSize {
    <#
    .SYNOPSIS
        Calculates total size of cache directory.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $totalSize = 0
    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)

    try {
        if (-not (Test-Path $expandedPath)) {
            return 0
        }

        # Handle wildcard paths
        if ($expandedPath -like '*`**') {
            $items = Get-ChildItem -Path $expandedPath -Directory -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $size = (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($null -ne $size) {
                    $totalSize += $size
                }
            }
        } else {
            $size = (Get-ChildItem -Path $expandedPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($null -ne $size) {
                $totalSize = $size
            }
        }
    }
    catch {
        Write-Verbose "Failed to calculate size for $expandedPath`: $_"
    }

    return $totalSize
}

function Remove-CacheDirectory {
    <#
    .SYNOPSIS
        Removes cache directory with safety checks.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$CacheName
    )

    $removedSize = 0
    $removedCount = 0
    $failedCount = 0
    $errors = @()

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)

    try {
        if (-not (Test-Path $expandedPath)) {
            Write-Verbose "Path does not exist: $expandedPath"
            return [PSCustomObject]@{
                RemovedSize = 0
                RemovedCount = 0
                FailedCount = 0
                Errors = @()
            }
        }

        # Handle wildcard paths (e.g., VisualStudio\*\ComponentModelCache)
        if ($expandedPath -like '*`**') {
            $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
        } else {
            $items = @(Get-Item -Path $expandedPath -Force -ErrorAction SilentlyContinue)
        }

        foreach ($item in $items) {
            try {
                # Calculate size before removal
                $itemSize = if ($item.PSIsContainer) {
                    $childSize = (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                    if ($null -eq $childSize) { 0 } else { $childSize }
                } else {
                    $item.Length
                }

                # Safety check: verify path is safe to delete
                if (-not (Test-WinOpsPathSafe -Path $item.FullName)) {
                    Write-Verbose "Skipping protected path: $($item.FullName)"
                    $failedCount++
                    continue
                }

                if ($PSCmdlet.ShouldProcess($item.FullName, "Remove $CacheName cache")) {
                    if ($UseTrash) {
                        Move-WinOpsToTrash -Path $item.FullName -Module "DevCleanup.$CacheName" -ErrorAction Stop | Out-Null
                    } else {
                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    }

                    $removedSize += $itemSize
                    $removedCount++
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

    return [PSCustomObject]@{
        RemovedSize = $removedSize
        RemovedCount = $removedCount
        FailedCount = $failedCount
        Errors = $errors
    }
}

function Test-ToolInstalled {
    <#
    .SYNOPSIS
        Checks if a development tool is installed by checking cache existence.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CacheTarget
    )

    if ($CacheTarget.ContainsKey('Paths')) {
        # Multiple paths - check if any exist
        foreach ($path in $CacheTarget.Paths) {
            $expandedPath = [Environment]::ExpandEnvironmentVariables($path)
            if ($expandedPath -like '*`**') {
                # Wildcard path
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
                if ($items) {
                    return $true
                }
            } elseif (Test-Path $expandedPath) {
                return $true
            }
        }
        return $false
    } else {
        # Single path
        $expandedPath = [Environment]::ExpandEnvironmentVariables($CacheTarget.Path)
        return (Test-Path $expandedPath)
    }
}

#endregion

#region Public Functions

function Get-WinOpsDevCacheTargets {
    <#
    .SYNOPSIS
        Gets information about all development tool cache targets.

    .DESCRIPTION
        Retrieves size and status information for all configured development caches.

    .PARAMETER Category
        Filter by category: PackageManager, IDE, or All

    .PARAMETER IncludeEmpty
        Include cache targets that don't exist or are empty

    .EXAMPLE
        Get-WinOpsDevCacheTargets
        # Shows all cache targets with sizes

    .EXAMPLE
        Get-WinOpsDevCacheTargets -Category PackageManager
        # Shows only package manager caches
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('PackageManager', 'IDE', 'All')]
        [string]$Category = 'All',

        [Parameter()]
        [switch]$IncludeEmpty
    )

    $results = @()

    foreach ($key in $script:DevCacheTargets.Keys) {
        $target = $script:DevCacheTargets[$key]

        if ($Category -ne 'All' -and $target.Category -ne $Category) {
            continue
        }

        $isInstalled = Test-ToolInstalled -CacheTarget $target

        if (-not $isInstalled -and -not $IncludeEmpty) {
            continue
        }

        # Calculate total size
        $totalSize = 0
        if ($target.ContainsKey('Paths')) {
            foreach ($path in $target.Paths) {
                $totalSize += Get-CacheSize -Path $path
            }
        } else {
            $totalSize = Get-CacheSize -Path $target.Path
        }

        if ($totalSize -eq 0 -and -not $IncludeEmpty) {
            continue
        }

        $results += [PSCustomObject]@{
            Key = $key
            Name = $target.Name
            Description = $target.Description
            Category = $target.Category
            TotalSize = $totalSize
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
            TotalSizeGB = [math]::Round($totalSize / 1GB, 3)
            Installed = $isInstalled
            CanRegenerate = $target.CanRegenerate
            RegenerateCommand = $target.CommandToRegenerate
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

function Invoke-WinOpsDevCleanup {
    <#
    .SYNOPSIS
        Cleans development tool caches.

    .DESCRIPTION
        Removes cache files from specified development tools with safety checks.

    .PARAMETER Target
        Cache target to clean. Use Get-WinOpsDevCacheTargets to see available targets.
        Special value 'All' cleans all available caches.

    .PARAMETER Category
        Clean all caches in a category: PackageManager or IDE

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion.

    .PARAMETER Force
        Bypass confirmation prompts.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .EXAMPLE
        Invoke-WinOpsDevCleanup -Target npm
        # Cleans npm cache

    .EXAMPLE
        Invoke-WinOpsDevCleanup -Category PackageManager -UseTrash
        # Cleans all package manager caches with recovery option

    .EXAMPLE
        Invoke-WinOpsDevCleanup -Target All -DryRun
        # Shows what would be cleaned without removing anything
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ParameterSetName = 'ByTarget')]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @('All') + $script:DevCacheTargets.Keys | Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string]$Target,

        [Parameter(ParameterSetName = 'ByCategory')]
        [ValidateSet('PackageManager', 'IDE')]
        [string]$Category,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DryRun
    )

    Write-WinOpsLog -Level INFO -Message "Starting development cache cleanup"

    # Determine targets to clean
    $targetsToClean = @()

    if ($PSCmdlet.ParameterSetName -eq 'ByTarget') {
        if ($Target -eq 'All') {
            $targetsToClean = $script:DevCacheTargets.Keys
        } elseif ($script:DevCacheTargets.ContainsKey($Target)) {
            $targetsToClean = @($Target)
        } else {
            Write-Error "Unknown target: $Target. Use Get-WinOpsDevCacheTargets to see available targets."
            return
        }
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByCategory') {
        $targetsToClean = $script:DevCacheTargets.Keys | Where-Object {
            $script:DevCacheTargets[$_].Category -eq $Category
        }
    } else {
        Write-Error "Must specify either -Target or -Category parameter"
        return
    }

    $results = @()

    foreach ($targetKey in $targetsToClean) {
        $targetInfo = $script:DevCacheTargets[$targetKey]

        Write-Verbose "Processing: $($targetInfo.Name)"

        # Check if tool is installed
        $isInstalled = Test-ToolInstalled -CacheTarget $targetInfo

        if (-not $isInstalled) {
            Write-Verbose "$($targetInfo.Name) not found (not installed or already clean)"
            continue
        }

        # Calculate current size
        $currentSize = 0
        $paths = if ($targetInfo.ContainsKey('Paths')) {
            $targetInfo.Paths
        } else {
            @($targetInfo.Path)
        }

        foreach ($path in $paths) {
            $currentSize += Get-CacheSize -Path $path
        }

        if ($currentSize -eq 0) {
            Write-Verbose "$($targetInfo.Name) is empty"
            continue
        }

        Write-Verbose "Cache size: $($targetInfo.Name) = $([math]::Round($currentSize / 1MB, 2)) MB"

        if ($DryRun) {
            $results += [PSCustomObject]@{
                Target = $targetInfo.Name
                Category = $targetInfo.Category
                Description = $targetInfo.Description
                CurrentSize = $currentSize
                CurrentSizeMB = [math]::Round($currentSize / 1MB, 2)
                WouldRemove = $true
                RemovedCount = 0
                RemovedSize = 0
                RegenerateCommand = $targetInfo.CommandToRegenerate
            }
            continue
        }

        # Confirmation
        if (-not $Force -and -not $PSCmdlet.ShouldProcess(
            "$($targetInfo.Name) ($([math]::Round($currentSize / 1MB, 2)) MB)",
            "Clear cache"
        )) {
            Write-Verbose "Skipped by user: $($targetInfo.Name)"
            continue
        }

        # Remove cache
        $totalRemoved = 0
        $totalRemovedSize = 0
        $totalFailed = 0
        $allErrors = @()

        foreach ($path in $paths) {
            $removeResult = Remove-CacheDirectory `
                -Path $path `
                -UseTrash:$UseTrash `
                -CacheName $targetInfo.Name

            $totalRemoved += $removeResult.RemovedCount
            $totalRemovedSize += $removeResult.RemovedSize
            $totalFailed += $removeResult.FailedCount
            $allErrors += $removeResult.Errors
        }

        $results += [PSCustomObject]@{
            Target = $targetInfo.Name
            Category = $targetInfo.Category
            Description = $targetInfo.Description
            CurrentSize = $currentSize
            CurrentSizeMB = [math]::Round($currentSize / 1MB, 2)
            RemovedCount = $totalRemoved
            RemovedSize = $totalRemovedSize
            RemovedSizeMB = [math]::Round($totalRemovedSize / 1MB, 2)
            FailedCount = $totalFailed
            Errors = $allErrors
            RegenerateCommand = $targetInfo.CommandToRegenerate
        }

        Write-WinOpsLog -Level INFO -Message "Cleaned $($targetInfo.Name): Removed $totalRemoved items ($([math]::Round($totalRemovedSize / 1MB, 2)) MB)"
    }

    # Summary
    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    if ($DryRun) {
        $potentialSavings = ($results | Measure-Object -Property CurrentSize -Sum).Sum
        Write-WinOpsLog -Level INFO -Message "Development cache cleanup (DRY RUN): Would remove $($results.Count) cache types ($([math]::Round($potentialSavings / 1MB, 2)) MB)"
    } else {
        Write-WinOpsLog -Level INFO -Message "Development cache cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1MB, 2)) MB)"
    }

    return $results
}

function Find-WinOpsNodeModules {
    <#
    .SYNOPSIS
        Finds large node_modules directories in the system.

    .DESCRIPTION
        Scans specified paths for node_modules directories and reports their sizes.
        Useful for identifying space-consuming JavaScript project dependencies.

    .PARAMETER Path
        Path to scan for node_modules. Defaults to user profile.

    .PARAMETER MinSizeMB
        Minimum size threshold in MB to report (default: 100 MB)

    .PARAMETER MaxDepth
        Maximum directory depth to scan (default: 5)

    .PARAMETER TopN
        Return only top N largest directories (default: 20)

    .EXAMPLE
        Find-WinOpsNodeModules
        # Finds large node_modules in user profile

    .EXAMPLE
        Find-WinOpsNodeModules -Path "C:\Projects" -MinSizeMB 500
        # Finds node_modules larger than 500 MB in Projects folder

    .EXAMPLE
        Find-WinOpsNodeModules -TopN 10
        # Returns top 10 largest node_modules directories
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$Path = $env:USERPROFILE,

        [Parameter()]
        [int]$MinSizeMB = 100,

        [Parameter()]
        [int]$MaxDepth = 5,

        [Parameter()]
        [int]$TopN = 20
    )

    Write-WinOpsLog -Level INFO -Message "Scanning for node_modules directories in: $Path"

    $results = @()
    $scanQueue = [System.Collections.Generic.Queue[PSCustomObject]]::new()
    $scanQueue.Enqueue([PSCustomObject]@{ Path = $Path; Depth = 0 })

    while ($scanQueue.Count -gt 0) {
        $current = $scanQueue.Dequeue()

        if ($current.Depth -ge $MaxDepth) {
            continue
        }

        try {
            $directories = Get-ChildItem -Path $current.Path -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) }

            foreach ($dir in $directories) {
                if ($dir.Name -eq 'node_modules') {
                    # Found node_modules - calculate size
                    Write-Verbose "Found node_modules: $($dir.FullName)"

                    $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum

                    if ($null -eq $size) { $size = 0 }

                    $sizeMB = [math]::Round($size / 1MB, 2)

                    if ($sizeMB -ge $MinSizeMB) {
                        $results += [PSCustomObject]@{
                            Path = $dir.FullName
                            ParentProject = Split-Path $dir.FullName -Parent
                            Size = $size
                            SizeMB = $sizeMB
                            SizeGB = [math]::Round($size / 1GB, 3)
                            LastModified = $dir.LastWriteTime
                        }
                    }

                    # Don't recurse into node_modules
                    continue
                }

                # Add directory to scan queue
                $scanQueue.Enqueue([PSCustomObject]@{
                    Path = $dir.FullName
                    Depth = $current.Depth + 1
                })
            }
        }
        catch {
            Write-Verbose "Failed to scan $($current.Path): $_"
        }
    }

    Write-WinOpsLog -Level INFO -Message "Found $($results.Count) node_modules directories"

    return $results |
        Sort-Object Size -Descending |
        Select-Object -First $TopN
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-WinOpsDevCacheTargets',
    'Invoke-WinOpsDevCleanup',
    'Find-WinOpsNodeModules'
)
