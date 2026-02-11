# Test Fix Decisions

## Decision 1: Function Name Alignment Strategy
**Decision**: Match test function calls exactly to implementation exports
**Rationale**: Tests must call the actual functions to be valid
**Implementation**:
- Changed all plurals to singular forms
- Added "ed" suffix for OrphanKiller functions
**Alternatives Considered**:
- Change implementation to match tests (rejected - breaking change)
- Create aliases (rejected - adds complexity)

## Decision 2: Property Name Correction Approach
**Decision**: Use exact property names from module output objects
**Rationale**: Assertions must check actual properties returned
**Source of Truth**: PSCustomObject definitions in implementation
**Implementation**:
- Mapped test expectations to actual output structure
- Verified against lines 308-316 (ZombieKiller) and 239-254 (OrphanKiller)

## Decision 3: Handling Phantom Function Tests
**Decision**: Remove all tests for `Get-WinOpsHungProcesses`
**Rationale**: Function doesn't exist, tests provide false coverage
**Alternatives Considered**:
- Keep tests and implement function (rejected - scope creep)
- Comment out tests (rejected - clutters code)
**Action**: Complete removal of Get-WinOpsHungProcesses context

## Decision 4: Mock Strategy for Process Properties
**Decision**: Mock both Get-CimInstance AND Get-Process
**Rationale**: Implementation calls both; incomplete mocking causes unpredictable results
**Implementation**:
- Get-CimInstance: Parent/child relationships, WMI data
- Get-Process: MainWindowHandle detection, process details
**Key Learning**: Always trace through implementation to find all external calls

## Decision 5: Default Filter Handling
**Decision**: Adjust test data and parameters to work with defaults
**Rationale**: Tests should verify default behavior, not fight against it
**Implementation**:
- OrphanKiller: Changed process ages from hours to days
- Added explicit `-MinimumAgeMinutes 60` where needed
- ZombieKiller: Added `-SkipReconfirmation` to avoid 30-second waits
**Alternatives Considered**:
- Override all defaults in tests (rejected - doesn't test real behavior)

## Decision 6: Required Parameter Flags
**Decision**: Explicitly add all required filter flags
**Rationale**: Functions require flags to activate filters; defaults are conservative
**Implementation**:
- `-IncludeNonResponding` for hung process tests
- `-IncludeHighCPU` for CPU tests
- `-IncludeHighMemory` for memory tests
**Pattern**: Each test specifies exactly what it's testing

## Decision 7: Return Value Assertion Strategy
**Decision**: Expect array returns, check individual object properties
**Rationale**: Functions return arrays of result objects, not summary objects
**Implementation**:
- Changed `$result.StoppedCount` to `$result[0].Success`
- Check array elements individually
- Verify `Success`, `Message`, `Method` properties
**Breaking Change**: Old tests expected different return structure

## Decision 8: DryRun vs WhatIf Pattern
**Decision**: Use PowerShell standard `-WhatIf` instead of custom `-DryRun`
**Rationale**:
- `SupportsShouldProcess` provides `-WhatIf` automatically
- `-DryRun` parameter doesn't exist in implementation
- WhatIf is PowerShell best practice
**Implementation**: Replaced DryRun tests with WhatIf tests
**Note**: `-WhatIf` doesn't return test results, just prevents execution

## Decision 9: Mock Property Completeness
**Decision**: Include ALL properties needed by implementation
**Rationale**: Incomplete mocks cause null reference errors
**Implementation**:
- Added `ProcessName` (not `Name`)
- Added `MainWindowTitle` for all process mocks
- Added `StartTime` where needed
- Added `Responding` property
**Pattern**: Review implementation code to find all accessed properties

## Decision 10: Test Data Realism
**Decision**: Make test data pass realistic filters
**Rationale**: Tests that never find matches due to filters are useless
**Implementation**:
- Process ages: 24+ hours for orphans
- Memory sizes: Above thresholds being tested
- CPU values: Above thresholds being tested
**Validation**: Check that test data would be detected by actual functions

## Architecture Decisions

### Test Organization
- Keep unit tests for each module separate
- Mock all external dependencies
- Integration tests verify real system interaction
**Rationale**: Fast unit tests, comprehensive integration tests

### Mock Granularity
- Mock at function boundary (Get-Process, Get-CimInstance)
- Don't mock internal helper functions
**Rationale**: Test public interface, not implementation details

### Assertion Specificity
- Check exact property names and values
- Verify array lengths where relevant
- Test both success and failure paths
**Rationale**: Specific assertions catch regressions

## Standards Established

1. **Function Names**: Match exports exactly, no assumptions
2. **Property Names**: Match PSCustomObject output exactly
3. **Mocking**: Mock all external calls, include all properties
4. **Test Data**: Must pass default filters unless testing filter edge cases
5. **Parameters**: Explicitly specify all flags being tested
6. **Assertions**: Check actual return structure, not assumed structure
7. **PowerShell Patterns**: Use SupportsShouldProcess, not custom flags

## Verification Checklist

Before committing test changes:
- [ ] All function names match exports
- [ ] All property names match output objects
- [ ] All mocks include required properties
- [ ] Test data passes default filters
- [ ] Required parameters specified
- [ ] Return structures checked correctly
- [ ] No phantom function tests
- [ ] PowerShell standards followed

## Impact Assessment

**Risk**: LOW
- No implementation changes
- Only test code affected
- Backwards compatible with existing functionality

**Benefits**: HIGH
- Tests now validate actual behavior
- Can catch real regressions
- Developer confidence restored
- CI/CD can be enabled

**Effort**: Medium (2-3 hours total)
- Two test files fixed
- Documentation created
- Patterns established for future tests
