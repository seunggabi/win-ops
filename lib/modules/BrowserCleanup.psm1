#Requires -Version 5.1

<#
.SYNOPSIS
    Browser cleanup module for Chrome, Edge, Firefox, and other browsers.

.DESCRIPTION
    Cleans browser-specific data:
    - Cache files
    - Cookies
    - History
    - Download history
    - Session data
    - Extension caches
    Supports: Chrome, Edge, Firefox, Opera, Brave

.NOTES
    Module: WinOps.Modules.BrowserCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force

#region Browser Definitions

$script:Browsers = @{
    Chrome = @{
        Name = "Google Chrome"
        ProcessName = "chrome"
        BasePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        DataTypes = @{
            Cache = @{
                Paths = @(
                    "Default\Cache",
                    "Default\Code Cache",
                    "Default\GPUCache",
                    "ShaderCache",
                    "GrShaderCache"
                )
                Description = "Browser cache"
            }
            Cookies = @{
                Paths = @(
                    "Default\Cookies",
                    "Default\Cookies-journal"
                )
                Description = "Cookies"
            }
            History = @{
                Paths = @(
                    "Default\History",
                    "Default\History-journal",
                    "Default\Visited Links"
                )
                Description = "Browsing history"
            }
            Downloads = @{
                Paths = @(
                    "Default\History"  # Downloads are in History database
                )
                Description = "Download history"
            }
            Sessions = @{
                Paths = @(
                    "Default\Sessions",
                    "Default\Session Storage"
                )
                Description = "Session data"
            }
        }
    }

    Edge = @{
        Name = "Microsoft Edge"
        ProcessName = "msedge"
        BasePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        DataTypes = @{
            Cache = @{
                Paths = @(
                    "Default\Cache",
                    "Default\Code Cache",
                    "Default\GPUCache",
                    "ShaderCache"
                )
                Description = "Browser cache"
            }
            Cookies = @{
                Paths = @(
                    "Default\Cookies",
                    "Default\Cookies-journal"
                )
                Description = "Cookies"
            }
            History = @{
                Paths = @(
                    "Default\History",
                    "Default\History-journal",
                    "Default\Visited Links"
                )
                Description = "Browsing history"
            }
            Sessions = @{
                Paths = @(
                    "Default\Sessions",
                    "Default\Session Storage"
                )
                Description = "Session data"
            }
        }
    }

    Firefox = @{
        Name = "Mozilla Firefox"
        ProcessName = "firefox"
        BasePath = "$env:APPDATA\Mozilla\Firefox\Profiles"
        DataTypes = @{
            Cache = @{
                Paths = @(
                    "*\cache2",
                    "*\startupCache",
                    "*\OfflineCache"
                )
                Description = "Browser cache"
            }
            Cookies = @{
                Paths = @(
                    "*\cookies.sqlite",
                    "*\cookies.sqlite-shm",
                    "*\cookies.sqlite-wal"
                )
                Description = "Cookies"
            }
            History = @{
                Paths = @(
                    "*\places.sqlite",
                    "*\places.sqlite-shm",
                    "*\places.sqlite-wal"
                )
                Description = "Browsing history and bookmarks"
            }
            Sessions = @{
                Paths = @(
                    "*\sessionstore.jsonlz4",
                    "*\sessionstore-backups"
                )
                Description = "Session data"
            }
        }
    }

    Brave = @{
        Name = "Brave Browser"
        ProcessName = "brave"
        BasePath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
        DataTypes = @{
            Cache = @{
                Paths = @(
                    "Default\Cache",
                    "Default\Code Cache",
                    "Default\GPUCache"
                )
                Description = "Browser cache"
            }
            Cookies = @{
                Paths = @(
                    "Default\Cookies",
                    "Default\Cookies-journal"
                )
                Description = "Cookies"
            }
            History = @{
                Paths = @(
                    "Default\History",
                    "Default\History-journal"
                )
                Description = "Browsing history"
            }
        }
    }

    Opera = @{
        Name = "Opera"
        ProcessName = "opera"
        BasePath = "$env:APPDATA\Opera Software\Opera Stable"
        DataTypes = @{
            Cache = @{
                Paths = @(
                    "Cache",
                    "Code Cache",
                    "GPUCache"
                )
                Description = "Browser cache"
            }
            Cookies = @{
                Paths = @(
                    "Cookies",
                    "Cookies-journal"
                )
                Description = "Cookies"
            }
            History = @{
                Paths = @(
                    "History",
                    "History-journal"
                )
                Description = "Browsing history"
            }
        }
    }
}

#endregion

#region Private Functions

function Test-BrowserRunning {
    <#
    .SYNOPSIS
        Checks if browser process is currently running.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName
    )

    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return ($null -ne $process)
}

function Get-BrowserDataSize {
    <#
    .SYNOPSIS
        Calculates size of browser data.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string[]]$RelativePaths
    )

    $totalSize = 0

    foreach ($relativePath in $RelativePaths) {
        $fullPath = Join-Path $BasePath $relativePath
        $expandedPath = [Environment]::ExpandEnvironmentVariables($fullPath)

        try {
            if ($expandedPath -like '*`**') {
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
            } else {
                if (-not (Test-Path $expandedPath)) {
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            foreach ($item in $items) {
                if (-not $item.PSIsContainer) {
                    $totalSize += $item.Length
                }
            }
        }
        catch {
            Write-Verbose "Failed to access path $expandedPath`: $_"
        }
    }

    return $totalSize
}

function Remove-BrowserData {
    <#
    .SYNOPSIS
        Removes browser data from specified paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string[]]$RelativePaths,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$BrowserName,

        [Parameter()]
        [string]$DataType
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $errors = @()

    foreach ($relativePath in $RelativePaths) {
        $fullPath = Join-Path $BasePath $relativePath
        $expandedPath = [Environment]::ExpandEnvironmentVariables($fullPath)

        try {
            if ($expandedPath -like '*`**') {
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction Stop
            } else {
                if (-not (Test-Path $expandedPath)) {
                    Write-Verbose "Path does not exist: $expandedPath"
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction Stop
            }

            foreach ($item in $items) {
                try {
                    # Check if file is in use
                    if (-not $item.PSIsContainer) {
                        try {
                            $stream = [File]::Open($item.FullName, [FileMode]::Open, [FileAccess]::Read, [FileShare]::None)
                            $stream.Close()
                            $stream.Dispose()
                        }
                        catch {
                            Write-Verbose "File in use or locked: $($item.FullName)"
                            $failedCount++
                            continue
                        }
                    }

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

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove $BrowserName $DataType")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module "BrowserCleanup.$BrowserName" -ErrorAction Stop | Out-Null
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
            $errorMsg = "Failed to access path $expandedPath`: $_"
            $errors += $errorMsg
            Write-Verbose $errorMsg
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

function Clear-WinOpsBrowserData {
    <#
    .SYNOPSIS
        Clears browser data for specified browsers and data types.

    .DESCRIPTION
        Removes browser cache, cookies, history, and other data with safety checks.

    .PARAMETER Browser
        Browser to clean. Valid values: Chrome, Edge, Firefox, Brave, Opera, All

    .PARAMETER DataType
        Type of data to clean. Valid values: Cache, Cookies, History, Downloads, Sessions, All

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion.

    .PARAMETER Force
        Bypass confirmation prompts and close browser if running.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .EXAMPLE
        Clear-WinOpsBrowserData -Browser Chrome -DataType Cache
        # Clears Chrome cache

    .EXAMPLE
        Clear-WinOpsBrowserData -Browser All -DataType Cache -UseTrash
        # Clears cache for all browsers with recovery option

    .EXAMPLE
        Clear-WinOpsBrowserData -Browser Edge -DataType All -Force
        # Clears all Edge data, closing browser if needed
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Chrome', 'Edge', 'Firefox', 'Brave', 'Opera', 'All')]
        [string]$Browser,

        [Parameter(Mandatory)]
        [ValidateSet('Cache', 'Cookies', 'History', 'Downloads', 'Sessions', 'All')]
        [string]$DataType,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DryRun
    )

    Write-WinOpsLog -Level INFO -Message "Starting browser data cleanup: $Browser - $DataType"

    $browsersToClean = if ($Browser -eq 'All') {
        $script:Browsers.Keys
    } else {
        @($Browser)
    }

    $results = @()

    foreach ($browserKey in $browsersToClean) {
        $browserInfo = $script:Browsers[$browserKey]

        # Check if browser is installed
        $basePath = [Environment]::ExpandEnvironmentVariables($browserInfo.BasePath)
        if (-not (Test-Path $basePath)) {
            Write-Verbose "$($browserInfo.Name) not installed (path not found: $basePath)"
            continue
        }

        Write-Verbose "Processing browser: $($browserInfo.Name)"

        # Check if browser is running
        $isRunning = Test-BrowserRunning -ProcessName $browserInfo.ProcessName

        if ($isRunning) {
            if ($Force) {
                # Safety check: verify process is not protected
                if (Test-WinOpsProcessProtected -ProcessName $browserInfo.ProcessName) {
                    Write-Warning "Cannot close protected process: $($browserInfo.Name)"
                    continue
                }

                Write-Warning "Closing $($browserInfo.Name)..."
                try {
                    Stop-Process -Name $browserInfo.ProcessName -Force -ErrorAction Stop
                    Start-Sleep -Seconds 2
                }
                catch {
                    Write-Warning "Failed to close $($browserInfo.Name): $_"
                    continue
                }
            } else {
                Write-Warning "$($browserInfo.Name) is running. Use -Force to close it automatically."
                continue
            }
        }

        # Determine data types to clean
        $dataTypesToClean = if ($DataType -eq 'All') {
            $browserInfo.DataTypes.Keys
        } else {
            if ($browserInfo.DataTypes.ContainsKey($DataType)) {
                @($DataType)
            } else {
                Write-Warning "$($browserInfo.Name) does not support cleaning $DataType"
                continue
            }
        }

        foreach ($dataTypeKey in $dataTypesToClean) {
            $dataTypeInfo = $browserInfo.DataTypes[$dataTypeKey]

            Write-Verbose "Processing data type: $dataTypeKey - $($dataTypeInfo.Description)"

            # Calculate current size
            $currentSize = Get-BrowserDataSize -BasePath $basePath -RelativePaths $dataTypeInfo.Paths

            if ($currentSize -eq 0) {
                Write-Verbose "No data found for $($browserInfo.Name) $dataTypeKey"
                continue
            }

            Write-Verbose "Data size: $($browserInfo.Name) $dataTypeKey = $([math]::Round($currentSize / 1MB, 2)) MB"

            if ($DryRun) {
                $results += [PSCustomObject]@{
                    Browser = $browserInfo.Name
                    DataType = $dataTypeKey
                    Description = $dataTypeInfo.Description
                    CurrentSize = $currentSize
                    WouldRemove = $true
                    RemovedCount = 0
                    RemovedSize = 0
                }
                continue
            }

            # Confirmation
            if (-not $Force -and -not $PSCmdlet.ShouldProcess(
                "$($browserInfo.Name) $dataTypeKey ($([math]::Round($currentSize / 1MB, 2)) MB)",
                "Clear browser data"
            )) {
                Write-Verbose "Skipped by user: $($browserInfo.Name) $dataTypeKey"
                continue
            }

            # Remove data
            $removeResult = Remove-BrowserData `
                -BasePath $basePath `
                -RelativePaths $dataTypeInfo.Paths `
                -UseTrash:$UseTrash `
                -BrowserName $browserInfo.Name `
                -DataType $dataTypeKey

            $results += [PSCustomObject]@{
                Browser = $browserInfo.Name
                DataType = $dataTypeKey
                Description = $dataTypeInfo.Description
                CurrentSize = $currentSize
                RemovedCount = $removeResult.RemovedCount
                RemovedSize = $removeResult.RemovedSize
                FailedCount = $removeResult.FailedCount
                Errors = $removeResult.Errors
            }

            Write-WinOpsLog -Level INFO -Message "Cleaned $($browserInfo.Name) $dataTypeKey`: Removed $($removeResult.RemovedCount) items ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
        }
    }

    # Summary
    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Browser data cleanup complete: Removed $totalCount items ($([math]::Round($totalRemoved / 1MB, 2)) MB)"

    return $results
}

function Get-WinOpsBrowserDataInfo {
    <#
    .SYNOPSIS
        Gets information about browser data sizes without removing them.

    .DESCRIPTION
        Retrieves size information for browser data types.

    .PARAMETER Browser
        Browser to query. Valid values: Chrome, Edge, Firefox, Brave, Opera, All

    .EXAMPLE
        Get-WinOpsBrowserDataInfo -Browser All
        # Shows data sizes for all installed browsers

    .EXAMPLE
        Get-WinOpsBrowserDataInfo -Browser Chrome
        # Shows data sizes for Chrome only
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('Chrome', 'Edge', 'Firefox', 'Brave', 'Opera', 'All')]
        [string]$Browser = 'All'
    )

    $browsersToQuery = if ($Browser -eq 'All') {
        $script:Browsers.Keys
    } else {
        @($Browser)
    }

    $results = @()

    foreach ($browserKey in $browsersToQuery) {
        $browserInfo = $script:Browsers[$browserKey]

        $basePath = [Environment]::ExpandEnvironmentVariables($browserInfo.BasePath)
        if (-not (Test-Path $basePath)) {
            continue
        }

        $isRunning = Test-BrowserRunning -ProcessName $browserInfo.ProcessName

        foreach ($dataTypeKey in $browserInfo.DataTypes.Keys) {
            $dataTypeInfo = $browserInfo.DataTypes[$dataTypeKey]

            Write-Verbose "Querying: $($browserInfo.Name) $dataTypeKey"

            $size = Get-BrowserDataSize -BasePath $basePath -RelativePaths $dataTypeInfo.Paths

            $results += [PSCustomObject]@{
                Browser = $browserInfo.Name
                DataType = $dataTypeKey
                Description = $dataTypeInfo.Description
                TotalSize = $size
                TotalSizeMB = [math]::Round($size / 1MB, 2)
                TotalSizeGB = [math]::Round($size / 1GB, 2)
                IsRunning = $isRunning
                BasePath = $basePath
            }
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

function Test-WinOpsBrowserInstalled {
    <#
    .SYNOPSIS
        Checks if specified browsers are installed.

    .DESCRIPTION
        Verifies browser installation by checking data directories.

    .PARAMETER Browser
        Browser to check. Valid values: Chrome, Edge, Firefox, Brave, Opera, All

    .EXAMPLE
        Test-WinOpsBrowserInstalled -Browser All
        # Returns installed status for all browsers
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('Chrome', 'Edge', 'Firefox', 'Brave', 'Opera', 'All')]
        [string]$Browser = 'All'
    )

    $browsersToCheck = if ($Browser -eq 'All') {
        $script:Browsers.Keys
    } else {
        @($Browser)
    }

    $results = @()

    foreach ($browserKey in $browsersToCheck) {
        $browserInfo = $script:Browsers[$browserKey]
        $basePath = [Environment]::ExpandEnvironmentVariables($browserInfo.BasePath)
        $isInstalled = Test-Path $basePath
        $isRunning = if ($isInstalled) { Test-BrowserRunning -ProcessName $browserInfo.ProcessName } else { $false }

        $results += [PSCustomObject]@{
            Browser = $browserInfo.Name
            Key = $browserKey
            Installed = $isInstalled
            Running = $isRunning
            BasePath = $basePath
        }
    }

    return $results
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsBrowserData',
    'Get-WinOpsBrowserDataInfo',
    'Test-WinOpsBrowserInstalled'
)
