#Requires -Version 5.1

<#
.SYNOPSIS
    Log file cleanup module for Windows applications and system logs.

.DESCRIPTION
    Manages log file cleanup from various sources:
    - Windows Event Logs
    - Application log files
    - IIS logs
    - SQL Server logs
    - System log files
    - Custom application logs

.NOTES
    Module: WinOps.Modules.LogCleanup
    Requires: Core modules (Config, Logger, Safety, Trash)
#>

using namespace System.IO
using namespace System.Diagnostics.Eventing.Reader

# Import required core modules (skip if already loaded to avoid scope conflicts)
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
if (-not (Get-Module -Name Config)) { Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force -Global }
if (-not (Get-Module -Name Logger)) { Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force -Global }
if (-not (Get-Module -Name Safety)) { Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force -Global }
if (-not (Get-Module -Name Trash)) { Import-Module (Join-Path $coreModulePath 'Trash.psm1') -Force -Global }

#region Log Locations

$script:LogLocations = @{
    WindowsLogs = @{
        Paths = @(
            "$env:SystemRoot\Logs\CBS\*.log",
            "$env:SystemRoot\Logs\DISM\*.log",
            "$env:SystemRoot\Logs\DPX\*.log",
            "$env:SystemRoot\Logs\MoSetup\*.log",
            "$env:SystemRoot\Logs\WindowsUpdate\*.log"
        )
        Description = "Windows system logs"
        DefaultAgeInDays = 90
        SafetyLevel = "Strict"
        RequiresElevation = $true
    }

    IISLogs = @{
        Paths = @(
            "C:\inetpub\logs\LogFiles\W3SVC*\*.log"
        )
        Description = "IIS web server logs"
        DefaultAgeInDays = 30
        SafetyLevel = "Normal"
        RequiresElevation = $true
    }

    ApplicationLogs = @{
        Paths = @(
            "$env:ProgramData\*.log",
            "$env:LOCALAPPDATA\*.log",
            "$env:APPDATA\*.log"
        )
        Description = "Application log files"
        DefaultAgeInDays = 60
        SafetyLevel = "Normal"
    }

    SetupLogs = @{
        Paths = @(
            "$env:SystemRoot\Panther\*.log",
            "$env:SystemRoot\INF\setupapi.dev.log",
            "$env:SystemRoot\INF\setupapi.app.log"
        )
        Description = "Windows setup and driver installation logs"
        DefaultAgeInDays = 180
        SafetyLevel = "Strict"
        RequiresElevation = $true
    }

    VSCodeLogs = @{
        Paths = @(
            "$env:APPDATA\Code\logs\*",
            "$env:APPDATA\Code\CachedData\*\logs\*"
        )
        Description = "Visual Studio Code logs"
        DefaultAgeInDays = 30
        SafetyLevel = "Normal"
    }

    PowerShellLogs = @{
        Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\*.log"
        )
        Description = "PowerShell logs"
        DefaultAgeInDays = 60
        SafetyLevel = "Normal"
    }
}

$script:EventLogCategories = @{
    Application = @{
        LogName = 'Application'
        Description = 'Application events'
        DefaultAgeInDays = 90
    }
    Security = @{
        LogName = 'Security'
        Description = 'Security audit events'
        DefaultAgeInDays = 180
    }
    System = @{
        LogName = 'System'
        Description = 'System events'
        DefaultAgeInDays = 90
    }
    Setup = @{
        LogName = 'Setup'
        Description = 'Setup events'
        DefaultAgeInDays = 180
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

function Get-LogFileInfo {
    <#
    .SYNOPSIS
        Gets information about log files matching criteria.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$AgeInDays = 0,

        [Parameter()]
        [long]$MinSizeBytes = 0
    )

    $totalCount = 0
    $totalSize = 0
    $cutoffDate = if ($AgeInDays -gt 0) {
        (Get-Date).AddDays(-$AgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        try {
            if ($expandedPath -like '*`**') {
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction SilentlyContinue
            } else {
                if (-not (Test-Path $expandedPath)) {
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -File -Force -ErrorAction SilentlyContinue
            }

            foreach ($item in $items) {
                if ($item.PSIsContainer) {
                    continue
                }

                if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                    continue
                }

                if ($MinSizeBytes -gt 0 -and $item.Length -lt $MinSizeBytes) {
                    continue
                }

                $totalCount++
                $totalSize += $item.Length
            }
        }
        catch {
            Write-Verbose "Failed to access path $expandedPath`: $_"
        }
    }

    return @{
        Count = $totalCount
        Size = $totalSize
    }
}

function Remove-LogFiles {
    <#
    .SYNOPSIS
        Removes log files from specified paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [Parameter()]
        [int]$AgeInDays = 0,

        [Parameter()]
        [long]$MinSizeBytes = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string]$LocationName,

        [Parameter()]
        [string[]]$ExcludePatterns = @()
    )

    $removedCount = 0
    $removedSize = 0
    $failedCount = 0
    $skippedCount = 0
    $errors = @()

    $cutoffDate = if ($AgeInDays -gt 0) {
        (Get-Date).AddDays(-$AgeInDays)
    } else {
        $null
    }

    foreach ($path in $Paths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)

        try {
            if ($expandedPath -like '*`**') {
                $items = Get-ChildItem -Path $expandedPath -Force -ErrorAction Stop
            } else {
                if (-not (Test-Path $expandedPath)) {
                    Write-Verbose "Path does not exist: $expandedPath"
                    continue
                }
                $items = Get-ChildItem -Path $expandedPath -Recurse -File -Force -ErrorAction Stop
            }

            foreach ($item in $items) {
                if ($item.PSIsContainer) {
                    continue
                }

                try {
                    # Age filter
                    if ($cutoffDate -and $item.LastWriteTime -gt $cutoffDate) {
                        $skippedCount++
                        continue
                    }

                    # Size filter
                    if ($MinSizeBytes -gt 0 -and $item.Length -lt $MinSizeBytes) {
                        $skippedCount++
                        continue
                    }

                    # Exclude patterns
                    $shouldExclude = $false
                    foreach ($pattern in $ExcludePatterns) {
                        if ($item.Name -like $pattern -or $item.FullName -like $pattern) {
                            $shouldExclude = $true
                            break
                        }
                    }

                    if ($shouldExclude) {
                        Write-Verbose "Excluded by pattern: $($item.FullName)"
                        $skippedCount++
                        continue
                    }

                    # Check if file is in use
                    try {
                        $stream = [File]::Open($item.FullName, [FileMode]::Open, [FileAccess]::Read, [FileShare]::None)
                        $stream.Close()
                        $stream.Dispose()
                    }
                    catch [UnauthorizedAccessException] {
                        Write-Verbose "File in use or access denied: $($item.FullName)"
                        $skippedCount++
                        continue
                    }
                    catch {
                        Write-Verbose "Cannot access file: $($item.FullName)"
                        $skippedCount++
                        continue
                    }

                    # Safety check: verify path is safe to delete
                    if (-not (Test-WinOpsPathSafe -Path $item.FullName)) {
                        Write-Verbose "Skipping protected path: $($item.FullName)"
                        $skippedCount++
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, "Remove log file")) {
                        if ($UseTrash) {
                            Move-WinOpsToTrash -Path $item.FullName -Module $LocationName -ErrorAction Stop | Out-Null
                        } else {
                            Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                        }

                        $removedCount++
                        $removedSize += $item.Length
                        Write-Verbose "Removed: $($item.FullName) ($($item.Length) bytes)"
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
        SkippedCount = $skippedCount
        Errors = $errors
    }
}

#endregion

#region Public Functions

function Clear-WinOpsLogFiles {
    <#
    .SYNOPSIS
        Clears log files from Windows and application locations.

    .DESCRIPTION
        Removes log files from specified locations with age and size filtering.

    .PARAMETER Location
        Location to clean. Valid values:
        - WindowsLogs, IISLogs, ApplicationLogs, SetupLogs, VSCodeLogs, PowerShellLogs, All

    .PARAMETER AgeInDays
        Only remove files older than specified days (0 = use default per location).

    .PARAMETER MinSizeMB
        Only remove files larger than specified MB (reduces clutter from small logs).

    .PARAMETER UseTrash
        Move files to trash instead of permanent deletion.

    .PARAMETER ExcludePatterns
        File name patterns to exclude (e.g., "current.log", "*active*").

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsLogFiles -Location WindowsLogs
        # Clears Windows logs older than default age

    .EXAMPLE
        Clear-WinOpsLogFiles -Location All -AgeInDays 60 -MinSizeMB 10
        # Clears all logs older than 60 days and larger than 10MB

    .EXAMPLE
        Clear-WinOpsLogFiles -Location ApplicationLogs -ExcludePatterns "important*.log" -DryRun
        # Shows what would be removed except important logs
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('WindowsLogs', 'IISLogs', 'ApplicationLogs', 'SetupLogs', 'VSCodeLogs', 'PowerShellLogs', 'All')]
        [string]$Location = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$MinSizeMB = 0,

        [Parameter()]
        [switch]$UseTrash,

        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    Write-WinOpsLog -Level INFO -Message "Starting log file cleanup: $Location"

    $isElevated = Test-IsElevated
    $minSizeBytes = [long]($MinSizeMB * 1MB)

    $locationsToClean = if ($Location -eq 'All') {
        $script:LogLocations.Keys
    } else {
        @($Location)
    }

    $results = @()

    foreach ($locationKey in $locationsToClean) {
        $locationInfo = $script:LogLocations[$locationKey]

        if ($locationInfo.RequiresElevation -and -not $isElevated) {
            Write-Warning "Skipping $locationKey - requires administrator privileges"
            continue
        }

        Write-Verbose "Processing location: $locationKey - $($locationInfo.Description)"

        $effectiveAge = if ($AgeInDays -gt 0) {
            $AgeInDays
        } else {
            $locationInfo.DefaultAgeInDays
        }

        $logInfo = Get-LogFileInfo -Paths $locationInfo.Paths -AgeInDays $effectiveAge -MinSizeBytes $minSizeBytes

        if ($logInfo.Count -eq 0) {
            Write-Verbose "No log files found for: $locationKey"
            continue
        }

        Write-Verbose "Found $($logInfo.Count) log files ($([math]::Round($logInfo.Size / 1MB, 2)) MB) in $locationKey"

        if ($DryRun) {
            $results += [PSCustomObject]@{
                Location = $locationKey
                Description = $locationInfo.Description
                FileCount = $logInfo.Count
                TotalSize = $logInfo.Size
                AgeInDays = $effectiveAge
                MinSizeMB = $MinSizeMB
                WouldRemove = $true
                RemovedCount = 0
                RemovedSize = 0
            }
            continue
        }

        if (-not $Force -and -not $PSCmdlet.ShouldProcess(
            "$locationKey - $($logInfo.Count) files ($([math]::Round($logInfo.Size / 1MB, 2)) MB)",
            "Remove log files older than $effectiveAge days"
        )) {
            Write-Verbose "Skipped by user: $locationKey"
            continue
        }

        $removeResult = Remove-LogFiles `
            -Paths $locationInfo.Paths `
            -AgeInDays $effectiveAge `
            -MinSizeBytes $minSizeBytes `
            -UseTrash:$UseTrash `
            -LocationName $locationKey `
            -ExcludePatterns $ExcludePatterns

        $results += [PSCustomObject]@{
            Location = $locationKey
            Description = $locationInfo.Description
            FileCount = $logInfo.Count
            TotalSize = $logInfo.Size
            AgeInDays = $effectiveAge
            MinSizeMB = $MinSizeMB
            RemovedCount = $removeResult.RemovedCount
            RemovedSize = $removeResult.RemovedSize
            FailedCount = $removeResult.FailedCount
            SkippedCount = $removeResult.SkippedCount
            Errors = $removeResult.Errors
        }

        Write-WinOpsLog -Level INFO -Message "Cleaned $locationKey`: Removed $($removeResult.RemovedCount) files ($([math]::Round($removeResult.RemovedSize / 1MB, 2)) MB)"
    }

    $totalRemoved = ($results | Measure-Object -Property RemovedSize -Sum).Sum
    $totalCount = ($results | Measure-Object -Property RemovedCount -Sum).Sum

    Write-WinOpsLog -Level INFO -Message "Log file cleanup complete: Removed $totalCount files ($([math]::Round($totalRemoved / 1MB, 2)) MB)"

    return $results
}

function Clear-WinOpsEventLog {
    <#
    .SYNOPSIS
        Clears Windows Event Logs.

    .DESCRIPTION
        Clears specified Windows Event Logs or archives old entries.

    .PARAMETER LogName
        Event log to clear. Valid values: Application, Security, System, Setup, All

    .PARAMETER ArchiveBeforeClear
        Archive the log before clearing it.

    .PARAMETER ArchivePath
        Path to save archived logs (default: %LOCALAPPDATA%\win-ops\eventlogs).

    .PARAMETER Force
        Bypass confirmation prompts.

    .EXAMPLE
        Clear-WinOpsEventLog -LogName Application -ArchiveBeforeClear
        # Archives and clears Application event log

    .EXAMPLE
        Clear-WinOpsEventLog -LogName All -Force
        # Clears all event logs without confirmation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Application', 'Security', 'System', 'Setup', 'All')]
        [string]$LogName,

        [Parameter()]
        [switch]$ArchiveBeforeClear,

        [Parameter()]
        [string]$ArchivePath = "$env:LOCALAPPDATA\win-ops\eventlogs",

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-IsElevated)) {
        throw "Clearing Event Logs requires administrator privileges"
    }

    Write-WinOpsLog -Level INFO -Message "Starting Event Log cleanup: $LogName"

    $logsToClear = if ($LogName -eq 'All') {
        $script:EventLogCategories.Keys
    } else {
        @($LogName)
    }

    if ($ArchiveBeforeClear) {
        if (-not (Test-Path $ArchivePath)) {
            New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
        }
    }

    $results = @()

    foreach ($log in $logsToClear) {
        $logInfo = $script:EventLogCategories[$log]

        try {
            $eventLog = Get-WinEvent -LogName $logInfo.LogName -MaxEvents 1 -ErrorAction Stop
            $recordCount = (Get-WinEvent -LogName $logInfo.LogName -ErrorAction Stop).Count

            if (-not $Force -and -not $PSCmdlet.ShouldProcess(
                "$($logInfo.LogName) ($recordCount records)",
                "Clear Event Log"
            )) {
                Write-Verbose "Skipped by user: $($logInfo.LogName)"
                continue
            }

            if ($ArchiveBeforeClear) {
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $archiveFile = Join-Path $ArchivePath "$($logInfo.LogName)-$timestamp.evtx"

                Write-Verbose "Archiving $($logInfo.LogName) to $archiveFile"
                wevtutil epl $logInfo.LogName $archiveFile
            }

            Write-Verbose "Clearing $($logInfo.LogName)..."
            wevtutil cl $logInfo.LogName

            $results += [PSCustomObject]@{
                LogName = $logInfo.LogName
                Description = $logInfo.Description
                RecordsCleared = $recordCount
                Archived = $ArchiveBeforeClear
                ArchivePath = if ($ArchiveBeforeClear) { $archiveFile } else { $null }
                Success = $true
            }

            Write-WinOpsLog -Level INFO -Message "Cleared Event Log: $($logInfo.LogName) ($recordCount records)"
        }
        catch {
            $results += [PSCustomObject]@{
                LogName = $logInfo.LogName
                Description = $logInfo.Description
                RecordsCleared = 0
                Archived = $false
                ArchivePath = $null
                Success = $false
                Error = $_.Exception.Message
            }

            Write-WinOpsLog -Level ERROR -Message "Failed to clear Event Log: $($logInfo.LogName)" -Exception $_
        }
    }

    return $results
}

function Get-WinOpsLogFileInfo {
    <#
    .SYNOPSIS
        Gets information about log files without removing them.

    .DESCRIPTION
        Retrieves count and size information for log file locations.

    .PARAMETER Location
        Location to query. Valid values: WindowsLogs, IISLogs, etc., or All.

    .PARAMETER AgeInDays
        Only count files older than specified days.

    .PARAMETER MinSizeMB
        Only count files larger than specified MB.

    .EXAMPLE
        Get-WinOpsLogFileInfo -Location All
        # Shows info for all log locations

    .EXAMPLE
        Get-WinOpsLogFileInfo -Location WindowsLogs -AgeInDays 90
        # Shows info for Windows logs older than 90 days
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateSet('WindowsLogs', 'IISLogs', 'ApplicationLogs', 'SetupLogs', 'VSCodeLogs', 'PowerShellLogs', 'All')]
        [string]$Location = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 0,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$MinSizeMB = 0
    )

    $locationsToQuery = if ($Location -eq 'All') {
        $script:LogLocations.Keys
    } else {
        @($Location)
    }

    $minSizeBytes = [long]($MinSizeMB * 1MB)
    $results = @()

    foreach ($locationKey in $locationsToQuery) {
        $locationInfo = $script:LogLocations[$locationKey]

        Write-Verbose "Querying location: $locationKey"

        $effectiveAge = if ($AgeInDays -gt 0) { $AgeInDays } else { $locationInfo.DefaultAgeInDays }

        $logInfo = Get-LogFileInfo -Paths $locationInfo.Paths -AgeInDays $effectiveAge -MinSizeBytes $minSizeBytes

        $results += [PSCustomObject]@{
            Location = $locationKey
            Description = $locationInfo.Description
            FileCount = $logInfo.Count
            TotalSize = $logInfo.Size
            TotalSizeMB = [math]::Round($logInfo.Size / 1MB, 2)
            TotalSizeGB = [math]::Round($logInfo.Size / 1GB, 2)
            DefaultAgeInDays = $locationInfo.DefaultAgeInDays
            Paths = $locationInfo.Paths
            RequiresElevation = $locationInfo.RequiresElevation
        }
    }

    return $results | Sort-Object TotalSize -Descending
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsLogFiles',
    'Clear-WinOpsEventLog',
    'Get-WinOpsLogFileInfo'
)
