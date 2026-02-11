# Test Alignment Learnings

## Critical Mismatches Between Tests and Implementation

### ZombieKiller Module

#### Function Names (Singular vs Plural)
- **Implementation**: `Find-WinOpsZombieProcess` (singular)
- **Old Tests**: `Find-WinOpsZombieProcesses` (plural)
- **Lesson**: Always verify exported function names before writing tests

#### Output Properties
1. **Responding Property**
   - Actual: `Responding` (boolean from System.Diagnostics.Process)
   - Test Expected: `IsResponding`
   - Source: Line 315 in ZombieKiller.psm1

2. **Reasons Property**
   - Actual: `Reasons` (plural, comma-joined string)
   - Test Expected: `Reason` (singular)
   - Source: Line 316 in ZombieKiller.psm1

3. **Process Name**
   - Actual: `ProcessName` property from Get-Process
   - Test Mock Used: `Name` property
   - Fix: Changed all mocks to use `ProcessName`

#### Behavior Requirements
- Non-responding detection requires `-IncludeNonResponding` flag
- 30-second reconfirmation by default (use `-SkipReconfirmation` in tests)
- High CPU requires `-IncludeHighCPU` flag
- High memory requires `-IncludeHighMemory` flag

#### Non-existent Functions
- `Get-WinOpsHungProcesses` was in tests but doesn't exist in implementation
- Tests removed for this phantom function

### OrphanKiller Module

#### Function Names ("Orphaned" vs "Orphan")
- **Implementation**: `Find-WinOpsOrphanedProcess` (with "ed")
- **Old Tests**: `Find-WinOpsOrphanProcesses` (without "ed", plural)
- **Lesson**: Subtle spelling differences matter

#### Property Name Differences
- **MemoryMB vs WorkingSetMB**
  - Actual Output: `MemoryMB` (Line 251 in OrphanKiller.psm1)
  - Test Expected: `WorkingSetMB`
  - Source: Calculated from WorkingSetSize but renamed in output

#### Default Behavior Issues
- **MinimumAgeMinutes Default**: 1440 minutes (24 hours)
- Tests created processes only 30-60 minutes old
- Solution: Changed test data to use `.AddDays(-2)` and added `-MinimumAgeMinutes 60` parameter

#### Console Detection
- Implementation calls `Get-Process` to check `MainWindowHandle`
- Tests must mock both `Get-CimInstance` AND `Get-Process`
- Missing `Get-Process` mock caused tests to fail silently

## Best Practices Learned

### 1. Read Implementation First
Before writing tests, read the actual module exports:
```powershell
Export-ModuleMember -Function @('FunctionName1', 'FunctionName2')
```

### 2. Check Output Object Structure
Find the actual `[PSCustomObject]@{}` creation in implementation:
```powershell
$result = [PSCustomObject]@{
    PropertyName = $value
    AnotherProperty = $anotherValue
}
```

### 3. Understand Default Filters
Many functions have default thresholds:
- CPU: 90%
- Memory: 2048 MB
- Age: 1440 minutes (24 hours)

Tests must account for these defaults.

### 4. Mock All External Calls
- `Get-Process` (even if you also mock `Get-CimInstance`)
- `Start-Sleep` (to speed up tests)
- Core module functions (`Write-WinOpsLog`, `Test-WinOpsProcessProtected`)

### 5. Use Correct Parameter Names
- Check `param()` block for exact parameter names
- Verify ValueFromPipelineByPropertyName bindings
- Understand SupportsShouldProcess behavior

## Pattern: Verification Loop
Both modules have similar patterns:
1. Get all processes
2. Filter by criteria
3. Optional: Reconfirm/wait
4. Build output objects
5. Return sorted results

Tests must mock each stage appropriately.

## Common Pitfalls

1. **Property vs Field**: System.Diagnostics.Process has specific property names
2. **Singular vs Plural**: Function names don't always match verb conventions
3. **Default Thresholds**: Functions filter by default, tests must provide data that passes filters
4. **Multiple Mocks**: WMI functions need CimInstance mocks, process checks need Get-Process mocks
5. **Return Structure**: Some functions return single objects, others return arrays

## Success Criteria

✅ All function names match implementation exactly
✅ All property names match output objects exactly
✅ All test data passes default filters
✅ All external calls are mocked
✅ Test expectations match actual return types
