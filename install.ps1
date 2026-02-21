#Requires -Version 5.1

<#
.SYNOPSIS
    Win-Ops installation script.

.DESCRIPTION
    Installs Win-Ops system cleanup tool with the following steps:
    - Verifies PowerShell 7+ is installed (required for parallel execution)
    - Creates necessary directory structure
    - Copies files to installation directory
    - Optionally adds Win-Ops to PATH
    - Optionally installs scheduled task

.PARAMETER InstallPath
    Installation directory. Default: $env:LOCALAPPDATA\win-ops

.PARAMETER AddToPath
    Add Win-Ops bin directory to user PATH

.PARAMETER InstallScheduledTask
    Install scheduled task for automatic cleanup

.PARAMETER ScheduleInterval
    Scheduled task interval (Hourly, Daily, Weekly). Default: Hourly

.PARAMETER SkipPowerShell7Check
    Skip PowerShell 7 version check (not recommended)

.EXAMPLE
    .\install.ps1
    # Basic installation

.EXAMPLE
    .\install.ps1 -AddToPath -InstallScheduledTask
    # Full installation with PATH and scheduled task

.EXAMPLE
    .\install.ps1 -InstallPath "C:\Tools\win-ops" -AddToPath
    # Custom installation path
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'win-ops'),

    [Parameter()]
    [switch]$AddToPath,

    [Parameter()]
    [switch]$InstallScheduledTask,

    [Parameter()]
    [ValidateSet('Hourly', 'Daily', 'Weekly')]
    [string]$ScheduleInterval = 'Hourly',

    [Parameter()]
    [switch]$SkipPowerShell7Check
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

function Write-InstallMessage {
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

function Test-PowerShell7Installed {
    try {
        $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Path
        if ($pwshPath) {
            $version = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
            $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
                "Found PowerShell: $version at $pwshPath"
            } else {
                "Found PowerShell: $version at $pwshPath"
            }
            Write-InstallMessage $msg -Type Info
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Add-WinOpsToPath {
    param([string]$BinPath)

    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')

    if ($currentPath -like "*$BinPath*") {
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'InstallScript_AlreadyInPath'
        } else {
            "Win-Ops is already in PATH"
        }
        Write-InstallMessage $msg -Type Info
        return
    }

    try {
        $newPath = "$currentPath;$BinPath"
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'InstallScript_AddedToPath' -Args $BinPath
        } else {
            "Added to PATH: $BinPath"
        }
        Write-InstallMessage $msg -Type Success
        $msg2 = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'InstallScript_RestartTerminal'
        } else {
            "Restart your terminal for PATH changes to take effect"
        }
        Write-InstallMessage $msg2 -Type Warning
    } catch {
        $msg = if (Get-Command Get-WinOpsMessage -ErrorAction SilentlyContinue) {
            Get-WinOpsMessage -Key 'InstallScript_AddToPathFailed' -Args $_
        } else {
            "Failed to add to PATH: $_"
        }
        Write-InstallMessage $msg -Type Error
        throw
    }
}

#endregion

#region Installation Steps

Write-Host ""
Write-Host "+========================================+" -ForegroundColor Cyan
Write-Host "|      Win-Ops Installation Script      |" -ForegroundColor Cyan
Write-Host "+========================================+" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check PowerShell version
Write-InstallMessage "Step 1: Checking PowerShell version..." -Type Info

$currentVersion = $PSVersionTable.PSVersion
Write-InstallMessage "Current PowerShell version: $currentVersion" -Type Info

if (-not $SkipPowerShell7Check) {
    if (-not (Test-PowerShell7Installed)) {
        Write-InstallMessage "PowerShell 7+ is required for parallel execution features" -Type Warning
        Write-Host ""
        Write-Host "Install PowerShell 7+ from: https://aka.ms/powershell" -ForegroundColor Yellow
        Write-Host "Or run: winget install --id Microsoft.PowerShell --source winget" -ForegroundColor Yellow
        Write-Host ""

        $continue = Read-Host "Continue installation without PowerShell 7? (y/N)"
        if ($continue -ne 'y') {
            Write-InstallMessage "Installation cancelled" -Type Warning
            exit 1
        }

        Write-InstallMessage "Continuing without PowerShell 7 (parallel features will be disabled)" -Type Warning
    } else {
        Write-InstallMessage "PowerShell 7+ detected" -Type Success
    }
} else {
    Write-InstallMessage "Skipping PowerShell 7 check (as requested)" -Type Warning
}

# Step 2: Create installation directory
Write-InstallMessage "Step 2: Creating installation directory..." -Type Info

if (Test-Path $InstallPath) {
    Write-InstallMessage "Installation directory already exists: $InstallPath" -Type Warning

    $overwrite = Read-Host "Overwrite existing installation? (y/N)"
    if ($overwrite -ne 'y') {
        Write-InstallMessage "Installation cancelled" -Type Warning
        exit 1
    }

    Write-InstallMessage "Removing existing installation..." -Type Info
    Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
}

try {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
    Write-InstallMessage "Created: $InstallPath" -Type Success
} catch {
    Write-InstallMessage "Failed to create installation directory: $_" -Type Error
    exit 1
}

# Step 3: Create directory structure
Write-InstallMessage "Step 3: Creating directory structure..." -Type Info

$directories = @(
    'bin',
    'lib\core',
    'lib\modules',
    'lib\utils',
    'config',
    'scheduler',
    'resources',
    'logs'
)

foreach ($dir in $directories) {
    $fullPath = Join-Path $InstallPath $dir
    New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    Write-Verbose "Created: $fullPath"
}

Write-InstallMessage "Directory structure created" -Type Success

# Step 4: Copy files
Write-InstallMessage "Step 4: Copying files..." -Type Info

$sourcePath = $PSScriptRoot

try {
    # Copy main executable
    Copy-Item -Path (Join-Path $sourcePath 'bin\win-ops.ps1') -Destination (Join-Path $InstallPath 'bin') -Force
    Write-Verbose "Copied: bin\win-ops.ps1"

    # Copy core modules
    Get-ChildItem -Path (Join-Path $sourcePath 'lib\core') -Filter '*.psm1' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'lib\core') -Force
        Write-Verbose "Copied: lib\core\$($_.Name)"
    }

    # Copy cleanup modules
    Get-ChildItem -Path (Join-Path $sourcePath 'lib\modules') -Filter '*.psm1' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'lib\modules') -Force
        Write-Verbose "Copied: lib\modules\$($_.Name)"
    }

    # Copy utility modules
    Get-ChildItem -Path (Join-Path $sourcePath 'lib\utils') -Filter '*.psm1' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'lib\utils') -Force
        Write-Verbose "Copied: lib\utils\$($_.Name)"
    }

    # Copy config files
    Get-ChildItem -Path (Join-Path $sourcePath 'config') -Filter '*.json' | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'config') -Force
        Write-Verbose "Copied: config\$($_.Name)"
    }

    # Copy scheduler files
    Get-ChildItem -Path (Join-Path $sourcePath 'scheduler') | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'scheduler') -Force
        Write-Verbose "Copied: scheduler\$($_.Name)"
    }

    # Copy resources (i18n language files)
    $resourcesSource = Join-Path $sourcePath 'resources'
    if (Test-Path $resourcesSource) {
        Get-ChildItem -Path $resourcesSource -Filter '*.json' | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $InstallPath 'resources') -Force
            Write-Verbose "Copied: resources\$($_.Name)"
        }
    }

    # Copy module manifest
    if (Test-Path (Join-Path $sourcePath 'win-ops.psd1')) {
        Copy-Item -Path (Join-Path $sourcePath 'win-ops.psd1') -Destination $InstallPath -Force
        Write-Verbose "Copied: win-ops.psd1"
    }

    Write-InstallMessage "Files copied successfully" -Type Success
} catch {
    Write-InstallMessage "Failed to copy files: $_" -Type Error
    exit 1
}

# Step 5: Add to PATH (optional)
if ($AddToPath) {
    Write-InstallMessage "Step 5: Adding to PATH..." -Type Info
    $binPath = Join-Path $InstallPath 'bin'
    Add-WinOpsToPath -BinPath $binPath
} else {
    Write-InstallMessage "Step 5: Skipping PATH addition (use -AddToPath to enable)" -Type Info
}

# Step 6: Install scheduled task (optional, or auto-update if already installed)
$taskAlreadyExists = Get-ScheduledTask -TaskName "Win-Ops System Cleanup" -ErrorAction SilentlyContinue

if ($InstallScheduledTask -or $taskAlreadyExists) {
    $reason = if ($taskAlreadyExists -and -not $InstallScheduledTask) { "updating existing" } else { "installing" }
    Write-InstallMessage "Step 6: $(if ($taskAlreadyExists -and -not $InstallScheduledTask) { 'Updating existing scheduled task (auto-detected)...' } else { 'Installing scheduled task...' })" -Type Info

    if (-not (Test-IsElevated)) {
        Write-InstallMessage "Administrator privileges required for scheduled task installation" -Type Error
        Write-InstallMessage "Re-run this script as Administrator with -InstallScheduledTask" -Type Warning
    } else {
        try {
            $schedulerModule = Join-Path $InstallPath 'scheduler\TaskScheduler.psm1'
            Import-Module $schedulerModule -Force

            Install-WinOpsScheduledTask -Interval $ScheduleInterval -Force
            Write-InstallMessage "Scheduled task $reason successfully" -Type Success
        } catch {
            Write-InstallMessage "Failed to $reason scheduled task: $_" -Type Error
            Write-InstallMessage "You can install it manually later using: Install-WinOpsScheduledTask" -Type Info
        }
    }
} else {
    Write-InstallMessage "Step 6: Skipping scheduled task installation (use -InstallScheduledTask to enable)" -Type Info
}

#endregion

#region Summary

Write-Host ""
Write-Host "+========================================+" -ForegroundColor Green
Write-Host "|     Installation Complete!            |" -ForegroundColor Green
Write-Host "+========================================+" -ForegroundColor Green
Write-Host ""

Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host "  Install Path: $InstallPath" -ForegroundColor White
Write-Host "  Added to PATH: $(if ($AddToPath) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Scheduled Task: $(if ($InstallScheduledTask) { 'Installed' } else { 'Not Installed' })" -ForegroundColor White
Write-Host ""

Write-Host "Quick Start:" -ForegroundColor Cyan

if ($AddToPath) {
    Write-Host "  Restart your terminal, then run:" -ForegroundColor Yellow
    Write-Host "  > win-ops --help" -ForegroundColor White
} else {
    Write-Host "  Run from installation directory:" -ForegroundColor Yellow
    Write-Host "  > & '$InstallPath\bin\win-ops.ps1' --help" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or add to PATH manually:" -ForegroundColor Yellow
    Write-Host "  > `$env:Path += ';$InstallPath\bin'" -ForegroundColor White
}

Write-Host ""
Write-Host "Documentation: https://github.com/seunggabi/win-ops" -ForegroundColor Gray
Write-Host ""

#endregion
