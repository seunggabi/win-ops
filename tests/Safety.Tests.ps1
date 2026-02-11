# Safety.Tests.ps1
# Comprehensive tests for Safety module

BeforeAll {
    Import-Module "$PSScriptRoot\..\lib\core\Safety.psm1" -Force
}

Describe "Test-WinOpsPathSafe" {
    Context "Protected system paths" {
        It "Detects C:\Windows as unsafe" {
            Test-WinOpsPathSafe -Path "C:\Windows\test.txt" | Should -Be $false
        }

        It "Detects C:\Program Files as unsafe" {
            Test-WinOpsPathSafe -Path "C:\Program Files\test.exe" | Should -Be $false
        }

        It "Detects C:\Program Files (x86) as unsafe" {
            Test-WinOpsPathSafe -Path "C:\Program Files (x86)\test.dll" | Should -Be $false
        }
    }

    Context "Protected user paths" {
        It "Detects Documents folder as unsafe" {
            $docsPath = Join-Path $env:USERPROFILE "Documents\test.txt"
            Test-WinOpsPathSafe -Path $docsPath | Should -Be $false
        }

        It "Detects Desktop folder as unsafe" {
            $desktopPath = Join-Path $env:USERPROFILE "Desktop\test.txt"
            Test-WinOpsPathSafe -Path $desktopPath | Should -Be $false
        }

        It "Detects Downloads folder as unsafe" {
            $downloadsPath = Join-Path $env:USERPROFILE "Downloads\test.txt"
            Test-WinOpsPathSafe -Path $downloadsPath | Should -Be $false
        }
    }

    Context "Safe paths" {
        It "Allows C:\Temp" {
            Test-WinOpsPathSafe -Path "C:\Temp\file.txt" | Should -Be $true
        }

        It "Allows D:\ drives" {
            Test-WinOpsPathSafe -Path "D:\data\file.txt" | Should -Be $true
        }

        It "Allows custom application data" {
            Test-WinOpsPathSafe -Path "C:\CustomApp\data.txt" | Should -Be $true
        }
    }

    Context "Safety levels" {
        It "Permissive mode only blocks WRP paths" {
            $result = Test-WinOpsPathSafe -Path "C:\Program Files\test.exe" -Level Permissive
            $result | Should -Be $true  # Program Files not in WRP list
        }

        It "Permissive mode blocks System32" {
            $result = Test-WinOpsPathSafe -Path "C:\Windows\System32\test.dll" -Level Permissive
            $result | Should -Be $false  # System32 is WRP
        }

        It "Normal mode blocks both protected and WRP paths" {
            Test-WinOpsPathSafe -Path "C:\Program Files\test.exe" -Level Normal | Should -Be $false
        }
    }

    Context "Error handling" {
        It "Throws on null path" {
            { Test-WinOpsPathSafe -Path $null } | Should -Throw
        }

        It "Throws on empty path" {
            { Test-WinOpsPathSafe -Path "" } | Should -Throw
        }

        It "Treats unresolvable paths as unsafe (fail-safe)" {
            # Invalid path format should fail safe
            $result = Test-WinOpsPathSafe -Path "::invalid::" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $result | Should -Be $false
        }
    }
}

Describe "Test-WinOpsProcessProtected" {
    Context "Critical system processes" {
        It "Protects System process" {
            Test-WinOpsProcessProtected -ProcessName "System" | Should -Be $true
        }

        It "Protects csrss" {
            Test-WinOpsProcessProtected -ProcessName "csrss" | Should -Be $true
        }

        It "Protects lsass" {
            Test-WinOpsProcessProtected -ProcessName "lsass" | Should -Be $true
        }

        It "Protects svchost" {
            Test-WinOpsProcessProtected -ProcessName "svchost" | Should -Be $true
        }

        It "Protects explorer" {
            Test-WinOpsProcessProtected -ProcessName "explorer" | Should -Be $true
        }
    }

    Context "Process name normalization" {
        It "Handles .exe extension" {
            Test-WinOpsProcessProtected -ProcessName "csrss.exe" | Should -Be $true
        }

        It "Is case-insensitive" {
            Test-WinOpsProcessProtected -ProcessName "LSASS" | Should -Be $true
            Test-WinOpsProcessProtected -ProcessName "LsAsS" | Should -Be $true
        }
    }

    Context "Non-protected processes" {
        It "Allows notepad" {
            Test-WinOpsProcessProtected -ProcessName "notepad" | Should -Be $false
        }

        It "Allows custom applications" {
            Test-WinOpsProcessProtected -ProcessName "myapp" | Should -Be $false
        }
    }

    Context "Safety levels" {
        It "Permissive mode only protects critical processes" {
            # svchost is not in critical list
            Test-WinOpsProcessProtected -ProcessName "svchost" -Level Permissive | Should -Be $false
        }

        It "Permissive mode protects csrss (critical)" {
            Test-WinOpsProcessProtected -ProcessName "csrss" -Level Permissive | Should -Be $true
        }

        It "Normal mode protects all configured processes" {
            Test-WinOpsProcessProtected -ProcessName "svchost" -Level Normal | Should -Be $true
        }
    }

    Context "Error handling" {
        It "Throws on null process name" {
            { Test-WinOpsProcessProtected -ProcessName $null } | Should -Throw
        }

        It "Throws on empty process name" {
            { Test-WinOpsProcessProtected -ProcessName "" } | Should -Throw
        }
    }
}

Describe "Test-WinOpsSizeGuard" {
    Context "Single file limits" {
        It "Allows files under 2GB" {
            Test-WinOpsSizeGuard -Size 1GB | Should -Be $true
        }

        It "Allows files at 2GB exactly" {
            Test-WinOpsSizeGuard -Size 2GB | Should -Be $true
        }

        It "Rejects files over 2GB" {
            Test-WinOpsSizeGuard -Size (2GB + 1) | Should -Be $false
        }
    }

    Context "Batch operation limits" {
        It "Allows batch under 10GB" {
            Test-WinOpsSizeGuard -Size 5GB -IsBatch | Should -Be $true
        }

        It "Allows batch at 10GB exactly" {
            Test-WinOpsSizeGuard -Size 10GB -IsBatch | Should -Be $true
        }

        It "Rejects batch over 10GB" {
            Test-WinOpsSizeGuard -Size (10GB + 1) -IsBatch | Should -Be $false
        }
    }

    Context "Safety levels adjust limits" {
        It "Permissive mode doubles single file limit" {
            Test-WinOpsSizeGuard -Size (3GB) -Level Permissive | Should -Be $true
        }

        It "Permissive mode doubles batch limit" {
            Test-WinOpsSizeGuard -Size (15GB) -IsBatch -Level Permissive | Should -Be $true
        }

        It "Strict mode halves single file limit" {
            Test-WinOpsSizeGuard -Size (1.5GB) -Level Strict | Should -Be $false
        }

        It "Strict mode halves batch limit" {
            Test-WinOpsSizeGuard -Size (6GB) -IsBatch -Level Strict | Should -Be $false
        }
    }

    Context "Edge cases" {
        It "Allows zero size" {
            Test-WinOpsSizeGuard -Size 0 | Should -Be $true
        }

        It "Throws on negative size" {
            { Test-WinOpsSizeGuard -Size -1 } | Should -Throw
        }
    }
}

Describe "Test-WinOpsSystemPath" {
    Context "WRP protected paths" {
        It "Detects System32 as WRP" {
            Test-WinOpsSystemPath -Path "C:\Windows\System32\kernel32.dll" | Should -Be $true
        }

        It "Detects SysWOW64 as WRP" {
            Test-WinOpsSystemPath -Path "C:\Windows\SysWOW64\test.dll" | Should -Be $true
        }

        It "Detects WinSxS as WRP" {
            Test-WinOpsSystemPath -Path "C:\Windows\WinSxS\test" | Should -Be $true
        }

        It "Detects Windows Defender as WRP" {
            Test-WinOpsSystemPath -Path "C:\Program Files\Windows Defender\MpClient.dll" | Should -Be $true
        }
    }

    Context "Non-WRP paths" {
        It "Does not detect C:\Temp as WRP" {
            Test-WinOpsSystemPath -Path "C:\Temp\file.txt" | Should -Be $false
        }

        It "Does not detect C:\Windows (root) as WRP" {
            Test-WinOpsSystemPath -Path "C:\Windows\test.txt" | Should -Be $false
        }

        It "Does not detect Program Files (non-Defender) as WRP" {
            Test-WinOpsSystemPath -Path "C:\Program Files\MyApp\file.exe" | Should -Be $false
        }
    }

    Context "Error handling" {
        It "Throws on null path" {
            { Test-WinOpsSystemPath -Path $null } | Should -Throw
        }

        It "Throws on empty path" {
            { Test-WinOpsSystemPath -Path "" } | Should -Throw
        }

        It "Treats unresolvable paths as WRP (fail-safe)" {
            $result = Test-WinOpsSystemPath -Path "::invalid::" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $result | Should -Be $true
        }
    }
}

Describe "Assert-WinOpsSafeOperation" {
    Context "Path validation" {
        It "Passes for safe paths" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Temp\test.txt"
            $result.OverallSafe | Should -Be $true
            $result.PathSafe | Should -Be $true
        }

        It "Fails for protected paths" {
            { Assert-WinOpsSafeOperation -Path "C:\Windows\test.txt" } | Should -Throw
        }

        It "Returns detailed errors in DryRun mode" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Windows\test.txt" -DryRun
            $result.OverallSafe | Should -Be $false
            $result.PathSafe | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context "Process validation" {
        It "Passes for non-protected processes" {
            $result = Assert-WinOpsSafeOperation -ProcessName "notepad"
            $result.OverallSafe | Should -Be $true
            $result.ProcessSafe | Should -Be $true
        }

        It "Fails for protected processes" {
            { Assert-WinOpsSafeOperation -ProcessName "csrss" } | Should -Throw
        }

        It "Returns detailed errors in DryRun mode" {
            $result = Assert-WinOpsSafeOperation -ProcessName "lsass" -DryRun
            $result.OverallSafe | Should -Be $false
            $result.ProcessSafe | Should -Be $false
            $result.Errors | Should -Contain "Process is protected: lsass"
        }
    }

    Context "Size validation" {
        It "Passes for acceptable sizes" {
            $result = Assert-WinOpsSafeOperation -Size 100MB
            $result.OverallSafe | Should -Be $true
            $result.SizeSafe | Should -Be $true
        }

        It "Fails for excessive sizes" {
            { Assert-WinOpsSafeOperation -Size (3GB) } | Should -Throw
        }

        It "Uses batch limits when specified" {
            $result = Assert-WinOpsSafeOperation -Size 5GB -IsBatch
            $result.OverallSafe | Should -Be $true
            $result.SizeSafe | Should -Be $true
        }
    }

    Context "Combined validation" {
        It "Passes when all checks succeed" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Temp\file.txt" -Size 100MB
            $result.OverallSafe | Should -Be $true
            $result.PathSafe | Should -Be $true
            $result.SizeSafe | Should -Be $true
        }

        It "Fails when any check fails" {
            { Assert-WinOpsSafeOperation -Path "C:\Windows\test.txt" -Size 100MB } | Should -Throw
        }

        It "Reports all failures in DryRun mode" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Windows\test.txt" -ProcessName "csrss" -Size (3GB) -DryRun
            $result.OverallSafe | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 2
        }
    }

    Context "WRP detection and warnings" {
        It "Warns about WRP paths in Normal mode" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Windows\System32\test.dll" -DryRun -Level Normal
            $result.Warnings | Should -Not -BeNullOrEmpty
        }

        It "Fails on WRP paths in Strict mode" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Windows\System32\test.dll" -DryRun -Level Strict
            $result.OverallSafe | Should -Be $false
        }
    }

    Context "Safety levels" {
        It "Permissive mode allows more operations" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Program Files\test.exe" -Level Permissive
            $result.OverallSafe | Should -Be $true
        }

        It "Strict mode is more restrictive" {
            { Assert-WinOpsSafeOperation -Size 1.5GB -Level Strict } | Should -Throw
        }
    }

    Context "DryRun mode" {
        It "Never throws, always returns results" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Windows\test.txt" -ProcessName "csrss" -Size (3GB) -DryRun
            $result | Should -Not -BeNullOrEmpty
            $result.OverallSafe | Should -Be $false
        }

        It "Includes all check results" {
            $result = Assert-WinOpsSafeOperation -Path "C:\Temp\file.txt" -ProcessName "notepad" -Size 100MB -DryRun
            $result.PSObject.Properties.Name | Should -Contain 'PathSafe'
            $result.PSObject.Properties.Name | Should -Contain 'ProcessSafe'
            $result.PSObject.Properties.Name | Should -Contain 'SizeSafe'
            $result.PSObject.Properties.Name | Should -Contain 'NotWRP'
            $result.PSObject.Properties.Name | Should -Contain 'OverallSafe'
        }
    }
}
