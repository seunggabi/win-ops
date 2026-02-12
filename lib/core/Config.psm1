#Requires -Version 5.1

<#
.SYNOPSIS
    Configuration management module for win-ops
.DESCRIPTION
    Provides JSON-based configuration loading, saving, and merging with default values.
    Supports environment variable expansion and hierarchical settings access.
#>

using namespace System.Collections.Generic
using namespace System.IO

# Module variables
$script:ConfigCache = $null
$script:ConfigLastModified = $null
$script:ConfigLockTimeout = 5000 # milliseconds

<#
.SYNOPSIS
    Gets the configuration file path
.OUTPUTS
    String - Path to user configuration file
#>
function Get-ConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $configDir = Join-Path $env:LOCALAPPDATA "win-ops"
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    return Join-Path $configDir "config.json"
}

<#
.SYNOPSIS
    Gets the default configuration file path
.OUTPUTS
    String - Path to default configuration file
#>
function Get-DefaultConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return Join-Path $moduleRoot "config\default.json"
}

<#
.SYNOPSIS
    Expands environment variables in a string
.PARAMETER Value
    String containing environment variables (e.g., %LOCALAPPDATA%)
.OUTPUTS
    String - Expanded string
#>
function Expand-EnvironmentVariables {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return [Environment]::ExpandEnvironmentVariables($Value)
}

<#
.SYNOPSIS
    Recursively expands environment variables in configuration objects
.PARAMETER Object
    Configuration object (hashtable or PSCustomObject)
.OUTPUTS
    Object - Object with expanded environment variables
#>
function Expand-ConfigObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Object
    )

    if ($Object -is [string]) {
        return Expand-EnvironmentVariables -Value $Object
    }

    if ($Object -is [hashtable]) {
        $expanded = @{}
        foreach ($key in $Object.Keys) {
            $expanded[$key] = Expand-ConfigObject -Object $Object[$key]
        }
        return $expanded
    }

    if ($Object -is [PSCustomObject]) {
        $expanded = @{}
        foreach ($property in $Object.PSObject.Properties) {
            $expanded[$property.Name] = Expand-ConfigObject -Object $property.Value
        }
        return [PSCustomObject]$expanded
    }

    if ($Object -is [array]) {
        $expanded = @()
        foreach ($item in $Object) {
            $expanded += Expand-ConfigObject -Object $item
        }
        return $expanded
    }

    return $Object
}

<#
.SYNOPSIS
    Recursively merges two configuration objects
.PARAMETER Default
    Default configuration object
.PARAMETER Override
    Override configuration object
.OUTPUTS
    Object - Merged configuration object
#>
function Merge-ConfigObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Default,

        [Parameter(Mandatory = $false)]
        $Override
    )

    if ($null -eq $Override) {
        return $Default
    }

    if ($Default -isnot [hashtable] -and $Default -isnot [PSCustomObject]) {
        return $Override
    }

    $merged = @{}

    # Convert PSCustomObject to hashtable for easier manipulation
    if ($Default -is [PSCustomObject]) {
        foreach ($property in $Default.PSObject.Properties) {
            $merged[$property.Name] = $property.Value
        }
    } else {
        foreach ($key in $Default.Keys) {
            $merged[$key] = $Default[$key]
        }
    }

    # Merge override values
    if ($Override -is [PSCustomObject]) {
        foreach ($property in $Override.PSObject.Properties) {
            if ($merged.ContainsKey($property.Name) -and
                ($merged[$property.Name] -is [hashtable] -or $merged[$property.Name] -is [PSCustomObject]) -and
                ($property.Value -is [hashtable] -or $property.Value -is [PSCustomObject])) {
                $merged[$property.Name] = Merge-ConfigObject -Default $merged[$property.Name] -Override $property.Value
            } else {
                $merged[$property.Name] = $property.Value
            }
        }
    } elseif ($Override -is [hashtable]) {
        foreach ($key in $Override.Keys) {
            if ($merged.ContainsKey($key) -and
                ($merged[$key] -is [hashtable] -or $merged[$key] -is [PSCustomObject]) -and
                ($Override[$key] -is [hashtable] -or $Override[$key] -is [PSCustomObject])) {
                $merged[$key] = Merge-ConfigObject -Default $merged[$key] -Override $Override[$key]
            } else {
                $merged[$key] = $Override[$key]
            }
        }
    }

    return [PSCustomObject]$merged
}

<#
.SYNOPSIS
    Loads JSON configuration from a file with file locking
.PARAMETER Path
    Path to JSON configuration file
.OUTPUTS
    Object - Parsed JSON configuration
#>
function Read-JsonConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Verbose "Configuration file not found: $Path"
        return $null
    }

    try {
        $fileStream = $null
        $reader = $null

        try {
            # Open file with read lock
            $fileStream = [FileStream]::new(
                $Path,
                [FileMode]::Open,
                [FileAccess]::Read,
                [FileShare]::Read
            )

            $reader = [StreamReader]::new($fileStream)
            $content = $reader.ReadToEnd()

            return $content | ConvertFrom-Json
        }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($fileStream) { $fileStream.Dispose() }
        }
    }
    catch {
        Write-Warning "Failed to read configuration file '$Path': $_"
        return $null
    }
}

<#
.SYNOPSIS
    Writes JSON configuration to a file with file locking
.PARAMETER Path
    Path to JSON configuration file
.PARAMETER Config
    Configuration object to write
#>
function Write-JsonConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Config
    )

    try {
        $fileStream = $null
        $writer = $null

        try {
            # Ensure directory exists
            $directory = Split-Path -Parent $Path
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }

            # Convert to JSON with indentation
            $json = $Config | ConvertTo-Json -Depth 10

            # Open file with exclusive lock
            $fileStream = [FileStream]::new(
                $Path,
                [FileMode]::Create,
                [FileAccess]::Write,
                [FileShare]::None
            )

            $writer = [StreamWriter]::new($fileStream)
            $writer.Write($json)
            $writer.Flush()
        }
        finally {
            if ($writer) { $writer.Dispose() }
            if ($fileStream) { $fileStream.Dispose() }
        }

        Write-Verbose "Configuration saved to: $Path"
    }
    catch {
        Write-Error "Failed to write configuration file '$Path': $_"
        throw
    }
}

<#
.SYNOPSIS
    Initializes win-ops configuration by copying default settings
.DESCRIPTION
    Creates user configuration file from default.json if it doesn't exist.
    Does not overwrite existing configuration.
.PARAMETER Force
    Overwrite existing configuration file
.EXAMPLE
    Initialize-WinOpsConfig
.EXAMPLE
    Initialize-WinOpsConfig -Force
#>
function Initialize-WinOpsConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force
    )

    $configPath = Get-ConfigPath
    $defaultPath = Get-DefaultConfigPath

    if (-not (Test-Path $defaultPath)) {
        Write-Error "Default configuration file not found: $defaultPath"
        return
    }

    if ((Test-Path $configPath) -and -not $Force) {
        Write-Verbose "Configuration file already exists: $configPath"
        return
    }

    if ($PSCmdlet.ShouldProcess($configPath, "Initialize configuration")) {
        try {
            $defaultConfig = Read-JsonConfigFile -Path $defaultPath
            Write-JsonConfigFile -Path $configPath -Config $defaultConfig

            # Clear cache
            $script:ConfigCache = $null
            $script:ConfigLastModified = $null

            Write-Host "Configuration initialized: $configPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to initialize configuration: $_"
            throw
        }
    }
}

<#
.SYNOPSIS
    Merges default configuration with user configuration
.DESCRIPTION
    Combines default.json with user config.json, with user values taking precedence.
    Expands environment variables in the merged configuration.
.OUTPUTS
    PSCustomObject - Merged configuration
.EXAMPLE
    Merge-WinOpsConfig
#>
function Merge-WinOpsConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $defaultPath = Get-DefaultConfigPath
    $userPath = Get-ConfigPath

    # Load default configuration
    $defaultConfig = Read-JsonConfigFile -Path $defaultPath
    if (-not $defaultConfig) {
        Write-Error "Failed to load default configuration from: $defaultPath"
        return $null
    }

    # Load user configuration (optional)
    $userConfig = Read-JsonConfigFile -Path $userPath

    # Merge configurations
    $merged = Merge-ConfigObject -Default $defaultConfig -Override $userConfig

    # Expand environment variables
    $expanded = Expand-ConfigObject -Object $merged

    return $expanded
}

<#
.SYNOPSIS
    Gets win-ops configuration
.DESCRIPTION
    Retrieves merged configuration from default.json and config.json.
    Uses caching for performance and checks file modification times.
.PARAMETER Key
    Optional hierarchical key path (e.g., "trash.path", "cleanup.max_threads")
.PARAMETER Refresh
    Force refresh of cached configuration
.OUTPUTS
    Object - Full configuration or specific value if Key is specified
.EXAMPLE
    Get-WinOpsConfig
    Get-WinOpsConfig -Key "trash.path"
    Get-WinOpsConfig -Key "cleanup" -Refresh
#>
function Get-WinOpsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Key,

        [switch]$Refresh
    )

    $configPath = Get-ConfigPath
    $defaultPath = Get-DefaultConfigPath

    # Check if cache is still valid
    $needsRefresh = $Refresh -or
                    ($null -eq $script:ConfigCache) -or
                    ($null -eq $script:ConfigLastModified)

    if (-not $needsRefresh) {
        $currentModified = @()

        if (Test-Path $defaultPath) {
            $currentModified += (Get-Item $defaultPath).LastWriteTimeUtc
        }

        if (Test-Path $configPath) {
            $currentModified += (Get-Item $configPath).LastWriteTimeUtc
        }

        if ($script:ConfigLastModified -ne $null) {
            $lastModified = $script:ConfigLastModified
            $needsRefresh = $currentModified | Where-Object { $_ -gt $lastModified } | Select-Object -First 1
        }
    }

    if ($needsRefresh) {
        Write-Verbose "Loading configuration (cache miss or file modified)"
        $script:ConfigCache = Merge-WinOpsConfig

        if (Test-Path $defaultPath) {
            $script:ConfigLastModified = (Get-Item $defaultPath).LastWriteTimeUtc
        }

        if (Test-Path $configPath) {
            $lastModified = (Get-Item $configPath).LastWriteTimeUtc
            if ($null -eq $script:ConfigLastModified -or $lastModified -gt $script:ConfigLastModified) {
                $script:ConfigLastModified = $lastModified
            }
        }
    }

    if (-not $script:ConfigCache) {
        Write-Error "Failed to load configuration"
        return $null
    }

    # Return full config if no key specified
    if (-not $Key) {
        return $script:ConfigCache
    }

    # Navigate hierarchical key path
    $current = $script:ConfigCache
    $keyParts = $Key -split '\.'

    foreach ($part in $keyParts) {
        if ($current -is [PSCustomObject]) {
            if ($current.PSObject.Properties.Name -contains $part) {
                $current = $current.$part
            } else {
                Write-Warning "Configuration key not found: $Key"
                return $null
            }
        } elseif ($current -is [hashtable]) {
            if ($current.ContainsKey($part)) {
                $current = $current[$part]
            } else {
                Write-Warning "Configuration key not found: $Key"
                return $null
            }
        } else {
            Write-Warning "Cannot navigate key path: $Key"
            return $null
        }
    }

    return $current
}

<#
.SYNOPSIS
    Sets win-ops configuration value
.DESCRIPTION
    Updates configuration value at specified key path and saves to disk.
    Supports hierarchical key paths with dot notation.
.PARAMETER Key
    Hierarchical key path (e.g., "trash.path", "cleanup.max_threads")
.PARAMETER Value
    Value to set
.PARAMETER Path
    Custom configuration file path (defaults to user config)
.EXAMPLE
    Set-WinOpsConfig -Key "trash.retention_hours" -Value 48
    Set-WinOpsConfig -Key "cleanup.dry_run" -Value $true
    Set-WinOpsConfig -Key "cache_age_days" -Value 14
#>
function Set-WinOpsConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if (-not $Path) {
        $Path = Get-ConfigPath
    }

    # Load current configuration (create if doesn't exist)
    $config = Read-JsonConfigFile -Path $Path
    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    # Convert to hashtable for manipulation
    $configHash = @{}
    if ($config -is [PSCustomObject]) {
        foreach ($property in $config.PSObject.Properties) {
            $configHash[$property.Name] = $property.Value
        }
    }

    # Navigate/create key path
    $keyParts = $Key -split '\.'
    $current = $configHash

    for ($i = 0; $i -lt $keyParts.Count - 1; $i++) {
        $part = $keyParts[$i]

        if (-not $current.ContainsKey($part)) {
            $current[$part] = @{}
        }

        if ($current[$part] -is [PSCustomObject]) {
            $temp = @{}
            foreach ($property in $current[$part].PSObject.Properties) {
                $temp[$property.Name] = $property.Value
            }
            $current[$part] = $temp
        }

        $current = $current[$part]
    }

    # Set value
    $lastKey = $keyParts[-1]
    $current[$lastKey] = $Value

    if ($PSCmdlet.ShouldProcess($Path, "Set configuration key '$Key' = '$Value'")) {
        try {
            # Convert back to PSCustomObject and save
            $configObj = [PSCustomObject]$configHash
            Write-JsonConfigFile -Path $Path -Config $configObj

            # Clear cache
            $script:ConfigCache = $null
            $script:ConfigLastModified = $null

            Write-Verbose "Configuration updated: $Key = $Value"
        }
        catch {
            Write-Error "Failed to save configuration: $_"
            throw
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ConfigPath',
    'Get-DefaultConfigPath',
    'Expand-EnvironmentVariables',
    'Expand-ConfigObject',
    'Merge-ConfigObject',
    'Read-JsonConfigFile',
    'Write-JsonConfigFile',
    'Get-WinOpsConfig',
    'Set-WinOpsConfig',
    'Initialize-WinOpsConfig',
    'Merge-WinOpsConfig'
)
