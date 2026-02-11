# Cleanup Modules Test Suite

Comprehensive Pester test suite for all WinOps cleanup modules.

## Test Files Overview

| Module | Test File | Lines | Test Coverage |
|--------|-----------|-------|---------------|
| CacheCleanup | CacheCleanup.Tests.ps1 | 318 | Unit + Integration |
| TmpCleanup | TmpCleanup.Tests.ps1 | 272 | Unit + Integration |
| LogCleanup | LogCleanup.Tests.ps1 | 334 | Unit + Integration |
| BrowserCleanup | BrowserCleanup.Tests.ps1 | 344 | Unit + Integration |
| DevCleanup | DevCleanup.Tests.ps1 | 315 | Unit + Integration |
| PackageManagerCleanup | PackageManagerCleanup.Tests.ps1 | 286 | Unit + Integration |
| DockerCleanup | DockerCleanup.Tests.ps1 | 346 | Unit + Integration |
| ZombieKiller | ZombieKiller.Tests.ps1 | 321 | Unit + Integration |
| OrphanKiller | OrphanKiller.Tests.ps1 | 410 | Unit + Integration |
| OrphanAppCleanup | OrphanAppCleanup.Tests.ps1 | 500 | Unit + Integration |
| Analyze | Analyze.Tests.ps1 | 461 | Unit + Integration |

**Total:** 3,907 lines of test code across 11 modules

## Test Strategy

### 1. Mock-Based Unit Tests
- **Filesystem Mocking**: Use mocks instead of creating real files
- **Core Dependencies**: Mock `Write-WinOpsLog`, `Move-WinOpsToTrash`, `Test-WinOpsProcessProtected`
- **External Commands**: Mock Docker, DISM, WMI/CIM calls
- **Isolation**: Each test is independent and doesn't affect the system

### 2. DryRun Mode Testing
Every cleanup module test includes:
- DryRun mode verification
- Ensure no actual deletions occur in DryRun
- Verify `WouldRemove` flags are set correctly
- Confirm counters remain at 0

### 3. Safety Integration Tests
- Protected path verification
- Protected process exclusion
- Elevation requirement checks
- Size limit validation

### 4. Trash System Integration
- Verify trash is used when `UseTrash` is specified
- Mock `Move-WinOpsToTrash` to prevent actual trash operations
- Test recovery scenarios

### 5. Integration Tests
- Real filesystem operations using `$TestDrive`
- Age-based filtering
- Size calculations
- Pattern matching

## Test Execution

### Run All Module Tests
```powershell
Invoke-Pester -Path ./tests/Modules/ -Output Detailed
```

### Run Specific Module Tests
```powershell
Invoke-Pester -Path ./tests/Modules/CacheCleanup.Tests.ps1 -Output Detailed
```

### Run Only Unit Tests
```powershell
Invoke-Pester -Path ./tests/Modules/ -Tag Unit -Output Detailed
```

### Run Only Integration Tests
```powershell
Invoke-Pester -Path ./tests/Modules/ -Tag Integration -Output Detailed
```

### Run with Coverage
```powershell
Invoke-Pester -Path ./tests/Modules/ -CodeCoverage ./lib/modules/*.psm1
```

## Test Coverage by Module

### CacheCleanup.Tests.ps1
- ✅ `Get-WinOpsCacheInfo` - Query all cache types
- ✅ `Clear-WinOpsCache` - Cleanup with age filters
- ✅ `Optimize-WinOpsIconCache` - Icon cache rebuild
- ✅ `Invoke-WinOpsCacheCleanup` - Main execution wrapper
- ✅ `Get-WinOpsCacheTargets` - Target enumeration
- ✅ DryRun mode support
- ✅ Trash integration
- ✅ Age filtering
- ✅ Size calculations

### TmpCleanup.Tests.ps1
- ✅ `Get-WinOpsTempFileInfo` - Temp file enumeration
- ✅ `Clear-WinOpsTempFiles` - Temp file removal
- ✅ DryRun mode support
- ✅ Trash integration
- ✅ Exclude patterns
- ✅ File lock handling
- ✅ Elevation requirements
- ✅ Age filtering

### LogCleanup.Tests.ps1
- ✅ `Get-WinOpsLogFileInfo` - Log file discovery
- ✅ `Clear-WinOpsLogFiles` - Log file cleanup
- ✅ `Clear-WinOpsEventLog` - Event log management
- ✅ DryRun mode support
- ✅ Minimum size filtering
- ✅ Archive before clear
- ✅ Elevation requirements
- ✅ Error handling

### BrowserCleanup.Tests.ps1
- ✅ `Get-WinOpsBrowserDataInfo` - Browser data enumeration
- ✅ `Clear-WinOpsBrowserData` - Browser cleanup
- ✅ `Test-WinOpsBrowserInstalled` - Installation detection
- ✅ DryRun mode support
- ✅ Browser process detection
- ✅ Graceful close with Force
- ✅ Multi-browser support
- ✅ Data type filtering

### DevCleanup.Tests.ps1
- ✅ `Get-WinOpsDevCacheInfo` - Dev cache enumeration
- ✅ `Clear-WinOpsDevCache` - Dev cache cleanup
- ✅ `Find-WinOpsNodeModules` - node_modules discovery
- ✅ DryRun mode support
- ✅ Package manager detection
- ✅ Size calculations
- ✅ Age filtering
- ✅ Category-based cleanup

### PackageManagerCleanup.Tests.ps1
- ✅ `Get-WinOpsPackageManagerInfo` - Package manager discovery
- ✅ `Clear-WinOpsPackageManagerCache` - Cache cleanup
- ✅ `Invoke-WinOpsComponentStoreCleanup` - DISM cleanup
- ✅ DryRun mode support
- ✅ Elevation requirements
- ✅ Package manager detection
- ✅ ResetBase option
- ✅ Error handling

### DockerCleanup.Tests.ps1
- ✅ `Get-WinOpsDockerDiskUsage` - Docker resource usage
- ✅ `Clear-WinOpsDockerContainers` - Container cleanup
- ✅ `Clear-WinOpsDockerImages` - Image cleanup
- ✅ `Clear-WinOpsDockerVolumes` - Volume cleanup
- ✅ `Invoke-WinOpsDockerSystemPrune` - System prune
- ✅ `Optimize-WinOpsDockerVhdx` - WSL2 VHDX compaction
- ✅ DryRun mode support
- ✅ Docker detection
- ✅ Size parsing

### ZombieKiller.Tests.ps1
- ✅ `Find-WinOpsZombieProcesses` - Zombie detection
- ✅ `Stop-WinOpsZombieProcesses` - Zombie termination
- ✅ `Get-WinOpsHungProcesses` - Hung process detection
- ✅ DryRun mode support
- ✅ CPU threshold filtering
- ✅ Memory threshold filtering
- ✅ Graceful close option
- ✅ Protected process exclusion

### OrphanKiller.Tests.ps1
- ✅ `Find-WinOpsOrphanProcesses` - Orphan detection
- ✅ `Stop-WinOpsOrphanProcesses` - Orphan termination
- ✅ `Get-WinOpsProcessTree` - Process tree building
- ✅ DryRun mode support
- ✅ Parent process validation
- ✅ Age filtering
- ✅ System process exclusion
- ✅ Protected process handling

### OrphanAppCleanup.Tests.ps1
- ✅ `Find-WinOpsOrphanedAppData` - Orphaned folder detection
- ✅ `Clear-WinOpsOrphanedAppData` - Orphaned folder cleanup
- ✅ `Find-WinOpsOrphanedShortcuts` - Broken shortcut detection
- ✅ `Remove-WinOpsOrphanedShortcuts` - Shortcut cleanup
- ✅ DryRun mode support
- ✅ Registry integration
- ✅ System folder exclusion
- ✅ Size calculations

### Analyze.Tests.ps1
- ✅ `Get-WinOpsCleanupAnalysis` - Comprehensive analysis
- ✅ `Export-WinOpsAnalysisReport` - Report generation
- ✅ `Get-WinOpsCategoryBreakdown` - Category aggregation
- ✅ `Show-WinOpsCleanupChart` - Visual charts
- ✅ CSV export
- ✅ JSON export
- ✅ HTML export
- ✅ Top N filtering

## Common Test Patterns

### 1. Module Loading
```powershell
It 'Should load module successfully' {
    Get-Module ModuleName | Should -Not -BeNullOrEmpty
}
```

### 2. DryRun Pattern
```powershell
It 'Should support DryRun mode' {
    $result = Invoke-Function -DryRun

    $result.WouldRemove | Should -Be $true
    $result.RemovedCount | Should -Be 0
    Should -Not -Invoke Remove-Item
}
```

### 3. Mock Pattern
```powershell
Mock Get-ChildItem -ModuleName ModuleName {
    @(
        [PSCustomObject]@{
            Name = 'test.file'
            FullName = 'C:\test.file'
            Length = 1024
        }
    )
}
```

### 4. Trash Integration Pattern
```powershell
It 'Should use trash when UseTrash is specified' {
    $result = Invoke-Function -UseTrash -Force -Confirm:$false

    Should -Invoke Move-WinOpsToTrash -ModuleName ModuleName
}
```

### 5. Integration Test Pattern
```powershell
BeforeEach {
    $script:TestDir = Join-Path $TestDrive 'Test'
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $script:TestDir 'file.txt') -Value 'test'
}
```

## Expected Test Results

All tests should pass with:
- ✅ No actual filesystem modifications (except in `$TestDrive`)
- ✅ No actual process terminations
- ✅ No actual Docker operations
- ✅ No actual trash operations
- ✅ All mocks properly invoked
- ✅ All assertions passing

## Continuous Integration

Tests are designed to run in CI/CD pipelines:
- No admin privileges required for most tests
- No actual system modifications
- Fast execution (< 5 minutes for full suite)
- Clear pass/fail indicators
- Detailed error messages

## Troubleshooting

### Mock Not Found
Ensure module name matches: `-ModuleName ModuleName`

### Test Drive Issues
Always use `$TestDrive` for temporary files in integration tests

### Assertion Failures
Check mock parameter filters and return values

### Elevation Tests
Some tests check elevation status - may need to mock `Test-IsElevated`

## Future Enhancements

- [ ] Performance benchmarking tests
- [ ] Stress testing with large datasets
- [ ] Concurrency testing for parallel operations
- [ ] End-to-end workflow tests
- [ ] Snapshot testing for visual reports
