# win-ops

Windows Operations Manager - Automated system maintenance and optimization toolkit

## Overview

win-ops is a comprehensive PowerShell-based system maintenance tool designed for Windows environments. It automates cleanup, optimization, and monitoring tasks while providing safe rollback capabilities through its trash management system.

## Features

- **System Analysis**: Analyze disk usage and identify cleanup opportunities
- **Safe Cleanup**: Automated cleanup of temporary files, caches, and logs with rollback support
- **Browser Cache Management**: Clean caches from Chrome, Edge, Firefox, and other browsers
- **Developer Tools Cleanup**: Clean build artifacts, package caches (npm, pip, Maven, NuGet, Docker)
- **Process Management**: Detect and terminate zombie processes and orphaned applications
- **Task Scheduling**: Automated scheduling via Windows Task Scheduler
- **Rollback Support**: Restore deleted items from trash
- **Parallel Execution**: Fast parallel cleanup operations
- **Safety Features**: File locking, critical path protection, and dry-run mode

## Requirements

- PowerShell 7.0 or higher
- Windows 10/11 or Windows Server 2016+
- Administrator privileges (for some operations)

## Installation

### Option 1: Automated Installation

```powershell
# Clone the repository
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Run installer (basic installation)
.\install.ps1

# Or install with PATH and scheduled task
.\install.ps1 -AddToPath -InstallScheduledTask
```

### Option 2: Manual Installation

```powershell
# Clone the repository
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Import the module
Import-Module .\win-ops.psd1

# Run directly
.\bin\win-ops.ps1 --help
```

### Option 3: Install as Scheduled Task

```powershell
# Install with automatic scheduling (requires admin)
.\install.ps1 -InstallScheduledTask -ScheduleInterval Hourly
```

## Usage

### Basic Commands

```powershell
# Display help
.\bin\win-ops.ps1 help

# Show version
.\bin\win-ops.ps1 version

# Analyze system (no changes made)
.\bin\win-ops.ps1 analyze

# Run cleanup with confirmation
.\bin\win-ops.ps1 run

# Run cleanup without confirmation
.\bin\win-ops.ps1 run --force

# Dry run (preview only)
.\bin\win-ops.ps1 run --dry-run

# Show system status
.\bin\win-ops.ps1 status

# List items in trash
.\bin\win-ops.ps1 list-trash

# Restore items from trash
.\bin\win-ops.ps1 restore
```

### Options

- `--dry-run, -n`: Preview operations without making changes
- `--force, -f`: Skip confirmation prompts
- `--verbose, -v`: Enable detailed output

## Project Structure

```
win-ops/
├── bin/
│   └── win-ops.ps1          # Main entry point
├── lib/
│   ├── core/                # Core functionality modules
│   ├── modules/             # Cleanup and utility modules
│   └── utils/               # Helper utilities
├── config/                  # Configuration files
├── scheduler/               # Task scheduler integration
├── tests/                   # Test suites
│   ├── Core/
│   ├── Modules/
│   ├── Utils/
│   └── Integration/
├── win-ops.psd1            # PowerShell module manifest
├── LICENSE                  # MIT License
└── README.md               # This file
```

## Modules

Win-Ops includes the following cleanup modules:

### Core Modules
- **Config**: Configuration management and validation
- **Logger**: Structured logging with rotation and ANSI colors
- **Lock**: Process locking to prevent concurrent operations
- **Safety**: Critical path protection and safety checks
- **Disk**: Disk space analysis and monitoring
- **Trash**: Safe deletion with rollback capability

### Cleanup Modules
- **CacheCleanup**: Windows and application caches
- **TmpCleanup**: Temporary files and folders
- **LogCleanup**: Application and system logs
- **BrowserCleanup**: Browser caches (Chrome, Edge, Firefox, Brave, Opera)
- **DevCleanup**: Development tool caches (npm, yarn, pip, NuGet, Maven, Gradle)
- **DockerCleanup**: Docker images, containers, and volumes
- **PackageManagerCleanup**: Package manager caches (Chocolatey, Scoop)

### Process Management
- **ZombieKiller**: Detect and terminate zombie processes
- **OrphanKiller**: Clean up orphaned child processes
- **OrphanAppCleanup**: Remove leftover data from uninstalled applications

### Utility Modules
- **Format**: Human-readable formatting utilities
- **Parallel**: Parallel execution engine (PowerShell 7+)
- **Notify**: Windows Toast notifications
- **Snapshot**: System state capture and comparison
- **Analyze**: Disk usage analysis and reporting

## Configuration

Configuration files are located in the `config/` directory:

- **win-ops.json**: Main configuration file
- **default.json**: Default settings (fallback)
- **protected-processes.json**: Processes that should never be terminated

### Example Configuration

```json
{
  "general": {
    "dryRun": false,
    "verbose": false,
    "useTrash": true,
    "parallel": true,
    "maxThreads": 4
  },
  "modules": [
    {
      "name": "CacheCleanup",
      "enabled": true,
      "settings": {
        "location": "All",
        "ageInDays": 7,
        "useTrash": true
      }
    }
  ],
  "safety": {
    "protectedPaths": [
      "%SystemRoot%",
      "%ProgramFiles%",
      "%USERPROFILE%\\Documents"
    ],
    "confirmDeletion": true,
    "maxBatchSize": 1000
  }
}
```

Customize cleanup rules, safety settings, and exclusion patterns to match your environment.

## Development

### Running Tests

```powershell
# Run all tests
Invoke-Pester

# Run specific test suite
Invoke-Pester -Path tests/Core/

# Run with coverage
Invoke-Pester -CodeCoverage
```

### Building

No build step required - win-ops is pure PowerShell.

## Safety Features

Win-Ops is designed with safety as a top priority:

### Trash System
- All deletions are moved to trash first (default retention: 72 hours)
- Easy recovery with `win-ops restore` command
- Automatic trash cleanup after retention period
- Per-module trash organization

### File Locking
- Prevents concurrent operations on the same files
- Mutex-based locking mechanism
- Automatic lock cleanup on process exit

### Critical Path Protection
- System-critical directories are never touched
- Protected paths defined in configuration
- Protected file extensions (exe, dll, sys, etc.)
- Protected processes list (System, lsass, csrss, etc.)

### Process Safety
- Never terminates critical Windows processes
- Age-based filtering for process cleanup
- CPU/memory threshold checks before termination
- Dry-run mode for testing

### Additional Safety Measures
- **Dry Run Mode**: Preview all changes before execution
- **Confirmation Prompts**: Optional confirmation for destructive operations
- **Comprehensive Logging**: All operations logged with timestamps
- **Snapshot Comparison**: Before/after system state comparison
- **Batch Size Limits**: Maximum items per operation to prevent accidents
- **Age Filters**: Only clean files/processes older than specified age

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Author

Seunggabi

## Links

- Repository: https://github.com/seunggabi/win-ops
- Issues: https://github.com/seunggabi/win-ops/issues
