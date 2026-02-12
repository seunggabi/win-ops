# I18n.psm1 - Win-Ops Internationalization Module
# Provides localized message retrieval with parameter substitution

#region Module Variables

$script:I18nConfig = @{
    CurrentLanguage = $null
    FallbackLanguage = 'en-US'
    Messages = @{}
    ResourcesPath = $null
    Initialized = $false
}

#endregion

#region Private Functions

function Get-SystemLanguage {
    <#
    .SYNOPSIS
        Detects the system UI language.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        # Try to get current UI culture
        $culture = [System.Globalization.CultureInfo]::CurrentUICulture.Name

        # Normalize to supported languages
        $supportedLanguages = @('en-US', 'ko-KR')

        if ($culture -in $supportedLanguages) {
            return $culture
        }

        # Check if base language is supported (e.g., 'ko' -> 'ko-KR')
        $baseLanguage = $culture.Split('-')[0]
        $match = $supportedLanguages | Where-Object { $_.StartsWith($baseLanguage) } | Select-Object -First 1

        if ($match) {
            return $match
        }

        # Fallback to English
        return 'en-US'
    }
    catch {
        Write-Verbose "Failed to detect system language: $_"
        return 'en-US'
    }
}

function Load-LanguageResources {
    <#
    .SYNOPSIS
        Loads language resource file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Language
    )

    $resourceFile = Join-Path $script:I18nConfig.ResourcesPath "$Language.json"

    if (-not (Test-Path $resourceFile)) {
        Write-Verbose "Resource file not found: $resourceFile"
        return @{}
    }

    try {
        $jsonContent = Get-Content -Path $resourceFile -Raw -ErrorAction Stop
        $data = $jsonContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        Write-Verbose "Loaded language resources: $Language ($($data.Count) messages)"
        return $data
    }
    catch {
        Write-Warning "Failed to load language resources from $resourceFile`: $_"
        return @{}
    }
}

#endregion

#region Public Functions

function Initialize-WinOpsI18n {
    <#
    .SYNOPSIS
        Initializes the internationalization system.

    .DESCRIPTION
        Sets up language detection, loads resource files, and configures message retrieval.

    .PARAMETER Language
        Specific language to use. If not specified, auto-detects from system.

    .PARAMETER ResourcesPath
        Path to resources directory containing language files. Defaults to .\resources

    .EXAMPLE
        Initialize-WinOpsI18n
        # Auto-detect system language

    .EXAMPLE
        Initialize-WinOpsI18n -Language 'ko-KR'
        # Force Korean language
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('en-US', 'ko-KR')]
        [string]$Language,

        [Parameter()]
        [string]$ResourcesPath
    )

    # Determine resources path
    if ($ResourcesPath) {
        $script:I18nConfig.ResourcesPath = $ResourcesPath
    }
    else {
        # Default: resources directory relative to project root
        # $PSScriptRoot is lib/core, so go up twice to get project root
        $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $script:I18nConfig.ResourcesPath = Join-Path $projectRoot 'resources'
    }

    # Ensure resources directory exists
    if (-not (Test-Path $script:I18nConfig.ResourcesPath)) {
        Write-Warning "Resources directory not found: $($script:I18nConfig.ResourcesPath)"
        Write-Warning "Falling back to English (en-US)"
        $script:I18nConfig.CurrentLanguage = 'en-US'
        $script:I18nConfig.Messages = @{}
        $script:I18nConfig.Initialized = $true
        return
    }

    # Detect or use specified language
    $targetLanguage = if ($Language) { $Language } else { Get-SystemLanguage }
    $script:I18nConfig.CurrentLanguage = $targetLanguage

    # Load primary language resources
    $script:I18nConfig.Messages = Load-LanguageResources -Language $targetLanguage

    # Load fallback language if primary language is not English
    if ($targetLanguage -ne $script:I18nConfig.FallbackLanguage) {
        $fallbackMessages = Load-LanguageResources -Language $script:I18nConfig.FallbackLanguage

        # Merge fallback messages (primary language takes precedence)
        foreach ($key in $fallbackMessages.Keys) {
            if (-not $script:I18nConfig.Messages.ContainsKey($key)) {
                $script:I18nConfig.Messages[$key] = $fallbackMessages[$key]
            }
        }
    }

    $script:I18nConfig.Initialized = $true

    Write-Verbose "I18n initialized: Language=$targetLanguage, Messages=$($script:I18nConfig.Messages.Count)"
}

function Get-WinOpsMessage {
    <#
    .SYNOPSIS
        Retrieves a localized message by key.

    .DESCRIPTION
        Gets a localized message string with optional parameter substitution.
        Supports .NET String.Format style placeholders: {0}, {1}, etc.

    .PARAMETER Key
        Message key to retrieve.

    .PARAMETER Args
        Optional arguments for parameter substitution.

    .PARAMETER Default
        Default message if key is not found.

    .EXAMPLE
        Get-WinOpsMessage -Key 'CLI_Help_Title'
        # Returns localized help title

    .EXAMPLE
        Get-WinOpsMessage -Key 'Cleanup_Complete' -Args 100, '5.2 GB'
        # Returns: "Cleanup completed. 100 items processed, 5.2 GB freed"

    .EXAMPLE
        Get-WinOpsMessage -Key 'Unknown_Key' -Default 'Fallback text'
        # Returns fallback text if key not found
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        [object[]]$Args,

        [Parameter()]
        [string]$Default
    )

    # Initialize if not done
    if (-not $script:I18nConfig.Initialized) {
        Initialize-WinOpsI18n
    }

    # Retrieve message
    $message = $script:I18nConfig.Messages[$Key]

    if (-not $message) {
        if ($Default) {
            $message = $Default
        }
        else {
            Write-Verbose "Message key not found: $Key"
            return "[$Key]"
        }
    }

    # Apply parameter substitution if arguments provided
    if ($Args -and $Args.Count -gt 0) {
        try {
            return [string]::Format($message, $Args)
        }
        catch {
            Write-Warning "Failed to format message '$Key': $_"
            return $message
        }
    }

    return $message
}

function Set-WinOpsLanguage {
    <#
    .SYNOPSIS
        Changes the current language.

    .DESCRIPTION
        Switches to a different language at runtime.

    .PARAMETER Language
        Language code to switch to.

    .EXAMPLE
        Set-WinOpsLanguage -Language 'ko-KR'
        # Switch to Korean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('en-US', 'ko-KR')]
        [string]$Language
    )

    if (-not $script:I18nConfig.Initialized) {
        Initialize-WinOpsI18n -Language $Language
        return
    }

    $oldLanguage = $script:I18nConfig.CurrentLanguage
    $script:I18nConfig.CurrentLanguage = $Language

    # Reload resources
    $script:I18nConfig.Messages = Load-LanguageResources -Language $Language

    # Load fallback if needed
    if ($Language -ne $script:I18nConfig.FallbackLanguage) {
        $fallbackMessages = Load-LanguageResources -Language $script:I18nConfig.FallbackLanguage

        foreach ($key in $fallbackMessages.Keys) {
            if (-not $script:I18nConfig.Messages.ContainsKey($key)) {
                $script:I18nConfig.Messages[$key] = $fallbackMessages[$key]
            }
        }
    }

    Write-Verbose "Language changed: $oldLanguage -> $Language"
}

function Get-WinOpsCurrentLanguage {
    <#
    .SYNOPSIS
        Returns the current language code.

    .DESCRIPTION
        Gets the currently active language.

    .EXAMPLE
        Get-WinOpsCurrentLanguage
        # Returns: 'en-US' or 'ko-KR'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not $script:I18nConfig.Initialized) {
        Initialize-WinOpsI18n
    }

    return $script:I18nConfig.CurrentLanguage
}

function Test-WinOpsMessageKey {
    <#
    .SYNOPSIS
        Tests if a message key exists.

    .DESCRIPTION
        Checks if a message key is defined in the current language resources.

    .PARAMETER Key
        Message key to test.

    .EXAMPLE
        Test-WinOpsMessageKey -Key 'CLI_Help_Title'
        # Returns: $true or $false
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not $script:I18nConfig.Initialized) {
        Initialize-WinOpsI18n
    }

    return $script:I18nConfig.Messages.ContainsKey($Key)
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Initialize-WinOpsI18n',
    'Get-WinOpsMessage',
    'Set-WinOpsLanguage',
    'Get-WinOpsCurrentLanguage',
    'Test-WinOpsMessageKey'
)

#endregion
