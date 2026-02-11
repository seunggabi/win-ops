# Issues Found and Fixed

## Critical Issues

### Issue 1: Function Name Mismatches
**Severity**: CRITICAL - Tests would never run the actual functions

#### ZombieKiller
- Test Called: `Find-WinOpsZombieProcesses` (plural)
- Actual Function: `Find-WinOpsZombieProcess` (singular)
- Test Called: `Stop-WinOpsZombieProcesses` (plural)
- Actual Function: `Stop-WinOpsZombieProcess` (singular)

#### OrphanKiller
- Test Called: `Find-WinOpsOrphanProcesses` (no "ed")
- Actual Function: `Find-WinOpsOrphanedProcess` (with "ed")
- Test Called: `Stop-WinOpsOrphanProcesses` (no "ed")
- Actual Function: `Stop-WinOpsOrphanedProcess` (with "ed")

**Impact**: Tests were calling non-existent functions, causing immediate failures.

### Issue 2: Property Name Mismatches
**Severity**: HIGH - Tests would fail assertions even if functions worked

#### ZombieKiller
1. `IsResponding` → Should be `Responding`
   - Line 119, 250 in old tests
   - Actual property at line 315 in ZombieKiller.psm1

2. `Reason` → Should be `Reasons` (plural)
   - Line 121 in old tests
   - Actual property at line 316 in ZombieKiller.psm1

3. Mock used `Name` → Should use `ProcessName`
   - System.Diagnostics.Process uses `ProcessName`, not `Name`

#### OrphanKiller
1. `WorkingSetMB` → Should be `MemoryMB`
   - Line 156 in old tests
   - Actual property at line 251 in OrphanKiller.psm1

**Impact**: All property assertions would fail.

### Issue 3: Phantom Function Tests
**Severity**: HIGH - Testing non-existent functionality

#### ZombieKiller
- Tests for `Get-WinOpsHungProcesses` (lines 233-278)
- Function doesn't exist in module exports
- Removed entire test context

**Impact**: False sense of coverage, tests that can never pass.

### Issue 4: Missing Required Parameters
**Severity**: MEDIUM - Tests wouldn't trigger expected behavior

#### ZombieKiller
- `Find-WinOpsZombieProcess` requires filter flags:
  - `-IncludeNonResponding`
  - `-IncludeHighCPU`
  - `-IncludeHighMemory`
- Without flags, no filters are applied except defaults

#### OrphanKiller
- 30-second reconfirmation for non-responding processes
- `-SkipReconfirmation` needed in tests to avoid delays

**Impact**: Tests would timeout or not find expected processes.

### Issue 5: Default Filter Threshold Problems
**Severity**: MEDIUM - Test data didn't match reality

#### OrphanKiller Age Filter
- Default `MinimumAgeMinutes`: 1440 (24 hours)
- Test data created processes only 30-60 minutes old
- Processes were filtered out before tests could check them

**Fix**: Changed test data to use `.AddDays(-2)` and added `-MinimumAgeMinutes 60`

**Impact**: Tests found zero results when they expected results.

### Issue 6: Incomplete Mocking
**Severity**: MEDIUM - Tests relied on actual system state

#### OrphanKiller
- Implementation calls both:
  - `Get-CimInstance` for parent/child relationships
  - `Get-Process` for MainWindowHandle detection
- Tests only mocked `Get-CimInstance`
- Missing `Get-Process` mock caused unpredictable behavior

**Fix**: Added `Mock Get-Process` with MainWindowHandle property

**Impact**: Tests could fail or pass based on actual system processes.

### Issue 7: Wrong Return Type Expectations
**Severity**: MEDIUM - Assertions checked wrong structure

#### Stop Functions
- Tests expected: `$result.StoppedCount`, `$result.WouldStop`
- Actual returns: Array of objects with `Success`, `Message`, `Method` properties
- Tests expected scalar, got array

**Fix**: Changed assertions to check `$result[0].Success`

**Impact**: Tests would fail with "property not found" errors.

### Issue 8: DryRun vs WhatIf Pattern
**Severity**: LOW - Non-standard PowerShell pattern

- Tests used `-DryRun` parameter
- Implementation uses `SupportsShouldProcess` with `-WhatIf`
- `-DryRun` doesn't exist in actual functions

**Fix**: Replaced with `-WhatIf` tests (proper PowerShell convention)

**Impact**: Tests couldn't actually test dry-run behavior.

## Root Causes

### 1. Tests Written Before Implementation
Pattern suggests tests were written speculatively:
- Function names didn't match
- Property names were guessed
- Return structures assumed

**Recommendation**: Always write tests AFTER implementation exists, or use TDD with frequent validation.

### 2. Copy-Paste Without Verification
Similar patterns across both test files suggest copy-paste:
- Same property mistakes (Name vs ProcessName)
- Same plural/singular confusion
- Same missing parameter patterns

**Recommendation**: Validate each copy-pasted test against actual implementation.

### 3. Insufficient Integration Testing
Unit tests mocked everything but didn't verify mocks matched reality:
- Process property names
- Function parameters
- Return structures

**Recommendation**: Add integration tests that use real modules without mocks.

### 4. No Continuous Validation
Tests weren't run during development:
- Otherwise function name mismatches would have been caught immediately
- Property mismatches would have been obvious

**Recommendation**: Run tests after every implementation change.

## Prevention Strategies

1. **Implementation-First Approach**: Write code, export functions, THEN write tests
2. **Property Validation**: Check actual output objects before writing assertions
3. **Mock Validation**: Ensure mocks match actual System types (System.Diagnostics.Process)
4. **Integration Tests**: At least one test per module that uses real implementations
5. **CI/CD**: Automated test runs on every commit
6. **Test Reviews**: Peer review tests against actual implementation

## Status: FIXED

All critical and high-severity issues have been corrected:
- ✅ Function names match implementation
- ✅ Property names match actual outputs
- ✅ Phantom function tests removed
- ✅ Required parameters added
- ✅ Default filters accounted for
- ✅ All external calls mocked
- ✅ Return type expectations corrected
- ✅ PowerShell patterns followed (WhatIf instead of DryRun)

**Next Step**: Run tests on Windows system to verify all fixes work correctly.
