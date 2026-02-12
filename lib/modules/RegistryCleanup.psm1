#Requires -Version 5.1

<#
.SYNOPSIS
    Registry cleanup module for orphaned entries from uninstalled programs.

.DESCRIPTION
    Cleans up Windows registry entries left behind by uninstalled applications:
    - Orphaned Uninstall entries (install path no longer exists)
    - Orphaned SharedDLLs entries (DLL files no longer exist)
    - Orphaned MUICache entries (executables no longer exist)
    - Invalid startup Run/RunOnce entries (targets no longer exist)
    - Orphaned application paths in App Paths registry

    All registry keys are exported as .reg backup files before deletion
    for safety and recoverability.

.NOTES
    Module: WinOps.Modules.RegistryCleanup
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

function Export-RegistryBackup {
    <#
    .SYNOPSIS
        Exports a registry key to a .reg file for backup before deletion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [string]$BackupDir
    )

    try {
        if (-not (Test-Path $BackupDir)) {
            New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeName = ($RegistryPath -replace '[\\/:*?"<>|]', '_')
        $backupFile = Join-Path $BackupDir "reg_backup_${timestamp}_${safeName}.reg"

        # Convert PowerShell registry path to reg.exe format
        $regPath = $RegistryPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                                 -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
                                 -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\'

        $null = & reg export $regPath $backupFile /y 2>$null
        return $backupFile
    }
    catch {
        Write-Verbose "Failed to export registry backup for $RegistryPath : $_"
        return $null
    }
}

function Test-PathExists {
    <#
    .SYNOPSIS
        Safely tests if a file system path exists, expanding environment variables.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    try {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
        # Remove quotes
        $expandedPath = $expandedPath.Trim('"', "'")
        # Handle paths with arguments (e.g., "C:\Program Files\app.exe" /arg)
        if ($expandedPath -match '^"?([^"]+)"?\s') {
            $expandedPath = $Matches[1]
        }
        elseif ($expandedPath -match '^(\S+)\s') {
            $testPath = $Matches[1]
            if (Test-Path $testPath -ErrorAction SilentlyContinue) {
                return $true
            }
        }

        return (Test-Path $expandedPath -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function Find-OrphanedUninstallEntries {
    <#
    .SYNOPSIS
        Finds registry Uninstall entries where InstallLocation no longer exists.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphans = @()

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($basePath in $uninstallPaths) {
        if (-not (Test-Path $basePath -ErrorAction SilentlyContinue)) { continue }

        $entries = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue

        foreach ($entry in $entries) {
            try {
                $props = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $displayName = $props.DisplayName
                if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

                # Check InstallLocation
                $installLocation = $props.InstallLocation
                $uninstallString = $props.UninstallString

                $isOrphan = $false

                # If has InstallLocation and it doesn't exist
                if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
                    if (-not (Test-PathExists -Path $installLocation)) {
                        $isOrphan = $true
                    }
                }
                # If has UninstallString and the executable doesn't exist
                elseif (-not [string]::IsNullOrWhiteSpace($uninstallString)) {
                    # Extract executable path from uninstall string
                    $exePath = $uninstallString -replace '^\s*"([^"]+)".*', '$1'
                    if ($exePath -eq $uninstallString) {
                        $exePath = ($uninstallString -split '\s')[0]
                    }
                    # Skip MsiExec entries (system component)
                    if ($exePath -notmatch 'MsiExec|msiexec') {
                        if (-not (Test-PathExists -Path $exePath)) {
                            $isOrphan = $true
                        }
                    }
                }

                if ($isOrphan) {
                    $orphans += [PSCustomObject]@{
                        DisplayName = $displayName
                        RegistryPath = $entry.PSPath
                        InstallLocation = $installLocation
                        UninstallString = $uninstallString
                        Publisher = $props.Publisher
                        Type = 'UninstallEntry'
                    }
                }
            }
            catch {
                Write-Verbose "Error processing uninstall entry: $_"
            }
        }
    }

    return $orphans
}

function Find-OrphanedSharedDLLs {
    <#
    .SYNOPSIS
        Finds SharedDLLs registry entries where the DLL file no longer exists.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphans = @()
    $sharedDllPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs'

    if (-not (Test-Path $sharedDllPath -ErrorAction SilentlyContinue)) {
        return $orphans
    }

    try {
        $sharedDlls = Get-ItemProperty -Path $sharedDllPath -ErrorAction SilentlyContinue

        if (-not $sharedDlls) { return $orphans }

        $sharedDlls.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^PS' -and $_.MemberType -eq 'NoteProperty'
        } | ForEach-Object {
            $dllPath = $_.Name
            $refCount = $_.Value

            # Only flag DLLs with 0 reference count that don't exist
            if ($refCount -eq 0 -and -not (Test-Path $dllPath -ErrorAction SilentlyContinue)) {
                $orphans += [PSCustomObject]@{
                    DisplayName = [System.IO.Path]::GetFileName($dllPath)
                    RegistryPath = $sharedDllPath
                    PropertyName = $dllPath
                    RefCount = $refCount
                    Type = 'SharedDLL'
                }
            }
        }
    }
    catch {
        Write-Verbose "Error scanning SharedDLLs: $_"
    }

    return $orphans
}

function Find-OrphanedMUICache {
    <#
    .SYNOPSIS
        Finds MUICache entries for executables that no longer exist.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphans = @()
    $muiCachePath = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'

    if (-not (Test-Path $muiCachePath -ErrorAction SilentlyContinue)) {
        return $orphans
    }

    try {
        $cache = Get-ItemProperty -Path $muiCachePath -ErrorAction SilentlyContinue
        if (-not $cache) { return $orphans }

        $cache.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^PS' -and $_.MemberType -eq 'NoteProperty'
        } | ForEach-Object {
            $entryName = $_.Name
            # MUICache keys look like: C:\path\to\app.exe.FriendlyAppName
            $exePath = $entryName -replace '\.[^.\\]+$', ''

            if ($exePath -match '\\' -and -not (Test-Path $exePath -ErrorAction SilentlyContinue)) {
                $orphans += [PSCustomObject]@{
                    DisplayName = [System.IO.Path]::GetFileName($exePath)
                    RegistryPath = $muiCachePath
                    PropertyName = $entryName
                    ExePath = $exePath
                    Type = 'MUICache'
                }
            }
        }
    }
    catch {
        Write-Verbose "Error scanning MUICache: $_"
    }

    return $orphans
}

function Find-OrphanedStartupEntries {
    <#
    .SYNOPSIS
        Finds Run/RunOnce entries pointing to non-existent executables.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphans = @()

    $runPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($runPath in $runPaths) {
        if (-not (Test-Path $runPath -ErrorAction SilentlyContinue)) { continue }

        try {
            $entries = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
            if (-not $entries) { continue }

            $entries.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^PS' -and $_.MemberType -eq 'NoteProperty'
            } | ForEach-Object {
                $name = $_.Name
                $value = $_.Value

                if ([string]::IsNullOrWhiteSpace($value)) { return }

                # Extract executable path
                $exePath = $value
                if ($exePath -match '^"([^"]+)"') {
                    $exePath = $Matches[1]
                }
                elseif ($exePath -match '^(\S+)') {
                    $exePath = $Matches[1]
                }

                $expandedPath = [Environment]::ExpandEnvironmentVariables($exePath)

                if (-not (Test-Path $expandedPath -ErrorAction SilentlyContinue)) {
                    $orphans += [PSCustomObject]@{
                        DisplayName = $name
                        RegistryPath = $runPath
                        PropertyName = $name
                        Value = $value
                        ExePath = $expandedPath
                        Type = 'StartupEntry'
                    }
                }
            }
        }
        catch {
            Write-Verbose "Error scanning startup entries at $runPath : $_"
        }
    }

    return $orphans
}

function Find-OrphanedAppPaths {
    <#
    .SYNOPSIS
        Finds App Paths entries where the application no longer exists.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $orphans = @()
    $appPathsBase = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'

    if (-not (Test-Path $appPathsBase -ErrorAction SilentlyContinue)) {
        return $orphans
    }

    try {
        $entries = Get-ChildItem -Path $appPathsBase -ErrorAction SilentlyContinue

        foreach ($entry in $entries) {
            $props = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }

            $defaultValue = $props.'(default)'
            if ([string]::IsNullOrWhiteSpace($defaultValue)) { continue }

            $expandedPath = [Environment]::ExpandEnvironmentVariables($defaultValue)
            $expandedPath = $expandedPath.Trim('"')

            if (-not (Test-Path $expandedPath -ErrorAction SilentlyContinue)) {
                $orphans += [PSCustomObject]@{
                    DisplayName = $entry.PSChildName
                    RegistryPath = $entry.PSPath
                    AppPath = $expandedPath
                    Type = 'AppPath'
                }
            }
        }
    }
    catch {
        Write-Verbose "Error scanning App Paths: $_"
    }

    return $orphans
}

#endregion

#region Public Functions

function Find-WinOpsOrphanedRegistry {
    <#
    .SYNOPSIS
        Scans for all types of orphaned registry entries.

    .DESCRIPTION
        Performs a comprehensive scan of the Windows registry to find
        entries left behind by uninstalled applications.

    .EXAMPLE
        Find-WinOpsOrphanedRegistry
        # Returns all orphaned registry entries
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $allOrphans = @()

    Write-Verbose "Scanning orphaned uninstall entries..."
    $allOrphans += Find-OrphanedUninstallEntries

    Write-Verbose "Scanning orphaned SharedDLLs..."
    $allOrphans += Find-OrphanedSharedDLLs

    Write-Verbose "Scanning orphaned MUICache..."
    $allOrphans += Find-OrphanedMUICache

    Write-Verbose "Scanning orphaned startup entries..."
    $allOrphans += Find-OrphanedStartupEntries

    Write-Verbose "Scanning orphaned App Paths..."
    $allOrphans += Find-OrphanedAppPaths

    return $allOrphans
}

function Clear-WinOpsRegistry {
    <#
    .SYNOPSIS
        Cleans orphaned registry entries from uninstalled applications.

    .DESCRIPTION
        Scans and removes registry entries left behind by uninstalled programs.
        All entries are backed up to .reg files before deletion for safety.

    .PARAMETER DryRun
        Show what would be removed without making changes.

    .PARAMETER Force
        Skip confirmation prompts.

    .EXAMPLE
        Clear-WinOpsRegistry -DryRun
        # Preview orphaned registry entries without removing them

    .EXAMPLE
        Clear-WinOpsRegistry -Force
        # Remove all orphaned registry entries without prompts
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
        Module = 'RegistryCleanup'
        ItemsProcessed = 0
        ItemsRemoved = 0
        BackupFiles = @()
        Actions = @()
        Success = $true
    }

    $backupDir = Join-Path $env:LOCALAPPDATA 'win-ops\registry-backups'

    try {
        Write-Host "  [Registry] Scanning for orphaned registry entries..." -ForegroundColor Cyan

        $orphans = Find-WinOpsOrphanedRegistry
        $results.ItemsProcessed = $orphans.Count

        if ($orphans.Count -eq 0) {
            Write-Host "    No orphaned registry entries found" -ForegroundColor Green
            return $results
        }

        # Group by type
        $grouped = $orphans | Group-Object -Property Type

        foreach ($group in $grouped) {
            $typeName = switch ($group.Name) {
                'UninstallEntry' { 'Uninstall Entries' }
                'SharedDLL'      { 'SharedDLL Entries' }
                'MUICache'       { 'MUI Cache Entries' }
                'StartupEntry'   { 'Startup Entries' }
                'AppPath'        { 'App Path Entries' }
                default          { $group.Name }
            }
            Write-Host "    Found $($group.Count) orphaned $typeName" -ForegroundColor Gray

            foreach ($orphan in $group.Group) {
                $displayInfo = "$($orphan.DisplayName)"
                if ($orphan.InstallLocation) {
                    $displayInfo += " ($($orphan.InstallLocation))"
                }
                elseif ($orphan.ExePath) {
                    $displayInfo += " ($($orphan.ExePath))"
                }

                if ($DryRun) {
                    Write-Host "      [DRY] Would remove: $displayInfo" -ForegroundColor Yellow
                }
                else {
                    try {
                        # Backup before removal
                        $backupPath = $null
                        if ($orphan.Type -eq 'UninstallEntry' -or $orphan.Type -eq 'AppPath') {
                            $backupPath = Export-RegistryBackup -RegistryPath $orphan.RegistryPath -BackupDir $backupDir
                            if ($backupPath) {
                                $results.BackupFiles += $backupPath
                            }
                        }

                        # Remove the entry
                        switch ($orphan.Type) {
                            'UninstallEntry' {
                                Remove-Item -Path $orphan.RegistryPath -Recurse -Force -ErrorAction Stop
                            }
                            'SharedDLL' {
                                Remove-ItemProperty -Path $orphan.RegistryPath -Name $orphan.PropertyName -Force -ErrorAction Stop
                            }
                            'MUICache' {
                                Remove-ItemProperty -Path $orphan.RegistryPath -Name $orphan.PropertyName -Force -ErrorAction Stop
                            }
                            'StartupEntry' {
                                Remove-ItemProperty -Path $orphan.RegistryPath -Name $orphan.PropertyName -Force -ErrorAction Stop
                            }
                            'AppPath' {
                                Remove-Item -Path $orphan.RegistryPath -Recurse -Force -ErrorAction Stop
                            }
                        }

                        $results.ItemsRemoved++
                        Write-Host "      [OK] Removed: $displayInfo" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "      [WARN] Failed to remove: $displayInfo - $_" -ForegroundColor Yellow
                    }
                }
            }
        }

        if ($DryRun) {
            Write-Host "  [Registry] Found $($orphans.Count) orphaned entries (dry run)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [Registry] Cleaned $($results.ItemsRemoved)/$($orphans.Count) orphaned entries" -ForegroundColor Green
            if ($results.BackupFiles.Count -gt 0) {
                Write-Host "    Backups saved to: $backupDir" -ForegroundColor Gray
            }
        }

        $results.Actions += "Scanned $($orphans.Count) orphaned entries"
        if ($results.ItemsRemoved -gt 0) {
            $results.Actions += "Removed $($results.ItemsRemoved) entries"
        }
    }
    catch {
        $results.Success = $false
        Write-Warning "Registry cleanup failed: $_"
    }

    return $results
}

function Get-WinOpsRegistryTargets {
    <#
    .SYNOPSIS
        Gets orphaned registry entries for analysis module integration.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $targets = @()
    $orphans = Find-WinOpsOrphanedRegistry

    foreach ($orphan in $orphans) {
        $targets += [PSCustomObject]@{
            Name = "$($orphan.DisplayName) ($($orphan.Type))"
            Path = $orphan.RegistryPath
            CurrentSizeMB = 0.01
            Category = "Registry"
            Module = "RegistryCleanup"
        }
    }

    return $targets
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsRegistry',
    'Find-WinOpsOrphanedRegistry',
    'Get-WinOpsRegistryTargets'
)
