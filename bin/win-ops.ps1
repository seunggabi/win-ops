#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows Operations Manager - Automated system maintenance and optimization toolkit

.DESCRIPTION
    win-ops is a comprehensive Windows system maintenance tool that automates cleanup,
    optimization, and monitoring tasks. It safely manages temporary files, browser caches,
    system logs, and provides rollback capabilities.

.PARAMETER Command
    The command to execute. Valid commands: help, version, run, analyze, status, list-trash, restore, install, uninstall, schedule, unschedule

.PARAMETER DryRun
    Perform a dry run without making actual changes

.PARAMETER Force
    Force execution without confirmation prompts

.EXAMPLE
    win-ops.ps1 help
    Display help information

.EXAMPLE
    win-ops.ps1 analyze --dry-run
    Analyze system without making changes

.EXAMPLE
    win-ops.ps1 run --force
    Execute cleanup operations without confirmation

.NOTES
    Version: Loaded from win-ops.psd1
    Author: Seunggabi
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'version', 'run', 'analyze', 'status', 'list-trash', 'restore', 'install', 'uninstall', 'schedule', 'unschedule', '--help', '--version')]
    [string]$Command = 'help',

    [Parameter()]
    [Alias('n')]
    [switch]$DryRun,

    [Parameter()]
    [Alias('f')]
    [switch]$Force,

    [Parameter()]
    [Alias('v')]
    [switch]$VerboseOutput,

    [Parameter()]
    [Alias('p')]
    [switch]$PurgeTrash,

    [Parameter()]
    [Alias('a')]
    [switch]$All,

    [Parameter()]
    [switch]$Version,

    [Parameter()]
    [Alias('h')]
    [switch]$Help
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module version (read from psd1 manifest - single source of truth)
$script:ModuleName = 'win-ops'
$script:ManifestPath = Join-Path (Split-Path -Parent $PSCommandPath | Split-Path -Parent) 'win-ops.psd1'
if (Test-Path $script:ManifestPath) {
    $manifestData = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:ModuleVersion = $manifestData.ModuleVersion
} else {
    $script:ModuleVersion = 'unknown'
}

# Handle --version and --help flags
if ($Version -or $Command -eq '--version') { $Command = 'version' }
if ($Help -or $Command -eq '--help') { $Command = 'help' }

# Set verbose preference if flag is provided
if ($VerboseOutput) {
    $VerbosePreference = 'Continue'
}

# Get script root directory
$script:ScriptRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent

# Import I18n module for localized messages
$i18nModule = Join-Path $script:ScriptRoot 'lib\core\I18n.psm1'
if (Test-Path $i18nModule) {
    Import-Module $i18nModule -Force
    Initialize-WinOpsI18n
}

function Get-WinOpsVersion {
    <#
    .SYNOPSIS
        Get the version of win-ops
    #>
    [CmdletBinding()]
    param()

    Write-Host (Get-WinOpsMessage -Key 'Version_Title' -Args $script:ModuleName, $script:ModuleVersion) -ForegroundColor Cyan
    if (Test-Path $script:ManifestPath) {
        $lastUpdated = (Get-Item $script:ManifestPath).LastWriteTime.ToString('yyyy-MM-dd')
        Write-Host "  Last Updated: $lastUpdated" -ForegroundColor Gray
    }
    Write-Host (Get-WinOpsMessage -Key 'Version_PowerShell' -Args $PSVersionTable.PSVersion) -ForegroundColor Gray
    $osInfo = if ($PSVersionTable.ContainsKey('OS')) { $PSVersionTable.OS } else { [System.Environment]::OSVersion.VersionString }
    Write-Host (Get-WinOpsMessage -Key 'Version_OS' -Args $osInfo) -ForegroundColor Gray
}

function Get-WinOpsHelp {
    <#
    .SYNOPSIS
        Display help information for win-ops
    #>
    [CmdletBinding()]
    param()

    $helpText = @"

$script:ModuleName - Windows Operations Manager v$script:ModuleVersion

USAGE:
    win-ops <command> [options]

COMMANDS:
    help            Display this help message
    version         Display version information
    analyze         Analyze system and show potential cleanup targets
                    Provides disk usage analysis, cleanup recommendations
    run             Execute cleanup operations
                    Runs enabled modules: cache, temp files, logs, etc.
    status          Show current system status and recent operations
                    Displays system metrics, last cleanup, trash status
    list-trash      List items in trash (available for restore)
                    Shows all deleted items within retention period
    restore         Restore items from trash
                    Interactive restore with search and filter options
    install         Install win-ops as a scheduled task
                    Sets up automatic hourly/daily cleanup (requires admin)
    uninstall       Uninstall win-ops scheduled task
                    Removes scheduled task and optionally data files
    schedule        Register scheduled task from config settings
                    Reads schedule section from win-ops.json (requires admin)
    unschedule      Remove scheduled task
                    Unregisters the Win-Ops scheduled task (requires admin)

OPTIONS:
    --dry-run, -n   Perform analysis without making actual changes
    --force, -f     Skip confirmation prompts
    --verbose, -v   Enable verbose output
    --all, -a       Enable ALL modules including advanced ones (DevCleanup, DockerCleanup, ZombieKiller, OrphanKiller)

EXAMPLES:
    win-ops help
        Display this help message

    win-ops version
        Show version information

    win-ops analyze
        Analyze system and show what would be cleaned

    win-ops analyze --dry-run
        Same as analyze (dry-run is implicit for analyze)

    win-ops run
        Execute cleanup with confirmation prompts

    win-ops run --force
        Execute cleanup without confirmation

    win-ops run --dry-run
        Preview cleanup operations without executing

    win-ops run --all
        Execute cleanup with ALL modules (including advanced/optional ones)

    win-ops run --all --force
        Execute full cleanup without confirmation

    win-ops status
        Show system status and operation history

    win-ops list-trash
        List all items that can be restored

    win-ops restore
        Interactive restore from trash

    win-ops install
        Install as scheduled task (requires admin)

    win-ops uninstall
        Remove scheduled task (requires admin)

    win-ops schedule
        Register scheduled task using config settings (requires admin)

    win-ops unschedule
        Remove scheduled task (requires admin)

CLEANUP MODULES:
    Cache           Windows and application caches
    Temp            Temporary files and folders
    Logs            Application and system logs
    Browser         Browser caches (Chrome, Edge, Firefox, Brave, Opera)
    Developer       Dev tool caches (npm, yarn, pip, NuGet, Maven, Gradle)
    Docker          Docker images, containers, volumes
    Packages        Package manager caches (Chocolatey, Scoop)
    Zombie          Zombie processes (high CPU/memory, unresponsive)
    Orphan          Orphaned processes and application data

CONFIGURATION:
    Config file: %LOCALAPPDATA%\win-ops\config\win-ops.json
    Edit configuration to enable/disable modules and customize behavior

    Example: Enable browser cleanup
        Set modules.BrowserCleanup.enabled = true in config

SAFETY FEATURES:
    - Trash system with 72-hour retention (configurable)
    - Protected paths and processes
    - File locking to prevent concurrent operations
    - Dry-run mode for safe testing
    - Before/after snapshots for comparison

DOCUMENTATION:
    README:   https://github.com/seunggabi/win-ops/blob/main/README.md
    Issues:   https://github.com/seunggabi/win-ops/issues
    License:  MIT License

"@

    Write-Host $helpText
}

function Start-WinOpsAnalysis {
    <#
    .SYNOPSIS
        Analyze system for cleanup opportunities
    #>
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    try {
        # Import required modules
        $analyzeModule = Join-Path $script:ScriptRoot 'lib\modules\Analyze.psm1'

        if (-not (Test-Path $analyzeModule)) {
            Write-Error "Analyze module not found: $analyzeModule"
            return
        }

        Import-Module $analyzeModule -Force

        Write-Host "`n$(Get-WinOpsMessage -Key 'Analyze_Starting')" -ForegroundColor Cyan
        Write-Host "$(Get-WinOpsMessage -Key 'Analyze_PleaseWait')`n" -ForegroundColor Gray

        # Run analysis
        $analysis = Get-WinOpsAnalysis -Detailed:$false -TopN 20

        if ($analysis.TotalItemCount -eq 0) {
            Write-Host (Get-WinOpsMessage -Key 'Analyze_NoTargets') -ForegroundColor Green
            return
        }

        Write-Host "`n$(Get-WinOpsMessage -Key 'Analyze_ToPerformCleanup')" -ForegroundColor Yellow
        Write-Host "  win-ops run --dry-run  " -ForegroundColor White -NoNewline
        Write-Host (Get-WinOpsMessage -Key 'Analyze_PreviewChanges') -ForegroundColor Gray
        Write-Host "  win-ops run            " -ForegroundColor White -NoNewline
        Write-Host (Get-WinOpsMessage -Key 'Analyze_ExecuteCleanup') -ForegroundColor Gray
        Write-Host ""
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Analyze_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Start-WinOpsCleanup {
    <#
    .SYNOPSIS
        Execute cleanup operations
    #>
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Force,
        [switch]$PurgeTrash,
        [switch]$All
    )

    try {
        # Import required modules
        $coreModules = @(
            'lib\core\Config.psm1'
            'lib\core\Logger.psm1'
            'lib\core\Lock.psm1'
            'lib\core\Trash.psm1'
        )

        foreach ($module in $coreModules) {
            $modulePath = Join-Path $script:ScriptRoot $module
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force -Global
            }
        }

        # Import Analyze module
        $analyzeModule = Join-Path $script:ScriptRoot 'lib\modules\Analyze.psm1'
        if (Test-Path $analyzeModule) {
            Import-Module $analyzeModule -Force -Global
        }

        # Initialize logger
        $logDir = Join-Path $env:LOCALAPPDATA 'win-ops\logs'
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $logPath = Join-Path $logDir 'win-ops.log'
        Initialize-WinOpsLogger -LogPath $logPath -LogLevel INFO

        Write-WinOpsLog -Level INFO -Message (Get-WinOpsMessage -Key 'Cleanup_Starting' -Args $DryRun, $Force)

        # Check for lock
        if (Test-WinOpsLocked) {
            Write-Warning (Get-WinOpsMessage -Key 'Lock_AnotherInstance')
            return
        }

        # Acquire lock
        if (-not (Lock-WinOps -TimeoutSeconds 30)) {
            Write-Error (Get-WinOpsMessage -Key 'Lock_FailedAcquire')
            return
        }

        try {
            Write-Host "`n$(Get-WinOpsMessage -Key 'Cleanup_Title')" -ForegroundColor Cyan
            Write-Host "===============`n" -ForegroundColor Cyan

            if ($DryRun) {
                Write-Host "$(Get-WinOpsMessage -Key 'Cleanup_DryRunMode')`n" -ForegroundColor Yellow
            }

            # Load configuration
            $config = Get-WinOpsConfig

            if (-not $config) {
                Write-Warning (Get-WinOpsMessage -Key 'Cleanup_ConfigNotFound')
                Initialize-WinOpsConfig
                $config = Get-WinOpsConfig
            }

            # Module name to function name mapping
            $moduleMap = @{
                'CacheCleanup'           = 'Clear-WinOpsCache'
                'TmpCleanup'             = 'Clear-WinOpsTempFiles'
                'LogCleanup'             = 'Clear-WinOpsLogFiles'
                'MemoryCleanup'          = 'Clear-WinOpsMemory'
                'RegistryCleanup'        = 'Clear-WinOpsRegistry'
                'HistoryCleanup'         = 'Clear-WinOpsHistory'
                'OrphanAppCleanup'       = 'Clear-WinOpsOrphanedAppData'
                'BrowserCleanup'         = 'Clear-WinOpsBrowserData'
                'DevCleanup'             = 'Invoke-WinOpsDevCleanup'
                'DockerCleanup'          = 'Clear-WinOpsDockerResources'
                'PackageManagerCleanup'  = 'Clear-WinOpsPackageManagerCache'
                'ZombieKiller'           = 'Invoke-WinOpsZombieCleanup'
                'OrphanKiller'           = 'Invoke-WinOpsOrphanCleanup'
            }

            # Default modules (safe and commonly needed)
            $defaultModules = @(
                'CacheCleanup', 'TmpCleanup', 'LogCleanup',
                'MemoryCleanup', 'RegistryCleanup', 'HistoryCleanup',
                'OrphanAppCleanup', 'BrowserCleanup', 'PackageManagerCleanup'
            )

            # All modules (including advanced/optional ones)
            $allModules = @(
                'CacheCleanup', 'TmpCleanup', 'LogCleanup',
                'MemoryCleanup', 'RegistryCleanup', 'HistoryCleanup',
                'OrphanAppCleanup', 'BrowserCleanup', 'PackageManagerCleanup',
                'DevCleanup', 'DockerCleanup', 'ZombieKiller', 'OrphanKiller'
            )

            # Choose module set based on --all flag
            $modulesToRun = if ($All) { $allModules } else { $defaultModules }

            # Capture ASIS state
            $asIsMemory = [math]::Round((Get-Process | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB, 2)
            $asIsDisks = @()
            try {
                $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
                foreach ($d in $drives) {
                    $asIsDisks += @{
                        Drive = $d.Name
                        UsedGB = [math]::Round($d.Used / 1GB, 2)
                        FreeGB = [math]::Round($d.Free / 1GB, 2)
                        TotalGB = [math]::Round(($d.Used + $d.Free) / 1GB, 2)
                    }
                }
            } catch { }

            # Perform analysis before cleanup (only for modules that will actually run)
            Write-Host (Get-WinOpsMessage -Key 'Cleanup_AnalyzingTargets') -ForegroundColor Cyan
            $beforeAnalysis = Get-WinOpsAnalysis -NoVisual -Modules $modulesToRun

            if ($beforeAnalysis.TotalItemCount -eq 0) {
                Write-Host "`n$(Get-WinOpsMessage -Key 'Cleanup_NoTargets')" -ForegroundColor Green
                return
            }

            # Confirmation prompt
            if (-not $Force -and -not $DryRun) {
                Write-Host "`n$(Get-WinOpsMessage -Key 'Cleanup_ReadyToClean')" -ForegroundColor Yellow
                Write-Host "  $(Get-WinOpsMessage -Key 'Cleanup_Items' -Args $beforeAnalysis.TotalItemCount)" -ForegroundColor White
                Write-Host "  $(Get-WinOpsMessage -Key 'Cleanup_Space' -Args $beforeAnalysis.TotalReclaimableGB)" -ForegroundColor White
                Write-Host ""
                $response = Read-Host (Get-WinOpsMessage -Key 'Cleanup_Confirm')
                if ($response -notmatch '^[Yy]') {
                    Write-Host (Get-WinOpsMessage -Key 'Cleanup_Cancelled') -ForegroundColor Gray
                    return
                }
            }

            # Execute cleanup modules
            Write-Host "`n$(Get-WinOpsMessage -Key 'Cleanup_Executing')" -ForegroundColor Cyan
            $results = @()

            # Suppress confirmation prompts for all modules (already confirmed at top level)
            $savedConfirmPreference = $ConfirmPreference
            $ConfirmPreference = 'None'

            # Build module settings lookup from win-ops.json
            $moduleSettings = @{}
            $winOpsJsonPath = Join-Path $script:ScriptRoot 'config\win-ops.json'
            if (Test-Path $winOpsJsonPath) {
                $rawConfig = Get-Content $winOpsJsonPath -Raw | ConvertFrom-Json
                if ($rawConfig.modules) {
                    foreach ($mod in $rawConfig.modules) {
                        if ($mod.name -and $mod.settings) {
                            $moduleSettings[$mod.name] = $mod.settings
                        }
                    }
                }
            }

            foreach ($moduleName in $modulesToRun) {
                try {
                    $modulePath = Join-Path $script:ScriptRoot "lib\modules\$moduleName.psm1"

                    if (-not (Test-Path $modulePath)) {
                        Write-Verbose "Module not found: $moduleName"
                        continue
                    }

                    Import-Module $modulePath -Force

                    $functionName = $moduleMap[$moduleName]
                    $command = Get-Command $functionName -ErrorAction SilentlyContinue

                    if ($command) {
                        Write-Host "  $(Get-WinOpsMessage -Key 'Cleanup_Running' -Args $moduleName)" -ForegroundColor Gray

                        $params = @{
                            DryRun = $DryRun
                            Force  = $true
                        }

                        # Merge module-specific config settings into params
                        if ($moduleSettings.ContainsKey($moduleName)) {
                            foreach ($key in $moduleSettings[$moduleName].PSObject.Properties.Name) {
                                $paramName = $key.Substring(0,1).ToUpper() + $key.Substring(1)
                                if ($command.Parameters.ContainsKey($paramName) -and -not $params.ContainsKey($paramName)) {
                                    $params[$paramName] = $moduleSettings[$moduleName].$key
                                }
                            }
                        }

                        # Fill mandatory parameters that have ValidateSet with "All" default
                        foreach ($pName in $command.Parameters.Keys) {
                            $p = $command.Parameters[$pName]
                            $isMandatory = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
                            if ($isMandatory -and -not $params.ContainsKey($pName)) {
                                $validateSet = $p.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
                                if ($validateSet -and $validateSet.ValidValues -contains 'All') {
                                    $params[$pName] = 'All'
                                }
                            }
                        }

                        $result = & $functionName @params
                        # Store result with module name for summary
                        $results += @{ Name = $moduleName; Result = $result }
                    }
                }
                catch {
                    Write-Warning (Get-WinOpsMessage -Key 'Cleanup_ModuleFailed' -Args $moduleName, $_)
                }
            }

            $ConfirmPreference = $savedConfirmPreference

            # Display summary
            Write-Host "`n=== Cleanup Summary ===" -ForegroundColor Cyan
            foreach ($entry in $results) {
                $r = $entry.Result
                if ($null -eq $r) { continue }
                $props = $r.PSObject.Properties
                $modName = $entry.Name
                $items = if ($props['ItemsProcessed'] -and $r.ItemsProcessed) { $r.ItemsProcessed } elseif ($props['ItemsRemoved'] -and $r.ItemsRemoved) { $r.ItemsRemoved } elseif ($props['TotalItemsRemoved'] -and $r.TotalItemsRemoved) { $r.TotalItemsRemoved } else { 0 }
                $freed = ''
                if ($props['MemoryFreedMB'] -and $r.MemoryFreedMB -gt 0) {
                    $freed = " ($($r.MemoryFreedMB) MB freed)"
                }
                elseif ($props['SpaceReclaimedMB'] -and $r.SpaceReclaimedMB -gt 0) {
                    $freed = " ($([math]::Round($r.SpaceReclaimedMB, 2)) MB)"
                }
                elseif ($props['TotalSizeRemovedMB'] -and $r.TotalSizeRemovedMB -gt 0) {
                    $freed = " ($([math]::Round($r.TotalSizeRemovedMB, 2)) MB)"
                }
                if ($items -gt 0) {
                    Write-Host "  $modName : $items items$freed" -ForegroundColor White
                }
            }

            # Capture TOBE state
            $toBeMemory = [math]::Round((Get-Process | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB, 2)
            $toBeDisks = @()
            try {
                $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
                foreach ($d in $drives) {
                    $toBeDisks += @{
                        Drive = $d.Name
                        UsedGB = [math]::Round($d.Used / 1GB, 2)
                        FreeGB = [math]::Round($d.Free / 1GB, 2)
                        TotalGB = [math]::Round(($d.Used + $d.Free) / 1GB, 2)
                    }
                }
            } catch { }

            # Save last cleanup results
            $lastCleanup = @{
                Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                DryRun = [bool]$DryRun
                Results = @()
                AsIs = @{
                    MemoryMB = $asIsMemory
                    Disks = $asIsDisks
                }
                ToBe = @{
                    MemoryMB = $toBeMemory
                    Disks = $toBeDisks
                }
            }
            foreach ($entry in $results) {
                $r = $entry.Result
                if ($null -eq $r) { continue }
                $props = $r.PSObject.Properties
                $items = if ($props['ItemsProcessed'] -and $r.ItemsProcessed) { $r.ItemsProcessed } elseif ($props['ItemsRemoved'] -and $r.ItemsRemoved) { $r.ItemsRemoved } elseif ($props['TotalItemsRemoved'] -and $r.TotalItemsRemoved) { $r.TotalItemsRemoved } else { 0 }
                $lastCleanup.Results += @{
                    Module = $entry.Name
                    Items = $items
                    MemoryFreedMB = if ($props['MemoryFreedMB']) { $r.MemoryFreedMB } else { 0 }
                    SpaceReclaimedMB = if ($props['SpaceReclaimedMB']) { $r.SpaceReclaimedMB } elseif ($props['TotalSizeRemovedMB']) { $r.TotalSizeRemovedMB } else { 0 }
                }
            }
            $lastCleanupPath = Join-Path $env:LOCALAPPDATA 'win-ops\last-cleanup.json'
            $lastCleanup | ConvertTo-Json -Depth 5 | Set-Content -Path $lastCleanupPath -Encoding UTF8 -Force -ErrorAction SilentlyContinue

            # Purge trash if requested
            if ($PurgeTrash -and -not $DryRun) {
                Write-Host ""
                Write-Host "=== Trash Purge ===" -ForegroundColor Cyan
                $trashResult = Clear-WinOpsTrash -Force
                if ($trashResult -and $trashResult.RemovedCount -gt 0) {
                    Write-Host "  Purged $($trashResult.RemovedCount) items ($($trashResult.ReclaimedMB) MB)" -ForegroundColor White
                } else {
                    Write-Host "  Trash is empty" -ForegroundColor Gray
                }
            }

            Write-Host ""
            Write-Host "$(Get-WinOpsMessage -Key 'Cleanup_Complete')" -ForegroundColor Green
            Write-Host ""

            # Show status after cleanup
            Get-WinOpsStatus
        }
        finally {
            Unlock-WinOps
        }
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Cleanup_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Get-WinOpsStatus {
    <#
    .SYNOPSIS
        Get current status of win-ops
    #>
    [CmdletBinding()]
    param()

    try {
        # Import required modules
        $diskModule = Join-Path $script:ScriptRoot 'lib\core\Disk.psm1'
        $trashModule = Join-Path $script:ScriptRoot 'lib\core\Trash.psm1'
        $lockModule = Join-Path $script:ScriptRoot 'lib\core\Lock.psm1'

        if (Test-Path $diskModule) { Import-Module $diskModule -Force }
        if (Test-Path $trashModule) { Import-Module $trashModule -Force }
        if (Test-Path $lockModule) { Import-Module $lockModule -Force }

        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                          $(Get-WinOpsMessage -Key 'Status_Title')                                  |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        # System status
        Write-Host "=== $(Get-WinOpsMessage -Key 'Status_System') ===" -ForegroundColor Cyan
        Write-Host ""

        # Lock status
        $isLocked = Test-WinOpsLocked
        Write-Host "$(Get-WinOpsMessage -Key 'Status_Operation') " -NoNewline
        if ($isLocked) {
            Write-Host (Get-WinOpsMessage -Key 'Status_Running') -ForegroundColor Yellow
        } else {
            Write-Host (Get-WinOpsMessage -Key 'Status_Idle') -ForegroundColor Green
        }

        # Disk usage
        Write-Host ""
        Write-Host "=== $(Get-WinOpsMessage -Key 'Status_DiskUsage') ===" -ForegroundColor Cyan
        Write-Host ""

        $disks = Get-WinOpsDiskUsage -ExcludeNetworkDrives -ExcludeRemovableDrives

        foreach ($disk in $disks) {
            $color = if ($disk.UsagePercent -gt 90) { "Red" }
                     elseif ($disk.UsagePercent -gt 80) { "Yellow" }
                     else { "Green" }

            Write-Host "Drive $($disk.Drive) " -NoNewline -ForegroundColor White
            Write-Host "($($disk.VolumeLabel))" -ForegroundColor Gray
            Write-Host "  Used: " -NoNewline
            Write-Host ("{0:N2} GB" -f ($disk.UsedSizeBytes / 1GB)) -NoNewline -ForegroundColor $color
            Write-Host " / " -NoNewline
            Write-Host ("{0:N2} GB" -f ($disk.TotalSizeBytes / 1GB)) -ForegroundColor Gray
            Write-Host "  Free: " -NoNewline
            Write-Host ("{0:N2} GB" -f ($disk.FreeSizeBytes / 1GB)) -NoNewline -ForegroundColor White
            Write-Host " ($($disk.UsagePercent)% used)" -ForegroundColor Gray
            Write-Host ""
        }

        # Trash status
        Write-Host "=== $(Get-WinOpsMessage -Key 'Status_TrashStatus') ===" -ForegroundColor Cyan
        Write-Host ""

        $trashItems = Get-WinOpsTrashList

        if ($trashItems) {
            $totalSize = ($trashItems | Measure-Object -Property SizeMB -Sum).Sum
            Write-Host "$(Get-WinOpsMessage -Key 'Status_TrashItems' -Args $trashItems.Count)" -ForegroundColor Yellow
            Write-Host (Get-WinOpsMessage -Key 'Status_TrashSize' -Args ("{0:N2}" -f ($totalSize / 1024))) -ForegroundColor Yellow
            Write-Host ""
            Write-Host "$(Get-WinOpsMessage -Key 'Status_TrashRecent')" -ForegroundColor Gray

            $recentItems = $trashItems | Select-Object -First 5
            foreach ($item in $recentItems) {
                Write-Host ("  {0,-10} {1}" -f "[$(Split-Path $item.OriginalPath -Leaf)]", $item.OriginalPath) -ForegroundColor DarkGray
            }

            if ($trashItems.Count -gt 5) {
                Write-Host "  $(Get-WinOpsMessage -Key 'Status_TrashMore' -Args ($trashItems.Count - 5))" -ForegroundColor DarkGray
            }
        } else {
            Write-Host (Get-WinOpsMessage -Key 'Status_TrashEmpty') -ForegroundColor Green
        }

        # Last cleanup results
        $lastCleanupPath = Join-Path $env:LOCALAPPDATA 'win-ops\last-cleanup.json'
        if (Test-Path $lastCleanupPath -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "=== Last Cleanup ===" -ForegroundColor Cyan
            Write-Host ""

            try {
                $jsonContent = Get-Content -Path $lastCleanupPath -Raw -Encoding UTF8 -ErrorAction Stop
                $lastObj = ConvertFrom-Json -InputObject $jsonContent -ErrorAction Stop
                Write-Host "  Time: $($lastObj.Timestamp)" -ForegroundColor White
                if ($lastObj.DryRun) {
                    Write-Host "  Mode: DRY RUN" -ForegroundColor Yellow
                }
                Write-Host ""

                # ASIS → TOBE comparison
                if ($lastObj.AsIs -and $lastObj.ToBe) {
                    Write-Host "  --- ASIS -> TOBE ---" -ForegroundColor Yellow
                    Write-Host ""

                    # Memory
                    $memBefore = $lastObj.AsIs.MemoryMB
                    $memAfter = $lastObj.ToBe.MemoryMB
                    $memDiff = [math]::Round($memBefore - $memAfter, 2)
                    $memColor = if ($memDiff -gt 0) { 'Green' } else { 'Gray' }
                    Write-Host "  Memory" -ForegroundColor White
                    Write-Host "    ASIS: " -NoNewline -ForegroundColor Gray
                    Write-Host ("{0:N0} MB" -f $memBefore) -ForegroundColor Gray
                    Write-Host "    TOBE: " -NoNewline -ForegroundColor Gray
                    Write-Host ("{0:N0} MB" -f $memAfter) -NoNewline -ForegroundColor White
                    if ($memDiff -gt 0) {
                        Write-Host "  (-$memDiff MB)" -ForegroundColor $memColor
                    } else {
                        Write-Host ""
                    }
                    Write-Host ""

                    # Disks
                    $asisDisks = @($lastObj.AsIs.Disks)
                    $tobeDisks = @($lastObj.ToBe.Disks)
                    if ($asisDisks.Count -gt 0) {
                        Write-Host "  Disk" -ForegroundColor White
                        for ($i = 0; $i -lt $asisDisks.Count; $i++) {
                            $asDisk = $asisDisks[$i]
                            $toBeDisk = $null
                            foreach ($td in $tobeDisks) {
                                if ($td.Drive -eq $asDisk.Drive) { $toBeDisk = $td; break }
                            }
                            if (-not $toBeDisk) { continue }
                            $freedGB = [math]::Round([double]$toBeDisk.FreeGB - [double]$asDisk.FreeGB, 2)
                            Write-Host "    [$($asDisk.Drive):]" -NoNewline -ForegroundColor White
                            Write-Host " Used " -NoNewline -ForegroundColor Gray
                            Write-Host ("{0:N2}" -f [double]$asDisk.UsedGB) -NoNewline -ForegroundColor Gray
                            Write-Host " -> " -NoNewline -ForegroundColor Gray
                            Write-Host ("{0:N2} GB" -f [double]$toBeDisk.UsedGB) -NoNewline -ForegroundColor White
                            if ($freedGB -gt 0) {
                                Write-Host "  (+$freedGB GB free)" -ForegroundColor Green
                            } elseif ($freedGB -lt 0) {
                                Write-Host "  ($freedGB GB)" -ForegroundColor Yellow
                            } else {
                                Write-Host "  (no change)" -ForegroundColor Gray
                            }
                        }
                    }
                    Write-Host ""
                }

                # Module results
                Write-Host "  --- Modules ---" -ForegroundColor Yellow
                foreach ($r in $lastObj.Results) {
                    $items = $r.Items
                    if ($items -le 0) { continue }
                    $extra = ''
                    if ($r.MemoryFreedMB -gt 0) {
                        $extra = " ($($r.MemoryFreedMB) MB freed)"
                    }
                    elseif ($r.SpaceReclaimedMB -gt 0) {
                        $extra = " ($([math]::Round($r.SpaceReclaimedMB, 2)) MB)"
                    }
                    Write-Host "    $($r.Module): $items items$extra" -ForegroundColor Gray
                }
            }
            catch {
                Write-Verbose "Failed to read last cleanup results: $_"
            }
        }

        Write-Host ""
        Write-Host (Get-WinOpsMessage -Key 'Status_RunAnalyze') -ForegroundColor Gray
        Write-Host (Get-WinOpsMessage -Key 'Status_RunListTrash') -ForegroundColor Gray
        Write-Host ""
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Status_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Get-TrashItems {
    <#
    .SYNOPSIS
        List items in trash
    #>
    [CmdletBinding()]
    param()

    try {
        # Import Trash module
        $trashModule = Join-Path $script:ScriptRoot 'lib\core\Trash.psm1'

        if (-not (Test-Path $trashModule)) {
            Write-Error "Trash module not found: $trashModule"
            return
        }

        Import-Module $trashModule -Force

        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                          $(Get-WinOpsMessage -Key 'Trash_Title')                                     |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        $items = Get-WinOpsTrashList

        if (-not $items -or $items.Count -eq 0) {
            Write-Host (Get-WinOpsMessage -Key 'Trash_Empty') -ForegroundColor Green
            Write-Host ""
            return
        }

        $totalSize = ($items | Measure-Object -Property SizeMB -Sum).Sum

        Write-Host (Get-WinOpsMessage -Key 'Trash_TotalItems' -Args $items.Count) -ForegroundColor Yellow
        Write-Host (Get-WinOpsMessage -Key 'Trash_TotalSize' -Args ("{0:N2}" -f ($totalSize / 1024))) -ForegroundColor Yellow
        Write-Host ""

        # Display items in a table format
        Write-Host ("{0,-12} {1,-20} {2,-10} {3,-12} {4}" -f "Hash", "Module", "Size (MB)", "Expires In", "Original Path") -ForegroundColor Gray
        Write-Host ("{0,-12} {1,-20} {2,-10} {3,-12} {4}" -f "----", "------", "---------", "----------", "-------------") -ForegroundColor DarkGray

        foreach ($item in $items) {
            $hashShort = $item.Hash.Substring(0, 12)
            $expiresColor = if ($item.ExpiresInHours -lt 1) { "Red" }
                           elseif ($item.ExpiresInHours -lt 12) { "Yellow" }
                           else { "Green" }

            $expiresText = if ($item.IsExpired) { "EXPIRED" }
                          elseif ($item.ExpiresInHours -lt 1) { "$([math]::Round($item.ExpiresInHours * 60))m" }
                          else { "$([math]::Round($item.ExpiresInHours, 1))h" }

            Write-Host ("{0,-12} " -f $hashShort) -NoNewline -ForegroundColor White
            Write-Host ("{0,-20} " -f $item.Module) -NoNewline -ForegroundColor Cyan
            Write-Host ("{0,10:N2} " -f $item.SizeMB) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,12} " -f $expiresText) -NoNewline -ForegroundColor $expiresColor
            Write-Host $item.OriginalPath -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host (Get-WinOpsMessage -Key 'Trash_ToRestore') -ForegroundColor Gray
        Write-Host "  win-ops restore" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Trash_ListFailed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Restore-TrashItem {
    <#
    .SYNOPSIS
        Restore items from trash
    #>
    [CmdletBinding()]
    param()

    try {
        # Import Trash module
        $trashModule = Join-Path $script:ScriptRoot 'lib\core\Trash.psm1'

        if (-not (Test-Path $trashModule)) {
            Write-Error "Trash module not found: $trashModule"
            return
        }

        Import-Module $trashModule -Force

        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                       $(Get-WinOpsMessage -Key 'Restore_Title')                                 |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        $items = Get-WinOpsTrashList

        if (-not $items -or $items.Count -eq 0) {
            Write-Host (Get-WinOpsMessage -Key 'Restore_Empty') -ForegroundColor Yellow
            Write-Host ""
            return
        }

        # Display items with numbers for selection
        Write-Host "$(Get-WinOpsMessage -Key 'Restore_SelectPrompt')`n" -ForegroundColor Yellow

        $index = 1
        foreach ($item in $items) {
            $hashShort = $item.Hash.Substring(0, 12)
            Write-Host ("{0,3}. " -f $index) -NoNewline -ForegroundColor White
            Write-Host ("[{0}] " -f $hashShort) -NoNewline -ForegroundColor Gray
            Write-Host $item.OriginalPath -NoNewline -ForegroundColor Cyan
            Write-Host " ({0:N2} MB, expires in {1:N1}h)" -f $item.SizeMB, $item.ExpiresInHours -ForegroundColor DarkGray
            $index++
        }

        Write-Host ""
        $selection = Read-Host (Get-WinOpsMessage -Key 'Restore_EnterNumber')

        if ($selection -eq 'q' -or $selection -eq 'Q') {
            Write-Host (Get-WinOpsMessage -Key 'Restore_Cancelled') -ForegroundColor Gray
            return
        }

        $selectedIndex = 0
        if (-not [int]::TryParse($selection, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $items.Count) {
            Write-Error (Get-WinOpsMessage -Key 'Restore_Invalid' -Args $items.Count)
            return
        }

        $selectedItem = $items[$selectedIndex - 1]

        Write-Host ""
        Write-Host "$(Get-WinOpsMessage -Key 'Restore_Restoring' -Args $selectedItem.OriginalPath)" -ForegroundColor Cyan

        # Check if original location exists
        if (Test-Path $selectedItem.OriginalPath) {
            Write-Host ""
            Write-Warning (Get-WinOpsMessage -Key 'Restore_LocationOccupied')
            $overwrite = Read-Host (Get-WinOpsMessage -Key 'Restore_Overwrite')
            if ($overwrite -notmatch '^[Yy]') {
                Write-Host (Get-WinOpsMessage -Key 'Restore_Cancelled') -ForegroundColor Gray
                return
            }
            $forceRestore = $true
        } else {
            $forceRestore = $false
        }

        # Restore
        $result = Restore-WinOpsFromTrash -Hash $selectedItem.Hash -Force:$forceRestore

        if ($result) {
            Write-Host ""
            Write-Host (Get-WinOpsMessage -Key 'Restore_Success' -Args $result.RestoredPath) -ForegroundColor Green
            Write-Host ""
        }
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Restore_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Install-WinOps {
    <#
    .SYNOPSIS
        Install win-ops as scheduled task
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                      $(Get-WinOpsMessage -Key 'Install_Title')                                     |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        # Check for admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Error (Get-WinOpsMessage -Key 'Install_AdminRequired')
            Write-Host ""
            Write-Host (Get-WinOpsMessage -Key 'Install_AdminPrompt') -ForegroundColor Yellow
            Write-Host "  Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', 'cd $PWD; .\bin\win-ops.ps1 install'" -ForegroundColor White
            Write-Host ""
            return
        }

        $installScript = Join-Path $script:ScriptRoot 'install.ps1'

        if (-not (Test-Path $installScript)) {
            Write-Error "Installation script not found: $installScript"
            return
        }

        Write-Host (Get-WinOpsMessage -Key 'Install_Running') -ForegroundColor Yellow
        Write-Host ""

        # Execute install script
        & $installScript

        Write-Host ""
        Write-Host (Get-WinOpsMessage -Key 'Install_Complete') -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Install_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Uninstall-WinOps {
    <#
    .SYNOPSIS
        Uninstall win-ops scheduled task
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                     $(Get-WinOpsMessage -Key 'Uninstall_Title')                                    |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        # Check for admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Error (Get-WinOpsMessage -Key 'Uninstall_AdminRequired')
            Write-Host ""
            Write-Host (Get-WinOpsMessage -Key 'Uninstall_AdminPrompt') -ForegroundColor Yellow
            Write-Host "  Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', 'cd $PWD; .\bin\win-ops.ps1 uninstall'" -ForegroundColor White
            Write-Host ""
            return
        }

        $uninstallScript = Join-Path $script:ScriptRoot 'uninstall.ps1'

        if (-not (Test-Path $uninstallScript)) {
            Write-Error "Uninstallation script not found: $uninstallScript"
            return
        }

        Write-Host (Get-WinOpsMessage -Key 'Uninstall_Running') -ForegroundColor Yellow
        Write-Host ""

        # Execute uninstall script
        & $uninstallScript

        Write-Host ""
        Write-Host (Get-WinOpsMessage -Key 'Uninstall_Complete') -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error (Get-WinOpsMessage -Key 'Uninstall_Failed' -Args $_)
        Write-Verbose $_.ScriptStackTrace
    }
}

function Set-WinOpsSchedule {
    <#
    .SYNOPSIS
        Register win-ops as a scheduled task using config settings
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                    Win-Ops Schedule Setup                                |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        # Check for admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Error (Get-WinOpsMessage -Key 'Install_AdminRequired' -Default 'Administrator privileges required.')
            Write-Host ""
            Write-Host (Get-WinOpsMessage -Key 'Install_AdminPrompt' -Default 'Run as Administrator:') -ForegroundColor Yellow
            Write-Host "  Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', 'cd $PWD; .\bin\win-ops.ps1 schedule'" -ForegroundColor White
            Write-Host ""
            return
        }

        # Load config to read schedule section
        $configModule = Join-Path $script:ScriptRoot 'lib\core\Config.psm1'
        if (Test-Path $configModule) {
            Import-Module $configModule -Force
        }

        $config = Get-WinOpsConfig
        $interval = 'Hourly'
        $startTime = $null

        if ($config -and $config.schedule) {
            if ($config.schedule.interval) { $interval = $config.schedule.interval }
            if ($config.schedule.startTime) { $startTime = $config.schedule.startTime }
        }

        # Import TaskScheduler module
        $schedulerModule = Join-Path $script:ScriptRoot 'scheduler\TaskScheduler.psm1'
        if (-not (Test-Path $schedulerModule)) {
            Write-Error "TaskScheduler module not found: $schedulerModule"
            return
        }
        Import-Module $schedulerModule -Force

        Write-Host "Registering scheduled task..." -ForegroundColor Yellow
        Write-Host "  Interval: $interval" -ForegroundColor Gray
        if ($startTime) {
            Write-Host "  Start Time: $startTime" -ForegroundColor Gray
        }
        Write-Host ""

        $params = @{
            Interval = $interval
            Force    = $true
        }
        if ($startTime) {
            $params['StartTime'] = $startTime
        }

        Install-WinOpsScheduledTask @params

        Write-Host ""
        Write-Host "Scheduled task registered successfully." -ForegroundColor Green
        Write-Host "  To change settings, edit config/win-ops.json [schedule] section." -ForegroundColor Gray
        Write-Host ""
    }
    catch {
        Write-Error "Failed to set schedule: $_"
        Write-Verbose $_.ScriptStackTrace
    }
}

function Remove-WinOpsSchedule {
    <#
    .SYNOPSIS
        Unregister win-ops scheduled task
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Host ""
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host "|                   Win-Ops Schedule Remove                                |" -ForegroundColor Cyan
        Write-Host "+==========================================================================+" -ForegroundColor Cyan
        Write-Host ""

        # Check for admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Error (Get-WinOpsMessage -Key 'Uninstall_AdminRequired' -Default 'Administrator privileges required.')
            Write-Host ""
            Write-Host (Get-WinOpsMessage -Key 'Uninstall_AdminPrompt' -Default 'Run as Administrator:') -ForegroundColor Yellow
            Write-Host "  Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', 'cd $PWD; .\bin\win-ops.ps1 unschedule'" -ForegroundColor White
            Write-Host ""
            return
        }

        # Import TaskScheduler module
        $schedulerModule = Join-Path $script:ScriptRoot 'scheduler\TaskScheduler.psm1'
        if (-not (Test-Path $schedulerModule)) {
            Write-Error "TaskScheduler module not found: $schedulerModule"
            return
        }
        Import-Module $schedulerModule -Force

        Write-Host "Removing scheduled task..." -ForegroundColor Yellow
        Write-Host ""

        Uninstall-WinOpsScheduledTask -Force

        Write-Host ""
        Write-Host "Scheduled task removed successfully." -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error "Failed to remove schedule: $_"
        Write-Verbose $_.ScriptStackTrace
    }
}

function Invoke-WinOps {
    <#
    .SYNOPSIS
        Main entry point for win-ops
    #>
    [CmdletBinding()]
    param(
        [string]$Command,
        [switch]$DryRun,
        [switch]$Force,
        [switch]$PurgeTrash,
        [switch]$All
    )

    switch ($Command.ToLower()) {
        'help' {
            Get-WinOpsHelp
        }
        'version' {
            Get-WinOpsVersion
        }
        'analyze' {
            Start-WinOpsAnalysis -DryRun:$DryRun
        }
        'run' {
            Start-WinOpsCleanup -DryRun:$DryRun -Force:$Force -PurgeTrash:$PurgeTrash -All:$All
        }
        'status' {
            Get-WinOpsStatus
        }
        'list-trash' {
            Get-TrashItems
        }
        'restore' {
            Restore-TrashItem
        }
        'install' {
            Install-WinOps
        }
        'uninstall' {
            Uninstall-WinOps
        }
        'schedule' {
            Set-WinOpsSchedule
        }
        'unschedule' {
            Remove-WinOpsSchedule
        }
        default {
            Write-Error (Get-WinOpsMessage -Key 'Error_UnknownCommand' -Args $Command)
            exit 1
        }
    }
}

# Main execution
try {
    Invoke-WinOps -Command $Command -DryRun:$DryRun -Force:$Force -PurgeTrash:$PurgeTrash -All:$All
    exit 0
}
catch {
    Write-Error (Get-WinOpsMessage -Key 'Error_Unknown' -Args $_ -Default "An error occurred: $_")
    Write-Error $_.ScriptStackTrace
    exit 1
}
