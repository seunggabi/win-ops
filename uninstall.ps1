#Requires -Version 5.1

<#
.SYNOPSIS
    Win-Ops uninstallation script.

.DESCRIPTION
    Removes Win-Ops system cleanup tool with the following steps:
    - Removes scheduled task (if installed)
    - Removes from PATH (if added)
    - Removes installation directory
    - Optionally removes data directories (logs, trash)

.PARAMETER InstallPath
    Installation directory. Default: $env:LOCALAPPDATA\win-ops

.PARAMETER RemoveData
    Remove data directories (logs, trash). Default: prompt user

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\uninstall.ps1
    # Interactive uninstallation

.EXAMPLE
    .\uninstall.ps1 -RemoveData -Force
    # Complete removal without prompts

.EXAMPLE
    .\uninstall.ps1 -InstallPath "C:\Tools\win-ops" -Force
    # Uninstall from custom path
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'win-ops'),

    [Parameter()]
    [switch]$RemoveData,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import I18n module
$scriptRoot = $PSScriptRoot
$i18nModule = Join-Path $scriptRoot 'lib\core\I18n.psm1'
if (Test-Path $i18nModule) {
    Import-Module $i18nModule -Force
    Initialize-WinOpsI18n
}

#region Helper Functions

function Write-UninstallMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $color = switch ($Type) {
        'Info'    { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
    }

    $prefix = switch ($Type) {
        'Info'    { if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) { Get-WinOpsMessage -Key 'Status_Info' } else { '[INFO]' } }
        'Success' { if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) { Get-WinOpsMessage -Key 'Status_Success' } else { '[OK]' } }
        'Warning' { if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) { Get-WinOpsMessage -Key 'Status_Warning' } else { '[WARN]' } }
        'Error'   { if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) { Get-WinOpsMessage -Key 'Status_Error' } else { '[ERROR]' } }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-WinOpsFromPath {
    param([string]$BinPath)

    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')

    if ($currentPath -notlike "*$BinPath*") {
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'UninstallScript_NotInPath'
        } else {
            "Win-Ops is not in PATH"
        }
        Write-UninstallMessage $msg -Type Info
        return
    }

    try {
        $pathEntries = $currentPath -split ';' | Where-Object { $_ -notlike "*$BinPath*" }
        $newPath = $pathEntries -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'UninstallScript_RemovedFromPath' -Args $BinPath
        } else {
            "Removed from PATH: $BinPath"
        }
        Write-UninstallMessage $msg -Type Success
    } catch {
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'UninstallScript_RemovePathFailed' -Args $_
        } else {
            "Failed to remove from PATH: $_"
        }
        Write-UninstallMessage $msg -Type Error
        throw
    }
}

#endregion

#region Uninstallation Steps

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║    Win-Ops Uninstallation Script      ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Confirmation prompt
if (-not $Force) {
    Write-Host "This will remove Win-Ops from your system." -ForegroundColor Yellow
    Write-Host "Installation Path: $InstallPath" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Continue with uninstallation? (y/N)"
    if ($confirm -ne 'y') {
        Write-UninstallMessage "Uninstallation cancelled" -Type Warning
        exit 0
    }
}

# Step 1: Check if installation exists
Write-UninstallMessage "Step 1: Checking installation..." -Type Info

if (-not (Test-Path $InstallPath)) {
    Write-UninstallMessage "Installation not found at: $InstallPath" -Type Warning

    $customPath = Read-Host "Enter custom installation path (or press Enter to exit)"
    if ([string]::IsNullOrWhiteSpace($customPath)) {
        Write-UninstallMessage "Uninstallation cancelled" -Type Warning
        exit 0
    }

    $InstallPath = $customPath
    if (-not (Test-Path $InstallPath)) {
        Write-UninstallMessage "Installation not found at: $InstallPath" -Type Error
        exit 1
    }
}

Write-UninstallMessage "Found installation at: $InstallPath" -Type Success

# Step 2: Remove scheduled task
Write-UninstallMessage "Step 2: Removing scheduled task..." -Type Info

try {
    $taskName = "Win-Ops System Cleanup"
    $scheduledTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($scheduledTask) {
        if (-not (Test-IsElevated)) {
            Write-UninstallMessage "Administrator privileges required to remove scheduled task" -Type Warning
            Write-UninstallMessage "Please remove the task manually or re-run as Administrator" -Type Info
        } else {
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                Write-UninstallMessage "Scheduled task removed successfully" -Type Success
            } catch {
                Write-UninstallMessage "Failed to remove scheduled task: $_" -Type Error
            }
        }
    } else {
        Write-UninstallMessage "No scheduled task found" -Type Info
    }
} catch {
    Write-UninstallMessage "Error checking scheduled task: $_" -Type Warning
}

# Step 3: Remove from PATH
Write-UninstallMessage "Step 3: Removing from PATH..." -Type Info

$binPath = Join-Path $InstallPath 'bin'
Remove-WinOpsFromPath -BinPath $binPath

# Step 4: Remove installation directory
Write-UninstallMessage "Step 4: Removing installation files..." -Type Info

try {
    # Stop any running processes
    $processNames = @('win-ops', 'pwsh')
    foreach ($processName in $processNames) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "$InstallPath*" }

        if ($processes) {
            Write-UninstallMessage "Stopping $($processes.Count) Win-Ops process(es)..." -Type Warning
            $processes | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    # Remove installation directory
    Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
    Write-UninstallMessage "Installation directory removed" -Type Success
} catch {
    Write-UninstallMessage "Failed to remove installation directory: $_" -Type Error
    Write-UninstallMessage "You may need to remove it manually: $InstallPath" -Type Warning
}

# Step 5: Remove data directories (optional)
Write-UninstallMessage "Step 5: Cleaning up data directories..." -Type Info

$dataPaths = @{
    'Logs' = (Join-Path $env:LOCALAPPDATA 'win-ops\logs')
    'Trash' = (Join-Path $env:LOCALAPPDATA 'win-ops\trash')
    'Config' = (Join-Path $env:LOCALAPPDATA 'win-ops\config')
}

$shouldRemoveData = $RemoveData

if (-not $Force -and -not $RemoveData) {
    Write-Host ""
    Write-Host "Data directories found:" -ForegroundColor Yellow

    foreach ($key in $dataPaths.Keys) {
        if (Test-Path $dataPaths[$key]) {
            $size = (Get-ChildItem -Path $dataPaths[$key] -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            Write-Host "  $key`: $($dataPaths[$key]) ($sizeMB MB)" -ForegroundColor White
        }
    }

    Write-Host ""
    $removeDataResponse = Read-Host "Remove data directories? (y/N)"
    $shouldRemoveData = ($removeDataResponse -eq 'y')
}

if ($shouldRemoveData) {
    foreach ($key in $dataPaths.Keys) {
        $path = $dataPaths[$key]
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-UninstallMessage "Removed $key`: $path" -Type Success
            } catch {
                Write-UninstallMessage "Failed to remove $key`: $_" -Type Warning
            }
        } else {
            Write-Verbose "$key not found: $path"
        }
    }
} else {
    Write-UninstallMessage "Data directories preserved (remove manually if needed)" -Type Info
}

# Step 6: Clean up parent directory if empty
$parentDir = Join-Path $env:LOCALAPPDATA 'win-ops'
if (Test-Path $parentDir) {
    $items = Get-ChildItem -Path $parentDir -Force -ErrorAction SilentlyContinue
    if ($items.Count -eq 0) {
        try {
            Remove-Item -Path $parentDir -Force -ErrorAction Stop
            Write-UninstallMessage "Removed empty parent directory" -Type Success
        } catch {
            Write-Verbose "Could not remove parent directory: $_"
        }
    }
}

#endregion

#region Summary

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║    Uninstallation Complete! ✓          ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Uninstallation Summary:" -ForegroundColor Cyan
Write-Host "  Installation removed: Yes" -ForegroundColor White
Write-Host "  Scheduled task removed: $(if ($scheduledTask) { 'Yes' } else { 'N/A' })" -ForegroundColor White
Write-Host "  Data directories removed: $(if ($shouldRemoveData) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Removed from PATH: Yes" -ForegroundColor White
Write-Host ""

if (-not $shouldRemoveData) {
    Write-Host "Data directories were preserved at:" -ForegroundColor Yellow
    foreach ($key in $dataPaths.Keys) {
        if (Test-Path $dataPaths[$key]) {
            Write-Host "  $($dataPaths[$key])" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

Write-Host "Win-Ops has been uninstalled from your system." -ForegroundColor Green
Write-Host "Restart your terminal for PATH changes to take effect." -ForegroundColor Gray
Write-Host ""

#endregion
