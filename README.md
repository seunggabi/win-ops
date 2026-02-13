# win-ops

> Windows Operations Manager - Automated system maintenance and optimization toolkit

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
# Register scheduled task using config settings (interval, startTime, etc.)
win-ops schedule

# Remove scheduled task
win-ops unschedule
```

Or via install script:

```powershell
.\install.ps1 -InstallScheduledTask -ScheduleInterval Hourly
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
| `schedule` | Register scheduled task from config settings (admin) |
| `unschedule` | Remove scheduled task (admin) |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-n` | Preview without making changes |
| `--force` | `-f` | Skip confirmation prompts |
| `--verbose` | `-v` | Detailed output |
| `--all` | `-a` | Enable ALL modules (includes DevCleanup, DockerCleanup, ZombieKiller, OrphanKiller) |

### Examples

```powershell
# Safe preview (default modules only)
win-ops run --dry-run

# Full cleanup with default modules, no prompts
win-ops run --force

# Enable ALL modules including advanced ones
win-ops run --all

# Full aggressive cleanup (all modules, no prompts)
win-ops run --all --force

# Check what happened last time
win-ops status

# Recover a deleted file
win-ops list-trash
win-ops restore
```

## Configuration

Config file: `%LOCALAPPDATA%\win-ops\config\win-ops.json`
Default config: [`config/win-ops.json`](config/win-ops.json)

### Configuration Reference

#### `general` - General settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dryRun` | bool | `false` | Global dry-run mode (no actual changes) |
| `verbose` | bool | `false` | Enable verbose logging output |
| `useTrash` | bool | `true` | Move files to trash instead of permanent delete |
| `parallel` | bool | `true` | Enable parallel module execution |
| `maxThreads` | int | `4` | Maximum parallel threads |
| `timeoutSeconds` | int | `300` | Per-module timeout in seconds |

#### `paths` - Directory paths

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trash` | string | `%LOCALAPPDATA%\win-ops\trash` | Trash storage directory |
| `logs` | string | `%LOCALAPPDATA%\win-ops\logs` | Log file directory |
| `config` | string | `%LOCALAPPDATA%\win-ops\config` | Config file directory |

#### `retention` - Data retention periods

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `trashHours` | int | `72` | Hours before trash items are permanently deleted |
| `logDays` | int | `14` | Days to keep log files |
| `snapshotDays` | int | `30` | Days to keep before/after snapshots |

#### `modules` - Cleanup module settings

Each module is an object with `name`, `enabled`, and `settings`:

| Module | Default Enabled | Key Settings |
|--------|:---:|-------------|
| `CacheCleanup` | ✅ | `location`: All, `ageInDays`: 7, `useTrash`: true |
| `TmpCleanup` | ✅ | `location`: All, `ageInDays`: 3, `useTrash`: true |
| `LogCleanup` | ✅ | `location`: All, `ageInDays`: 90, `minSizeMB`: 1, `useTrash`: true |
| `BrowserCleanup` | ✅ | `browser`: All, `dataType`: Cache, `useTrash`: true |
| `PackageManagerCleanup` | ✅ | `managers`: ["chocolatey", "scoop"], `useTrash`: true |
| `MemoryCleanup` | ✅ | `minWorkingSetMB`: 50, `minIdleMinutes`: 10 |
| `HistoryCleanup` | ✅ | `clearRunDialog`, `clearExplorerPaths`, `clearClipboard`, `clearShellHistory`, etc. |
| `RegistryCleanup` | ✅ | `backupBeforeDelete`: true, `cleanUninstallEntries`, `cleanSharedDLLs`, `cleanMUICache`, etc. |
| `OrphanAppCleanup` | ✅ | `dataType`: All, `minAgeInDays`: 30, `useTrash`: true |
| `ZombieKiller` | ✅ | `cpuThreshold`: 0.5, `memoryThresholdMB`: 100, `minAgeMinutes`: 30, `dryRun`: true |
| `DevCleanup` | ❌ | `targets`: ["npm", "yarn", "pip"], `useTrash`: true |
| `DockerCleanup` | ❌ | `pruneImages`: false, `pruneContainers`: true, `pruneVolumes`: false, `pruneNetworks`: true |
| `OrphanKiller` | ❌ | `minAgeMinutes`: 60 |

#### `safety` - Safety constraints

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `protectedPaths` | string[] | `["%SystemRoot%", "%ProgramFiles%", ...]` | Directories that are never modified |
| `protectedExtensions` | string[] | `[".exe", ".dll", ".sys", ".ini", ".cfg"]` | File extensions that are never deleted |
| `confirmDeletion` | bool | `true` | Require confirmation before cleanup |
| `maxBatchSize` | int | `1000` | Maximum items per batch operation |

#### `notifications` - Toast notification settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable Windows toast notifications |
| `types.success` | bool | `true` | Notify on successful cleanup |
| `types.warning` | bool | `true` | Notify on warnings |
| `types.error` | bool | `true` | Notify on errors |
| `minSpaceFreedMB` | int | `100` | Minimum freed space (MB) to trigger notification |

#### `logging` - Log settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `level` | string | `"INFO"` | Log level: DEBUG, INFO, WARN, ERROR |
| `maxLogSizeMB` | int | `5` | Maximum log file size before rotation |
| `maxLogFiles` | int | `7` | Number of rotated log files to keep |
| `colorOutput` | bool | `true` | Enable colored console output |

#### `snapshot` - Before/after snapshot settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `beforeCleanup` | bool | `true` | Capture system state before cleanup |
| `afterCleanup` | bool | `true` | Capture system state after cleanup |
| `exportPath` | string | `%LOCALAPPDATA%\win-ops\snapshots` | Snapshot storage directory |
| `retention.keepCount` | int | `30` | Maximum number of snapshots to keep |
| `retention.keepDays` | int | `90` | Days to keep snapshots |

#### `schedule` - Scheduled task settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable scheduled task |
| `interval` | string | `"Hourly"` | Execution interval: `Hourly`, `Daily`, `Weekly` |
| `startTime` | string | `"00:00"` | Start time for Daily/Weekly schedules |
| `runOnBattery` | bool | `false` | Run when on battery power |

### Module activation modes

**Default mode** (`win-ops run`):
Runs safe, commonly needed modules. Suitable for regular automated cleanup.

**All mode** (`win-ops run --all`):
Activates ALL modules including advanced/optional ones for deep cleaning.

| Module | Default | --all | Notes |
|--------|---------|-------|-------|
| CacheCleanup | ✅ | ✅ | 7-day-old caches |
| TmpCleanup | ✅ | ✅ | 3-day-old temp files |
| LogCleanup | ✅ | ✅ | 90-day-old logs, min 1MB |
| MemoryCleanup | ✅ | ✅ | Idle process trim, DNS flush |
| RegistryCleanup | ✅ | ✅ | Backs up before deleting |
| HistoryCleanup | ✅ | ✅ | All history types |
| OrphanAppCleanup | ✅ | ✅ | 30+ day-old uninstalled app data |
| BrowserCleanup | ✅ | ✅ | Browser caches (Chrome, Edge, Firefox, etc.) |
| PackageManagerCleanup | ✅ | ✅ | Chocolatey/Scoop caches |
| DevCleanup | ❌ | ✅ | Dev tool caches (npm, yarn, pip) |
| DockerCleanup | ❌ | ✅ | Docker resources (containers, networks) |
| ZombieKiller | ❌ | ✅ | Zombie processes (stuck/unresponsive) |
| OrphanKiller | ❌ | ✅ | Orphaned processes (advanced) |

> 💡 **Tip**: Start with default mode. Use `--all` when you need deep cleaning or are troubleshooting performance issues.

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

When installed as a scheduled task, win-ops automatically runs `win-ops run --force` at the configured interval.

### How it works

1. **Installation** registers a Windows Task Scheduler task named `"Win-Ops System Cleanup"`
2. **Default interval is Hourly** — every hour, the task executes cleanup with all default modules
3. The interval can be changed in `config/win-ops.json` under `schedule.interval` (`Hourly`, `Daily`, `Weekly`)
4. On battery power, the task is **skipped by default** (`runOnBattery: false`)
5. Each run acquires a mutex lock to prevent concurrent execution — if a previous run is still active, the new run exits gracefully

### Install / Manage

```powershell
# Register scheduled task using config settings (requires admin)
win-ops schedule

# Remove scheduled task (requires admin)
win-ops unschedule

# Or install with custom interval via install.ps1
.\install.ps1 -InstallScheduledTask -ScheduleInterval Daily

# Check task status
Get-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Disable temporarily
Disable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Re-enable
Enable-ScheduledTask -TaskName "Win-Ops System Cleanup"

# Remove completely
win-ops uninstall
# or manually:
Unregister-ScheduledTask -TaskName "Win-Ops System Cleanup"
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

Then re-run `win-ops schedule` to apply the new schedule.

## Development

```powershell
# Run all tests
Invoke-Pester

# Run specific module tests
Invoke-Pester -Path tests/Core/

# Run with coverage
Invoke-Pester -CodeCoverage
```

## Release Process

### Creating a new release

Releases are automatically built and published via GitHub Actions when you push a version tag:

```bash
# 1. Update version in your code (if needed)

# 2. Commit changes
git add .
git commit -m "chore: prepare release v0.5.0"

# 3. Create and push tag
git tag v0.5.0
git push origin main --tags

# 4. GitHub Actions will automatically:
#    - Build win-ops.exe on Windows
#    - Create GitHub Release
#    - Upload exe and zip files
#    - Generate release notes from commits
```

### What gets released

Each release includes:
- `win-ops.exe` - Standalone executable (no installation needed)
- `win-ops-{version}-windows-x64.zip` - Full package with all files
- Automated release notes with changelog

### Manual build (Windows only)

If you need to build locally on Windows:

```powershell
# Install ps2exe
Install-Module ps2exe -Scope CurrentUser

# Build exe
ps2exe `
  -inputFile "bin\win-ops.ps1" `
  -outputFile "win-ops.exe" `
  -title "win-ops" `
  -version "0.5.0" `
  -x64
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

## Star History

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=seunggabi/win-ops&type=Date)](https://star-history.com/#seunggabi/win-ops&Date)

</div>

## Contributors

<div align="center">

[![Contributors](https://contrib.rocks/image?repo=seunggabi/win-ops)](https://github.com/seunggabi/win-ops/graphs/contributors)

</div>

## License

MIT License - see [LICENSE](LICENSE)

---

<div align="center">

**Author**: [Seunggabi](https://github.com/seunggabi) | **Repository**: [github.com/seunggabi/win-ops](https://github.com/seunggabi/win-ops)

Made with ❤️ for Windows users

</div>
