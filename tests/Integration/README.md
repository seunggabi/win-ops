# Integration Tests

This directory contains end-to-end integration tests for the win-ops system.

## E2E.Tests.ps1

Comprehensive integration tests covering the entire win-ops workflow.

### Test Coverage

#### 1. Full Cleanup Flow (Dry Run)
- **Dry run execution**: Identifies cleanup targets without deleting
- **Space calculation**: Calculates total reclaimable space
- **Categorization**: Groups targets by type (Cache, Temp, Logs)
- **Safety checks**: Validates protected paths, processes, and size limits

#### 2. Analyze Flow
- **Category-based analysis**: Groups files by category with size reporting
- **Largest items identification**: Identifies top space consumers
- **Age filtering**: Filters files by modification date
- **Report generation**: Generates comprehensive space analysis reports

#### 3. Trash Recovery Flow
- **Move to trash**: Safely moves files to trash directory
- **Index management**: Creates and maintains trash index
- **List trash contents**: Lists all recoverable items
- **Restore from trash**: Restores files to original locations
- **72-hour retention**: Automatically purges expired items

#### 4. Config Management
- **Config loading**: Loads default and user configurations
- **Config merging**: Merges user overrides with defaults
- **Environment variable expansion**: Expands %LOCALAPPDATA% etc.
- **Config validation**: Validates numeric values and enums

#### 5. Integrated Safety System
- **Multi-tier checks**: Tests all 5 safety tiers in combination
  - Tier 1: Protected paths (Windows, Program Files, Documents)
  - Tier 2: Protected processes (csrss, lsass, System)
  - Tier 3: Size guards (2GB single, 10GB batch)
  - Tier 4: WRP detection (System32, SysWOW64)
  - Tier 5: Integrated assertions
- **Safety level cascading**: Tests Strict, Normal, Permissive modes
- **Fail-safe behavior**: Ensures safe defaults on errors

#### 6. Error Handling and Recovery
- **Missing config files**: Graceful degradation
- **Locked files**: Handles file locks without crashing
- **Permission errors**: Detects and reports permission issues

### Test Scenarios

#### Scenario 1: Dry Run Analysis
```powershell
# Simulates: win-ops analyze --dry-run
1. Creates test files (cache, temp, logs)
2. Identifies cleanup targets
3. Calculates space savings
4. Does NOT delete files
5. Verifies all files still exist
```

#### Scenario 2: Category Reporting
```powershell
# Simulates: win-ops analyze with detailed reporting
1. Creates diverse file types
2. Groups by category
3. Sorts by size
4. Filters by age
5. Generates summary report
```

#### Scenario 3: Trash and Restore
```powershell
# Simulates: Complete trash workflow
1. Delete file → Moves to trash
2. Create index entry with metadata
3. List trash contents
4. Restore file → Returns to original path
5. Remove from index
6. Purge expired items (>72h)
```

#### Scenario 4: Safety Validation
```powershell
# Simulates: Safety checks before operations
1. Block C:\Windows\System32 (protected + WRP)
2. Block csrss process (critical system)
3. Block 15GB batch (over limit)
4. Allow C:\Temp operations (safe)
5. Respect safety level settings
```

### Mock Environment

All tests run in isolated mock environments:

- **TestDrive**: Pester's temporary test directory
- **MockTrashPath**: Isolated trash directory
- **MockConfigPath**: Test configuration files
- **No real system modifications**: All operations are sandboxed

### Helper Functions

#### New-TestFile
Creates test files with specific size and timestamp:
```powershell
New-TestFile -Path "C:\test.txt" -SizeInBytes 5MB -LastWriteTime (Get-Date).AddDays(-30)
```

#### New-MockConfig
Creates mock configuration for testing:
```powershell
New-MockConfig  # Returns path to test config
```

### Running Tests

```powershell
# Run all integration tests
Invoke-Pester tests/Integration/E2E.Tests.ps1 -Output Detailed

# Run specific test group
Invoke-Pester tests/Integration/E2E.Tests.ps1 -FullName "*Trash Recovery Flow*"

# Generate coverage report
Invoke-Pester tests/Integration/E2E.Tests.ps1 -CodeCoverage "lib/**/*.psm1"
```

### Validation Checklist

- [ ] All test scenarios pass
- [ ] No actual system files modified
- [ ] Safety checks block dangerous operations
- [ ] Config merging works correctly
- [ ] Trash index maintained properly
- [ ] 72-hour retention enforced
- [ ] Error handling prevents crashes
- [ ] All edge cases covered

### Integration Points

Tests validate integration between:

1. **Config + Safety**: Safety levels from config affect validation
2. **Trash + Logger**: Trash operations logged correctly
3. **Safety + All Modules**: All cleanup modules respect safety
4. **Analyze + Modules**: Analysis aggregates all module data
5. **Config + Environment**: Environment variables expanded

### Notes

- Tests are **platform-aware** but designed for Windows
- On macOS/Linux, some Windows-specific paths are mocked
- PowerShell 7.0+ required for full compatibility
- Pester 5.x required for test execution
