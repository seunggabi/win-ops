# win-ops Test Suite

Comprehensive test suite for win-ops using Pester 5.x.

## Structure

```
tests/
├── Core/              # Core module tests (Config, Logger, Lock, Safety, etc.)
├── Modules/           # Cleanup module tests (Cache, Browser, Docker, etc.)
├── Utils/             # Utility tests (Format, Parallel, Notify, etc.)
├── Integration/       # Integration tests
├── unit/              # Legacy unit tests
├── lib/               # Additional test libraries
├── TestHelpers.psm1   # Test helper functions
├── coverage.xml       # Code coverage report (generated)
└── test-results.xml   # Test results (generated)
```

## Running Tests

### Basic Execution

```powershell
# Run all tests
.\Run-Tests.ps1

# Run with coverage
.\Run-Tests.ps1

# Run without coverage
.\Run-Tests.ps1 -NoCoverage

# Run in CI mode
.\Run-Tests.ps1 -CI
```

### Filtering Tests

```powershell
# Run specific test file
.\Run-Tests.ps1 -Path ./tests/Core/Config.Tests.ps1

# Run by tag
.\Run-Tests.ps1 -Tags Unit

# Exclude by tag
.\Run-Tests.ps1 -ExcludeTags Integration
```

### Parallel Execution

```powershell
# Enable parallel execution (experimental)
.\Run-Tests.ps1 -Parallel
```

## Using Pester Directly

```powershell
# Import configuration
$config = New-PesterConfiguration (Import-PowerShellDataFile ./PesterConfiguration.psd1)

# Or use script config
$config = & ./.pester.ps1

# Run tests
Invoke-Pester -Configuration $config
```

## Writing Tests

### Test Structure

```powershell
BeforeAll {
    # Import test helpers
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force

    # Import module under test
    Import-Module "$PSScriptRoot/../../lib/core/MyModule.psm1" -Force

    # Setup test environment
    $script:TestDir = New-TestDirectory -Prefix "mymodule"
}

AfterAll {
    # Cleanup
    Remove-TestDirectory -Path $script:TestDir
    Remove-Module MyModule -ErrorAction SilentlyContinue
}

Describe 'MyModule' -Tag 'Unit', 'Core' {
    Context 'Function Tests' {
        BeforeEach {
            # Per-test setup
            Reset-TestDirectory -Path $script:TestDir
        }

        It 'Should do something' {
            # Test implementation
            $result = Do-Something
            $result | Should -Be $expected
        }
    }
}
```

### Using Test Helpers

```powershell
# Create test directory
$testDir = New-TestDirectory -Prefix "config-test"

# Create test files
New-TestFile -Path "$testDir/test.txt" -Content "test data"
New-TestFile -Path "$testDir/large.bin" -Size 1MB
New-TestFiles -Directory $testDir -Count 10 -Pattern "file-{0}.txt"

# Mock configuration
$config = New-MockWinOpsConfig -Overrides @{
    dry_run = $true
    cache_age_days = 30
}
Mock-WinOpsConfig -Config $config

# Mock logger with message capture
Mock-WinOpsLogger -CaptureMessages
# ... run code that logs ...
$errors = Get-MockLogMessages -Level 'ERROR'
$errors.Count | Should -Be 0

# Cleanup
Remove-TestDirectory -Path $testDir
Clear-MockLogMessages
```

### Assertions

```powershell
# Built-in Pester assertions
$result | Should -Be $expected
$result | Should -BeNullOrEmpty
$result | Should -BeGreaterThan 10
$result | Should -Match 'pattern'
$result | Should -Contain 'item'

# Custom test helper assertions
Assert-PathExists -Path $testFile
Assert-PathNotExists -Path $deletedFile
```

## Test Tags

Common tags used in the test suite:

- `Unit` - Unit tests for individual functions
- `Integration` - Integration tests across modules
- `Core` - Core module tests
- `Cleanup` - Cleanup module tests
- `Utils` - Utility tests
- `Safety` - Safety-related tests
- `Slow` - Tests that take longer to execute

## Code Coverage

### Coverage Goals

- **Target**: 80%+ code coverage
- **Minimum**: 60% for core modules
- **Focus**: Critical paths and error handling

### Viewing Coverage

```powershell
# Generate coverage report
.\Run-Tests.ps1

# Coverage report is saved to: tests/coverage.xml (JaCoCo format)
# Test results saved to: tests/test-results.xml (NUnit format)
```

### Coverage in CI/CD

The GitHub Actions workflow automatically:
- Runs tests with coverage
- Uploads coverage reports as artifacts
- Displays coverage percentage in workflow output

## Mocking

### Module Mocking

```powershell
# Mock within module scope
Mock Get-WinOpsConfig {
    return [PSCustomObject]@{ dry_run = $true }
} -ModuleName MyModule

# Mock external commands
Mock Remove-Item { }
Mock Get-ChildItem {
    return @(
        [PSCustomObject]@{ Name = 'file1.txt'; Length = 100 }
    )
}
```

### InModuleScope

```powershell
# Test private functions
InModuleScope MyModule {
    It 'Should call private function' {
        $result = PrivateFunction -Param 'test'
        $result | Should -Not -BeNullOrEmpty
    }
}
```

## Continuous Integration

### GitHub Actions

Tests run automatically on:
- Push to `main` or `develop` branches
- Pull requests
- Manual workflow dispatch

The workflow:
1. Sets up PowerShell 7.4 and latest
2. Installs Pester 5.x
3. Runs tests with coverage
4. Uploads test results and coverage reports
5. Publishes test result summaries

### Local CI Simulation

```powershell
# Simulate CI environment
.\Run-Tests.ps1 -CI -Parallel
```

## Troubleshooting

### Pester Version Issues

```powershell
# Check Pester version
Get-Module -ListAvailable Pester

# Ensure Pester 5.x is installed
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

### Test Isolation Issues

- Use `BeforeEach` for per-test setup
- Use `AfterEach` for per-test cleanup
- Avoid shared state between tests
- Use unique test directories with `New-TestDirectory`

### Mock Issues

- Ensure `-ModuleName` matches the module being tested
- Use `Get-Mock` to verify mocks are set up correctly
- Clear mocks between tests if needed

### Coverage Not Collected

- Verify module paths in `PesterConfiguration.psd1`
- Ensure modules are imported correctly in tests
- Check that code is actually executed (not just mocked)

## Performance

### Test Execution Time

- Unit tests should complete in < 5 seconds
- Integration tests may take longer (tag with `Slow`)
- Use `-Parallel` for faster execution

### Optimization Tips

- Mock external dependencies
- Use `TestDrive` for temporary files
- Avoid unnecessary file I/O
- Mock logger to reduce overhead

## Best Practices

1. **Arrange-Act-Assert**: Structure tests clearly
2. **One Assertion Per Test**: Focus tests on single behaviors
3. **Descriptive Names**: Use clear `Describe`, `Context`, and `It` names
4. **Test Isolation**: Each test should be independent
5. **Mock External Deps**: Don't rely on external services
6. **Error Cases**: Test both success and failure paths
7. **Edge Cases**: Test boundary conditions
8. **Documentation**: Add comments for complex test logic

## Resources

- [Pester Documentation](https://pester.dev/docs/quick-start)
- [Pester v5 Migration Guide](https://pester.dev/docs/migrations/v4-to-v5)
- [PowerShell Testing Best Practices](https://pester.dev/docs/usage/test-file-structure)
