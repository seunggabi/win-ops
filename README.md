# win-ops

> Windows Operations Manager - Automated system maintenance and optimization toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/badge/version-0.3.0-brightgreen.svg)](https://github.com/seunggabi/win-ops/releases/tag/v0.3.0)

## What is win-ops?

**win-ops** is a PowerShell-based Windows system cleanup tool. It removes caches, temp files, orphaned registry entries, unused app data, and browsing history — all with a built-in trash system so you can undo anything within 72 hours.

**One command** cleans your entire system:

```powershell
win-ops run --force
```

### What it cleans

| Module | What it does |
|--------|-------------|
| **CacheCleanup** | Windows, app, icon, font, thumbnail caches |
| **TmpCleanup** | Temp files, prefetch, crash dumps, installer leftovers |
| **LogCleanup** | Application logs, IIS logs, Windows event logs |
| **MemoryCleanup** | DNS cache flush, idle process working set trim, .NET GC |
| **RegistryCleanup** | Orphaned uninstall entries, dead SharedDLLs, stale startup items, MUICache |
| **HistoryCleanup** | Run dialog, Explorer paths/search, jump lists, clipboard, shell history |
| **OrphanAppCleanup** | Leftover AppData/ProgramData from uninstalled programs |
| **BrowserCleanup** | Chrome, Edge, Firefox, Brave, Opera caches |
| **DevCleanup** | npm, yarn, pip, NuGet, Maven, Gradle caches |
| **DockerCleanup** | Unused images, stopped containers, dangling volumes |
| **PackageManagerCleanup** | Chocolatey, Scoop cache directories |
| **ZombieKiller** | Stuck processes (high CPU/memory, unresponsive) |
| **OrphanKiller** | Orphaned child processes |

## Quick Start

### 1. Install

```powershell
# Clone
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Install (copies to %LOCALAPPDATA%\win-ops)
.\install.ps1
```

### 2. Run

```powershell
# Preview what will be cleaned (no changes)
win-ops analyze

# Run cleanup
win-ops run

# Run without confirmation prompt
win-ops run --force
```

### 3. Schedule (optional, requires admin)

```powershell
# Register hourly automatic cleanup
.\install.ps1 -InstallScheduledTask -ScheduleInterval Hourly
```

Or if already installed:

```powershell
# Run as Administrator
Import-Module "$env:LOCALAPPDATA\win-ops\scheduler\TaskScheduler.psm1"
Install-WinOpsScheduledTask -Interval Hourly -Force
```

## Requirements

- **PowerShell** 5.1+ (Windows PowerShell) or 7.0+ (PowerShell Core)
- **Windows** 10 / 11 / Server 2016+
- **Admin privileges** only needed for: scheduled task, system temp, Windows logs, standby memory, HKLM registry

## Commands

```
win-ops <command> [options]
```

| Command | Description |
|---------|-------------|
| `help` | Show help |
| `version` | Show version info |
| `analyze` | Analyze system and show cleanup targets |
| `run` | Execute cleanup |
| `status` | Show system status and last cleanup results |
| `list-trash` | List recoverable items |
| `restore` | Restore deleted items from trash |
| `install` | Install as scheduled task (admin) |
| `uninstall` | Remove scheduled task (admin) |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-n` | Preview without making changes |
| `--force` | `-f` | Skip confirmation prompts |
| `--verbose` | `-v` | Detailed output |

### Examples

```powershell
# Safe preview
win-ops run --dry-run

# Full cleanup, no prompts
win-ops run --force

# Check what happened last time
win-ops status

# Recover a deleted file
win-ops list-trash
win-ops restore
```

## Configuration

Config file: `%LOCALAPPDATA%\win-ops\config\win-ops.json`

### Enable/disable modules

Each module can be toggled independently:

```json
{
  "modules": [
    {
      "name": "CacheCleanup",
      "enabled": true,
      "settings": {
        "location": "All",
        "ageInDays": 7,
        "useTrash": true
      }
    },
    {
      "name": "BrowserCleanup",
      "enabled": false,
      "settings": {
        "browser": "All",
        "dataType": "Cache"
      }
    },
    {
      "name": "MemoryCleanup",
      "enabled": true,
      "settings": {
        "minWorkingSetMB": 50,
        "minIdleMinutes": 10
      }
    },
    {
      "name": "RegistryCleanup",
      "enabled": true,
      "settings": {
        "backupBeforeDelete": true,
        "cleanUninstallEntries": true,
        "cleanSharedDLLs": true
      }
    },
    {
      "name": "HistoryCleanup",
      "enabled": true,
      "settings": {
        "clearRunDialog": true,
        "clearExplorerPaths": true,
        "clearClipboard": true,
        "clearShellHistory": true
      }
    }
  ]
}
```

### Default enabled modules

| Module | Default | Notes |
|--------|---------|-------|
| CacheCleanup | ON | 7-day-old caches |
| TmpCleanup | ON | 3-day-old temp files |
| LogCleanup | ON | 90-day-old logs, min 1MB |
| MemoryCleanup | ON | Idle process trim, DNS flush |
| RegistryCleanup | ON | Backs up before deleting |
| HistoryCleanup | ON | All history types |
| OrphanAppCleanup | OFF | Removes uninstalled app data |
| BrowserCleanup | OFF | Clears browser caches |
| DevCleanup | OFF | Clears dev tool caches |
| DockerCleanup | OFF | Prunes Docker resources |
| PackageManagerCleanup | OFF | Chocolatey/Scoop caches |
| ZombieKiller | ON | DryRun by default |
| OrphanKiller | OFF | Orphaned processes |

### Key settings

```json
{
  "general": {
    "dryRun": false,
    "useTrash": true,
    "parallel": true,
    "maxThreads": 4,
    "timeoutSeconds": 300
  },
  "retention": {
    "trashHours": 72,
    "logDays": 14,
    "snapshotDays": 30
  },
  "safety": {
    "protectedPaths": ["%SystemRoot%", "%ProgramFiles%", "%USERPROFILE%\\Documents"],
    "protectedExtensions": [".exe", ".dll", ".sys"],
    "confirmDeletion": true,
    "maxBatchSize": 1000
  },
  "schedule": {
    "enabled": true,
    "interval": "Hourly"
  }
}
```

## Safety

### Trash system

Every deleted file goes to trash first (not permanently deleted). You have 72 hours to restore.

```powershell
win-ops list-trash    # See what's in trash
win-ops restore       # Interactive restore
```

### Protected paths

These directories are **never** touched:
- `%SystemRoot%` (C:\Windows)
- `%ProgramFiles%`, `%ProgramFiles(x86)%`
- `%USERPROFILE%\Documents`, `Desktop`, `Pictures`, `Music`, `Videos`

### Protected extensions

Files with these extensions are skipped: `.exe`, `.dll`, `.sys`, `.ini`, `.cfg`

### Registry backup

Before deleting any registry entries, RegistryCleanup exports `.reg` backup files to `%LOCALAPPDATA%\win-ops\backups\registry\`.

### Dry-run mode

Always preview first:

```powershell
win-ops run --dry-run
```

## Project Structure

```
win-ops/
├── bin/
│   └── win-ops.ps1                # CLI entry point
├── lib/
│   ├── core/                      # Core modules
│   │   ├── Config.psm1            # JSON config with env var expansion
│   │   ├── Logger.psm1            # Structured logging with rotation
│   │   ├── Lock.psm1              # Mutex-based process locking
│   │   ├── Safety.psm1            # 5-tier safety system
│   │   ├── Disk.psm1              # Disk usage monitoring (CIM)
│   │   ├── Trash.psm1             # 72-hour trash recovery (SHA256)
│   │   └── I18n.psm1              # Korean/English localization
│   ├── modules/                   # Cleanup modules (13)
│   │   ├── CacheCleanup.psm1
│   │   ├── TmpCleanup.psm1
│   │   ├── LogCleanup.psm1
│   │   ├── MemoryCleanup.psm1     # Memory optimization
│   │   ├── RegistryCleanup.psm1   # Orphaned registry entries
│   │   ├── HistoryCleanup.psm1    # Privacy/history cleanup
│   │   ├── OrphanAppCleanup.psm1  # Uninstalled app data
│   │   ├── BrowserCleanup.psm1
│   │   ├── DevCleanup.psm1
│   │   ├── DockerCleanup.psm1
│   │   ├── PackageManagerCleanup.psm1
│   │   ├── ZombieKiller.psm1
│   │   ├── OrphanKiller.psm1
│   │   └── Analyze.psm1           # System analysis
│   └── utils/
│       ├── Format.psm1            # Size/duration formatting
│       ├── Parallel.psm1          # Multi-threaded execution
│       ├── Notify.psm1            # Windows notifications
│       └── Snapshot.psm1          # Before/after snapshots
├── config/
│   ├── win-ops.json               # Default configuration
│   └── protected-processes.json
├── resources/
│   ├── en-US.json                 # English strings
│   └── ko-KR.json                 # Korean strings
├── scheduler/
│   └── TaskScheduler.psm1        # Windows Task Scheduler integration
├── tests/                         # Pester 5.x test suite
├── install.ps1
├── uninstall.ps1
└── win-ops.psd1
```

## Localization

win-ops supports Korean and English. The language is auto-detected from your Windows locale. All UI messages, warnings, and status output are localized.

- `ko-KR` : Korean (default on Korean Windows)
- `en-US` : English (fallback)

## Scheduled Task

When installed as a scheduled task, win-ops runs `win-ops run --force` at the configured interval (default: hourly).

```powershell
# Check task status
Get-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Disable
Disable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Enable
Enable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Remove
Unregister-ScheduledTask -TaskName "Win-Ops System Cleanup"
```

## Development

```powershell
# Run all tests
Invoke-Pester

# Run specific module tests
Invoke-Pester -Path tests/Core/

# Run with coverage
Invoke-Pester -CodeCoverage
```

## Troubleshooting

**"Administrator privileges required"**
```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-Command', 'win-ops run --force'
```

**"Another instance is running"**
```powershell
win-ops status  # Check lock state, wait or remove lock file
```

**Korean not showing (labels only)**
```powershell
# Ensure resources directory exists in install path
Copy-Item -Recurse .\resources "$env:LOCALAPPDATA\win-ops\resources" -Force
```

**Check logs**
```powershell
Get-Content "$env:LOCALAPPDATA\win-ops\logs\win-ops.log" -Tail 50
```

## License

MIT License - see [LICENSE](LICENSE)

---

**Version**: 0.3.0 | **Author**: [Seunggabi](https://github.com/seunggabi) | **Repository**: [github.com/seunggabi/win-ops](https://github.com/seunggabi/win-ops)
