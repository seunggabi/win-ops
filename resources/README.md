# Win-Ops Internationalization (i18n)

This directory contains language resource files for Win-Ops internationalization support.

## Overview

Win-Ops supports multiple languages through the I18n module (`lib/core/I18n.psm1`). Language resources are stored as PowerShell Data Files (`.psd1`) in this directory.

## Supported Languages

- **en-US** (English - United States) - Default/Fallback language
- **ko-KR** (Korean - Korea)

## Language Detection

The I18n system automatically detects the system UI culture and loads the appropriate language file:

1. Checks current UI culture (`[System.Globalization.CultureInfo]::CurrentUICulture.Name`)
2. Matches to supported languages
3. Falls back to `en-US` if language not supported
4. Loads fallback language for missing keys

## Usage in Code

### Initialize I18n

```powershell
# Import and initialize (usually done once in main script)
Import-Module (Join-Path $scriptRoot 'lib\core\I18n.psm1') -Force
Initialize-WinOpsI18n
```

### Get Localized Messages

```powershell
# Simple message
$message = Get-WinOpsMessage -Key 'CLI_Help_Title'
# Returns: "Windows Operations Manager" (en-US) or "Windows 운영 관리자" (ko-KR)

# Message with parameters
$message = Get-WinOpsMessage -Key 'Cleanup_Complete' -Args 100, '5.2 GB'
# Returns: "Cleanup completed. 100 items processed, 5.2 GB freed"

# Message with default fallback
$message = Get-WinOpsMessage -Key 'Unknown_Key' -Default 'Fallback text'
# Returns: 'Fallback text' if key not found
```

### Check Message Key

```powershell
# Test if a key exists
if (Test-WinOpsMessageKey -Key 'CLI_Help_Title') {
    # Key exists
}
```

### Change Language

```powershell
# Switch to Korean
Set-WinOpsLanguage -Language 'ko-KR'

# Switch to English
Set-WinOpsLanguage -Language 'en-US'
```

### Get Current Language

```powershell
$currentLang = Get-WinOpsCurrentLanguage
# Returns: 'en-US' or 'ko-KR'
```

## Message Key Naming Conventions

Message keys follow a hierarchical naming pattern:

### Format
```
<Category>_<Context>_<Specific>
```

### Categories
- `CLI_` - Command-line interface messages
- `CMD_` - Command descriptions
- `OPT_` - Option descriptions
- `Analyze_` - Analysis module messages
- `Cleanup_` - Cleanup operation messages
- `Status_` - Status display messages
- `Trash_` - Trash/restore messages
- `Install_` - Installation messages
- `Uninstall_` - Uninstallation messages
- `Logger_` - Logger module messages
- `Cache_` - Cache cleanup messages
- `Error_` - Error messages
- `Warning_` - Warning messages

### Examples
```powershell
# Good key names
CLI_Help_Title              # Clear, hierarchical
Cleanup_Complete           # Specific context
Status_TrashItems          # Category + context

# Avoid
Help_Text                  # Too generic
CleanupComplete           # Missing separator
cleanup_complete          # Use PascalCase
```

## Parameter Substitution

Messages support .NET String.Format style placeholders:

```powershell
# In resource file (en-US.psd1)
@{
    Cleanup_Items = "Items: {0}"
    Cleanup_Summary = "Removed {0} items, freed {1} GB"
    Version_Title = "{0} version {1}"
}

# In code
Get-WinOpsMessage -Key 'Cleanup_Items' -Args 100
# Returns: "Items: 100"

Get-WinOpsMessage -Key 'Cleanup_Summary' -Args 50, 2.5
# Returns: "Removed 50 items, freed 2.5 GB"

Get-WinOpsMessage -Key 'Version_Title' -Args 'win-ops', '1.0.0'
# Returns: "win-ops version 1.0.0"
```

## Adding a New Language

1. Create a new `.psd1` file in this directory (e.g., `fr-FR.psd1` for French)
2. Copy the structure from `en-US.psd1`
3. Translate all message values (keep keys in English)
4. Update `Initialize-WinOpsI18n` to include the new language in validation
5. Update `Get-SystemLanguage` to handle the new language mapping

### Example: Adding French

```powershell
# resources/fr-FR.psd1
@{
    CLI_Help_Title = "Gestionnaire des opérations Windows"
    CLI_Help_Usage = "UTILISATION:"
    # ... rest of translations
}

# Update lib/core/I18n.psm1
# In Get-SystemLanguage function:
$supportedLanguages = @('en-US', 'ko-KR', 'fr-FR')

# In Initialize-WinOpsI18n function:
[ValidateSet('en-US', 'ko-KR', 'fr-FR')]
```

## Translation Guidelines

### DO
- ✅ Keep technical terms in English (e.g., "PowerShell", "GitHub", "GB", "MB")
- ✅ Translate user-facing messages and descriptions
- ✅ Preserve placeholder positions (`{0}`, `{1}`)
- ✅ Maintain consistent tone and style
- ✅ Test messages with actual parameter values

### DON'T
- ❌ Translate message keys (always keep in English)
- ❌ Translate command names or file paths
- ❌ Remove or reorder placeholders
- ❌ Add emojis unless in original
- ❌ Change technical parameter names

### Examples

```powershell
# Good translation (ko-KR)
Cleanup_Complete = "정리 완료!"  # Translate user message
Cache_Starting = "캐시 정리 시작: {0} (기간: {1}일)"  # Keep placeholders

# Bad translation
Cleanup_Complete = "Cleanup 완료! 😊"  # Don't add emojis
Cache_Starting = "캐시 정리 시작: {1}일 (기간: {0})"  # Don't reorder placeholders
```

## Resource File Structure

Each `.psd1` file is a PowerShell hashtable:

```powershell
@{
    # Comments for organization
    # CLI - Main Help
    CLI_Help_Title = "Windows Operations Manager"
    CLI_Help_Usage = "USAGE:"

    # Cleanup
    Cleanup_Starting = "Starting cleanup (DryRun: {0}, Force: {1})"
    Cleanup_Complete = "Cleanup complete!"
}
```

## Testing Translations

Test your translations by:

1. Setting your system UI language
2. Running Win-Ops commands
3. Verifying messages display correctly
4. Testing with various parameter values

```powershell
# Test language detection
Initialize-WinOpsI18n
Get-WinOpsCurrentLanguage

# Test specific messages
Get-WinOpsMessage -Key 'CLI_Help_Title'
Get-WinOpsMessage -Key 'Cleanup_Complete' -Args 100, '5.2 GB'

# Test language switching
Set-WinOpsLanguage -Language 'ko-KR'
Get-WinOpsMessage -Key 'CLI_Help_Title'
```

## Fallback Behavior

If a message key is not found:

1. Checks current language file
2. Falls back to `en-US` if not found
3. Returns `[KeyName]` if not in fallback either
4. Returns `Default` parameter if provided

```powershell
# Key exists in current language
Get-WinOpsMessage -Key 'CLI_Help_Title'
# Returns: localized message

# Key missing in ko-KR but exists in en-US
Get-WinOpsMessage -Key 'NewFeature_Message'
# Returns: en-US message (fallback)

# Key doesn't exist anywhere
Get-WinOpsMessage -Key 'NonExistent_Key'
# Returns: "[NonExistent_Key]"

# Key doesn't exist but default provided
Get-WinOpsMessage -Key 'NonExistent_Key' -Default 'Default text'
# Returns: "Default text"
```

## Performance Notes

- Language files are loaded once during initialization
- Messages are cached in memory
- No file I/O on each message retrieval
- Minimal overhead for parameter substitution

## File Encoding

All `.psd1` files must use UTF-8 encoding with BOM to support Unicode characters.

## Contributing Translations

When contributing translations:

1. Ensure complete coverage of all keys in `en-US.psd1`
2. Test with actual usage scenarios
3. Have translations reviewed by native speaker
4. Document any cultural adaptations needed
5. Update this README with new language information

## Support

For translation issues or questions:
- Check existing translations in `en-US.psd1` and `ko-KR.psd1`
- Review I18n module code in `lib/core/I18n.psm1`
- Open an issue on GitHub with translation questions
