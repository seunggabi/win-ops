# Config Module Test Fixes

## Changes Applied

### 1. Expand-ConfigObject - Null Handling (Line 87-89)
**Issue**: ParameterBindingValidationException when null values are passed
**Fix**: Added null check at the beginning of the function:
```powershell
if ($null -eq $Object) {
    return $null
}
```

### 2. Read-JsonConfigFile - Empty File Handling (Line 225-228)
**Issue**: Empty configuration files causing JSON parsing errors
**Fix**: Added empty content check before ConvertFrom-Json:
```powershell
if ([string]::IsNullOrWhiteSpace($content)) {
    Write-Verbose "Configuration file is empty: $Path"
    return $null
}
```

### 3. Initialize-WinOpsConfig - Improved Validation and Directory Creation (Line 336-345)
**Issue**: 
- Config file not created in correct location
- No validation after reading default config
- Missing 'default' property error

**Fix**: 
- Added validation check after reading default config
- Ensured config directory exists before writing
```powershell
if (-not $defaultConfig) {
    Write-Error "Failed to read default configuration from: $defaultPath"
    return
}

# Ensure config directory exists
$configDir = Split-Path -Parent $configPath
if (-not (Test-Path $configDir)) {
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
}
```

## Test Cases Addressed

1. **Expand-ConfigObject** - null value handling
   - Returns null when $null is passed instead of throwing exception

2. **Get-WinOpsConfig** - environment variable expansion
   - Properly expands %LOCALAPPDATA% and other env vars in config values

3. **Initialize-WinOpsConfig** - config file creation
   - Creates config directory if it doesn't exist
   - Validates default config was successfully read
   - Properly copies default.json to config.json location

4. **Initialize-WinOpsConfig -Force** - overwrite existing config
   - No longer throws "property 'default' not found" error
   - Properly validates and copies default config

5. **Edge Cases** - empty configuration files
   - Returns null instead of throwing JSON parsing errors
   - Provides verbose logging for debugging

## Files Modified

- `/Users/seunggabi/seunggabi/project/n8n/win-ops/lib/core/Config.psm1`

## Testing Notes

All fixes maintain backward compatibility and improve error handling:
- Better null safety
- Clearer error messages
- Improved validation before operations
- Proper directory creation
