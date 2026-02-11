# Test Fixes Summary

## ZombieKiller.Tests.ps1 Changes

### Function Name Corrections
- `Find-WinOpsZombieProcesses` → `Find-WinOpsZombieProcess` (singular)
- `Stop-WinOpsZombieProcesses` → `Stop-WinOpsZombieProcess` (singular)
- Removed `Get-WinOpsHungProcesses` tests (function doesn't exist)
- Added `Find-WinOpsDuplicateProcess` to exported functions
- Added `Invoke-WinOpsZombieCleanup` to exported functions

### Property Name Corrections
- `Name` → `ProcessName` (System.Diagnostics.Process property)
- `IsResponding` → `Responding` (actual property name)
- `Reason` → `Reasons` (actual property name, plural)
- Added `MainWindowTitle` property to all mocks

### Test Logic Updates
- Added `-IncludeNonResponding` flag where needed
- Added `-SkipReconfirmation` flag to avoid 30-second wait
- Added `-IncludeHighCPU` and `-IncludeHighMemory` flags
- Changed test expectations to match actual function signatures
- Updated `Stop-WinOpsZombieProcess` tests to expect array of result objects with `Success` property
- Replaced DryRun test with WhatIf test (proper PowerShell pattern)

## OrphanKiller.Tests.ps1 Changes

### Function Name Corrections
- `Find-WinOpsOrphanProcesses` → `Find-WinOpsOrphanedProcess` ("Orphaned" not "Orphan")
- `Stop-WinOpsOrphanProcesses` → `Stop-WinOpsOrphanedProcess` ("Orphaned" not "Orphan")
- Added `Invoke-WinOpsOrphanCleanup` to exported functions
- Added `Get-WinOpsProcessTree` to exported functions

### Property Name Corrections
- `WorkingSetMB` → `MemoryMB` (actual output property name)

### Test Logic Updates
- Changed all process ages from hours to days (default MinimumAgeMinutes is 1440 = 24 hours)
- Added `Mock Get-Process` with `MainWindowHandle` for console-less process detection
- Added `-MinimumAgeMinutes 60` parameter to tests to avoid default 24-hour filter
- Updated `Stop-WinOpsOrphanedProcess` tests to use `ProcessId` or `ProcessName` parameters
- Changed test expectations to match actual function signatures
- Replaced DryRun test with WhatIf test
- Removed `-MinAgeMinutes` parameter (doesn't exist in Stop function)

## Key Issues Fixed

1. **Function naming mismatch**: Tests used plural forms but actual functions are singular
2. **Property naming mismatch**: Tests used incorrect property names from System.Diagnostics.Process
3. **Missing required parameters**: Tests didn't specify filter flags that are required
4. **Age filter issues**: Orphan tests created processes too young to be detected by default 24-hour filter
5. **Return value expectations**: Tests expected different return structures than actual implementation
6. **Missing mocks**: Some tests needed additional mocks for Get-Process calls

## Verification Required

Since PowerShell is not available on this macOS system, manual verification is required:

1. Run tests on Windows: `Invoke-Pester -Path tests/Modules/ZombieKiller.Tests.ps1`
2. Run tests on Windows: `Invoke-Pester -Path tests/Modules/OrphanKiller.Tests.ps1`
3. Verify all tests pass with the corrected function names and properties
4. Check that integration tests work with actual system processes
