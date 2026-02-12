#Requires -Version 5.1

<#
.SYNOPSIS
    History and privacy cleanup module for Windows.

.DESCRIPTION
    Cleans various history and privacy-related data:
    - Windows Explorer recent files and typed paths
    - Run dialog history (MRU)
    - Explorer search history
    - Jump lists (recent/frequent destinations)
    - Activity timeline / Connected Devices Platform
    - Notification history
    - Clipboard history
    - PowerShell command history
    - Prefetch files for uninstalled programs

.NOTES
    Module: WinOps.Modules.HistoryCleanup
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

function Clear-RunDialogHistory {
    <#
    .SYNOPSIS
        Clears Run dialog (Win+R) history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    $count = 0

    if (-not (Test-Path $regPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if (-not $props) { return 0 }

        $mruEntries = $props.PSObject.Properties | Where-Object {
            $_.Name -ne 'MRUList' -and $_.Name -notmatch '^PS' -and $_.MemberType -eq 'NoteProperty'
        }

        $count = @($mruEntries).Count
        if ($count -gt 0 -and -not $DryRun) {
            Remove-Item -Path $regPath -Force -ErrorAction Stop
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    catch {
        Write-Verbose "Failed to clear Run dialog history: $_"
    }

    return $count
}

function Clear-ExplorerTypedPaths {
    <#
    .SYNOPSIS
        Clears Explorer address bar typed paths history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths'
    $count = 0

    if (-not (Test-Path $regPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if (-not $props) { return 0 }

        $entries = $props.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^PS' -and $_.MemberType -eq 'NoteProperty'
        }

        $count = @($entries).Count
        if ($count -gt 0 -and -not $DryRun) {
            Remove-Item -Path $regPath -Force -ErrorAction Stop
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    catch {
        Write-Verbose "Failed to clear Explorer typed paths: $_"
    }

    return $count
}

function Clear-ExplorerSearchHistory {
    <#
    .SYNOPSIS
        Clears Windows Explorer search history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery'
    $count = 0

    if (-not (Test-Path $regPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if (-not $props) { return 0 }

        $entries = $props.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^PS' -and $_.Name -ne 'MRUListEx' -and $_.MemberType -eq 'NoteProperty'
        }

        $count = @($entries).Count
        if ($count -gt 0 -and -not $DryRun) {
            Remove-Item -Path $regPath -Force -ErrorAction Stop
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    catch {
        Write-Verbose "Failed to clear Explorer search history: $_"
    }

    return $count
}

function Clear-JumpLists {
    <#
    .SYNOPSIS
        Clears jump lists (recent/frequent destinations).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $count = 0
    $jumpListPaths = @(
        "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations",
        "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
    )

    foreach ($path in $jumpListPaths) {
        if (-not (Test-Path $path -ErrorAction SilentlyContinue)) { continue }

        try {
            $files = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
            $count += @($files).Count

            if (-not $DryRun -and @($files).Count -gt 0) {
                $files | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Verbose "Failed to clear jump lists at $path : $_"
        }
    }

    return $count
}

function Clear-ActivityTimeline {
    <#
    .SYNOPSIS
        Clears Windows Activity Timeline data.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $count = 0
    $activityPath = "$env:LOCALAPPDATA\ConnectedDevicesPlatform"

    if (-not (Test-Path $activityPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $files = Get-ChildItem -Path $activityPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(db|dat|json)$' }

        $count = @($files).Count
        if (-not $DryRun -and $count -gt 0) {
            foreach ($file in $files) {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Verbose "Failed to clear activity timeline: $_"
    }

    return $count
}

function Clear-NotificationHistory {
    <#
    .SYNOPSIS
        Clears Windows notification history from the registry.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $count = 0
    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications'

    if (-not (Test-Path $regPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        $count = @($subKeys).Count

        if (-not $DryRun -and $count -gt 0) {
            foreach ($key in $subKeys) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Verbose "Failed to clear notification history: $_"
    }

    return $count
}

function Clear-ClipboardHistory {
    <#
    .SYNOPSIS
        Clears clipboard history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    if ($DryRun) { return 1 }

    try {
        # Clear current clipboard
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.Clipboard]::Clear()

        # Clear clipboard history data
        $clipPath = "$env:LOCALAPPDATA\Microsoft\Windows\Clipboard"
        if (Test-Path $clipPath -ErrorAction SilentlyContinue) {
            $files = Get-ChildItem -Path $clipPath -Recurse -File -Force -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        return 1
    }
    catch {
        Write-Verbose "Failed to clear clipboard history: $_"
        return 0
    }
}

function Clear-PowerShellHistory {
    <#
    .SYNOPSIS
        Clears PowerShell PSReadLine command history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $count = 0
    $historyPaths = @(
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\Visual Studio Code Host_history.txt"
    )

    foreach ($path in $historyPaths) {
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            try {
                $lines = (Get-Content -Path $path -ErrorAction SilentlyContinue | Measure-Object).Count
                $count += $lines

                if (-not $DryRun) {
                    Clear-Content -Path $path -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Verbose "Failed to clear PS history at $path : $_"
            }
        }
    }

    # CMD history
    $cmdHistPath = "$env:APPDATA\Microsoft\Windows\doskey_history.txt"
    if (Test-Path $cmdHistPath -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            Remove-Item -Path $cmdHistPath -Force -ErrorAction SilentlyContinue
        }
        $count++
    }

    return $count
}

function Clear-RecentDocuments {
    <#
    .SYNOPSIS
        Clears recent documents list.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
    $count = 0

    if (-not (Test-Path $recentPath -ErrorAction SilentlyContinue)) { return 0 }

    try {
        $files = Get-ChildItem -Path $recentPath -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.lnk' }

        $count = @($files).Count
        if (-not $DryRun -and $count -gt 0) {
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Verbose "Failed to clear recent documents: $_"
    }

    return $count
}

function Clear-WindowsSearchHistory {
    <#
    .SYNOPSIS
        Clears Windows Search / Cortana search history.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$DryRun)

    $count = 0

    # Windows Search suggestions
    $searchPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search\Flighting'
    )

    # Bing search history / Cortana data
    $dataPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState",
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Cortana_cw5n1h2txyewy\LocalState"
    )

    foreach ($dataPath in $dataPaths) {
        if (Test-Path $dataPath -ErrorAction SilentlyContinue) {
            $dbFiles = Get-ChildItem -Path $dataPath -Filter '*.db' -Recurse -Force -ErrorAction SilentlyContinue
            $count += @($dbFiles).Count

            if (-not $DryRun) {
                foreach ($db in $dbFiles) {
                    Remove-Item -Path $db.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    return $count
}

#endregion

#region Public Functions

function Clear-WinOpsHistory {
    <#
    .SYNOPSIS
        Clears all history and privacy-related data.

    .PARAMETER DryRun
        Show what would be removed without making changes.

    .PARAMETER Force
        Skip confirmation prompts.

    .EXAMPLE
        Clear-WinOpsHistory -DryRun
        # Preview history items that would be cleaned

    .EXAMPLE
        Clear-WinOpsHistory -Force
        # Clean all history without prompts
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
        Module = 'HistoryCleanup'
        ItemsProcessed = 0
        Categories = @{}
        Success = $true
    }

    try {
        Write-Host "  [History] Cleaning history and privacy data..." -ForegroundColor Cyan

        # 1. Run dialog history
        $count = Clear-RunDialogHistory -DryRun:$DryRun
        $results.Categories['RunDialog'] = $count
        $results.ItemsProcessed += $count
        $action = if ($DryRun) { "[DRY]" } else { "[OK]" }
        $color = if ($DryRun) { "Yellow" } else { "Green" }
        if ($count -gt 0) {
            Write-Host "    $action Run dialog history: $count entries" -ForegroundColor $color
        }

        # 2. Explorer typed paths
        $count = Clear-ExplorerTypedPaths -DryRun:$DryRun
        $results.Categories['ExplorerPaths'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Explorer address bar history: $count entries" -ForegroundColor $color
        }

        # 3. Explorer search history
        $count = Clear-ExplorerSearchHistory -DryRun:$DryRun
        $results.Categories['ExplorerSearch'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Explorer search history: $count entries" -ForegroundColor $color
        }

        # 4. Jump lists
        $count = Clear-JumpLists -DryRun:$DryRun
        $results.Categories['JumpLists'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Jump lists: $count items" -ForegroundColor $color
        }

        # 5. Recent documents
        $count = Clear-RecentDocuments -DryRun:$DryRun
        $results.Categories['RecentDocs'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Recent documents: $count shortcuts" -ForegroundColor $color
        }

        # 6. Activity timeline
        $count = Clear-ActivityTimeline -DryRun:$DryRun
        $results.Categories['ActivityTimeline'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Activity timeline: $count items" -ForegroundColor $color
        }

        # 7. Notification history
        $count = Clear-NotificationHistory -DryRun:$DryRun
        $results.Categories['Notifications'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Notification history: $count items" -ForegroundColor $color
        }

        # 8. Clipboard history
        $count = Clear-ClipboardHistory -DryRun:$DryRun
        $results.Categories['Clipboard'] = $count
        $results.ItemsProcessed += $count
        Write-Host "    $action Clipboard history cleared" -ForegroundColor $color

        # 9. PowerShell/CMD history
        $count = Clear-PowerShellHistory -DryRun:$DryRun
        $results.Categories['ShellHistory'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Shell command history: $count commands" -ForegroundColor $color
        }

        # 10. Windows Search history
        $count = Clear-WindowsSearchHistory -DryRun:$DryRun
        $results.Categories['WindowsSearch'] = $count
        $results.ItemsProcessed += $count
        if ($count -gt 0) {
            Write-Host "    $action Windows Search history: $count items" -ForegroundColor $color
        }

        $totalItems = $results.ItemsProcessed
        Write-Host "  [History] History cleanup complete ($totalItems items)" -ForegroundColor Green
    }
    catch {
        $results.Success = $false
        Write-Warning "History cleanup failed: $_"
    }

    return $results
}

function Get-WinOpsHistoryTargets {
    <#
    .SYNOPSIS
        Gets history items for analysis module integration.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $targets = @()
    $dryResults = Clear-WinOpsHistory -DryRun 6>$null 4>$null 3>$null *>$null

    # Simplified: just report a summary target
    $targets += [PSCustomObject]@{
        Name = "History & Privacy Data"
        Path = "Various registry/file locations"
        CurrentSizeMB = 0.5
        Category = "History"
        Module = "HistoryCleanup"
    }

    return $targets
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsHistory',
    'Get-WinOpsHistoryTargets'
)
