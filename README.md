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

```powershell
# Clone the repository
git clone https://github.com/seunggabi/win-ops.git
cd win-ops

# Import the module
Import-Module .\win-ops.psd1

# Or install as a scheduled task (requires admin)
.\bin\win-ops.ps1 install
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

## Configuration

Configuration files are located in the `config/` directory. Customize cleanup rules, safety settings, and exclusion patterns to match your environment.

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

## Safety

win-ops includes multiple safety features:

- **Trash System**: All deletions are moved to trash first, allowing recovery
- **File Locking**: Prevents concurrent operations on the same files
- **Critical Path Protection**: System-critical directories are never touched
- **Dry Run Mode**: Preview changes before execution
- **Logging**: All operations are logged for audit purposes

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Author

Seunggabi

## Links

- Repository: https://github.com/seunggabi/win-ops
- Issues: https://github.com/seunggabi/win-ops/issues
