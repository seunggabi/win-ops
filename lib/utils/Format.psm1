# lib/utils/Format.psm1
# Formatting and output utilities for Windows

<#
.SYNOPSIS
Convert bytes to human-readable format

.PARAMETER Bytes
Number of bytes to convert

.EXAMPLE
Format-WinOpsBytes -Bytes 1073741824
# Returns: "1.0 GB"
#>
function Format-WinOpsBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [long]$Bytes
    )

    process {
        if ($Bytes -eq $null -or $Bytes -lt 0) {
            return "0 B"
        }

        if ($Bytes -lt 1KB) {
            return "$Bytes B"
        }
        elseif ($Bytes -lt 1MB) {
            return "{0:N1} KB" -f ($Bytes / 1KB)
        }
        elseif ($Bytes -lt 1GB) {
            return "{0:N1} MB" -f ($Bytes / 1MB)
        }
        elseif ($Bytes -lt 1TB) {
            return "{0:N1} GB" -f ($Bytes / 1GB)
        }
        else {
            return "{0:N1} TB" -f ($Bytes / 1TB)
        }
    }
}

<#
.SYNOPSIS
Convert seconds to human-readable duration format

.PARAMETER Seconds
Number of seconds to convert

.EXAMPLE
Format-WinOpsDuration -Seconds 3665
# Returns: "1h 1m 5s"
#>
function Format-WinOpsDuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [int]$Seconds
    )

    process {
        if ($Seconds -eq $null -or $Seconds -lt 0) {
            return "0s"
        }

        if ($Seconds -lt 60) {
            return "${Seconds}s"
        }
        elseif ($Seconds -lt 3600) {
            $mins = [Math]::Floor($Seconds / 60)
            $secs = $Seconds % 60
            return "${mins}m ${secs}s"
        }
        else {
            $hours = [Math]::Floor($Seconds / 3600)
            $mins = [Math]::Floor(($Seconds % 3600) / 60)
            $secs = $Seconds % 60

            if ($secs -gt 0) {
                return "${hours}h ${mins}m ${secs}s"
            }
            else {
                return "${hours}h ${mins}m"
            }
        }
    }
}

<#
.SYNOPSIS
Write colored text to console using ANSI escape codes

.PARAMETER Text
Text to display

.PARAMETER Color
Color name (Red, Green, Yellow, Blue, Cyan, Magenta, White, Bold)

.PARAMETER NoNewline
If specified, does not add a newline after the text

.EXAMPLE
Write-WinOpsColor -Text "Error occurred" -Color Red
#>
function Write-WinOpsColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Red', 'Green', 'Yellow', 'Blue', 'Cyan', 'Magenta', 'White', 'Bold', 'Reset')]
        [string]$Color = 'White',

        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )

    process {
        # ANSI color codes
        $colorCodes = @{
            'Red'     = "`e[31m"
            'Green'   = "`e[32m"
            'Yellow'  = "`e[33m"
            'Blue'    = "`e[34m"
            'Cyan'    = "`e[36m"
            'Magenta' = "`e[35m"
            'White'   = "`e[37m"
            'Bold'    = "`e[1m"
            'Reset'   = "`e[0m"
        }

        $resetCode = "`e[0m"
        $colorCode = $colorCodes[$Color]

        $output = "${colorCode}${Text}${resetCode}"

        if ($NoNewline) {
            Write-Host $output -NoNewline
        }
        else {
            Write-Host $output
        }
    }
}

<#
.SYNOPSIS
Format array data as aligned table

.PARAMETER Data
Array of objects to display

.PARAMETER Properties
Property names to display (optional, defaults to all properties)

.PARAMETER Width
Column widths as hashtable (optional)

.EXAMPLE
$data = @(
    [PSCustomObject]@{Name="File1.txt"; Size=1024; Date="2024-01-01"}
    [PSCustomObject]@{Name="File2.txt"; Size=2048; Date="2024-01-02"}
)
Format-WinOpsTable -Data $data -Properties Name,Size,Date
#>
function Format-WinOpsTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [array]$Data,

        [Parameter(Mandatory = $false)]
        [string[]]$Properties,

        [Parameter(Mandatory = $false)]
        [hashtable]$Width
    )

    process {
        if ($Data.Count -eq 0) {
            return
        }

        # Auto-detect properties if not specified
        if (-not $Properties) {
            $Properties = $Data[0].PSObject.Properties.Name
        }

        # Calculate column widths if not specified
        if (-not $Width) {
            $Width = @{}
            foreach ($prop in $Properties) {
                # Start with header width
                $maxWidth = $prop.Length

                # Check data width
                foreach ($item in $Data) {
                    $value = $item.$prop
                    if ($value) {
                        $valueLength = $value.ToString().Length
                        if ($valueLength -gt $maxWidth) {
                            $maxWidth = $valueLength
                        }
                    }
                }

                $Width[$prop] = $maxWidth + 2  # Add padding
            }
        }

        # Print header
        $headerParts = @()
        foreach ($prop in $Properties) {
            $w = if ($Width.ContainsKey($prop)) { $Width[$prop] } else { 20 }
            $headerParts += $prop.PadRight($w)
        }
        Write-WinOpsColor -Text ($headerParts -join " ") -Color Bold

        # Print separator
        $separatorParts = @()
        foreach ($prop in $Properties) {
            $w = if ($Width.ContainsKey($prop)) { $Width[$prop] } else { 20 }
            $separatorParts += ("-" * $w)
        }
        Write-Host ($separatorParts -join " ")

        # Print data rows
        foreach ($item in $Data) {
            $rowParts = @()
            foreach ($prop in $Properties) {
                $value = $item.$prop
                if ($value -eq $null) {
                    $value = ""
                }
                $w = if ($Width.ContainsKey($prop)) { $Width[$prop] } else { 20 }
                $rowParts += $value.ToString().PadRight($w)
            }
            Write-Host ($rowParts -join " ")
        }
    }
}

<#
.SYNOPSIS
Print formatted header with separator

.PARAMETER Title
Header title text

.EXAMPLE
Write-WinOpsHeader -Title "System Cleanup Report"
#>
function Write-WinOpsHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-WinOpsColor -Text ("=" * 50) -Color Bold
    Write-WinOpsColor -Text $Title -Color Bold
    Write-WinOpsColor -Text ("=" * 50) -Color Bold
    Write-Host ""
}

<#
.SYNOPSIS
Print execution summary with cleanup statistics

.PARAMETER CleanedCount
Number of items cleaned

.PARAMETER CleanedBytes
Total bytes cleaned

.PARAMETER KilledProcs
Number of processes terminated

.EXAMPLE
Write-WinOpsSummary -CleanedCount 42 -CleanedBytes 1073741824 -KilledProcs 3
#>
function Write-WinOpsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$CleanedCount = 0,

        [Parameter(Mandatory = $false)]
        [long]$CleanedBytes = 0,

        [Parameter(Mandatory = $false)]
        [int]$KilledProcs = 0
    )

    Write-Host ""
    Write-WinOpsColor -Text "=== Execution Summary ===" -Color Bold

    if ($CleanedCount -gt 0) {
        $formattedSize = Format-WinOpsBytes -Bytes $CleanedBytes
        Write-WinOpsColor -Text "OK" -Color Green -NoNewline
        Write-Host " Files cleaned: $CleanedCount items ($formattedSize)"
    }

    if ($KilledProcs -gt 0) {
        Write-WinOpsColor -Text "OK" -Color Green -NoNewline
        Write-Host " Processes terminated: $KilledProcs items"
    }

    if ($CleanedCount -eq 0 -and $KilledProcs -eq 0) {
        Write-WinOpsColor -Text "[INFO]" -Color Blue -NoNewline
        Write-Host " No items to clean"
    }

    Write-Host ""
}

<#
.SYNOPSIS
Print system report with before/after comparison

.PARAMETER BeforeSnapshot
Before snapshot (hashtable with DiskUsagePct, DiskFreeBytes, MemUsedBytes, MemTotalBytes)

.PARAMETER AfterSnapshot
After snapshot (same format as BeforeSnapshot)

.PARAMETER CleanedCount
Number of items cleaned

.PARAMETER CleanedBytes
Total bytes cleaned

.PARAMETER KilledProcs
Number of processes terminated

.EXAMPLE
$before = @{DiskUsagePct=75; DiskFreeBytes=10GB; MemUsedBytes=8GB; MemTotalBytes=16GB}
$after = @{DiskUsagePct=70; DiskFreeBytes=12GB; MemUsedBytes=7GB; MemTotalBytes=16GB}
Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after -CleanedCount 10 -CleanedBytes 2GB
#>
function Write-WinOpsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BeforeSnapshot,

        [Parameter(Mandatory = $true)]
        [hashtable]$AfterSnapshot,

        [Parameter(Mandatory = $false)]
        [int]$CleanedCount = 0,

        [Parameter(Mandatory = $false)]
        [long]$CleanedBytes = 0,

        [Parameter(Mandatory = $false)]
        [int]$KilledProcs = 0
    )

    # Calculate deltas
    $diskUsageDelta = $AfterSnapshot.DiskUsagePct - $BeforeSnapshot.DiskUsagePct
    $diskFreeDelta = $AfterSnapshot.DiskFreeBytes - $BeforeSnapshot.DiskFreeBytes
    $memUsedDelta = $AfterSnapshot.MemUsedBytes - $BeforeSnapshot.MemUsedBytes

    # Format values
    $beforeDiskFree = Format-WinOpsBytes -Bytes $BeforeSnapshot.DiskFreeBytes
    $afterDiskFree = Format-WinOpsBytes -Bytes $AfterSnapshot.DiskFreeBytes
    $beforeMemUsed = Format-WinOpsBytes -Bytes $BeforeSnapshot.MemUsedBytes
    $afterMemUsed = Format-WinOpsBytes -Bytes $AfterSnapshot.MemUsedBytes

    $diskFreeDeltaAbs = [Math]::Abs($diskFreeDelta)
    $memUsedDeltaAbs = [Math]::Abs($memUsedDelta)

    $diskFreeDeltaFmt = Format-WinOpsBytes -Bytes $diskFreeDeltaAbs
    $memUsedDeltaFmt = Format-WinOpsBytes -Bytes $memUsedDeltaAbs

    Write-Host ""
    Write-WinOpsColor -Text "=== System Report ===" -Color Bold

    # Disk usage row
    $diskUsageIndicator = if ($diskUsageDelta -lt 0) {
        Write-WinOpsColor -Text "v" -Color Green -NoNewline
        "v"
    } elseif ($diskUsageDelta -eq 0) {
        "="
    } else {
        Write-WinOpsColor -Text "^" -Color Yellow -NoNewline
        "^"
    }

    Write-Host ("{0,-12} : {1,6}   ->  {2,6}   ({3} {4}%)" -f `
        "Disk", `
        "$($BeforeSnapshot.DiskUsagePct)%", `
        "$($AfterSnapshot.DiskUsagePct)%", `
        $diskUsageIndicator, `
        [Math]::Abs($diskUsageDelta))

    # Disk free row
    $diskFreeIndicator = if ($diskFreeDelta -gt 0) {
        Write-WinOpsColor -Text "^" -Color Green -NoNewline
        "^"
    } elseif ($diskFreeDelta -eq 0) {
        "="
    } else {
        Write-WinOpsColor -Text "v" -Color Yellow -NoNewline
        "v"
    }

    Write-Host ("{0,-12} : {1,9} ->  {2,9} ({3} {4})" -f `
        "Disk Free", `
        $beforeDiskFree, `
        $afterDiskFree, `
        $diskFreeIndicator, `
        $diskFreeDeltaFmt)

    # Memory used row
    $memUsedIndicator = if ($memUsedDelta -lt 0) {
        Write-WinOpsColor -Text "v" -Color Green -NoNewline
        "v"
    } elseif ($memUsedDelta -eq 0) {
        "="
    } else {
        Write-WinOpsColor -Text "^" -Color Yellow -NoNewline
        "^"
    }

    Write-Host ("{0,-12} : {1,9} ->  {2,9} ({3} {4})" -f `
        "Memory", `
        $beforeMemUsed, `
        $afterMemUsed, `
        $memUsedIndicator, `
        $memUsedDeltaFmt)

    Write-Host ""
    Write-WinOpsColor -Text "=== Cleanup Summary ===" -Color Bold

    $formattedSize = Format-WinOpsBytes -Bytes $CleanedBytes

    if ($CleanedCount -gt 0) {
        Write-WinOpsColor -Text "OK" -Color Green -NoNewline
        Write-Host " Files cleaned: $CleanedCount items ($formattedSize)"
    }

    if ($KilledProcs -gt 0) {
        Write-WinOpsColor -Text "OK" -Color Green -NoNewline
        Write-Host " Processes terminated: $KilledProcs items"
    }

    if ($CleanedCount -eq 0 -and $KilledProcs -eq 0) {
        Write-WinOpsColor -Text "[INFO]" -Color Blue -NoNewline
        Write-Host " No items to clean"
    }

    Write-Host ""
}

# Export functions
Export-ModuleMember -Function @(
    'Format-WinOpsBytes',
    'Format-WinOpsDuration',
    'Write-WinOpsColor',
    'Format-WinOpsTable',
    'Write-WinOpsHeader',
    'Write-WinOpsSummary',
    'Write-WinOpsReport'
)
