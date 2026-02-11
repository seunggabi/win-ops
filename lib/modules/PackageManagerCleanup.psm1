#Requires -Version 5.1

<#
.SYNOPSIS
    Package manager cleanup module for Windows.

.DESCRIPTION
    Cleans package manager caches and old packages:
    - Chocolatey
    - Scoop
    - Winget
    - Windows Update cache
    - Component Store cleanup

.NOTES
    Module: WinOps.Modules.PackageManagerCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force

#region Package Manager Locations

$script:PackageManagers = @{
    Chocolatey = @{
        Name = "Chocolatey"
        CachePaths = @(
            "$env:ProgramData\chocolatey\lib-bad",
            "$env:ProgramData\chocolatey\lib-backup",
            "$env:TEMP\chocolatey"
        )
        Description = "Chocolatey package manager"
        TestCommand = "choco"
    }

    Scoop = @{
        Name = "Scoop"
        CachePaths = @(
            "$env:USERPROFILE\scoop\cache"
        )
        Description = "Scoop package manager"
        TestCommand = "scoop"
    }

    Winget = @{
        Name = "Windows Package Manager"
        CachePaths = @(
            "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalCache"
        )
        Description = "Windows Package Manager (winget)"
        TestCommand = "winget"
    }

    WindowsUpdate = @{
        Name = "Windows Update"
        CachePaths = @(
            "$env:SystemRoot\SoftwareDistribution\Download"
        )
        Description = "Windows Update download cache"
        RequiresElevation = $true
    }

    DISM = @{
        Name = "DISM Logs"
        CachePaths = @(
            "$env:SystemRoot\Logs\DISM"
        )
        Description = "DISM and deployment logs"
        RequiresElevation = $true
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

function Test-PackageManagerInstalled {
    <#
    .SYNOPSIS
        Checks if package manager is installed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$TestCommand
    )

    try {
        $result = Get-Command $TestCommand -ErrorAction SilentlyContinue
        return ($null -ne $result)
    }
    catch {
        return $false
    }
}

function Test-WindowsUpdateActive {
    <#
    .SYNOPSIS
        Checks if Windows Update is currently running.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($null -eq $wuService) {
            return $false
        }

        # Check if service is running
        if ($wuService.Status -ne 'Running') {
            return $false
        }

        # Check for active update sessions
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction SilentlyContinue
        if ($null -ne $updateSession) {
            $updateSearcher = $updateSession.CreateUpdateSearcher()

            # If we can create a searcher and it's not busy, updates are not active
            try {
                $searchResult = $updateSearcher.Search("IsInstalled=0")
                return $false
            }
            catch {
                # If search fails, updates might be installing
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Verbose "Failed to check Windows Update status: $_"
        return $false
    }
}

function Get-PackageManagerCacheSize {
    <#
    .SYNOPSIS
        Calculates package manager cache size.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )

    $totalSize = 0

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        if (-not (Test-Path $expandedPath)) {
            continue
        }

        try {
            $size = (Get-ChildItem -Path $expandedPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum

            if ($null -ne $size) {
                $totalSize += $size
            }
        }
        catch {
            Write-Verbose "Failed to calculate cache size for $expandedPath`: $_"
        }
    }

    return $totalSize
}

function Remove-PackageManagerCache {
    <#
    .SYNOPSIS
        Removes package manager cache files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$ManagerName
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $errors = @()

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        if (-not (Test-Path $expandedPath)) {
            Write-Verbose "Path does not exist: $expandedPath"
            continue
        }

        try {
            $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction Stop

            foreach ($item in $items) {
                try {
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

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove $ManagerName cache")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module "PackageManager.$ManagerName" -ErrorAction Stop | Out-Null
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

function Clear-WinOpsPackageManagerCache {
    <#
    .SYNOPSIS
        Clears package manager caches.

    .DESCRIPTION
        Removes cached files from package managers including Chocolatey, Scoop, Winget, and Windows Update.

    .PARAMETER PackageManager
        Package manager to clean. Valid values: Chocolatey, Scoop, Winget, WindowsUpdate, DISM, All

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsPackageManagerCache -PackageManager Chocolatey
        # Clears Chocolatey cache

    .EXAMPLE
        Clear-WinOpsPackageManagerCache -PackageManager All -UseTrash
        # Clears all package manager caches with recovery option
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Chocolatey', 'Scoop', 'Winget', 'WindowsUpdate', 'DISM', 'All')]
        [string]$PackageManager,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    Write-WinOpsLog -Level INFO -Message "Starting package manager cache cleanup: $PackageManager"

    $isElevated = Test-IsElevated

    $managersToClean = if ($PackageManager -eq 'All') {
        $script:PackageManagers.Keys
    } else {
        @($PackageManager)
    }

    $results = @()

    foreach ($managerKey in $managersToClean) {
        $managerInfo = $script:PackageManagers[$managerKey]

        # Check elevation requirement
        if ($managerInfo.RequiresElevation -and -not $isElevated) {
            Write-Warning "Skipping $($managerInfo.Name) - requires administrator privileges"
            continue
        }

        # Check if Windows Update is active (skip cleaning if it is)
        if ($managerKey -eq 'WindowsUpdate' -and (Test-WindowsUpdateActive)) {
            Write-Warning "Skipping Windows Update cache - updates are currently active"
            continue
        }

        # Check if package manager is installed
        if ($managerInfo.TestCommand) {
            if (-not (Test-PackageManagerInstalled -TestCommand $managerInfo.TestCommand)) {
                Write-Verbose "$($managerInfo.Name) not installed"
                continue
            }
        }

        Write-Verbose "Processing: $($managerInfo.Name)"

        # Calculate cache size
        $cacheSize = Get-PackageManagerCacheSize -Paths $managerInfo.CachePaths

        if ($cacheSize -eq 0) {
            Write-Verbose "No cache found for $($managerInfo.Name)"
            continue
        }

        Write-Verbose "Cache size: $($managerInfo.Name) = $([math]::Round($cacheSize / 1MB, 2)) MB"

        if ($DryRun) {
            $results += [PSCustomObject]@{
                PackageManager = $managerInfo.Name
                Description = $managerInfo.Description
                CacheSize = $cacheSize
                WouldRemove = $true
                RemovedCount = 0
                RemovedSize = 0
            }
            continue
        }

        if (-not $Force -and -not $PSCmdlet.ShouldProcess(
            "$($managerInfo.Name) cache ($([math]::Round($cacheSize / 1MB, 2)) MB)",
            "Clear cache"
        )) {
            Write-Verbose "Skipped by user: $($managerInfo.Name)"
            continue
        }

        # Remove cache
        $removeResult = Remove-PackageManagerCache `
            -Paths $managerInfo.CachePaths `
            -UseTrash:$UseTrash `
            -ManagerName $managerInfo.Name

        $results += [PSCustomObject]@{
            PackageManager = $managerInfo.Name
            Description = $managerInfo.Description
            CacheSize = $cacheSize
            RemovedCount = $removeResult.RemovedCount
            RemovedSize = $removeResult.RemovedSize
            FailedCount = $removeResult.FailedCount
            Errors = $removeResult.Errors
        }

        Write-WinOpsLog -Level INFO -Message "Cleaned $($managerInfo.Name): Removed $($removeResult.RemovedCount) items ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
    }

    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Package manager cache cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1MB, 2)) MB)"

    return $results
}

function Invoke-WinOpsComponentStoreCleanup {
    <#
    .SYNOPSIS
        Runs Windows Component Store cleanup using DISM.

    .DESCRIPTION
        Uses DISM to clean up superseded components and reduce WinSxS folder size.
        Requires administrator privileges.

    .PARAMETER AnalyzeOnly
        Analyze component store without cleaning (show potential savings).

    .PARAMETER ResetBase
        Remove all superseded versions of components (cannot be undone).

    .EXAMPLE
        Invoke-WinOpsComponentStoreCleanup -AnalyzeOnly
        # Shows potential space savings

    .EXAMPLE
        Invoke-WinOpsComponentStoreCleanup
        # Runs standard component store cleanup

    .EXAMPLE
        Invoke-WinOpsComponentStoreCleanup -ResetBase
        # Aggressive cleanup, removes all old component versions
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AnalyzeOnly,

        [Parameter()]
        [switch]$ResetBase
    )

    if (-not (Test-IsElevated)) {
        throw "Component Store cleanup requires administrator privileges"
    }

    Write-WinOpsLog -Level INFO -Message "Starting Component Store cleanup"

    try {
        if ($AnalyzeOnly) {
            Write-Verbose "Analyzing Component Store..."
            $output = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1

            $output | ForEach-Object { Write-Verbose $_ }

            # Parse output for size information
            $sizePattern = "Component Store \(WinSxS\) size : (\d+\.\d+) (GB|MB)"
            $reclaimablePattern = "Size of superseded packages : (\d+\.\d+) (GB|MB)"

            $size = 0
            $reclaimable = 0

            foreach ($line in $output) {
                if ($line -match $sizePattern) {
                    $size = [double]$matches[1]
                    if ($matches[2] -eq "GB") {
                        $size *= 1GB
                    } else {
                        $size *= 1MB
                    }
                }
                if ($line -match $reclaimablePattern) {
                    $reclaimable = [double]$matches[1]
                    if ($matches[2] -eq "GB") {
                        $reclaimable *= 1GB
                    } else {
                        $reclaimable *= 1MB
                    }
                }
            }

            return [PSCustomObject]@{
                Operation = "Analyze"
                ComponentStoreSize = $size
                ReclaimableSpace = $reclaimable
                Success = $true
            }
        }

        if ($ResetBase) {
            if (-not $PSCmdlet.ShouldProcess("Component Store", "Reset base (remove all superseded components)")) {
                return [PSCustomObject]@{
                    Operation = "ResetBase"
                    Success = $false
                    Message = "Cancelled by user"
                }
            }

            Write-Warning "Running DISM /ResetBase - this cannot be undone!"
            Write-Verbose "Starting Component Store reset..."

            $output = & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
            $exitCode = $LASTEXITCODE

            $output | ForEach-Object { Write-Verbose $_ }

            if ($exitCode -eq 0) {
                Write-WinOpsLog -Level INFO -Message "Component Store reset completed successfully"
                return [PSCustomObject]@{
                    Operation = "ResetBase"
                    Success = $true
                    ExitCode = $exitCode
                    Message = "Component Store reset completed"
                }
            } else {
                throw "DISM ResetBase failed with exit code: $exitCode"
            }
        } else {
            if (-not $PSCmdlet.ShouldProcess("Component Store", "Clean up superseded components")) {
                return [PSCustomObject]@{
                    Operation = "Cleanup"
                    Success = $false
                    Message = "Cancelled by user"
                }
            }

            Write-Verbose "Starting Component Store cleanup..."
            $output = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
            $exitCode = $LASTEXITCODE

            $output | ForEach-Object { Write-Verbose $_ }

            if ($exitCode -eq 0) {
                Write-WinOpsLog -Level INFO -Message "Component Store cleanup completed successfully"
                return [PSCustomObject]@{
                    Operation = "Cleanup"
                    Success = $true
                    ExitCode = $exitCode
                    Message = "Component Store cleanup completed"
                }
            } else {
                throw "DISM cleanup failed with exit code: $exitCode"
            }
        }
    }
    catch {
        Write-WinOpsLog -Level ERROR -Message "Component Store cleanup failed" -Exception $_
        return [PSCustomObject]@{
            Operation = if ($ResetBase) { "ResetBase" } elseif ($AnalyzeOnly) { "Analyze" } else { "Cleanup" }
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-WinOpsPackageManagerInfo {
    <#
    .SYNOPSIS
        Gets information about package manager caches without removing them.

    .DESCRIPTION
        Retrieves cache size information for package managers.

    .PARAMETER PackageManager
        Package manager to query. Valid values: Chocolatey, Scoop, Winget, WindowsUpdate, DISM, All

    .EXAMPLE
        Get-WinOpsPackageManagerInfo -PackageManager All
        # Shows cache sizes for all package managers
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('Chocolatey', 'Scoop', 'Winget', 'WindowsUpdate', 'DISM', 'All')]
        [string]$PackageManager = 'All'
    )

    $managersToQuery = if ($PackageManager -eq 'All') {
        $script:PackageManagers.Keys
    } else {
        @($PackageManager)
    }

    $results = @()

    foreach ($managerKey in $managersToQuery) {
        $managerInfo = $script:PackageManagers[$managerKey]

        # Check if installed
        $isInstalled = if ($managerInfo.TestCommand) {
            Test-PackageManagerInstalled -TestCommand $managerInfo.TestCommand
        } else {
            $true
        }

        if (-not $isInstalled) {
            continue
        }

        Write-Verbose "Querying: $($managerInfo.Name)"

        $cacheSize = Get-PackageManagerCacheSize -Paths $managerInfo.CachePaths

        $results += [PSCustomObject]@{
            PackageManager = $managerInfo.Name
            Description = $managerInfo.Description
            CacheSize = $cacheSize
            CacheSizeMB = [math]::Round($cacheSize / 1MB, 2)
            CacheSizeGB = [math]::Round($cacheSize / 1GB, 2)
            CachePaths = $managerInfo.CachePaths
            Installed = $isInstalled
            RequiresElevation = $managerInfo.RequiresElevation
        }
    }

    return $results | Sort-Object CacheSize -Descending
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsPackageManagerCache',
    'Invoke-WinOpsComponentStoreCleanup',
    'Get-WinOpsPackageManagerInfo'
)
