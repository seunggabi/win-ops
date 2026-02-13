#Requires -Version 5.1

<#
.SYNOPSIS
    Scheduled execution script for Win-Ops cleanup operations.

.DESCRIPTION
    This script is called by Windows Task Scheduler to run automated cleanup operations.
    It initializes the Win-Ops environment, executes configured cleanup modules, and logs results.

.NOTES
    This script is designed to be run by Task Scheduler with elevated privileges.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = "$PSScriptRoot\..\config\win-ops.json",

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [ValidateSet('Quiet', 'Normal', 'Verbose')]
    [string]$OutputMode = 'Quiet'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'

# Determine module path
$modulePath = Split-Path -Parent $PSScriptRoot

# Import core modules
Import-Module (Join-Path $modulePath 'lib\core\Logger.psm1') -Force
Import-Module (Join-Path $modulePath 'lib\core\Config.psm1') -Force
Import-Module (Join-Path $modulePath 'lib\core\Lock.psm1') -Force
Import-Module (Join-Path $modulePath 'lib\utils\Snapshot.psm1') -Force
Import-Module (Join-Path $modulePath 'lib\utils\Notify.psm1') -Force

# Initialize logger
$logPath = Join-Path $env:LOCALAPPDATA 'win-ops\logs\scheduled.log'
Initialize-WinOpsLogger -LogPath $logPath -LogLevel INFO

try {
    Write-WinOpsLog -Level INFO -Message "Starting scheduled Win-Ops cleanup"

    # Check for existing lock
    if (Test-WinOpsLocked) {
        Write-WinOpsLog -Level WARN -Message "Another Win-Ops instance is running. Exiting."
        exit 0
    }

    # Acquire lock
    if (-not (Lock-WinOps -TimeoutSeconds 30)) {
        Write-WinOpsLog -Level ERROR -Message "Failed to acquire lock. Exiting."
        exit 1
    }

    try {
        # Load configuration
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }

        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Take before snapshot
        Write-WinOpsLog -Level INFO -Message "Taking system snapshot (before)"
        $snapshotBefore = Get-WinOpsSnapshot -IncludeDisk -IncludeMemory

        # Module name to function name mapping
        $functionMap = @{
            'CacheCleanup'          = 'Clear-WinOpsCache'
            'TmpCleanup'            = 'Clear-WinOpsTempFiles'
            'LogCleanup'            = 'Clear-WinOpsLogFiles'
            'MemoryCleanup'         = 'Clear-WinOpsMemory'
            'RegistryCleanup'       = 'Clear-WinOpsRegistry'
            'HistoryCleanup'        = 'Clear-WinOpsHistory'
            'OrphanAppCleanup'      = 'Clear-WinOpsOrphanedAppData'
            'BrowserCleanup'        = 'Clear-WinOpsBrowserData'
            'DevCleanup'            = 'Invoke-WinOpsDevCleanup'
            'DockerCleanup'         = 'Clear-WinOpsDockerResources'
            'PackageManagerCleanup' = 'Clear-WinOpsPackageManagerCache'
            'ZombieKiller'          = 'Invoke-WinOpsZombieCleanup'
            'OrphanKiller'          = 'Invoke-WinOpsOrphanCleanup'
        }

        # Execute cleanup modules based on configuration
        $results = @()
        $totalFreed = 0
        $totalItems = 0

        foreach ($module in $config.Modules) {
            if (-not $module.Enabled) {
                Write-WinOpsLog -Level DEBUG -Message "Module $($module.Name) is disabled"
                continue
            }

            try {
                Write-WinOpsLog -Level INFO -Message "Executing module: $($module.Name)"

                # Import module
                $moduleFilePath = Join-Path $modulePath "lib\modules\$($module.Name).psm1"

                if (-not (Test-Path $moduleFilePath)) {
                    Write-WinOpsLog -Level WARN -Message "Module file not found: $moduleFilePath"
                    continue
                }

                Import-Module $moduleFilePath -Force

                # Execute cleanup function (use mapping, fallback to convention)
                $functionName = if ($functionMap.ContainsKey($module.Name)) { $functionMap[$module.Name] } else { "Clear-WinOps$($module.Name)" }

                if (-not (Get-Command $functionName -ErrorAction SilentlyContinue)) {
                    Write-WinOpsLog -Level WARN -Message "Function $functionName not found"
                    continue
                }

                # Build parameters from config
                $params = @{}

                if ($DryRun) {
                    $params['DryRun'] = $true
                }

                if ($module.Settings -and @($module.Settings.PSObject.Properties).Count -gt 0) {
                    foreach ($key in $module.Settings.PSObject.Properties.Name) {
                        $params[$key] = $module.Settings.$key
                    }
                }

                # Execute
                $result = & $functionName @params -ErrorAction Stop

                # Collect statistics
                if ($result) {
                    $itemsRemoved = 0
                    $spaceFreed = 0

                    if ($result.PSObject.Properties['ItemsRemoved']) {
                        $itemsRemoved = $result.ItemsRemoved
                    } elseif ($result.PSObject.Properties['RemovedCount']) {
                        $itemsRemoved = $result.RemovedCount
                    } elseif ($result.PSObject.Properties['FilesRemoved']) {
                        $itemsRemoved = $result.FilesRemoved
                    }

                    if ($result.PSObject.Properties['SpaceFreedMB']) {
                        $spaceFreed = $result.SpaceFreedMB * 1MB
                    } elseif ($result.PSObject.Properties['RemovedSize']) {
                        $spaceFreed = $result.RemovedSize
                    } elseif ($result.PSObject.Properties['TotalSize']) {
                        $spaceFreed = $result.TotalSize
                    }

                    $totalItems += $itemsRemoved
                    $totalFreed += $spaceFreed

                    $results += @{
                        Module = $module.Name
                        Success = $true
                        ItemsRemoved = $itemsRemoved
                        SpaceFreed = $spaceFreed
                    }

                    Write-WinOpsLog -Level INFO -Message "Module $($module.Name) completed: $itemsRemoved items, $([math]::Round($spaceFreed / 1MB, 2)) MB freed"
                } else {
                    $results += @{
                        Module = $module.Name
                        Success = $true
                        ItemsRemoved = 0
                        SpaceFreed = 0
                    }
                }

            } catch {
                Write-WinOpsLog -Level ERROR -Message "Module $($module.Name) failed" -Exception $_
                $results += @{
                    Module = $module.Name
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }

        # Take after snapshot
        Write-WinOpsLog -Level INFO -Message "Taking system snapshot (after)"
        $snapshotAfter = Get-WinOpsSnapshot -IncludeDisk -IncludeMemory

        # Compare snapshots
        $comparison = Compare-WinOpsSnapshot -Before $snapshotBefore -After $snapshotAfter -Format Raw

        # Generate summary
        $totalFreedGB = [math]::Round($totalFreed / 1GB, 2)
        $successCount = @($results | Where-Object { $_.Success }).Count
        $failureCount = @($results | Where-Object { -not $_.Success }).Count

        $summary = @"
Win-Ops Scheduled Cleanup Summary
==================================
Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Total Modules: $($results.Count)
Successful: $successCount
Failed: $failureCount
Total Items Cleaned: $totalItems
Total Space Freed: $totalFreedGB GB

Disk Space Change:
"@

        if ($comparison.Disk) {
            foreach ($drive in $comparison.Disk.Keys) {
                $diskChange = $comparison.Disk[$drive]
                $summary += "`n  $drive - Freed: $($diskChange.FreedGB) GB (Used: $($diskChange.BeforeUsedPercent)% -> $($diskChange.AfterUsedPercent)%)"
            }
        }

        Write-WinOpsLog -Level INFO -Message $summary

        # Send notification if configured
        if ($config.Notifications -and $config.Notifications.Enabled) {
            $notificationType = if ($failureCount -gt 0) { 'Warning' } else { 'Success' }
            $notificationMessage = "Cleaned $totalItems items, freed $totalFreedGB GB. $successCount/$($results.Count) modules succeeded."

            Send-WinOpsNotification -Title "Win-Ops Cleanup Complete" -Message $notificationMessage -Type $notificationType
        }

        Write-WinOpsLog -Level INFO -Message "Scheduled cleanup completed successfully"
        exit 0

    } finally {
        # Release lock
        Unlock-WinOps
    }

} catch {
    Write-WinOpsLog -Level ERROR -Message "Scheduled cleanup failed" -Exception $_

    # Send error notification
    try {
        Send-WinOpsNotification -Title "Win-Ops Cleanup Failed" -Message $_.Exception.Message -Type Error
    } catch {
        # Silent failure for notification
    }

    exit 1
}
