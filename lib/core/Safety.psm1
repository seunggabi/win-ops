# Safety.psm1
# 5-Tier Safety System for WinOps

<#
.SYNOPSIS
    Comprehensive safety system for Windows operations
.DESCRIPTION
    Implements multi-layered protection:
    - Tier 1: Protected paths (system directories)
    - Tier 2: Protected processes (critical system processes)
    - Tier 3: Size guards (file/batch size limits)
    - Tier 4: WRP detection (Windows Resource Protection)
    - Tier 5: Integrated safety checks with configurable levels
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Safety levels
enum SafetyLevel {
    Strict      # Maximum protection, minimal risk
    Normal      # Balanced protection
    Permissive  # Minimal protection, user responsibility
}

# Size limits (in bytes)
$script:SIZE_LIMIT_SINGLE_FILE = 2GB
$script:SIZE_LIMIT_BATCH = 10GB

# Protected paths (base patterns)
$script:PROTECTED_PATHS = @(
    'C:\Windows',
    'C:\Program Files',
    'C:\Program Files (x86)',
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Pictures",
    "$env:USERPROFILE\Videos",
    "$env:USERPROFILE\Music"
)

# WRP protected paths (Windows Resource Protection)
$script:WRP_PATHS = @(
    'C:\Windows\System32',
    'C:\Windows\SysWOW64',
    'C:\Windows\WinSxS',
    'C:\Windows\servicing',
    'C:\Program Files\Windows Defender',
    'C:\Program Files\WindowsApps'
)

# Base protected processes (always protected)
$script:BASE_PROTECTED_PROCESSES = @(
    'System',
    'csrss',
    'lsass',
    'svchost',
    'explorer'
)

# Cache for protected processes config
$script:ProtectedProcessesCache = $null
$script:ConfigLoadTime = $null

<#
.SYNOPSIS
    Load protected processes from configuration
.DESCRIPTION
    Loads and caches protected process list from config file
#>
function Get-ProtectedProcesses {
    [CmdletBinding()]
    param()

    # Refresh cache every 5 minutes
    $now = Get-Date
    if ($script:ProtectedProcessesCache -and $script:ConfigLoadTime -and
        (($now - $script:ConfigLoadTime).TotalMinutes -lt 5)) {
        return $script:ProtectedProcessesCache
    }

    $processes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # Add base protected processes
    foreach ($proc in $script:BASE_PROTECTED_PROCESSES) {
        [void]$processes.Add($proc)
    }

    # Load additional processes from config
    $configPath = Join-Path $PSScriptRoot '..\..\config\protected-processes.json'
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json

            foreach ($category in @('critical_processes', 'system_processes', 'security_processes')) {
                if ($config.PSObject.Properties.Name -contains $category) {
                    foreach ($proc in $config.$category) {
                        [void]$processes.Add($proc)
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to load protected processes config: $_"
        }
    }

    # Update cache
    $script:ProtectedProcessesCache = $processes
    $script:ConfigLoadTime = $now

    return $processes
}

<#
.SYNOPSIS
    Test if a path is in protected locations
.DESCRIPTION
    Checks if the given path is under protected directories
.PARAMETER Path
    Path to check
.PARAMETER Level
    Safety level (Strict, Normal, Permissive)
.EXAMPLE
    Test-WinOpsPathSafe -Path "C:\Windows\System32\file.dll"
    Returns $false (protected path)
#>
function Test-WinOpsPathSafe {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,

        [Parameter()]
        [SafetyLevel]$Level = [SafetyLevel]::Normal
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "Path cannot be null or empty"
        }

        try {
            # Resolve to absolute path
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            # In Permissive mode, only check WRP paths
            $pathsToCheck = if ($Level -eq [SafetyLevel]::Permissive) {
                $script:WRP_PATHS
            }
            else {
                $script:PROTECTED_PATHS + $script:WRP_PATHS
            }

            # Check if path is under any protected location
            foreach ($protectedPath in $pathsToCheck) {
                $expandedProtected = [System.Environment]::ExpandEnvironmentVariables($protectedPath)

                if ($resolvedPath -like "$expandedProtected\*" -or $resolvedPath -eq $expandedProtected) {
                    Write-Verbose "Path '$resolvedPath' is under protected location '$expandedProtected'"
                    return $false
                }
            }

            return $true
        }
        catch {
            Write-Warning "Failed to resolve path '$Path': $_"
            # Fail safe: treat as unsafe if we can't resolve
            return $false
        }
    }
}

<#
.SYNOPSIS
    Test if a process is protected
.DESCRIPTION
    Checks if the given process name is in the protected process list
.PARAMETER ProcessName
    Name of the process (with or without .exe)
.PARAMETER Level
    Safety level (affects which processes are protected)
.EXAMPLE
    Test-WinOpsProcessProtected -ProcessName "csrss"
    Returns $true (critical system process)
#>
function Test-WinOpsProcessProtected {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$ProcessName,

        [Parameter()]
        [SafetyLevel]$Level = [SafetyLevel]::Normal
    )

    process {
        if ([string]::IsNullOrWhiteSpace($ProcessName)) {
            throw "ProcessName cannot be null or empty"
        }

        # Normalize process name (remove .exe if present)
        $normalizedName = $ProcessName -replace '\.exe$', ''

        # In Permissive mode, only protect critical processes
        if ($Level -eq [SafetyLevel]::Permissive) {
            $criticalProcesses = @('System', 'csrss', 'lsass', 'smss', 'services')
            return $criticalProcesses -contains $normalizedName
        }

        # Load protected processes list
        $protectedProcesses = Get-ProtectedProcesses

        $isProtected = $protectedProcesses.Contains($normalizedName)

        if ($isProtected) {
            Write-Verbose "Process '$normalizedName' is protected"
        }

        return $isProtected
    }
}

<#
.SYNOPSIS
    Test if size is within allowed limits
.DESCRIPTION
    Validates file or batch operation size against configured limits
.PARAMETER Size
    Size in bytes
.PARAMETER IsBatch
    Whether this is a batch operation (uses higher limit)
.PARAMETER Level
    Safety level (Permissive mode increases limits)
.EXAMPLE
    Test-WinOpsSizeGuard -Size 1500000000 -IsBatch $false
    Returns $true (under 2GB single file limit)
#>
function Test-WinOpsSizeGuard {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [long]$Size,

        [Parameter()]
        [switch]$IsBatch,

        [Parameter()]
        [SafetyLevel]$Level = [SafetyLevel]::Normal
    )

    if ($Size -lt 0) {
        throw "Size cannot be negative"
    }

    # Adjust limits based on safety level
    $singleLimit = $script:SIZE_LIMIT_SINGLE_FILE
    $batchLimit = $script:SIZE_LIMIT_BATCH

    if ($Level -eq [SafetyLevel]::Permissive) {
        $singleLimit *= 2
        $batchLimit *= 2
    }
    elseif ($Level -eq [SafetyLevel]::Strict) {
        $singleLimit = [long]($singleLimit * 0.5)
        $batchLimit = [long]($batchLimit * 0.5)
    }

    $limit = if ($IsBatch) { $batchLimit } else { $singleLimit }
    $limitType = if ($IsBatch) { "batch" } else { "single file" }

    if ($Size -gt $limit) {
        Write-Verbose "Size $Size bytes exceeds $limitType limit of $limit bytes"
        return $false
    }

    return $true
}

<#
.SYNOPSIS
    Test if path is WRP protected
.DESCRIPTION
    Detects Windows Resource Protection (WRP) paths that require TrustedInstaller
.PARAMETER Path
    Path to check
.EXAMPLE
    Test-WinOpsSystemPath -Path "C:\Windows\System32\kernel32.dll"
    Returns $true (WRP protected)
#>
function Test-WinOpsSystemPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "Path cannot be null or empty"
        }

        try {
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            foreach ($wrpPath in $script:WRP_PATHS) {
                $expandedWrp = [System.Environment]::ExpandEnvironmentVariables($wrpPath)

                if ($resolvedPath -like "$expandedWrp\*" -or $resolvedPath -eq $expandedWrp) {
                    Write-Verbose "Path '$resolvedPath' is WRP protected: '$expandedWrp'"
                    return $true
                }
            }

            return $false
        }
        catch {
            Write-Warning "Failed to resolve path '$Path': $_"
            # Fail safe: treat as WRP if we can't resolve
            return $true
        }
    }
}

<#
.SYNOPSIS
    Integrated safety check for operations
.DESCRIPTION
    Performs comprehensive safety validation before allowing an operation
    Combines all safety tiers into a single validation function
.PARAMETER Path
    Path to validate (optional)
.PARAMETER ProcessName
    Process name to validate (optional)
.PARAMETER Size
    Size to validate (optional)
.PARAMETER IsBatch
    Whether this is a batch operation
.PARAMETER Level
    Safety level (Strict, Normal, Permissive)
.PARAMETER DryRun
    If specified, returns validation results without throwing
.EXAMPLE
    Assert-WinOpsSafeOperation -Path "C:\Temp\file.txt" -Size 1000000
    Validates path safety and size limits, throws if unsafe
.EXAMPLE
    Assert-WinOpsSafeOperation -Path "C:\Windows\System32" -DryRun
    Returns validation object without throwing
#>
function Assert-WinOpsSafeOperation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$ProcessName,

        [Parameter()]
        [long]$Size = -1,

        [Parameter()]
        [switch]$IsBatch,

        [Parameter()]
        [SafetyLevel]$Level = [SafetyLevel]::Normal,

        [Parameter()]
        [switch]$DryRun
    )

    $checks = [ordered]@{
        PathSafe = $null
        ProcessSafe = $null
        SizeSafe = $null
        NotWRP = $null
        OverallSafe = $true
        Errors = @()
        Warnings = @()
    }

    # Check 1: Path safety
    if ($Path) {
        try {
            $checks.PathSafe = Test-WinOpsPathSafe -Path $Path -Level $Level
            if (-not $checks.PathSafe) {
                $checks.OverallSafe = $false
                $checks.Errors += "Path is in protected location: $Path"
            }
        }
        catch {
            $checks.PathSafe = $false
            $checks.OverallSafe = $false
            $checks.Errors += "Path validation failed: $_"
        }
    }

    # Check 2: Process safety
    if ($ProcessName) {
        try {
            $isProtected = Test-WinOpsProcessProtected -ProcessName $ProcessName -Level $Level
            $checks.ProcessSafe = -not $isProtected
            if ($isProtected) {
                $checks.OverallSafe = $false
                $checks.Errors += "Process is protected: $ProcessName"
            }
        }
        catch {
            $checks.ProcessSafe = $false
            $checks.OverallSafe = $false
            $checks.Errors += "Process validation failed: $_"
        }
    }

    # Check 3: Size guard
    if ($Size -ge 0) {
        try {
            $checks.SizeSafe = Test-WinOpsSizeGuard -Size $Size -IsBatch:$IsBatch -Level $Level
            if (-not $checks.SizeSafe) {
                $checks.OverallSafe = $false
                $limitType = if ($IsBatch) { "batch" } else { "single file" }
                $checks.Errors += "Size exceeds $limitType limit: $Size bytes"
            }
        }
        catch {
            $checks.SizeSafe = $false
            $checks.OverallSafe = $false
            $checks.Errors += "Size validation failed: $_"
        }
    }

    # Check 4: WRP detection
    if ($Path) {
        try {
            $isWRP = Test-WinOpsSystemPath -Path $Path
            $checks.NotWRP = -not $isWRP
            if ($isWRP) {
                if ($Level -eq [SafetyLevel]::Strict) {
                    $checks.OverallSafe = $false
                    $checks.Errors += "Path is WRP protected (requires TrustedInstaller): $Path"
                }
                else {
                    $checks.Warnings += "Path is WRP protected, elevated permissions may be required: $Path"
                }
            }
        }
        catch {
            $checks.NotWRP = $false
            $checks.Warnings += "WRP detection failed: $_"
        }
    }

    # Build result object
    $result = [PSCustomObject]$checks
    $result.PSObject.TypeNames.Insert(0, 'WinOps.SafetyCheckResult')

    # DryRun mode: return results without throwing
    if ($DryRun) {
        return $result
    }

    # Normal mode: throw if unsafe
    if (-not $checks.OverallSafe) {
        $errorMessage = "Safety validation failed:`n" + ($checks.Errors -join "`n")
        if ($checks.Warnings.Count -gt 0) {
            $errorMessage += "`nWarnings:`n" + ($checks.Warnings -join "`n")
        }
        throw $errorMessage
    }

    # Log warnings even if overall safe
    foreach ($warning in $checks.Warnings) {
        Write-Warning $warning
    }

    return $result
}

# Export functions
Export-ModuleMember -Function @(
    'Test-WinOpsPathSafe',
    'Test-WinOpsProcessProtected',
    'Test-WinOpsSizeGuard',
    'Test-WinOpsSystemPath',
    'Assert-WinOpsSafeOperation'
)
