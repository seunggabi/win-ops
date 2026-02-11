# Win-Ops CLI Quick Reference

## Command Overview

| Command | Function | Description | Modules Used |
|---------|----------|-------------|--------------|
| `help` | `Get-WinOpsHelp` | Display help | Built-in |
| `version` | `Get-WinOpsVersion` | Show version | Built-in |
| `analyze` | `Start-WinOpsAnalysis` | Analyze cleanup targets | Analyze |
| `run` | `Start-WinOpsCleanup` | Execute cleanup | Config, Logger, Lock, Trash, Analyze, Cleanup modules |
| `status` | `Get-WinOpsStatus` | Show system status | Disk, Trash, Lock |
| `list-trash` | `Get-TrashItems` | List trash items | Trash |
| `restore` | `Restore-TrashItem` | Restore from trash | Trash |
| `install` | `Install-WinOps` | Install scheduler | install.ps1 |
| `uninstall` | `Uninstall-WinOps` | Remove scheduler | uninstall.ps1 |

## Usage Examples

```powershell
# Analyze system
.\bin\win-ops.ps1 analyze

# Preview cleanup (dry-run)
.\bin\win-ops.ps1 run --dry-run

# Execute cleanup with confirmation
.\bin\win-ops.ps1 run

# Execute cleanup without confirmation
.\bin\win-ops.ps1 run --force

# Check status
.\bin\win-ops.ps1 status

# List trash
.\bin\win-ops.ps1 list-trash

# Restore from trash (interactive)
.\bin\win-ops.ps1 restore

# Install as scheduled task (requires admin)
.\bin\win-ops.ps1 install

# Uninstall scheduled task (requires admin)
.\bin\win-ops.ps1 uninstall
```

## Module Function Reference

### Core Modules (lib/core/)

**Config.psm1**
- `Get-WinOpsConfig` - Get configuration
- `Set-WinOpsConfig` - Set configuration value
- `Initialize-WinOpsConfig` - Create default config
- `Merge-WinOpsConfig` - Merge default + user config

**Logger.psm1**
- `Initialize-WinOpsLogger` - Setup logging
- `Write-WinOpsLog` - Write log entry
- Levels: DEBUG, INFO, WARN, ERROR

**Lock.psm1**
- `Lock-WinOps` - Acquire global lock
- `Unlock-WinOps` - Release lock
- `Test-WinOpsLocked` - Check if locked
- `Clear-WinOpsStaleLock` - Remove stale locks

**Disk.psm1**
- `Get-WinOpsDiskUsage` - Disk usage info
- `Test-WinOpsDiskSpace` - Check free space
- `Get-WinOpsLargestFiles` - Find large files
- `Get-WinOpsDirectorySize` - Calculate dir size
- `ConvertTo-HumanReadableSize` - Format bytes

**Trash.psm1**
- `Move-WinOpsToTrash` - Trash a file/folder
- `Get-WinOpsTrashList` - List trash items
- `Restore-WinOpsFromTrash` - Restore item
- `Remove-WinOpsExpiredTrash` - Clean expired
- `Clear-WinOpsTrash` - Empty trash

### Analysis Module (lib/modules/)

**Analyze.psm1**
- `Get-WinOpsAnalysis` - Full system analysis
- `Compare-WinOpsAnalysis` - Before/after comparison

### Cleanup Modules (lib/modules/)

**CacheCleanup.psm1**
- `Clear-WinOpsCache` - Clean Windows/app caches
- `Get-WinOpsCacheTargets` - List cache targets

**TmpCleanup.psm1**
- `Clear-WinOpsTemp` - Clean temp files
- `Get-WinOpsTempFileInfo` - List temp files

**LogCleanup.psm1**
- `Clear-WinOpsLog` - Clean log files
- `Get-WinOpsLogFileInfo` - List log files

**BrowserCleanup.psm1**
- `Clear-WinOpsBrowser` - Clean browser data
- `Get-WinOpsBrowserDataInfo` - List browser data

**DevCleanup.psm1**
- `Clear-WinOpsDev` - Clean dev caches
- `Get-WinOpsDevCacheInfo` - List dev caches

**DockerCleanup.psm1**
- `Clear-WinOpsDocker` - Clean Docker
- `Get-WinOpsDockerInfo` - List Docker items

**PackageManagerCleanup.psm1**
- `Clear-WinOpsPackageManager` - Clean package caches
- `Get-WinOpsPackageManagerInfo` - List package data

**ZombieKiller.psm1**
- `Stop-WinOpsZombieProcess` - Kill zombie processes

**OrphanKiller.psm1**
- `Remove-WinOpsOrphanFiles` - Remove orphaned files

**OrphanAppCleanup.psm1**
- `Clear-WinOpsOrphanApp` - Clean orphaned app data

## Key File Locations

### Configuration
- Default: `config/default.json`
- User: `%LOCALAPPDATA%\win-ops\config.json`

### Runtime Data
- Lock metadata: `%LOCALAPPDATA%\win-ops\.lock`
- Trash index: `%LOCALAPPDATA%\win-ops\trash\.index.json`
- Trash files: `%LOCALAPPDATA%\win-ops\trash\{hash}-{filename}`
- Logs: `%LOCALAPPDATA%\win-ops\logs\win-ops.log`
- Scheduled log: `%LOCALAPPDATA%\win-ops\logs\scheduled.log`

### Installation
- Entry point: `bin/win-ops.ps1`
- Installer: `install.ps1`
- Uninstaller: `uninstall.ps1`
- Scheduler: `scheduler/Invoke-WinOpsScheduled.ps1`

## Lock System

**Named Mutex:** `Global\WinOps`
**Metadata File:** `%LOCALAPPDATA%\win-ops\.lock`

**Lock Metadata:**
```json
{
  "PID": 12345,
  "StartTime": "2024-01-15T10:30:00Z",
  "Hostname": "DESKTOP-ABC",
  "Process": "pwsh",
  "CommandLine": "pwsh -File bin/win-ops.ps1 run"
}
```

**Stale Lock Detection:**
- Process no longer exists
- Lock age > 60 minutes (configurable)

## Trash System

**Retention:** 72 hours (configurable)
**Hash Algorithm:** SHA256 (path + timestamp)

**Trash Index Entry:**
```json
{
  "items": {
    "a1b2c3d4...": {
      "original_path": "C:\\Users\\...\\cache.tmp",
      "trash_path": "C:\\Users\\...\\win-ops\\trash\\a1b2c3d4-cache.tmp",
      "deleted_at": "2024-01-15T10:30:00Z",
      "size": 257698816,
      "module": "CacheCleanup"
    }
  }
}
```

## Error Handling Pattern

All CLI commands follow this pattern:

```powershell
function Command-WinOps {
    [CmdletBinding()]
    param(...)

    try {
        # Import required modules
        $module = Join-Path $script:ScriptRoot 'lib\...\Module.psm1'

        if (-not (Test-Path $module)) {
            Write-Error "Module not found: $module"
            return
        }

        Import-Module $module -Force

        # ... operation logic ...
    }
    catch {
        Write-Error "Operation failed: $_"
        Write-Verbose $_.ScriptStackTrace
    }
}
```

## Parameter Conventions

**Global Flags:**
- `--dry-run` / `-n`: Preview mode, no changes
- `--force` / `-f`: Skip confirmations
- `--verbose` / `-v`: Detailed output

**Module Parameters:**
- `AgeInDays`: Filter by age (default: 7)
- `MinSizeGB`: Minimum size filter
- `ExcludeSystemFiles`: Skip system files
- `AsHumanReadable`: Format sizes

## Color Scheme

| Color | Usage |
|-------|-------|
| Cyan | Headers, section titles |
| Yellow | Warnings, prompts, highlights |
| Green | Success, available items |
| Red | Errors, critical warnings |
| Gray | Secondary info, help text |
| White | Primary data |
| DarkGray | Timestamps, metadata |
| Magenta | Special categories |
| Blue | Actions, links |

## Status Indicators

| Indicator | Meaning |
|-----------|---------|
| ✅ | Complete, success |
| ❌ | Failed, error |
| ⚠️ | Warning |
| ℹ️ | Information |
| 🟢 | Healthy (< 80% disk) |
| 🟡 | Warning (80-90% disk) |
| 🔴 | Critical (> 90% disk) |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Lock acquisition failed |
| 4 | Admin privileges required |

## Common Issues

### Issue: "Module not found"
**Solution:** Verify script is run from project root with correct relative paths

### Issue: "Lock acquisition failed"
**Solution:** Wait for other instance to finish, or clear stale lock:
```powershell
Import-Module .\lib\core\Lock.psm1
Clear-WinOpsStaleLock
```

### Issue: "Configuration not found"
**Solution:** Initialize configuration:
```powershell
Import-Module .\lib\core\Config.psm1
Initialize-WinOpsConfig
```

### Issue: "Administrator privileges required"
**Solution:** Run from elevated PowerShell:
```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', 'cd C:\path\to\win-ops; .\bin\win-ops.ps1 install'
```

## Development Notes

### Adding a New Cleanup Module

1. Create `lib/modules/NewCleanup.psm1`
2. Implement functions:
   - `Clear-WinOpsNew` - Main cleanup function
   - `Get-WinOpsNewInfo` - Info/analysis function
3. Add to `lib/modules/Analyze.psm1` categories
4. Add to `bin/win-ops.ps1` cleanup modules list
5. Add to default configuration

### Testing a Module

```powershell
# Import module
Import-Module .\lib\modules\YourModule.psm1 -Force

# Test info function
Get-WinOpsYourInfo -Verbose

# Test cleanup (dry-run)
Clear-WinOpsYour -DryRun -Verbose

# Test actual cleanup (careful!)
Clear-WinOpsYour -Verbose
```

## Architecture Summary

```
win-ops/
├── bin/
│   └── win-ops.ps1           ← CLI entry point (811 lines)
├── lib/
│   ├── core/                 ← Core functionality (5 modules)
│   │   ├── Config.psm1
│   │   ├── Logger.psm1
│   │   ├── Lock.psm1
│   │   ├── Disk.psm1
│   │   └── Trash.psm1
│   ├── modules/              ← Cleanup modules (11 modules)
│   │   ├── Analyze.psm1
│   │   ├── CacheCleanup.psm1
│   │   ├── TmpCleanup.psm1
│   │   ├── LogCleanup.psm1
│   │   ├── BrowserCleanup.psm1
│   │   ├── DevCleanup.psm1
│   │   ├── DockerCleanup.psm1
│   │   ├── PackageManagerCleanup.psm1
│   │   ├── ZombieKiller.psm1
│   │   ├── OrphanKiller.psm1
│   │   └── OrphanAppCleanup.psm1
│   └── utils/                ← Utility modules (4 modules)
│       ├── Format.psm1
│       ├── Notify.psm1
│       ├── Parallel.psm1
│       └── Snapshot.psm1
├── scheduler/
│   └── Invoke-WinOpsScheduled.ps1  ← Scheduled task script
├── config/
│   └── default.json          ← Default configuration
├── install.ps1               ← Installer
└── uninstall.ps1            ← Uninstaller
```

## Performance Tips

1. **Use DryRun first** - Always test with `--dry-run`
2. **Check disk space** - Ensure sufficient space before cleanup
3. **Review trash** - Check trash before permanent deletion
4. **Schedule wisely** - Run during off-hours
5. **Monitor logs** - Check logs for errors

## Security Considerations

1. **Admin privileges** - Only for install/uninstall
2. **Protected paths** - System directories are protected
3. **Trash recovery** - 72-hour safety window
4. **File locking** - Prevents concurrent modifications
5. **Audit logs** - All operations logged

---

**Last Updated:** 2024-01-15
**Version:** 1.0.0
**Status:** ✅ Production Ready
