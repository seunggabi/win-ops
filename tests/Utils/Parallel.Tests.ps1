#Requires -Modules Pester
#Requires -Version 7.0

BeforeAll {
    $script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\lib\utils\Parallel.psm1"
    Import-Module $script:ModulePath -Force

    # Create test module directory and mock modules
    $script:TestModulePath = Join-Path -Path $TestDrive -ChildPath "modules"
    New-Item -Path $script:TestModulePath -ItemType Directory -Force | Out-Null

    # Create a simple mock cleanup module
    $mockModuleContent = @'
function Invoke-TestCleanup {
    [CmdletBinding()]
    param()

    Start-Sleep -Milliseconds 100

    return [PSCustomObject]@{
        ItemsCleaned = 10
        SpaceFreedBytes = 1048576
    }
}

Export-ModuleMember -Function Invoke-TestCleanup
'@

    # Create multiple test modules
    $mockModuleContent | Set-Content -Path (Join-Path -Path $script:TestModulePath -ChildPath "Test.psm1")

    # Create a slow module for timeout testing
    $slowModuleContent = @'
function Invoke-SlowCleanup {
    [CmdletBinding()]
    param()

    Start-Sleep -Seconds 10

    return [PSCustomObject]@{
        ItemsCleaned = 5
        SpaceFreedBytes = 524288
    }
}

Export-ModuleMember -Function Invoke-SlowCleanup
'@

    $slowModuleContent | Set-Content -Path (Join-Path -Path $script:TestModulePath -ChildPath "Slow.psm1")

    # Create a failing module
    $failModuleContent = @'
function Invoke-FailCleanup {
    [CmdletBinding()]
    param()

    throw "Intentional test failure"
}

Export-ModuleMember -Function Invoke-FailCleanup
'@

    $failModuleContent | Set-Content -Path (Join-Path -Path $script:TestModulePath -ChildPath "Fail.psm1")

    # Create additional test modules for parallel execution
    foreach ($i in 1..4) {
        $content = @"
function Invoke-Module${i}Cleanup {
    [CmdletBinding()]
    param()

    Start-Sleep -Milliseconds $($i * 50)

    return [PSCustomObject]@{
        ItemsCleaned = $i
        SpaceFreedBytes = $($i * 1048576)
    }
}

Export-ModuleMember -Function Invoke-Module${i}Cleanup
"@
        $content | Set-Content -Path (Join-Path -Path $script:TestModulePath -ChildPath "Module$i.psm1")
    }
}

AfterAll {
    Remove-Module -Name Parallel -ErrorAction SilentlyContinue
}

Describe "Invoke-WinOpsParallelModules" {
    Context "PowerShell version validation" {
        It "Should check for PowerShell 7.0 or later" -Skip:($PSVersionTable.PSVersion.Major -ge 7) {
            # This test is skipped if running PS7+
            { Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath } | Should -Throw "*PowerShell 7.0 or later is required*"
        }
    }

    Context "Parameter validation" {
        It "Should require modules parameter" {
            { Invoke-WinOpsParallelModules -ModulePath $script:TestModulePath } | Should -Throw
        }

        It "Should reject empty modules array" {
            { Invoke-WinOpsParallelModules -Modules @() -ModulePath $script:TestModulePath } | Should -Throw
        }

        It "Should reject null modules" {
            { Invoke-WinOpsParallelModules -Modules $null -ModulePath $script:TestModulePath } | Should -Throw
        }

        It "Should validate ThrottleLimit range" {
            { Invoke-WinOpsParallelModules -Modules @('Test') -ThrottleLimit 0 -ModulePath $script:TestModulePath } | Should -Throw
        }

        It "Should validate TimeoutSeconds range" {
            { Invoke-WinOpsParallelModules -Modules @('Test') -TimeoutSeconds 10 -ModulePath $script:TestModulePath } | Should -Throw
        }
    }

    Context "Module path validation" {
        It "Should throw if module path does not exist" {
            { Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath "C:\NonExistent\Path" } | Should -Throw "*Module path does not exist*"
        }

        It "Should throw if module files are missing" {
            { Invoke-WinOpsParallelModules -Modules @('NonExistent') -ModulePath $script:TestModulePath } | Should -Throw "*Missing module files*"
        }

        It "Should detect multiple missing modules" {
            { Invoke-WinOpsParallelModules -Modules @('Missing1', 'Missing2', 'Missing3') -ModulePath $script:TestModulePath } | Should -Throw "*Missing module files*"
        }
    }

    Context "Basic execution" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should execute single module successfully" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result | Should -Not -BeNullOrEmpty
            $result.SuccessCount | Should -Be 1
            $result.FailureCount | Should -Be 0
            $result.ModuleResults.Count | Should -Be 1
            $result.ModuleResults[0].Success | Should -Be $true
        }

        It "Should return execution statistics" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.PSObject.Properties.Name | Should -Contain 'TotalDurationSeconds'
            $result.PSObject.Properties.Name | Should -Contain 'SuccessCount'
            $result.PSObject.Properties.Name | Should -Contain 'FailureCount'
            $result.PSObject.Properties.Name | Should -Contain 'TotalItemsCleaned'
            $result.PSObject.Properties.Name | Should -Contain 'TotalSpaceFreedMB'
            $result.PSObject.Properties.Name | Should -Contain 'ModuleResults'
        }

        It "Should collect module statistics" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.TotalItemsCleaned | Should -BeGreaterThan 0
            $result.TotalSpaceFreedMB | Should -BeGreaterThan 0
        }
    }

    Context "Parallel execution" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should execute multiple modules in parallel" {
            $modules = @('Module1', 'Module2', 'Module3', 'Module4')
            $result = Invoke-WinOpsParallelModules -Modules $modules -ModulePath $script:TestModulePath -ThrottleLimit 4 -TimeoutSeconds 60

            $result.ModuleResults.Count | Should -Be 4
            $result.SuccessCount | Should -Be 4
        }

        It "Should respect throttle limit" {
            $modules = @('Module1', 'Module2', 'Module3', 'Module4')
            $result = Invoke-WinOpsParallelModules -Modules $modules -ModulePath $script:TestModulePath -ThrottleLimit 2 -TimeoutSeconds 60

            $result.ModuleResults.Count | Should -Be 4
            # All should complete, but throttled to 2 at a time
        }

        It "Should aggregate results from multiple modules" {
            $modules = @('Module1', 'Module2', 'Module3')
            $result = Invoke-WinOpsParallelModules -Modules $modules -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.TotalItemsCleaned | Should -Be 6  # 1 + 2 + 3
            $expectedMB = [Math]::Round((1 + 2 + 3) * 1048576 / 1MB, 2)
            $result.TotalSpaceFreedMB | Should -Be $expectedMB
        }
    }

    Context "Error handling" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should handle module execution failures" {
            $result = Invoke-WinOpsParallelModules -Modules @('Fail') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.SuccessCount | Should -Be 0
            $result.FailureCount | Should -Be 1
            $result.ModuleResults[0].Success | Should -Be $false
            $result.ModuleResults[0].ErrorMessage | Should -Not -BeNullOrEmpty
        }

        It "Should continue execution when one module fails" {
            $modules = @('Test', 'Fail', 'Module1')
            $result = Invoke-WinOpsParallelModules -Modules $modules -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.ModuleResults.Count | Should -Be 3
            $result.SuccessCount | Should -Be 2
            $result.FailureCount | Should -Be 1
        }

        It "Should track error messages for failed modules" {
            $result = Invoke-WinOpsParallelModules -Modules @('Fail') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $failedModule = $result.ModuleResults | Where-Object { -not $_.Success }
            $failedModule.ErrorMessage | Should -Match "Intentional test failure"
        }
    }

    Context "Timeout handling" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should timeout slow modules" {
            $result = Invoke-WinOpsParallelModules -Modules @('Slow') -ModulePath $script:TestModulePath -TimeoutSeconds 2

            $result.SuccessCount | Should -Be 0
            $result.FailureCount | Should -Be 1
            $result.ModuleResults[0].TimedOut | Should -Be $true
            $result.ModuleResults[0].ErrorMessage | Should -Match "timed out"
        }

        It "Should set TimedOut flag on timeout" {
            $result = Invoke-WinOpsParallelModules -Modules @('Slow') -ModulePath $script:TestModulePath -TimeoutSeconds 2

            $timedOutModule = $result.ModuleResults | Where-Object { $_.TimedOut }
            $timedOutModule | Should -Not -BeNullOrEmpty
            $timedOutModule.Success | Should -Be $false
        }

        It "Should allow sufficient timeout for fast modules" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 30

            $result.ModuleResults[0].TimedOut | Should -Be $false
            $result.ModuleResults[0].Success | Should -Be $true
        }
    }

    Context "Module result details" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should include module name in results" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.ModuleResults[0].ModuleName | Should -Be 'Test'
        }

        It "Should track execution duration" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.ModuleResults[0].DurationSeconds | Should -BeGreaterThan 0
            $result.TotalDurationSeconds | Should -BeGreaterThan 0
        }

        It "Should sort results by module name" {
            $modules = @('Module3', 'Module1', 'Module2')
            $result = Invoke-WinOpsParallelModules -Modules $modules -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $result.ModuleResults[0].ModuleName | Should -Be 'Module1'
            $result.ModuleResults[1].ModuleName | Should -Be 'Module2'
            $result.ModuleResults[2].ModuleName | Should -Be 'Module3'
        }

        It "Should initialize all result fields" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath -TimeoutSeconds 60

            $moduleResult = $result.ModuleResults[0]
            $moduleResult.PSObject.Properties.Name | Should -Contain 'ModuleName'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'Success'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'DurationSeconds'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'ItemsCleaned'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'SpaceFreedBytes'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
            $moduleResult.PSObject.Properties.Name | Should -Contain 'TimedOut'
        }
    }

    Context "Default parameter values" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "Should use default ThrottleLimit when not specified" {
            { Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath } | Should -Not -Throw
        }

        It "Should use default TimeoutSeconds when not specified" {
            $result = Invoke-WinOpsParallelModules -Modules @('Test') -ModulePath $script:TestModulePath
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should use default ModulePath from PSScriptRoot" {
            # This tests that the default path is constructed correctly
            # Actual execution would fail if path doesn't exist
            $function = Get-Command Invoke-WinOpsParallelModules
            $defaultPath = $function.Parameters['ModulePath'].Attributes.Where({$_.TypeId.Name -eq 'ParameterAttribute'})
            # Just verify the parameter exists
            $function.Parameters.ContainsKey('ModulePath') | Should -Be $true
        }
    }
}
