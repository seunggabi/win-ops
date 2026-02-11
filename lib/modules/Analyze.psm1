#Requires -Version 5.1

<#
.SYNOPSIS
    Analysis and reporting module for cleanup operations.

.DESCRIPTION
    Provides comprehensive analysis of cleanup targets across all modules:
    - Aggregates data from all Get-*Targets functions
    - Category-based size reporting
    - Visual reports (charts, bar graphs)
    - CSV/JSON export options
    - Top N largest items
    - DryRun mode for safe analysis

.NOTES
    Module: WinOps.Modules.Analyze
    Requires: Core modules (Config, Logger, Format)
#>

using namespace System.IO
using namespace System.Collections.Generic

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force

# Import format module for visual output
$utilsModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\utils'
if (Test-Path (Join-Path $utilsModulePath 'Format.psm1')) {
    Import-Module (Join-Path $utilsModulePath 'Format.psm1') -Force -ErrorAction SilentlyContinue
}

#region Category Definitions

$script:CleanupCategories = @{
    Cache = @{
        Name = "Cache"
        Description = "Application and system caches"
        Modules = @('CacheCleanup')
        Color = "Cyan"
    }

    Temp = @{
        Name = "Temporary Files"
        Description = "Temporary files and folders"
        Modules = @('TmpCleanup')
        Color = "Yellow"
    }

    Logs = @{
        Name = "Log Files"
        Description = "System and application logs"
        Modules = @('LogCleanup')
        Color = "Gray"
    }

    Browser = @{
        Name = "Browser Data"
        Description = "Browser caches, cookies, history"
        Modules = @('BrowserCleanup')
        Color = "Magenta"
    }

    Development = @{
        Name = "Development"
        Description = "Dev tools, node_modules, build artifacts"
        Modules = @('DevCleanup')
        Color = "Green"
    }

    PackageManagers = @{
        Name = "Package Managers"
        Description = "Chocolatey, Scoop, Winget caches"
        Modules = @('PackageManagerCleanup')
        Color = "Blue"
    }

    Docker = @{
        Name = "Docker"
        Description = "Docker images, containers, volumes"
        Modules = @('DockerCleanup')
        Color = "DarkBlue"
    }

    Zombies = @{
        Name = "Zombie Processes"
        Description = "Stuck processes and orphaned handles"
        Modules = @('ZombieKiller')
        Color = "Red"
    }

    Orphans = @{
        Name = "Orphaned Files"
        Description = "Orphaned files and broken shortcuts"
        Modules = @('OrphanKiller', 'OrphanAppCleanup')
        Color = "DarkYellow"
    }
}

#endregion

#region Private Functions

function Import-CleanupModule {
    <#
    .SYNOPSIS
        Imports a cleanup module if available.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    $modulePath = Join-Path $PSScriptRoot "$ModuleName.psm1"

    if (-not (Test-Path $modulePath)) {
        Write-Verbose "Module not found: $ModuleName"
        return $false
    }

    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Failed to import module $ModuleName`: $_"
        return $false
    }
}

function Get-ModuleTargets {
    <#
    .SYNOPSIS
        Calls Get-*Targets function from a module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter()]
        [hashtable]$Parameters = @{}
    )

    # Determine the Get-*Targets function name
    $functionName = "Get-WinOps$($ModuleName.Replace('Cleanup', ''))Targets"

    # Special cases for non-standard naming
    switch ($ModuleName) {
        'CacheCleanup' { $functionName = 'Get-WinOpsCacheTargets' }
        'TmpCleanup' { $functionName = 'Get-WinOpsTempFileInfo' }
        'LogCleanup' { $functionName = 'Get-WinOpsLogFileInfo' }
        'BrowserCleanup' { $functionName = 'Get-WinOpsBrowserDataInfo' }
        'DevCleanup' { $functionName = 'Get-WinOpsDevCacheInfo' }
        'PackageManagerCleanup' { $functionName = 'Get-WinOpsPackageManagerInfo' }
        'DockerCleanup' { $functionName = 'Get-WinOpsDockerInfo' }
    }

    Write-Verbose "Calling function: $functionName"

    try {
        $command = Get-Command $functionName -ErrorAction Stop

        # Call function with parameters
        $result = & $functionName @Parameters

        return $result
    }
    catch {
        Write-Verbose "Failed to call $functionName`: $_"
        return @()
    }
}

function ConvertTo-UnifiedTarget {
    <#
    .SYNOPSIS
        Converts module-specific target format to unified format.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Target,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$Category
    )

    # Extract common fields with fallbacks
    $name = if ($Target.PSObject.Properties['Name']) { $Target.Name }
            elseif ($Target.PSObject.Properties['Location']) { $Target.Location }
            elseif ($Target.PSObject.Properties['CacheType']) { $Target.CacheType }
            elseif ($Target.PSObject.Properties['Browser']) { $Target.Browser }
            elseif ($Target.PSObject.Properties['PackageManager']) { $Target.PackageManager }
            else { "Unknown" }

    $description = if ($Target.PSObject.Properties['Description']) { $Target.Description } else { "" }

    # Extract size information (try multiple field names)
    $sizeMB = if ($Target.PSObject.Properties['CurrentSizeMB']) { $Target.CurrentSizeMB }
              elseif ($Target.PSObject.Properties['TotalSizeMB']) { $Target.TotalSizeMB }
              elseif ($Target.PSObject.Properties['CacheSizeMB']) { $Target.CacheSizeMB }
              elseif ($Target.PSObject.Properties['SizeMB']) { $Target.SizeMB }
              else { 0 }

    $sizeGB = if ($Target.PSObject.Properties['CurrentSizeGB']) { $Target.CurrentSizeGB }
              elseif ($Target.PSObject.Properties['TotalSizeGB']) { $Target.TotalSizeGB }
              elseif ($Target.PSObject.Properties['CacheSizeGB']) { $Target.CacheSizeGB }
              elseif ($Target.PSObject.Properties['SizeGB']) { $Target.SizeGB }
              else { [math]::Round($sizeMB / 1024, 2) }

    $sizeBytes = if ($Target.PSObject.Properties['TotalSize']) { $Target.TotalSize }
                 elseif ($Target.PSObject.Properties['CurrentSize']) { $Target.CurrentSize }
                 elseif ($Target.PSObject.Properties['CacheSize']) { $Target.CacheSize }
                 else { [long]($sizeMB * 1MB) }

    return [PSCustomObject]@{
        Category = $category
        Module = $ModuleName
        Name = $name
        Description = $description
        SizeBytes = $sizeBytes
        SizeMB = $sizeMB
        SizeGB = $sizeGB
        WillCleanup = if ($Target.PSObject.Properties['WillCleanup']) { $Target.WillCleanup } else { $sizeMB -gt 0 }
        RawTarget = $Target
    }
}

function Get-CategorySummary {
    <#
    .SYNOPSIS
        Summarizes targets by category.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Targets
    )

    $summary = @{}

    foreach ($target in $Targets) {
        if (-not $summary.ContainsKey($target.Category)) {
            $categoryInfo = $script:CleanupCategories[$target.Category]

            $summary[$target.Category] = [PSCustomObject]@{
                Category = $target.Category
                CategoryName = if ($categoryInfo) { $categoryInfo.Name } else { $target.Category }
                Description = if ($categoryInfo) { $categoryInfo.Description } else { "" }
                ItemCount = 0
                TotalSizeBytes = [long]0
                TotalSizeMB = 0.0
                TotalSizeGB = 0.0
                Color = if ($categoryInfo) { $categoryInfo.Color } else { "White" }
            }
        }

        $summary[$target.Category].ItemCount++
        $summary[$target.Category].TotalSizeBytes += $target.SizeBytes
        $summary[$target.Category].TotalSizeMB += $target.SizeMB
        $summary[$target.Category].TotalSizeGB += $target.SizeGB
    }

    return $summary.Values | Sort-Object TotalSizeBytes -Descending
}

function Format-SizeBar {
    <#
    .SYNOPSIS
        Creates a visual bar chart for size representation.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Value,

        [Parameter(Mandatory)]
        [double]$MaxValue,

        [Parameter()]
        [int]$Width = 40,

        [Parameter()]
        [string]$Color = "Green"
    )

    if ($MaxValue -eq 0) {
        return ""
    }

    $percentage = $Value / $MaxValue
    $filledWidth = [math]::Floor($percentage * $Width)

    $bar = "█" * $filledWidth + "░" * ($Width - $filledWidth)

    return $bar
}

#endregion

#region Public Functions

function Get-WinOpsAnalysis {
    <#
    .SYNOPSIS
        Performs comprehensive cleanup analysis across all modules.

    .DESCRIPTION
        Aggregates cleanup targets from all available modules and provides:
        - Category-based summaries
        - Detailed item listings
        - Total reclaimable space
        - Top N largest items
        - Visual reports

    .PARAMETER Detailed
        Include detailed item-by-item listing.

    .PARAMETER TopN
        Number of top items to show (default: 10).

    .PARAMETER Category
        Filter by specific category. Valid values: Cache, Temp, Logs, Browser, Development, PackageManagers, Docker, Zombies, Orphans, All

    .PARAMETER AgeInDays
        Age filter to pass to modules (default: 7).

    .PARAMETER ExportPath
        Export results to CSV file at specified path.

    .PARAMETER ExportJson
        Export results to JSON file at specified path.

    .PARAMETER NoVisual
        Disable visual bar charts and formatting.

    .EXAMPLE
        Get-WinOpsAnalysis
        # Shows category summaries and top 10 items

    .EXAMPLE
        Get-WinOpsAnalysis -Detailed -TopN 20
        # Shows all items and top 20 largest

    .EXAMPLE
        Get-WinOpsAnalysis -Category Development -AgeInDays 30
        # Analyzes only development caches older than 30 days

    .EXAMPLE
        Get-WinOpsAnalysis -ExportPath "C:\cleanup-report.csv"
        # Exports analysis to CSV file
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Detailed,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$TopN = 10,

        [Parameter()]
        [ValidateSet('Cache', 'Temp', 'Logs', 'Browser', 'Development', 'PackageManagers', 'Docker', 'Zombies', 'Orphans', 'All')]
        [string]$Category = 'All',

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$AgeInDays = 7,

        [Parameter()]
        [string]$ExportPath,

        [Parameter()]
        [string]$ExportJson,

        [Parameter()]
        [switch]$NoVisual
    )

    Write-WinOpsLog -Level INFO -Message "Starting cleanup analysis (Age filter: $AgeInDays days)"

    $allTargets = [List[PSCustomObject]]::new()

    # Determine which categories to analyze
    $categoriesToAnalyze = if ($Category -eq 'All') {
        $script:CleanupCategories.Keys
    } else {
        @($Category)
    }

    # Collect targets from all modules
    foreach ($categoryKey in $categoriesToAnalyze) {
        $categoryInfo = $script:CleanupCategories[$categoryKey]

        Write-Verbose "Analyzing category: $($categoryInfo.Name)"

        foreach ($moduleName in $categoryInfo.Modules) {
            Write-Verbose "  Loading module: $moduleName"

            if (-not (Import-CleanupModule -ModuleName $moduleName)) {
                continue
            }

            $parameters = @{
                AgeInDays = $AgeInDays
            }

            # Get targets from module
            $moduleTargets = Get-ModuleTargets -ModuleName $moduleName -Parameters $parameters

            if ($null -eq $moduleTargets -or $moduleTargets.Count -eq 0) {
                Write-Verbose "  No targets found in $moduleName"
                continue
            }

            Write-Verbose "  Found $($moduleTargets.Count) targets in $moduleName"

            # Convert to unified format
            foreach ($target in $moduleTargets) {
                $unified = ConvertTo-UnifiedTarget -Target $target -ModuleName $moduleName -Category $categoryKey
                $allTargets.Add($unified)
            }
        }
    }

    Write-Verbose "Total targets collected: $($allTargets.Count)"

    if ($allTargets.Count -eq 0) {
        Write-Warning "No cleanup targets found"
        return [PSCustomObject]@{
            Summary = @()
            TopItems = @()
            AllTargets = @()
            TotalReclaimableGB = 0
            TotalReclaimableMB = 0
            TotalItemCount = 0
            CategoryCount = 0
            Timestamp = (Get-Date)
        }
    }

    # Generate category summary
    $categorySummary = Get-CategorySummary -Targets $allTargets

    # Calculate totals
    $totalSizeBytes = ($allTargets | Measure-Object -Property SizeBytes -Sum).Sum
    $totalSizeMB = [math]::Round($totalSizeBytes / 1MB, 2)
    $totalSizeGB = [math]::Round($totalSizeBytes / 1GB, 2)

    # Get top N items
    $topItems = $allTargets | Sort-Object SizeBytes -Descending | Select-Object -First $TopN

    # Build result
    $result = [PSCustomObject]@{
        Summary = $categorySummary
        TopItems = $topItems
        AllTargets = if ($Detailed) { $allTargets } else { @() }
        TotalReclaimableGB = $totalSizeGB
        TotalReclaimableMB = $totalSizeMB
        TotalReclaimableBytes = $totalSizeBytes
        TotalItemCount = $allTargets.Count
        CategoryCount = $categorySummary.Count
        AgeFilterDays = $AgeInDays
        Timestamp = (Get-Date)
    }

    # Display visual report
    if (-not $NoVisual) {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                    Win-Ops Cleanup Analysis Report                       ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Analysis Time: " -NoNewline
        Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
        Write-Host "Age Filter: " -NoNewline
        Write-Host "$AgeInDays days" -ForegroundColor Yellow
        Write-Host ""

        # Category summary with bars
        Write-Host "═══ Category Summary ═══" -ForegroundColor Cyan
        Write-Host ""

        $maxSize = ($categorySummary | Measure-Object -Property TotalSizeGB -Maximum).Maximum

        foreach ($cat in $categorySummary) {
            $bar = Format-SizeBar -Value $cat.TotalSizeGB -MaxValue $maxSize -Width 30 -Color $cat.Color

            Write-Host ("{0,-20}" -f $cat.CategoryName) -NoNewline -ForegroundColor $cat.Color
            Write-Host " $bar " -NoNewline
            Write-Host ("{0,8:N2} GB" -f $cat.TotalSizeGB) -ForegroundColor White
            Write-Host ("{0,-20} ({1} items)" -f "", $cat.ItemCount) -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "═══ Summary ═══" -ForegroundColor Cyan
        Write-Host "Total Reclaimable Space: " -NoNewline
        Write-Host ("{0:N2} GB" -f $totalSizeGB) -ForegroundColor Green -NoNewline
        Write-Host " ({0:N2} MB)" -f $totalSizeMB -ForegroundColor Gray
        Write-Host "Total Items: " -NoNewline
        Write-Host $allTargets.Count -ForegroundColor Yellow
        Write-Host "Categories: " -NoNewline
        Write-Host $categorySummary.Count -ForegroundColor Yellow
        Write-Host ""

        # Top N items
        Write-Host "═══ Top $TopN Largest Items ═══" -ForegroundColor Cyan
        Write-Host ""

        $rank = 1
        foreach ($item in $topItems) {
            $categoryInfo = $script:CleanupCategories[$item.Category]
            $color = if ($categoryInfo) { $categoryInfo.Color } else { "White" }

            Write-Host ("{0,2}. " -f $rank) -NoNewline -ForegroundColor Gray
            Write-Host ("[{0}] " -f $item.Category) -NoNewline -ForegroundColor $color
            Write-Host $item.Name -NoNewline -ForegroundColor White
            Write-Host (" - {0:N2} GB" -f $item.SizeGB) -ForegroundColor Green

            if ($item.Description) {
                Write-Host ("    {0}" -f $item.Description) -ForegroundColor DarkGray
            }

            $rank++
        }

        Write-Host ""
    }

    # Export to CSV if requested
    if ($ExportPath) {
        try {
            $exportData = $allTargets | Select-Object Category, Module, Name, Description, SizeMB, SizeGB
            $exportData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
            Write-Host "Exported to CSV: $ExportPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to export CSV: $_"
        }
    }

    # Export to JSON if requested
    if ($ExportJson) {
        try {
            $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $ExportJson -Encoding UTF8
            Write-Host "Exported to JSON: $ExportJson" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to export JSON: $_"
        }
    }

    Write-WinOpsLog -Level INFO -Message "Analysis complete: $($allTargets.Count) items, $($totalSizeGB) GB reclaimable"

    return $result
}

function Compare-WinOpsAnalysis {
    <#
    .SYNOPSIS
        Compares two analysis snapshots to show changes.

    .DESCRIPTION
        Compares before/after analysis results to show cleanup effectiveness.

    .PARAMETER Before
        Analysis result from before cleanup.

    .PARAMETER After
        Analysis result from after cleanup.

    .EXAMPLE
        $before = Get-WinOpsAnalysis
        # ... perform cleanup ...
        $after = Get-WinOpsAnalysis
        Compare-WinOpsAnalysis -Before $before -After $after
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Before,

        [Parameter(Mandatory)]
        [PSCustomObject]$After
    )

    $freedSpaceGB = $Before.TotalReclaimableGB - $After.TotalReclaimableGB
    $freedSpaceMB = $Before.TotalReclaimableMB - $After.TotalReclaimableMB
    $itemsRemoved = $Before.TotalItemCount - $After.TotalItemCount

    $comparison = [PSCustomObject]@{
        BeforeGB = $Before.TotalReclaimableGB
        AfterGB = $After.TotalReclaimableGB
        FreedGB = $freedSpaceGB
        FreedMB = $freedSpaceMB
        ItemsRemoved = $itemsRemoved
        PercentageReduction = if ($Before.TotalReclaimableGB -gt 0) {
            [math]::Round(($freedSpaceGB / $Before.TotalReclaimableGB) * 100, 2)
        } else { 0 }
        BeforeTimestamp = $Before.Timestamp
        AfterTimestamp = $After.Timestamp
    }

    Write-Host ""
    Write-Host "═══ Cleanup Comparison ═══" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Before: " -NoNewline
    Write-Host ("{0:N2} GB" -f $comparison.BeforeGB) -ForegroundColor Yellow
    Write-Host "After:  " -NoNewline
    Write-Host ("{0:N2} GB" -f $comparison.AfterGB) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Freed:  " -NoNewline
    Write-Host ("{0:N2} GB" -f $comparison.FreedGB) -ForegroundColor Green -NoNewline
    Write-Host (" ({0}%)" -f $comparison.PercentageReduction) -ForegroundColor Gray
    Write-Host "Items Removed: " -NoNewline
    Write-Host $comparison.ItemsRemoved -ForegroundColor Green
    Write-Host ""

    return $comparison
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-WinOpsAnalysis',
    'Compare-WinOpsAnalysis'
)
