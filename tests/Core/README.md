# Core Module Pester Tests

Comprehensive Pester test suite for all 6 Core modules in the WinOps system.

## Test Files Created

| Module | Test File | Test Cases | Lines | Coverage Areas |
|--------|-----------|------------|-------|----------------|
| **Config.psm1** | Config.Tests.ps1 | 42 | 458 | Configuration management, JSON I/O, merging, environment variable expansion |
| **Logger.psm1** | Logger.Tests.ps1 | 37 | 456 | Logging initialization, log levels, rotation, buffering, thread safety |
| **Lock.psm1** | Lock.Tests.ps1 | 32 | 418 | Mutex-based locking, metadata management, stale lock detection, concurrency |
| **Trash.psm1** | Trash.Tests.ps1 | 39 | 515 | Trash operations, 72-hour retention, restoration, index management |
| **Safety.psm1** | Safety.Tests.ps1 | 80 | 518 | Path safety, process protection, size guards, WRP detection, safety levels |
| **Disk.psm1** | Disk.Tests.ps1 | 69 | 493 | Disk usage, space checks, large files, directory size, CIM operations |

**Total: 299 test cases across 2,858 lines**

## Test Coverage

### Config.Tests.ps1 (42 tests)
- ✅ Path resolution and directory creation
- ✅ Environment variable expansion (single, multiple, nested)
- ✅ Configuration merging (simple, nested, PSCustomObject)
- ✅ JSON file I/O with locking
- ✅ Hierarchical key navigation (dot notation)
- ✅ Initialize, get, and set operations
- ✅ Cache validation and refresh logic
- ✅ Edge cases: empty configs, deep nesting, special characters

### Logger.Tests.ps1 (37 tests)
- ✅ Logger initialization with custom parameters
- ✅ All log levels (DEBUG, INFO, WARN, ERROR)
- ✅ Log level filtering
- ✅ Context data and exception logging
- ✅ Timestamp formatting
- ✅ Auto-initialization
- ✅ Log rotation mechanisms
- ✅ Buffer management and flushing
- ✅ Thread safety and concurrent writes
- ✅ File cleanup operations
- ✅ Edge cases: empty messages, long messages, special characters

### Lock.Tests.ps1 (32 tests)
- ✅ Lock acquisition and release
- ✅ Metadata file creation (PID, timestamp, hostname)
- ✅ Concurrent access prevention
- ✅ Lock status checking (non-blocking)
- ✅ Stale lock detection and cleanup
- ✅ Force acquisition
- ✅ Timeout handling
- ✅ Module cleanup on unload
- ✅ Multiple unlock calls
- ✅ Edge cases: zero timeout, repeated operations

### Trash.Tests.ps1 (39 tests)
- ✅ Move files and directories to trash
- ✅ SHA256 hash generation
- ✅ Index management with JSON
- ✅ 72-hour retention tracking
- ✅ Restore by hash and original path
- ✅ Expired item removal
- ✅ Clear all trash operations
- ✅ Collision handling
- ✅ Parent directory creation on restore
- ✅ Size calculation for directories
- ✅ Thread safety with file locking
- ✅ Edge cases: special characters, empty files/dirs, long paths

### Safety.Tests.ps1 (80 tests)
- ✅ **Tier 1:** Protected path detection (Windows, Program Files, user folders)
- ✅ **Tier 2:** Protected process detection (system processes, configurable list)
- ✅ **Tier 3:** Size guards (single file 2GB, batch 10GB limits)
- ✅ **Tier 4:** WRP detection (Windows Resource Protection paths)
- ✅ **Tier 5:** Integrated safety checks with all tiers
- ✅ Three safety levels (Strict, Normal, Permissive)
- ✅ Path resolution and environment variable expansion
- ✅ DryRun mode for validation without throwing
- ✅ Result objects with detailed error/warning arrays
- ✅ Edge cases: long paths, UNC paths, special characters
- ✅ Coverage of all protected directories and processes

### Disk.Tests.ps1 (69 tests)
- ✅ Human-readable size conversion (B, KB, MB, GB, TB)
- ✅ Disk usage queries via CIM
- ✅ Drive filtering (by letter, type, network/removable)
- ✅ Space checking (bytes, GB, percentage)
- ✅ Largest files discovery
- ✅ Directory size calculation (recursive)
- ✅ Subdirectory breakdown
- ✅ CIM session management and caching
- ✅ Performance benchmarks
- ✅ Edge cases: zero-byte files, special characters, access denied

## Test Structure

Each test file follows a consistent structure:

```powershell
BeforeAll {
    # Import module
    # Setup test environment
    # Create temporary directories
}

AfterAll {
    # Cleanup test artifacts
    # Remove module
    # Restore environment
}

Describe "Module - FunctionName" {
    BeforeEach {
        # Per-test setup
    }

    AfterEach {
        # Per-test cleanup
    }

    It "Test case description" {
        # Arrange, Act, Assert
    }
}
```

## Running the Tests

### Run all Core tests
```powershell
Invoke-Pester -Path .\tests\Core\ -Output Detailed
```

### Run specific module tests
```powershell
Invoke-Pester -Path .\tests\Core\Config.Tests.ps1
Invoke-Pester -Path .\tests\Core\Logger.Tests.ps1
Invoke-Pester -Path .\tests\Core\Lock.Tests.ps1
Invoke-Pester -Path .\tests\Core\Trash.Tests.ps1
Invoke-Pester -Path .\tests\Core\Safety.Tests.ps1
Invoke-Pester -Path .\tests\Core\Disk.Tests.ps1
```

### Run with code coverage
```powershell
$config = [PesterConfiguration]::Default
$config.Run.Path = '.\tests\Core\'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\lib\core\*.psm1'
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

### Run specific test patterns
```powershell
Invoke-Pester -Path .\tests\Core\*.Tests.ps1 -TestName "*Thread Safety*"
Invoke-Pester -Path .\tests\Core\*.Tests.ps1 -TestName "*Edge Cases*"
```

## Test Categories

### Functional Tests
- Core functionality of each module
- Expected behavior validation
- Parameter handling
- Return value verification

### Error Handling Tests
- Invalid input handling
- Non-existent paths/files
- Permission denied scenarios
- Graceful degradation

### Integration Tests
- Module interaction
- File system operations
- CIM queries
- Concurrent access

### Edge Case Tests
- Empty values
- Boundary conditions
- Special characters
- Large values
- Null/empty handling

### Performance Tests
- Operation timing benchmarks
- Large dataset handling
- Caching effectiveness

## Coverage Goals

Target: **80%+ code coverage** for all Core modules

### Expected Coverage by Module
- **Config.psm1**: 85%+ (all public functions, most code paths)
- **Logger.psm1**: 80%+ (excluding some async edge cases)
- **Lock.psm1**: 90%+ (small, critical module)
- **Trash.psm1**: 85%+ (all operations, index management)
- **Safety.psm1**: 95%+ (safety-critical, comprehensive testing)
- **Disk.psm1**: 80%+ (CIM queries, file operations)

## Test Isolation

Each test suite:
- ✅ Creates isolated temporary directories
- ✅ Uses unique GUIDs for test artifacts
- ✅ Cleans up after execution
- ✅ Does not interfere with other tests
- ✅ Mocks external dependencies where appropriate

## Known Limitations

Some tests are marked as `-Skip` or documented as skipped:
- Log rotation tests (require actual size manipulation)
- Abandoned mutex edge cases (require process crashes)
- Some concurrent access scenarios (timing-dependent)

## CI/CD Integration

These tests are designed to run in CI/CD pipelines:
- Fast execution (most tests < 100ms)
- No external dependencies required
- Clean setup/teardown
- Clear pass/fail signals
- Detailed output for debugging

## Notes

- All tests use Pester 5.x syntax
- Tests are Windows-specific (use CIM, Win32 APIs)
- Temporary files are created in `$env:TEMP`
- Tests handle both PowerShell 5.1 and 7.x
- Thread safety tests use background jobs
- Mock usage is minimal (prefer real operations with isolated data)

## Maintenance

To update tests when modules change:
1. Review the corresponding module changes
2. Update test cases to match new behavior
3. Add new tests for new functions
4. Ensure backward compatibility tests pass
5. Update coverage expectations if needed

## Related Documentation

- [Module Documentation](../../docs/modules/core/)
- [Pester Documentation](https://pester.dev/)
- [Test Strategy](../README.md)
