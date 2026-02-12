#Requires -Version 5.1

<#
.SYNOPSIS
    Orphaned application data cleanup module.

.DESCRIPTION
    Cleans up leftover data from uninstalled applications:
    - Registry entries for uninstalled apps
    - AppData folders from removed apps
    - Program Files remnants
    - Start Menu shortcuts
    - Desktop shortcuts
    - Temporary installation files

.NOTES
    Module: WinOps.Modules.OrphanAppCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force -Global }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force -Global }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force -Global }
if (-not (Get-Module -Name Trash)) { Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force -Global }

#region Private Functions

function Get-InstalledApplications {
    <#
    .SYNOPSIS
        Gets list of installed applications from registry.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $installedApps = @()

    # Check both 64-bit and 32-bit registry paths
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object -ExpandProperty DisplayName

            $installedApps += $apps
        }
        catch {
            Write-Verbose "Failed to query registry path: $path"
        }
    }

    return $installedApps | Select-Object -Unique
}

function Find-OrphanedAppDataFolders {
    <#
    .SYNOPSIS
        Finds AppData folders that don't match installed applications.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$InstalledApps,

        [Parameter()]
        [int]$MinAgeInDays = 30
    )

    $orphanedFolders = @()
    $cutoffDate = (Get-Date).AddDays(-$MinAgeInDays)

    $appDataPaths = @(
        "$env:LOCALAPPDATA",
        "$env:APPDATA",
        "$env:ProgramData"
    )

    foreach ($basePath in $appDataPaths) {
        if (-not (Test-Path $basePath)) {
            continue
        }

        try {
            $folders = Get-ChildItem -Path $basePath -Directory -Force -ErrorAction SilentlyContinue

            foreach ($folder in $folders) {
                # Skip system folders
                $systemFolders = @(
                    'Microsoft', 'Windows', 'Temp', 'Package Cache', 'Packages',
                    'Local', 'LocalLow', 'Roaming', 'Application Data'
                )

                if ($folder.Name -in $systemFolders) {
                    continue
                }

                # Check age
                if ($folder.LastWriteTime -gt $cutoffDate) {
                    continue
                }

                # Check if folder name matches any installed app
                $matchesInstalledApp = $false
                foreach ($app in $InstalledApps) {
                    # Normalize names for comparison
                    $appName = $app -replace '[^\w\s]', ''
                    $folderName = $folder.Name -replace '[^\w\s]', ''

                    if ($folderName -like "*$appName*" -or $appName -like "*$folderName*") {
                        $matchesInstalledApp = $true
                        break
                    }
                }

                if (-not $matchesInstalledApp) {
                    # Calculate folder size
                    $size = 0
                    try {
                        $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                        if ($null -eq $size) { $size = 0 }
                    }
                    catch {
                        $size = 0
                    }

                    $orphanedFolders += [PSCustomObject]@{
                        Path = $folder.FullName
                        Name = $folder.Name
                        Location = $basePath
                        LastModified = $folder.LastWriteTime
                        SizeMB = [math]::Round($size / 1MB, 2)
                        AgeInDays = [math]::Round(((Get-Date) - $folder.LastWriteTime).TotalDays, 1)
                    }
                }
            }
        }
        catch {
            Write-Verbose "Error scanning $basePath`: $_"
        }
    }

    return $orphanedFolders
}

function Find-OrphanedShortcuts {
    <#
    .SYNOPSIS
        Finds shortcuts pointing to non-existent targets.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphanedShortcuts = @()

    $shortcutLocations = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu",
        "$env:ProgramData\Microsoft\Windows\Start Menu",
        "$env:USERPROFILE\Desktop",
        "$env:PUBLIC\Desktop"
    )

    $shell = New-Object -ComObject WScript.Shell

    foreach ($location in $shortcutLocations) {
        if (-not (Test-Path $location)) {
            continue
        }

        try {
            $shortcuts = Get-ChildItem -Path $location -Recurse -Filter "*.lnk" -Force -ErrorAction SilentlyContinue

            foreach ($shortcut in $shortcuts) {
                try {
                    $link = $shell.CreateShortcut($shortcut.FullName)
                    $targetPath = $link.TargetPath

                    # Check if target exists
                    if ($targetPath -and -not (Test-Path $targetPath)) {
                        $orphanedShortcuts += [PSCustomObject]@{
                            ShortcutPath = $shortcut.FullName
                            ShortcutName = $shortcut.Name
                            TargetPath = $targetPath
                            Location = $location
                            LastModified = $shortcut.LastWriteTime
                        }
                    }
                }
                catch {
                    Write-Verbose "Failed to check shortcut: $($shortcut.FullName)"
                }
            }
        }
        catch {
            Write-Verbose "Error scanning shortcuts in $location`: $_"
        }
    }

    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

    return $orphanedShortcuts
}

function Find-OrphanedProgramFiles {
    <#
    .SYNOPSIS
        Finds leftover folders in Program Files that don't match installed apps.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$InstalledApps,

        [Parameter()]
        [int]$MinAgeInDays = 90
    )

    $orphanedFolders = @()
    $cutoffDate = (Get-Date).AddDays(-$MinAgeInDays)

    $programFilesPaths = @(
        "${env:ProgramFiles}",
        "${env:ProgramFiles(x86)}"
    )

    foreach ($basePath in $programFilesPaths) {
        if (-not (Test-Path $basePath)) {
            continue
        }

        try {
            $folders = Get-ChildItem -Path $basePath -Directory -Force -ErrorAction SilentlyContinue

            foreach ($folder in $folders) {
                # Skip common system folders
                $systemFolders = @(
                    'Windows Defender', 'Windows NT', 'WindowsPowerShell', 'Microsoft',
                    'Common Files', 'Internet Explorer', 'Windows Mail', 'Windows Media Player'
                )

                if ($folder.Name -in $systemFolders) {
                    continue
                }

                # Check age
                if ($folder.LastWriteTime -gt $cutoffDate) {
                    continue
                }

                # Check if folder matches any installed app
                $matchesInstalledApp = $false
                foreach ($app in $InstalledApps) {
                    $appName = $app -replace '[^\w\s]', ''
                    $folderName = $folder.Name -replace '[^\w\s]', ''

                    if ($folderName -like "*$appName*" -or $appName -like "*$folderName*") {
                        $matchesInstalledApp = $true
                        break
                    }
                }

                if (-not $matchesInstalledApp) {
                    # Calculate folder size
                    $size = 0
                    try {
                        $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                        if ($null -eq $size) { $size = 0 }
                    }
                    catch {
                        $size = 0
                    }

                    $orphanedFolders += [PSCustomObject]@{
                        Path = $folder.FullName
                        Name = $folder.Name
                        Location = $basePath
                        LastModified = $folder.LastWriteTime
                        SizeMB = [math]::Round($size / 1MB, 2)
                        AgeInDays = [math]::Round(((Get-Date) - $folder.LastWriteTime).TotalDays, 1)
                    }
                }
            }
        }
        catch {
            Write-Verbose "Error scanning $basePath`: $_"
        }
    }

    return $orphanedFolders
}

#endregion

#region Public Functions

function Find-WinOpsOrphanedAppData {
    <#
    .SYNOPSIS
        Finds orphaned application data from uninstalled applications.

    .DESCRIPTION
        Scans for leftover data including AppData folders, Program Files remnants, and broken shortcuts.

    .PARAMETER DataType
        Type of orphaned data to find:
        - AppData: Orphaned folders in AppData/LocalAppData/ProgramData
        - Shortcuts: Broken shortcuts in Start Menu and Desktop
        - ProgramFiles: Leftover folders in Program Files
        - All: All types

    .PARAMETER MinAgeInDays
        Minimum age in days for data to be considered orphaned (default varies by type).

    .EXAMPLE
        Find-WinOpsOrphanedAppData -DataType All
        # Finds all types of orphaned app data

    .EXAMPLE
        Find-WinOpsOrphanedAppData -DataType AppData -MinAgeInDays 60
        # Finds AppData folders older than 60 days
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AppData', 'Shortcuts', 'ProgramFiles', 'All')]
        [string]$DataType,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$MinAgeInDays = 0
    )

    Write-WinOpsLog -Level INFO -Message "Scanning for orphaned app data: $DataType"

    # Get installed applications
    Write-Verbose "Retrieving list of installed applications..."
    $installedApps = Get-InstalledApplications
    Write-Verbose "Found $($installedApps.Count) installed applications"

    $results = @{
        AppDataFolders = @()
        OrphanedShortcuts = @()
        ProgramFilesFolders = @()
    }

    if ($DataType -in @('AppData', 'All')) {
        $ageInDays = if ($MinAgeInDays -gt 0) { $MinAgeInDays } else { 30 }
        Write-Verbose "Scanning for orphaned AppData folders (age: $ageInDays days)..."
        $results.AppDataFolders = Find-OrphanedAppDataFolders -InstalledApps $installedApps -MinAgeInDays $ageInDays
        Write-Verbose "Found $($results.AppDataFolders.Count) orphaned AppData folders"
    }

    if ($DataType -in @('Shortcuts', 'All')) {
        Write-Verbose "Scanning for orphaned shortcuts..."
        $results.OrphanedShortcuts = Find-OrphanedShortcuts
        Write-Verbose "Found $($results.OrphanedShortcuts.Count) orphaned shortcuts"
    }

    if ($DataType -in @('ProgramFiles', 'All')) {
        $ageInDays = if ($MinAgeInDays -gt 0) { $MinAgeInDays } else { 90 }
        Write-Verbose "Scanning for orphaned Program Files folders (age: $ageInDays days)..."
        $results.ProgramFilesFolders = Find-OrphanedProgramFiles -InstalledApps $installedApps -MinAgeInDays $ageInDays
        Write-Verbose "Found $($results.ProgramFilesFolders.Count) orphaned Program Files folders"
    }

    $totalCount = $results.AppDataFolders.Count + $results.OrphanedShortcuts.Count + $results.ProgramFilesFolders.Count
    $totalSize = ($results.AppDataFolders | Measure-Object -Property SizeMB -Sum).Sum +
                 ($results.ProgramFilesFolders | Measure-Object -Property SizeMB -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Found $totalCount orphaned items ($([math]::Round($totalSize / 1024, 2)) GB)"

    return [PSCustomObject]@{
        AppDataFolders = $results.AppDataFolders
        OrphanedShortcuts = $results.OrphanedShortcuts
        ProgramFilesFolders = $results.ProgramFilesFolders
        TotalCount = $totalCount
        TotalSizeMB = $totalSize
    }
}

function Clear-WinOpsOrphanedAppData {
    <#
    .SYNOPSIS
        Clears orphaned application data.

    .DESCRIPTION
        Removes orphaned AppData folders, shortcuts, and Program Files remnants.

    .PARAMETER DataType
        Type of orphaned data to clean.

    .PARAMETER MinAgeInDays
        Minimum age for data to be cleaned.

    .PARAMETER UseTrash
        Move items to trash instead of permanent deletion.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsOrphanedAppData -DataType Shortcuts -Force
        # Removes all broken shortcuts

    .EXAMPLE
        Clear-WinOpsOrphanedAppData -DataType All -UseTrash -DryRun
        # Shows what would be removed with recovery option
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AppData', 'Shortcuts', 'ProgramFiles', 'All')]
        [string]$DataType,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$MinAgeInDays = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    Write-WinOpsLog -Level INFO -Message "Starting orphaned app data cleanup: $DataType"

    # Find orphaned data
    $orphanedData = Find-WinOpsOrphanedAppData -DataType $DataType -MinAgeInDays $MinAgeInDays

    if ($orphanedData.TotalCount -eq 0) {
        Write-WinOpsLog -Level INFO -Message "No orphaned app data found"
        return [PSCustomObject]@{
            ItemsFound = 0
            ItemsRemoved = 0
            SpaceReclaimedMB = 0
        }
    }

    Write-Host "`nFound orphaned data:"
    Write-Host "  AppData folders: $($orphanedData.AppDataFolders.Count)"
    Write-Host "  Shortcuts: $($orphanedData.OrphanedShortcuts.Count)"
    Write-Host "  Program Files folders: $($orphanedData.ProgramFilesFolders.Count)"
    Write-Host "  Total size: $([math]::Round($orphanedData.TotalSizeMB / 1024, 2)) GB`n"

    if ($DryRun) {
        return [PSCustomObject]@{
            ItemsFound = $orphanedData.TotalCount
            ItemsRemoved = 0
            SpaceReclaimedMB = $orphanedData.TotalSizeMB
            DryRun = $true
        }
    }

    $removedCount = 0
    $spaceReclaimed = 0

    # Remove AppData folders
    if ($orphanedData.AppDataFolders.Count -gt 0) {
        foreach ($folder in $orphanedData.AppDataFolders) {
            # Safety check: verify path is safe to delete
            if (-not (Test-WinOpsPathSafe -Path $folder.Path)) {
                Write-Verbose "Skipping protected path: $($folder.Path)"
                continue
            }

            if ($Force -or $PSCmdlet.ShouldProcess($folder.Path, "Remove orphaned AppData folder")) {
                try {
                    if ($UseTrash) {
                        Move-WinOpsToTrash -Path $folder.Path -Module "OrphanAppCleanup" -ErrorAction Stop | Out-Null
                    } else {
                        Remove-Item -Path $folder.Path -Recurse -Force -ErrorAction Stop
                    }
                    $removedCount++
                    $spaceReclaimed += $folder.SizeMB
                    Write-Verbose "Removed: $($folder.Path)"
                }
                catch {
                    Write-Warning "Failed to remove $($folder.Path): $_"
                }
            }
        }
    }

    # Remove orphaned shortcuts
    if ($orphanedData.OrphanedShortcuts.Count -gt 0) {
        foreach ($shortcut in $orphanedData.OrphanedShortcuts) {
            # Safety check: verify path is safe to delete
            if (-not (Test-WinOpsPathSafe -Path $shortcut.ShortcutPath)) {
                Write-Verbose "Skipping protected path: $($shortcut.ShortcutPath)"
                continue
            }

            if ($Force -or $PSCmdlet.ShouldProcess($shortcut.ShortcutPath, "Remove orphaned shortcut")) {
                try {
                    Remove-Item -Path $shortcut.ShortcutPath -Force -ErrorAction Stop
                    $removedCount++
                    Write-Verbose "Removed shortcut: $($shortcut.ShortcutPath)"
                }
                catch {
                    Write-Warning "Failed to remove shortcut $($shortcut.ShortcutPath): $_"
                }
            }
        }
    }

    # Remove Program Files folders
    if ($orphanedData.ProgramFilesFolders.Count -gt 0) {
        foreach ($folder in $orphanedData.ProgramFilesFolders) {
            # Safety check: verify path is safe to delete
            if (-not (Test-WinOpsPathSafe -Path $folder.Path)) {
                Write-Verbose "Skipping protected path: $($folder.Path)"
                continue
            }

            if ($Force -or $PSCmdlet.ShouldProcess($folder.Path, "Remove orphaned Program Files folder")) {
                try {
                    if ($UseTrash) {
                        Move-WinOpsToTrash -Path $folder.Path -Module "OrphanAppCleanup" -ErrorAction Stop | Out-Null
                    } else {
                        Remove-Item -Path $folder.Path -Recurse -Force -ErrorAction Stop
                    }
                    $removedCount++
                    $spaceReclaimed += $folder.SizeMB
                    Write-Verbose "Removed: $($folder.Path)"
                }
                catch {
                    Write-Warning "Failed to remove $($folder.Path): $_"
                }
            }
        }
    }

    Write-WinOpsLog -Level INFO -Message "Orphaned app data cleanup complete: Removed $removedCount items ($([math]::Round($spaceReclaimed / 1024, 2)) GB)"

    return [PSCustomObject]@{
        ItemsFound = $orphanedData.TotalCount
        ItemsRemoved = $removedCount
        SpaceReclaimedMB = $spaceReclaimed
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Find-WinOpsOrphanedAppData',
    'Clear-WinOpsOrphanedAppData'
)
