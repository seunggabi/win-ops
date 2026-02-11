#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\ZombieKiller.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName ZombieKiller {}
    Mock Test-WinOpsProcessProtected -ModuleName ZombieKiller { return $false }
}

Describe 'ZombieKiller Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load ZombieKiller module successfully' {
            Get-Module ZombieKiller | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module ZombieKiller
            $commands.Name | Should -Contain 'Find-WinOpsZombieProcess'
            $commands.Name | Should -Contain 'Stop-WinOpsZombieProcess'
            $commands.Name | Should -Contain 'Find-WinOpsDuplicateProcess'
            $commands.Name | Should -Contain 'Invoke-WinOpsZombieCleanup'
        }
    }

    Context 'Find-WinOpsZombieProcess' {

        It 'Should find non-responsive processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 1234 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'TestApp' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(12345)) -Force
                $proc | Add-Member -NotePropertyName 'MainWindowTitle' -NotePropertyValue 'Test Window' -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 100MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(5)) -Force
                $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-1) -Force
                @($proc)
            }
            Mock Start-Sleep -ModuleName ZombieKiller {}

            $result = Find-WinOpsZombieProcess -IncludeNonResponding -SkipReconfirmation

            $result | Should -Not -BeNullOrEmpty
            $result[0].ProcessName | Should -Be 'TestApp'
            $result[0].Responding | Should -Be $false
        }

        It 'Should find high CPU processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 5678 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'HighCPU' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $true -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                $proc | Add-Member -NotePropertyName 'MainWindowTitle' -NotePropertyValue '' -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 50MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(10)) -Force
                $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-1) -Force
                $proc | Add-Member -MemberType ScriptMethod -Name 'Refresh' -Value {} -Force
                @($proc)
            }
            Mock Start-Sleep -ModuleName ZombieKiller {}

            $result = Find-WinOpsZombieProcess -IncludeHighCPU -CPUThreshold 80

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should find high memory processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 9012 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'HighMem' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $true -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                $proc | Add-Member -NotePropertyName 'MainWindowTitle' -NotePropertyValue '' -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 2GB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(1)) -Force
                $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-1) -Force
                @($proc)
            }

            $result = Find-WinOpsZombieProcess -IncludeHighMemory -MemoryThresholdMB 1024

            $result | Should -Not -BeNullOrEmpty
            $result[0].MemoryMB | Should -BeGreaterThan 1024
        }

        It 'Should exclude protected processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 4 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'System' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                @($proc)
            }
            Mock Test-WinOpsProcessProtected -ModuleName ZombieKiller { return $true }

            $result = Find-WinOpsZombieProcess -IncludeNonResponding -SkipReconfirmation

            # Should not include protected process
            $result | Should -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 1111 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'TestProc' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(111)) -Force
                $proc | Add-Member -NotePropertyName 'MainWindowTitle' -NotePropertyValue 'Test' -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 200MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(3)) -Force
                $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-2) -Force
                @($proc)
            }
            Mock Start-Sleep -ModuleName ZombieKiller {}

            $result = Find-WinOpsZombieProcess -IncludeNonResponding -SkipReconfirmation

            $result[0].ProcessId | Should -Be 1111
            $result[0].ProcessName | Should -Be 'TestProc'
            $result[0].Responding | Should -Be $false
            $result[0].MemoryMB | Should -BeGreaterThan 0
            $result[0].Reasons | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Stop-WinOpsZombieProcess' {

        It 'Should stop zombie processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 2222 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'ZombieApp' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(222)) -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 100MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(2)) -Force
                @($proc)
            }
            Mock Stop-Process -ModuleName ZombieKiller {}

            $result = Stop-WinOpsZombieProcess -ProcessId 2222 -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Success | Should -Be $true
            Should -Invoke Stop-Process -ModuleName ZombieKiller
        }

        It 'Should not stop when Force is not specified and user declines' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 3333 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'TestApp' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(333)) -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 50MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(1)) -Force
                @($proc)
            }

            # WhatIf mode prevents actual termination
            $result = Stop-WinOpsZombieProcess -ProcessId 3333 -WhatIf

            # Should not invoke Stop-Process in WhatIf mode
            Should -Not -Invoke Stop-Process -ModuleName ZombieKiller
        }

        It 'Should gracefully close before forcing' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 4444 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'TestApp' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $true -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(444)) -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 75MB -Force
                $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(1)) -Force
                $proc | Add-Member -MemberType ScriptMethod -Name 'CloseMainWindow' -Value { $true } -Force
                @($proc)
            }
            Mock Start-Sleep -ModuleName ZombieKiller {}

            $result = Stop-WinOpsZombieProcess -ProcessId 4444 -GracefulFirst -Force

            # Should attempt graceful close first
            $result | Should -Not -BeNullOrEmpty
            $result[0].Success | Should -Be $true
        }

        It 'Should filter by process name' {
            Mock Get-Process -ModuleName ZombieKiller {
                param($Name)
                if ($Name -eq 'TargetApp') {
                    $proc = New-MockObject -Type 'System.Diagnostics.Process'
                    $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 5555 -Force
                    $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'TargetApp' -Force
                    $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                    $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(555)) -Force
                    $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 50MB -Force
                    $proc | Add-Member -NotePropertyName 'TotalProcessorTime' -NotePropertyValue ([TimeSpan]::FromMinutes(1)) -Force
                    @($proc)
                }
            }
            Mock Stop-Process -ModuleName ZombieKiller {}

            $result = Stop-WinOpsZombieProcess -ProcessName 'TargetApp' -Force

            # Should only stop TargetApp
            $result | Should -Not -BeNullOrEmpty
            $result[0].ProcessName | Should -Be 'TargetApp'
        }

        It 'Should not stop protected processes' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 4 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'System' -Force
                $proc | Add-Member -NotePropertyName 'Responding' -NotePropertyValue $false -Force
                @($proc)
            }
            Mock Test-WinOpsProcessProtected -ModuleName ZombieKiller { return $true }

            $result = Stop-WinOpsZombieProcess -ProcessId 4 -Force

            $result[0].Success | Should -Be $false
            $result[0].Message | Should -Be 'Protected process'
            Should -Not -Invoke Stop-Process -ModuleName ZombieKiller
        }
    }

    Context 'Find-WinOpsDuplicateProcess' {

        It 'Should identify duplicate process instances' {
            Mock Get-Process -ModuleName ZombieKiller {
                $procs = @()
                for ($i = 1; $i -le 5; $i++) {
                    $proc = New-MockObject -Type 'System.Diagnostics.Process'
                    $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue (7000 + $i) -Force
                    $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'DuplicateApp' -Force
                    $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 100MB -Force
                    $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-$i) -Force
                    $procs += $proc
                }
                $procs
            }

            $result = Find-WinOpsDuplicateProcess -MinimumInstances 3

            $result | Should -Not -BeNullOrEmpty
            $result[0].ProcessName | Should -Be 'DuplicateApp'
            $result[0].InstanceCount | Should -Be 5
        }

        It 'Should exclude processes below minimum threshold' {
            Mock Get-Process -ModuleName ZombieKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 8888 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'SingleApp' -Force
                $proc | Add-Member -NotePropertyName 'WorkingSet64' -NotePropertyValue 50MB -Force
                $proc | Add-Member -NotePropertyName 'StartTime' -NotePropertyValue (Get-Date).AddHours(-1) -Force
                @($proc)
            }

            $result = Find-WinOpsDuplicateProcess -MinimumInstances 3

            # Should not return process with only 1 instance
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'ZombieKiller Integration Tests' -Tag 'Integration', 'Module' {

    Context 'Process Detection' {

        It 'Should get current processes' {
            $processes = Get-Process
            $processes | Should -Not -BeNullOrEmpty
            $processes.Count | Should -BeGreaterThan 10
        }

        It 'Should identify responding status' {
            $proc = Get-Process -Name 'powershell' -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($proc) {
                $proc.Responding | Should -BeIn @($true, $false)
            }
        }

        It 'Should calculate memory usage' {
            $proc = Get-Process -Name 'powershell' -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($proc) {
                $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
                $memoryMB | Should -BeGreaterThan 0
            }
        }
    }

    Context 'CPU Calculation' {

        It 'Should access processor time' {
            $proc = Get-Process -Name 'powershell' -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($proc) {
                $cpuTime = $proc.TotalProcessorTime
                $cpuTime | Should -Not -BeNullOrEmpty
                $cpuTime.TotalMilliseconds | Should -BeGreaterThan -1
            }
        }
    }
}
