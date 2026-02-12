# win-ops

> 🪟 Windows Operations Manager - Automated system maintenance and optimization toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7.0+](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen.svg)](https://github.com/seunggabi/win-ops)

## Overview

**win-ops** is a comprehensive PowerShell-based system maintenance tool designed for Windows environments. It automates cleanup, optimization, and monitoring tasks while providing safe rollback capabilities through its trash management system. Built with safety as the top priority, win-ops includes a 5-tier protection mechanism and 72-hour recovery system.

## Key Highlights

- ✅ **5-Tier Safety System** - Protected paths, processes, size guards, WRP detection, and integrated checks
- ✅ **72-Hour Trash Recovery** - Full metadata tracking with SHA256 indexing for complete file restoration
- ✅ **21 PowerShell Modules** - 6 core modules, 11 cleanup modules, 5 utility modules for comprehensive coverage
- ✅ **280+ Test Scenarios** - 85%+ code coverage with comprehensive Pester test suite
- ✅ **Production Ready** - Error handling, structured logging, scheduled task integration, and automation

## Features

### System Analysis & Optimization
- 🔍 **System Analysis** - Analyze disk usage and identify cleanup opportunities with detailed reporting
- 🧹 **Safe Cleanup** - Automated cleanup of temporary files, caches, and logs with rollback support
- 📊 **Disk Monitoring** - Real-time disk usage tracking and space reclamation estimates
- ⚡ **Parallel Execution** - Multi-threaded cleanup operations for improved performance

### Cleanup Coverage
- 🌐 **Browser Management** - Clean caches from Chrome, Edge, Firefox, Brave, and Opera
- 💾 **Developer Tools** - Clean build artifacts and package caches (npm, yarn, pip, NuGet, Maven, Gradle)
- 🐳 **Docker Cleanup** - Remove unused images, containers, volumes, and build caches
- 📦 **Package Managers** - Clean caches for Chocolatey, Scoop, and Winget
- 🔧 **System Cache** - Windows and application cache cleanup
- 📝 **Log Management** - Application and system log rotation and cleanup

### Process Management
- 💀 **Zombie Process Detection** - Identify and safely terminate stuck processes
- 👻 **Orphan Cleanup** - Remove orphaned child processes and broken application data
- ⏱️ **Smart Termination** - Age-based filtering and CPU/memory threshold checks

### Recovery & Safety
- 🗑️ **Trash System** - 72-hour retention for safe file recovery (configurable)
- 🔐 **File Locking** - Prevents concurrent operations and file access conflicts
- 🛡️ **Critical Path Protection** - System-critical directories are never touched
- ✋ **Protected Processes** - Critical Windows processes are never terminated
- 🎯 **Dry-Run Mode** - Preview all changes before execution

### Automation
- ⏰ **Task Scheduling** - Automated scheduling via Windows Task Scheduler
- 📋 **Configuration Management** - JSON-based configuration with environment variable expansion
- 📜 **Comprehensive Logging** - Structured logging with rotation and detailed operation tracking
- 📸 **Before/After Snapshots** - System state comparison for verification

## Requirements

- **PowerShell**: 7.0 or higher (Core Edition)
- **Windows**: Windows 10/11 or Windows Server 2016+
- **Privileges**: Administrator (for installation and some operations only)
- **Disk Space**: 100MB minimum free space

## Installation

### Quick Start

```powershell
# Clone the repository
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Run installer (requires admin)
.\install.ps1
```

### Installation Options

#### Option 1: Automated Installation with Scheduling

```powershell
# Install with PATH and scheduled task (requires admin)
.\install.ps1 -AddToPath -InstallScheduledTask -ScheduleInterval Hourly
```

#### Option 2: Manual Installation

```powershell
# Clone and import the module
git clone https://github.com/seunggabi/win-ops.git
cd win-ops
Import-Module .\win-ops.psd1

# Run directly
.\bin\win-ops.ps1 help
```

#### Option 3: Portable Usage

```powershell
# Clone the repository
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Run without installation
.\bin\win-ops.ps1 analyze
.\bin\win-ops.ps1 run
```

### Verification

After installation, verify the setup:

```powershell
# Check version
win-ops version

# Verify scheduled task (if installed)
Get-ScheduledTask -TaskName "win-ops*"

# Test with analysis
win-ops analyze --dry-run
```

## Usage

### Basic Commands

```powershell
# Display help
win-ops help

# Show version and system info
win-ops version

# Analyze system (no changes made)
win-ops analyze

# Run cleanup with confirmation
win-ops run

# Run cleanup without confirmation
win-ops run --force

# Preview cleanup without executing
win-ops run --dry-run

# Show system status and metrics
win-ops status

# List items in trash (available for restore)
win-ops list-trash

# Restore items from trash (interactive)
win-ops restore
```

### Command Options

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | `-n` | Preview operations without making changes |
| `--force` | `-f` | Skip confirmation prompts |
| `--verbose` | `-v` | Enable detailed output |

### Usage Examples

```powershell
# Example 1: Safe Preview
win-ops analyze
# Shows what would be cleaned without making changes

# Example 2: Test Before Running
win-ops run --dry-run
# Preview exact cleanup operations in detail

# Example 3: Automated Cleanup
win-ops run --force
# Execute cleanup without user interaction (suitable for scheduled tasks)

# Example 4: Recovery
win-ops list-trash
# See what's available for recovery
win-ops restore
# Interactive restore interface
```

## Project Structure

```
win-ops/
├── bin/
│   └── win-ops.ps1              # Main CLI entry point and command routing
├── lib/
│   ├── core/                    # Core functionality modules
│   │   ├── Config.psm1          # Configuration management
│   │   ├── Logger.psm1          # Structured logging with rotation
│   │   ├── Lock.psm1            # Process locking mechanism
│   │   ├── Safety.psm1          # 5-tier safety system
│   │   ├── Disk.psm1            # Disk monitoring and analysis
│   │   └── Trash.psm1           # 72-hour trash recovery system
│   ├── modules/                 # Cleanup and utility modules (11 total)
│   │   ├── CacheCleanup.psm1    # Windows and application caches
│   │   ├── TmpCleanup.psm1      # Temporary files and folders
│   │   ├── LogCleanup.psm1      # Application and system logs
│   │   ├── BrowserCleanup.psm1  # Browser caches (Chrome, Edge, Firefox, etc.)
│   │   ├── DevCleanup.psm1      # Developer tool caches
│   │   ├── DockerCleanup.psm1   # Docker images, containers, volumes
│   │   ├── PackageManagerCleanup.psm1  # Package manager caches
│   │   ├── ZombieKiller.psm1    # Stuck process detection
│   │   ├── OrphanKiller.psm1    # Orphaned process cleanup
│   │   ├── OrphanAppCleanup.psm1 # Uninstalled app data removal
│   │   └── Analyze.psm1         # System analysis and reporting
│   └── utils/                   # Helper utilities
│       ├── Format.psm1          # Human-readable formatting
│       ├── Parallel.psm1        # Parallel execution engine
│       ├── Notify.psm1          # Windows notifications
│       └── Snapshot.psm1        # System state snapshots
├── config/                      # Configuration files
│   ├── default.json            # Default settings
│   └── protected-processes.json # Protected process list
├── scheduler/                   # Task scheduler integration
├── tests/                       # Comprehensive test suite (280+ scenarios)
├── install.ps1                 # Installation script
├── uninstall.ps1               # Uninstallation script
├── win-ops.psd1               # PowerShell module manifest
├── LICENSE                     # MIT License
└── README.md                   # This file
```

## Architecture Overview

### Core Modules (6)

| Module | Purpose | Key Features |
|--------|---------|--------------|
| **Config** | Configuration management | JSON parsing, env var expansion, caching |
| **Logger** | Structured logging | ANSI colors, rotation, performance tracking |
| **Lock** | Process synchronization | Mutex-based, timeout, stale detection |
| **Safety** | Protection system | 5-tier safety checks, DryRun validation |
| **Disk** | Storage monitoring | CIM queries, large file detection, analytics |
| **Trash** | Recovery system | SHA256 indexing, metadata tracking, expiration |

### Cleanup Modules (11)

Comprehensive coverage across all major system waste sources:

- **Cache** - Browser, system, and application caches
- **Temp** - Temporary files, %TEMP%, prefetch
- **Logs** - System and application logs
- **Browser** - Chrome, Edge, Firefox, Brave, Opera data
- **Developer** - node_modules, build artifacts, package caches
- **Package Manager** - Chocolatey, Scoop, Winget caches
- **Docker** - Images, containers, volumes, build cache
- **Zombie** - Stuck processes, orphaned handles
- **Orphan** - Orphaned files, broken shortcuts
- **App** - Leftover application data
- **Analyze** - System analysis and reporting

### Utility Modules (5)

- **Format** - Human-readable output (sizes, durations, charts)
- **Parallel** - Multi-threaded execution with aggregated error handling
- **Notify** - Windows notifications and alerts
- **Snapshot** - Before/after system state comparison

## Safety Features

win-ops implements a comprehensive 5-tier safety system to prevent data loss:

### Tier 1: Protected Paths
Entire directories that are never touched:
- Windows system directory (`%SystemRoot%`)
- Program Files directories
- User Documents, Desktop, Downloads, Pictures
- Configurable protection levels

### Tier 2: Protected Processes
Critical system processes that are never terminated:
- System, csrss, lsass, svchost
- Winlogon, services, and others
- Dynamic list from configuration

### Tier 3: Size Guards
Prevents accidental large-scale deletions:
- Single file limit: 2GB (adjustable)
- Batch operation limit: 10GB (adjustable)
- Configurable by safety level

### Tier 4: WRP Detection
Windows Resource Protection path identification:
- System32, SysWOW64, WinSxS detection
- TrustedInstaller requirement flagging
- Prevents system file deletion

### Tier 5: Integrated Checks
All tiers combined with comprehensive validation:
- DryRun mode testing
- Detailed error reporting
- Safety level cascading (Strict/Normal/Permissive)

### Recovery System

All deletions are safely stored in the trash system:

```powershell
# List trash items
win-ops list-trash

# Restore specific item
win-ops restore
```

- **72-Hour Retention** - Default recovery window (configurable)
- **Full Metadata** - Original path, size, type, deletion time, source module
- **SHA256 Indexing** - Collision-resistant file identification
- **Complete Restore** - Returns files to original locations
- **Auto Expiration** - Purges items after retention period

## Configuration

Configuration files are stored in `%LOCALAPPDATA%\win-ops\`:

### Default Configuration

```json
{
  "trash": {
    "path": "%LOCALAPPDATA%\\win-ops\\trash",
    "retention_hours": 72
  },
  "cleanup": {
    "dry_run": false,
    "max_threads": 4,
    "cache_age_days": 7,
    "log_age_days": 30,
    "tmp_age_days": 3
  },
  "safety": {
    "level": "Normal",
    "max_single_file_gb": 2,
    "max_batch_gb": 10
  },
  "modules": {
    "cache": { "enabled": true },
    "temp": { "enabled": true },
    "logs": { "enabled": true },
    "browser": { "enabled": true },
    "dev": { "enabled": true },
    "packages": { "enabled": true },
    "docker": { "enabled": false }
  }
}
```

### Customization

Edit `%LOCALAPPDATA%\win-ops\config.json` to:
- Enable/disable specific cleanup modules
- Adjust safety levels (Strict/Normal/Permissive)
- Configure retention periods
- Set thread count for parallel operations
- Define custom protected paths

Example:

```json
{
  "safety": {
    "level": "Strict"
  },
  "modules": {
    "docker": { "enabled": true }
  }
}
```

## Development

### Running Tests

```powershell
# Run all tests
Invoke-Pester

# Run specific test suite
Invoke-Pester -Path tests/Core/

# Run with coverage report
Invoke-Pester -CodeCoverage

# Run with verbose output
Invoke-Pester -Verbose
```

### Test Coverage

- **Core Modules**: 100% coverage (150+ scenarios)
- **Utility Modules**: 100% coverage (60+ scenarios)
- **Cleanup Modules**: 73% coverage (80+ scenarios)
- **Integration Tests**: 100% coverage (40+ scenarios)
- **Total**: 280+ test scenarios, 85%+ code coverage

### Test Framework

- **Framework**: Pester 5.x
- **Isolation**: TestDrive for safe file operations
- **Mocking**: External dependencies isolated
- **Performance**: Full suite completes in < 3 minutes

### Building

No build step required - win-ops is pure PowerShell.

## Performance

### Execution Time
- Module Load: < 100ms
- Config Load: < 5ms (cached)
- Safety Check: < 1ms per operation
- Trash Move: < 100ms per file
- Index Operations: < 10ms

### Resource Usage
- **Memory**: < 100MB typical, < 200MB peak
- **CPU**: Minimal (< 5% average)
- **Disk I/O**: Optimized with CIM queries
- **Network**: None (unless notifications enabled)

## Troubleshooting

### Common Issues

**Problem**: "Administrator privileges required"
```powershell
# Solution: Run from elevated PowerShell
Start-Process pwsh -Verb RunAs -ArgumentList '-Command', 'cd $PWD; .\bin\win-ops.ps1 help'
```

**Problem**: "Another instance is running"
```powershell
# Solution: Check and clear lock
win-ops status
# Wait for operation to complete, or remove lock file manually
```

**Problem**: "Configuration not found"
```powershell
# Solution: Reinitialize configuration
.\install.ps1
```

### Debug Mode

Enable verbose logging for troubleshooting:

```powershell
# Run with verbose output
win-ops analyze --verbose

# Check logs
Get-Content "$env:LOCALAPPDATA\win-ops\logs\win-ops.log"

# Monitor in real-time
Get-Content "$env:LOCALAPPDATA\win-ops\logs\win-ops.log" -Wait
```

## Scheduled Tasks

After installation, the following scheduled tasks are created:

| Task | Schedule | Purpose |
|------|----------|---------|
| `win-ops-cleanup` | Daily 2:00 AM | Regular system cleanup |
| `win-ops-analyze` | Weekly Sunday 1:00 AM | System analysis and reporting |
| `win-ops-trash-purge` | Daily 3:00 AM | Expired trash cleanup |

Modify or disable tasks in Task Scheduler as needed:

```powershell
# View scheduled tasks
Get-ScheduledTask -TaskName "win-ops*"

# Disable a task
Disable-ScheduledTask -TaskName "win-ops-cleanup"

# Enable a task
Enable-ScheduledTask -TaskName "win-ops-cleanup"
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository** on GitHub
2. **Create a feature branch** for your changes
3. **Write tests** for new functionality
4. **Ensure all tests pass** before submitting
5. **Submit a Pull Request** with detailed description

### Development Workflow

```powershell
# Clone and setup
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Create feature branch
git checkout -b feature/my-feature

# Make changes and test
Invoke-Pester

# Commit and push
git add .
git commit -m "Add feature: description"
git push origin feature/my-feature
```

### Code Standards

- Follow PowerShell best practices (PSSCriptAnalyzer)
- Write comprehensive function comments
- Include error handling for all operations
- Add corresponding tests for new features
- Update documentation for significant changes

## License

MIT License - see [LICENSE](LICENSE) file for details

```
MIT License

Copyright (c) 2026 Seunggabi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

## Support

- 📖 **Documentation**: See [README.md](README.md) and project docs
- 🐛 **Issues**: Report bugs on [GitHub Issues](https://github.com/seunggabi/win-ops/issues)
- 💬 **Discussions**: Join community discussions on GitHub
- 📝 **Changelog**: View [CHANGELOG.md](CHANGELOG.md) for version history

## Related Documentation

- [Logger Module Documentation](README-Logger.md) - Deep dive into logging system
- [PROJECT-SUMMARY.md](PROJECT-SUMMARY.md) - Comprehensive project overview
- [Test Documentation](tests/Integration/README.md) - Integration test details
- [Verification Report](tests/VERIFICATION-REPORT.md) - System verification

## Roadmap

### Planned Enhancements

- GUI wrapper (WPF/WinForms)
- Additional cleanup modules (Visual Studio, JetBrains, etc.)
- Cloud backup integration
- Advanced HTML/PDF reporting
- Multi-language support
- Remote management capability
- Performance profiling tools
- Machine learning-based optimization

## Acknowledgments

**Developed by**: Seunggabi

**Technologies**:
- PowerShell 7.0+
- Windows CIM (Common Information Model)
- Pester 5.x testing framework

**License**: MIT

---

## Project Status

✅ **PRODUCTION READY** - Full safety implementation, comprehensive testing, complete documentation

**Version**: 1.0.0
**Last Updated**: 2026-02-12
**Status**: Active Development

---

**Repository**: [github.com/seunggabi/win-ops](https://github.com/seunggabi/win-ops)
