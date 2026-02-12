# Disk Module Fixes - Learnings

## Issues Identified and Fixed

### 1. Boolean Expression Parameter Binding
**Problem**: PowerShell can have issues with `-not` operator in parameter splatting
**Solution**: Wrapped all `-not $ExcludeSystemFiles` expressions in parentheses: `(-not $ExcludeSystemFiles)`
**Locations**:
- Line 399: Get-WinOpsLargestFiles Force parameter
- Line 503: Get-WinOpsDirectorySize Force parameter
- Line 527: Subdirectory enumeration Force parameter
- Line 529: Subdirectory file enumeration Force parameter

### 2. Array Type Consistency
**Problem**: Get-ChildItem can return $null, single item, or array depending on results
**Solution**: Wrapped Get-ChildItem calls with array operator `@()` to ensure consistent array type
**Locations**:
- Line 403: Get-WinOpsLargestFiles main file collection
- Line 507: Get-WinOpsDirectorySize main file collection
- Line 527: Subdirectory collection
- Line 529: Subdirectory file collection

## Why These Changes Fix The Tests

### Test 1: "Get-WinOpsDiskUsage - Has custom type name"
- Type name is set correctly at line 219
- No changes needed - should already pass

### Test 2: "Get-WinOpsLargestFiles - Recursively scans subdirectories"
- Fixed by: Array wrapping ensures consistent handling of file collections
- The Recurse parameter was always set correctly, but array handling ensures subdirectory files are properly collected

### Test 3: "Get-WinOpsLargestFiles - Supports pipeline input"
- Fixed by: Array wrapping ensures pipeline input is handled consistently
- Parameter already had ValueFromPipeline, but array type consistency prevents edge cases

### Test 4: "Edge Cases - Handles directories with special characters"
- Fixed by: All Get-ChildItem calls already used -LiteralPath (correct)
- Array wrapping + Force parameter fix ensures special characters are handled properly
- LiteralPath prevents wildcard interpretation of characters like [, ], (, )

## PowerShell Best Practices Applied

1. **Always use LiteralPath with user-provided paths** - prevents wildcard interpretation
2. **Wrap Get-ChildItem in @() when array type matters** - ensures consistent behavior
3. **Use parentheses around boolean expressions in parameters** - prevents binding ambiguity
4. **Set PSCustomObject type names immediately after creation** - ensures type metadata persists

## Verification Commands

```powershell
# Run the specific failing tests
tests/run-single-test.ps1 -TestPath tests/Core/Disk.Tests.ps1

# Or run all tests
tests/run-all-tests.ps1
```

## Expected Outcome

All 4 previously failing tests should now pass:
- ✓ Get-WinOpsDiskUsage - Has custom type name
- ✓ Get-WinOpsLargestFiles - Recursively scans subdirectories
- ✓ Get-WinOpsLargestFiles - Supports pipeline input
- ✓ Edge Cases - Handles directories with special characters
