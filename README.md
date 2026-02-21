# win-ops

> Windows Operations Manager — Automated system maintenance and optimization toolkit

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/github/v/release/seunggabi/win-ops?color=brightgreen)](https://github.com/seunggabi/win-ops/releases/latest)
[![GitHub Stars](https://img.shields.io/github/stars/seunggabi/win-ops?style=social)](https://github.com/seunggabi/win-ops/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/seunggabi/win-ops?style=social)](https://github.com/seunggabi/win-ops/network/members)

[![GitHub Issues](https://img.shields.io/github/issues/seunggabi/win-ops)](https://github.com/seunggabi/win-ops/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/seunggabi/win-ops)](https://github.com/seunggabi/win-ops/pulls)
[![GitHub Contributors](https://img.shields.io/github/contributors/seunggabi/win-ops)](https://github.com/seunggabi/win-ops/graphs/contributors)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/seunggabi/win-ops)](https://github.com/seunggabi/win-ops/commits/main)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/seunggabi/win-ops/test.yml?branch=main&label=tests)](https://github.com/seunggabi/win-ops/actions)

</div>

## Overview

**win-ops** is a PowerShell-based Windows system maintenance tool. It cleans caches, temp files, orphaned registry entries, unused application data, and browsing history — all backed by a built-in trash system so nothing is permanently lost for 72 hours.

**One command** cleans your entire system:

```powershell
win-ops run --force
```

## Features

- **14 cleanup modules** covering caches, temp files, logs, memory, registry, history, browsers, package managers, Docker, and more
- **Trash system** with 72-hour retention — restore any deleted file
- **Protected paths and extensions** — critical system files are never touched
- **Dry-run mode** — preview all changes before executing
- **Scheduled task support** — automate cleanup on an hourly, daily, or weekly basis
- **Localization** — English and Korean UI (auto-detected from system locale)
- **ASIS/TOBE comparison** — before/after metrics for every cleanup run

## Requirements

- **PowerShell** 5.1+ (Windows PowerShell) or 7.0+ (PowerShell Core)
- **Windows** 10 / 11 / Server 2016+
- **Admin privileges** only needed for: scheduled task registration, system temp cleanup, Windows event logs, standby memory trim, HKLM registry entries

## Installation

### From source (recommended)

```powershell
winget install --id Git.Git -e --source winget
git clone https://github.com/seunggabi/win-ops.git
cd win-ops
PowerShell -ExecutionPolicy Bypass -File .\install.ps1
```

### Manual installation

```powershell
# Copy the project to your local app data
Copy-Item -Recurse .\win-ops "$env:LOCALAPPDATA\win-ops"

# Add to PATH (current session)
$env:PATH += ";$env:LOCALAPPDATA\win-ops\bin"
```

### Install script options

```powershell
# Install with scheduled task
.\install.ps1 -InstallScheduledTask -ScheduleInterval Hourly

# Install to a custom path
.\install.ps1 -InstallPath "D:\tools\win-ops"
```

## Quick Start

```powershell
# 1. Analyze — see what would be cleaned (no changes made)
win-ops analyze

# 2. Preview — dry-run shows exact operations
win-ops run --dry-run

# 3. Clean — execute cleanup with confirmation prompt
win-ops run

# 4. Clean without prompts
win-ops run --force

# 5. Deep clean — enable ALL modules including advanced ones
win-ops run --all --force
```

## Command Reference

```
win-ops <command> [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `help` | Display help message |
| `version` | Display version and environment info |
| `analyze` | Analyze system and show cleanup targets with estimated space savings |
| `run` | Execute cleanup operations across enabled modules |
| `status` | Show system status, disk usage, trash info, and last cleanup results |
| `list-trash` | List all recoverable items in trash with expiry times |
| `restore` | Interactive restore — select and recover items from trash |
| `install` | Install win-ops as a Windows scheduled task (requires admin) |
| `uninstall` | Remove win-ops scheduled task and optionally data files (requires admin) |
| `schedule` | Register scheduled task using `config/win-ops.json` settings (requires admin) |
| `unschedule` | Remove the scheduled task (requires admin) |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-n` | Preview changes without executing |
| `--force` | `-f` | Skip confirmation prompts |
| `--verbose` | `-v` | Enable detailed output |
| `--all` | `-a` | Enable ALL modules (includes DevCleanup, DockerCleanup, ZombieKiller, OrphanKiller) |
| `--purge-trash` | `-p` | Permanently delete all trash items after cleanup |

### Examples

```powershell
# Safe preview with default modules
win-ops run --dry-run

# Full cleanup, no prompts
win-ops run --force

# All modules including advanced ones
win-ops run --all

# Full aggressive cleanup — all modules, no prompts
win-ops run --all --force

# Check last cleanup results and system health
win-ops status

# Recover a deleted file
win-ops list-trash
win-ops restore
```

## Cleanup Modules

win-ops includes 14 modules. By default, 9 safe modules run automatically. The remaining 4 advanced modules activate with `--all`.

| Module | Description | Default | --all |
|--------|-------------|:-------:|:-----:|
| **CacheCleanup** | Windows, app, icon, font, thumbnail caches | Yes | Yes |
| **TmpCleanup** | Temp files, prefetch, crash dumps, installer leftovers | Yes | Yes |
| **LogCleanup** | Application logs, IIS logs, Windows event logs | Yes | Yes |
| **MemoryCleanup** | DNS cache flush, idle process working set trim, .NET GC | Yes | Yes |
| **RegistryCleanup** | Orphaned uninstall entries, dead SharedDLLs, stale startup items, MUICache | Yes | Yes |
| **HistoryCleanup** | Run dialog, Explorer paths/search, jump lists, clipboard, shell history | Yes | Yes |
| **OrphanAppCleanup** | Leftover AppData/ProgramData from uninstalled programs | Yes | Yes |
| **BrowserCleanup** | Chrome, Edge, Firefox, Brave, Opera caches | Yes | Yes |
| **PackageManagerCleanup** | Chocolatey, Scoop, Winget, Windows Update cache directories | Yes | Yes |
| **DevCleanup** | npm, yarn, pip, NuGet, Maven, Gradle caches | No | Yes |
| **DockerCleanup** | Unused images, stopped containers, dangling volumes, networks | No | Yes |
| **ZombieKiller** | Stuck processes (high CPU/memory, unresponsive) | No | Yes |
| **OrphanKiller** | Orphaned child processes | No | Yes |
| **Analyze** | System analysis and cleanup target discovery (used internally) | — | — |

## Configuration

**Config file location:** `%LOCALAPPDATA%\win-ops\config\win-ops.json`
**Default config:** [`config/win-ops.json`](config/win-ops.json)

### `general` — General settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dryRun` | bool | `false` | Global dry-run mode |
| `verbose` | bool | `false` | Enable verbose logging |
| `useTrash` | bool | `true` | Move files to trash instead of permanent delete |
| `parallel` | bool | `true` | Enable parallel module execution |
| `maxThreads` | int | `4` | Maximum parallel threads |
| `timeoutSeconds` | int | `300` | Per-module timeout in seconds |

### `paths` — Directory paths

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trash` | string | `%LOCALAPPDATA%\win-ops\trash` | Trash storage directory |
| `logs` | string | `%LOCALAPPDATA%\win-ops\logs` | Log file directory |
| `config` | string | `%LOCALAPPDATA%\win-ops\config` | Config file directory |

### `retention` — Data retention periods

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trashHours` | int | `72` | Hours before trash auto-purge |
| `logDays` | int | `14` | Days to keep log files |
| `snapshotDays` | int | `30` | Days to keep before/after snapshots |

### `modules` — Cleanup module settings

Each module entry has `name`, `enabled`, and `settings`:

| Module | Default | Key Settings |
|--------|:---:|-------------|
| `CacheCleanup` | On | `location`: All, `ageInDays`: 7, `useTrash`: true |
| `TmpCleanup` | On | `location`: All, `ageInDays`: 3, `useTrash`: true |
| `LogCleanup` | On | `location`: All, `ageInDays`: 90, `minSizeMB`: 1, `useTrash`: true |
| `BrowserCleanup` | On | `browser`: All, `dataType`: Cache, `useTrash`: true |
| `PackageManagerCleanup` | On | `managers`: ["chocolatey", "scoop"], `useTrash`: true |
| `MemoryCleanup` | On | `minWorkingSetMB`: 50, `minIdleMinutes`: 10 |
| `HistoryCleanup` | On | `clearRunDialog`, `clearExplorerPaths`, `clearClipboard`, `clearShellHistory` |
| `RegistryCleanup` | On | `backupBeforeDelete`: true, `cleanUninstallEntries`, `cleanSharedDLLs`, `cleanMUICache` |
| `OrphanAppCleanup` | On | `dataType`: All, `minAgeInDays`: 30, `useTrash`: true |
| `ZombieKiller` | On | `cpuThreshold`: 0.5, `memoryThresholdMB`: 100, `minAgeMinutes`: 30, `dryRun`: true |
| `DevCleanup` | Off | `targets`: ["npm", "yarn", "pip"], `useTrash`: true |
| `DockerCleanup` | Off | `pruneImages`: false, `pruneContainers`: true, `pruneVolumes`: false |
| `OrphanKiller` | Off | `minAgeMinutes`: 60 |

### `safety` — Safety constraints

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `protectedPaths` | string[] | `["%SystemRoot%", "%ProgramFiles%", ...]` | Directories never modified |
| `protectedExtensions` | string[] | `[".exe", ".dll", ".sys", ".ini", ".cfg"]` | File types never deleted |
| `confirmDeletion` | bool | `true` | Require confirmation before cleanup |
| `maxBatchSize` | int | `1000` | Maximum items per batch operation |

### `notifications` — Toast notification settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Windows toast notifications |
| `types.success` | bool | `true` | Notify on successful cleanup |
| `types.warning` | bool | `true` | Notify on warnings |
| `types.error` | bool | `true` | Notify on errors |
| `minSpaceFreedMB` | int | `100` | Minimum freed space to trigger notification |

### `logging` — Log settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `level` | string | `"INFO"` | Log level: DEBUG, INFO, WARN, ERROR |
| `maxLogSizeMB` | int | `5` | Max log file size before rotation |
| `maxLogFiles` | int | `7` | Number of rotated log files to keep |
| `colorOutput` | bool | `true` | Enable colored console output |

### `snapshot` — Before/after snapshot settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `beforeCleanup` | bool | `true` | Capture system state before cleanup |
| `afterCleanup` | bool | `true` | Capture system state after cleanup |
| `exportPath` | string | `%LOCALAPPDATA%\win-ops\snapshots` | Snapshot storage directory |
| `retention.keepCount` | int | `30` | Maximum snapshots to keep |
| `retention.keepDays` | int | `90` | Days to keep snapshots |

### `schedule` — Scheduled task settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable scheduled task |
| `interval` | string | `"Hourly"` | Interval: `Hourly`, `Daily`, `Weekly` |
| `startTime` | string | `"00:00"` | Start time for Daily/Weekly schedules |
| `runOnBattery` | bool | `false` | Run when on battery power |

## Scheduled Task

When installed as a scheduled task, win-ops runs `win-ops run --force` automatically at the configured interval.

### How it works

1. A Windows Task Scheduler task named `"Win-Ops System Cleanup"` is registered
2. Default interval is **Hourly** — configurable via `config/win-ops.json`
3. On battery power, the task is **skipped by default** (`runOnBattery: false`)
4. A mutex lock prevents concurrent execution — overlapping runs exit gracefully

### Register / Remove

```powershell
# Register scheduled task (requires admin)
win-ops schedule

# Remove scheduled task (requires admin)
win-ops unschedule

# Or install with custom interval
.\install.ps1 -InstallScheduledTask -ScheduleInterval Daily
```

### Change interval

Edit `%LOCALAPPDATA%\win-ops\config\win-ops.json`:

```json
{
  "schedule": {
    "enabled": true,
    "interval": "Daily",
    "startTime": "03:00",
    "runOnBattery": false
  }
}
```

Then re-run `win-ops schedule` to apply.

### Manage the task

```powershell
# Check task status
Get-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Disable temporarily
Disable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Re-enable
Enable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Remove completely
Unregister-ScheduledTask -TaskName "Win-Ops System Cleanup"
```

## Safety

### Trash system

Every deleted file goes to trash first. You have **72 hours** (configurable) to restore before auto-purge.

```powershell
win-ops list-trash    # See what's in trash
win-ops restore       # Interactive restore
```

### Protected paths

These directories are **never** modified:
- `%SystemRoot%` (C:\Windows)
- `%ProgramFiles%`, `%ProgramFiles(x86)%`
- `%USERPROFILE%\Documents`, `Desktop`, `Pictures`, `Music`, `Videos`

### Protected extensions

Files with these extensions are always skipped: `.exe`, `.dll`, `.sys`, `.ini`, `.cfg`

### Registry backup

Before removing any registry entries, `RegistryCleanup` exports `.reg` backup files to `%LOCALAPPDATA%\win-ops\backups\registry\`.

### Dry-run mode

Always preview first:

```powershell
win-ops run --dry-run
```

## Architecture

```
win-ops/
├── bin/
│   └── win-ops.ps1                # CLI entry point
├── lib/
│   ├── core/                      # Core infrastructure
│   │   ├── Config.psm1            # JSON config with env var expansion
│   │   ├── Logger.psm1            # Structured logging with rotation
│   │   ├── Lock.psm1              # Mutex-based process locking
│   │   ├── Safety.psm1            # 5-tier safety system
│   │   ├── Disk.psm1              # Disk usage monitoring (CIM)
│   │   ├── Trash.psm1             # 72-hour trash recovery (SHA256)
│   │   └── I18n.psm1              # Korean/English localization
│   ├── modules/                   # Cleanup modules (14)
│   │   ├── Analyze.psm1           # System analysis engine
│   │   ├── CacheCleanup.psm1
│   │   ├── TmpCleanup.psm1
│   │   ├── LogCleanup.psm1
│   │   ├── MemoryCleanup.psm1
│   │   ├── RegistryCleanup.psm1
│   │   ├── HistoryCleanup.psm1
│   │   ├── OrphanAppCleanup.psm1
│   │   ├── BrowserCleanup.psm1
│   │   ├── DevCleanup.psm1
│   │   ├── DockerCleanup.psm1
│   │   ├── PackageManagerCleanup.psm1
│   │   ├── ZombieKiller.psm1
│   │   └── OrphanKiller.psm1
│   └── utils/
│       ├── Format.psm1            # Size/duration formatting
│       ├── Parallel.psm1          # Multi-threaded execution
│       ├── Notify.psm1            # Windows toast notifications
│       └── Snapshot.psm1          # Before/after snapshots
├── config/
│   ├── win-ops.json               # Default configuration
│   └── protected-processes.json   # Process protection list
├── resources/
│   ├── en-US.json                 # English strings
│   └── ko-KR.json                 # Korean strings
├── scheduler/
│   └── TaskScheduler.psm1        # Windows Task Scheduler integration
├── tests/                         # Pester 5.x test suite
├── install.ps1                    # Installation script
├── uninstall.ps1                  # Uninstallation script
└── win-ops.psd1                   # Module manifest
```

## Troubleshooting

**"Administrator privileges required"**
```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-Command', 'win-ops run --force'
```

**"Another instance is running"**
```powershell
win-ops status  # Check lock state — wait or remove lock file manually
```

**Korean labels not showing**
```powershell
# Copy resources to the install path
Copy-Item -Recurse .\resources "$env:LOCALAPPDATA\win-ops\resources" -Force
```

**View logs**
```powershell
Get-Content "$env:LOCALAPPDATA\win-ops\logs\win-ops.log" -Tail 50
```

**Module not found errors after update**
```powershell
# Re-run install to sync all files
.\install.ps1
```

## Development

```powershell
# Run all tests
Invoke-Pester

# Run specific module tests
Invoke-Pester -Path tests/Core/

# Run with code coverage
Invoke-Pester -CodeCoverage
```

## Release

Releases are built and published automatically via GitHub Actions when a version tag is pushed:

```bash
git tag v0.7.0
git push origin main --tags
```

Each release includes:
- `win-ops.exe` — Standalone executable (no installation needed)
- `win-ops-{version}-windows-x64.zip` — Full package with all files
- Automated release notes from commit history

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

## License

MIT License — see [LICENSE](LICENSE)

---

<div align="center">

**Author**: [Seunggabi](https://github.com/seunggabi) | **Repository**: [github.com/seunggabi/win-ops](https://github.com/seunggabi/win-ops)

[![Star History Chart](https://api.star-history.com/svg?repos=seunggabi/win-ops&type=Date)](https://star-history.com/#seunggabi/win-ops&Date)

[![Contributors](https://contrib.rocks/image?repo=seunggabi/win-ops)](https://github.com/seunggabi/win-ops/graphs/contributors)

</div>
