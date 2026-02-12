#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows Operations Manager - Automated system maintenance and optimization toolkit

.DESCRIPTION
    win-ops is a comprehensive Windows system maintenance tool that automates cleanup,
    optimization, and monitoring tasks. It safely manages temporary files, browser caches,
    system logs, and provides rollback capabilities.

.PARAMETER Command
    The command to execute. Valid commands: help, version, run, analyze, status, list-trash, restore, install, uninstall

.PARAMETER DryRun
    Perform a dry run without making actual changes

.PARAMETER Force
    Force execution without confirmation prompts

.PARAMETER Verbose
    Enable verbose output

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
    Version: 1.0.0
    Author: Seunggabi
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'version', 'run', 'analyze', 'status', 'list-trash', 'restore', 'install', 'uninstall')]
    [string]$Command = 'help',

    [Parameter()]
    [Alias('n')]
    [switch]$DryRun,

    [Parameter()]
    [Alias('f')]
    [switch]$Force,

    [Parameter()]
    [Alias('v')]
    [switch]$Verbose
)

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module version
$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'win-ops'

# Set verbose preference if flag is provided
if ($Verbose) {
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
    Write-Host (Get-WinOpsMessage -Key 'Version_PowerShell' -Args $PSVersionTable.PSVersion) -ForegroundColor Gray
    Write-Host (Get-WinOpsMessage -Key 'Version_OS' -Args $PSVersionTable.OS) -ForegroundColor Gray
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

OPTIONS:
    --dry-run, -n   Perform analysis without making actual changes
    --force, -f     Skip confirmation prompts
    --verbose, -v   Enable verbose output

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
        [switch]$Force
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
                Import-Module $modulePath -Force
            }
        }

        # Import Analyze module
        $analyzeModule = Join-Path $script:ScriptRoot 'lib\modules\Analyze.psm1'
        if (Test-Path $analyzeModule) {
            Import-Module $analyzeModule -Force
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
            Write-Host "═══════════════`n" -ForegroundColor Cyan

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

            # Perform analysis before cleanup
            Write-Host (Get-WinOpsMessage -Key 'Cleanup_AnalyzingTargets') -ForegroundColor Cyan
            $beforeAnalysis = Get-WinOpsAnalysis -NoVisual

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

            $modulesToRun = @('CacheCleanup', 'TmpCleanup', 'LogCleanup')

            foreach ($moduleName in $modulesToRun) {
                try {
                    $modulePath = Join-Path $script:ScriptRoot "lib\modules\$moduleName.psm1"

                    if (-not (Test-Path $modulePath)) {
                        Write-Verbose "Module not found: $moduleName"
                        continue
                    }

                    Import-Module $modulePath -Force

                    $functionName = "Clear-WinOps$($moduleName.Replace('Cleanup', ''))"

                    if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                        Write-Host "  $(Get-WinOpsMessage -Key 'Cleanup_Running' -Args $moduleName)" -ForegroundColor Gray

                        $params = @{
                            DryRun = $DryRun
                        }

                        $result = & $functionName @params
                        $results += $result
                    }
                }
                catch {
                    Write-Warning (Get-WinOpsMessage -Key 'Cleanup_ModuleFailed' -Args $moduleName, $_)
                }
            }

            Write-Host "`n$(Get-WinOpsMessage -Key 'Cleanup_Complete')" -ForegroundColor Green
            Write-Host "$(Get-WinOpsMessage -Key 'Cleanup_SeeResults')`n" -ForegroundColor Gray
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
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                          $(Get-WinOpsMessage -Key 'Status_Title')                                  ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        # System status
        Write-Host "═══ $(Get-WinOpsMessage -Key 'Status_System') ═══" -ForegroundColor Cyan
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
        Write-Host "═══ $(Get-WinOpsMessage -Key 'Status_DiskUsage') ═══" -ForegroundColor Cyan
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
        Write-Host "═══ $(Get-WinOpsMessage -Key 'Status_TrashStatus') ═══" -ForegroundColor Cyan
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
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                          $(Get-WinOpsMessage -Key 'Trash_Title')                                     ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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
        Write-Host ("{0,-12} {1,-20} {2,-10} {3,-12} {4}" -f "────", "──────", "─────────", "──────────", "─────────────") -ForegroundColor DarkGray

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
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                       $(Get-WinOpsMessage -Key 'Restore_Title')                                 ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                      $(Get-WinOpsMessage -Key 'Install_Title')                                     ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                     $(Get-WinOpsMessage -Key 'Uninstall_Title')                                    ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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

function Invoke-WinOps {
    <#
    .SYNOPSIS
        Main entry point for win-ops
    #>
    [CmdletBinding()]
    param(
        [string]$Command,
        [switch]$DryRun,
        [switch]$Force
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
            Start-WinOpsCleanup -DryRun:$DryRun -Force:$Force
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
        default {
            Write-Error (Get-WinOpsMessage -Key 'Error_UnknownCommand' -Args $Command)
            exit 1
        }
    }
}

# Main execution
try {
    Invoke-WinOps -Command $Command -DryRun:$DryRun -Force:$Force -Verbose:$Verbose
    exit 0
}
catch {
    Write-Error (Get-WinOpsMessage -Key 'Error_Unknown' -Args $_ -Default "An error occurred: $_")
    Write-Error $_.ScriptStackTrace
    exit 1
}
