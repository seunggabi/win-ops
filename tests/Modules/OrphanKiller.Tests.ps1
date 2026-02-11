#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\OrphanKiller.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName OrphanKiller {}
    Mock Test-WinOpsProcessProtected -ModuleName OrphanKiller { return $false }
}

Describe 'OrphanKiller Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load OrphanKiller module successfully' {
            Get-Module OrphanKiller | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module OrphanKiller
            $commands.Name | Should -Contain 'Find-WinOpsOrphanedProcess'
            $commands.Name | Should -Contain 'Stop-WinOpsOrphanedProcess'
            $commands.Name | Should -Contain 'Invoke-WinOpsOrphanCleanup'
            $commands.Name | Should -Contain 'Get-WinOpsProcessTree'
        }
    }

    Context 'Find-WinOpsOrphanedProcess' {

        It 'Should find processes without parent' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 1234
                        Name = 'orphan.exe'
                        ParentProcessId = 9999
                        CommandLine = 'orphan.exe'
                        CreationDate = (Get-Date).AddDays(-2)
                        WorkingSetSize = 100MB
                        HandleCount = 50
                    }
                    [PSCustomObject]@{
                        ProcessId = 9999
                        Name = 'System'
                        ParentProcessId = 0
                        CommandLine = $null
                        CreationDate = (Get-Date).AddDays(-30)
                        WorkingSetSize = 50MB
                        HandleCount = 1000
                    }
                )
            }
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                @($proc)
            }

            $result = Find-WinOpsOrphanedProcess -MinimumAgeMinutes 60

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should identify processes with terminated parents' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 5678
                        Name = 'child.exe'
                        ParentProcessId = 1111
                        CommandLine = 'child.exe'
                        CreationDate = (Get-Date).AddDays(-2)
                        WorkingSetSize = 75MB
                        HandleCount = 25
                    }
                )
            }
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                @($proc)
            }

            $result = Find-WinOpsOrphanedProcess -MinimumAgeMinutes 60

            # Parent process 1111 doesn't exist
            $result | Should -Not -BeNullOrEmpty
            $result[0].ProcessId | Should -Be 5678
            $result[0].ParentExists | Should -Be $false
        }

        It 'Should exclude system processes' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 0
                        Name = 'System'
                        ParentProcessId = 0
                        CommandLine = $null
                        CreationDate = (Get-Date).AddDays(-30)
                        WorkingSetSize = 10MB
                        HandleCount = 5000
                    }
                    [PSCustomObject]@{
                        ProcessId = 4
                        Name = 'System'
                        ParentProcessId = 0
                        CommandLine = $null
                        CreationDate = (Get-Date).AddDays(-30)
                        WorkingSetSize = 5MB
                        HandleCount = 3000
                    }
                )
            }

            $result = Find-WinOpsOrphanedProcess

            # Should not include system processes
            $result | Should -BeNullOrEmpty
        }

        It 'Should exclude protected processes' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 100
                        Name = 'csrss.exe'
                        ParentProcessId = 9999
                        CommandLine = 'csrss.exe'
                        CreationDate = (Get-Date).AddDays(-2)
                        WorkingSetSize = 20MB
                        HandleCount = 500
                    }
                )
            }
            Mock Test-WinOpsProcessProtected -ModuleName OrphanKiller { return $true }
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                @($proc)
            }

            $result = Find-WinOpsOrphanedProcess -MinimumAgeMinutes 60

            # Should not include protected processes
            $result | Should -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 2000
                        Name = 'orphan.exe'
                        ParentProcessId = 8888
                        CommandLine = 'orphan.exe --arg'
                        CreationDate = (Get-Date).AddDays(-2)
                        WorkingSetSize = 150MB
                        HandleCount = 100
                    }
                )
            }
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::Zero) -Force
                @($proc)
            }

            $result = Find-WinOpsOrphanedProcess -MinimumAgeMinutes 60

            $result[0].ProcessId | Should -Be 2000
            $result[0].ProcessName | Should -Be 'orphan.exe'
            $result[0].ParentProcessId | Should -Be 8888
            $result[0].ParentExists | Should -Be $false
            $result[0].CommandLine | Should -Not -BeNullOrEmpty
            $result[0].MemoryMB | Should -BeGreaterThan 0
        }
    }

    Context 'Stop-WinOpsOrphanedProcess' {

        It 'Should stop orphaned processes' {
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 3000 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'orphan' -Force
                @($proc)
            }
            Mock Stop-Process -ModuleName OrphanKiller {}

            $result = Stop-WinOpsOrphanedProcess -ProcessId 3000 -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Success | Should -Be $true
            Should -Invoke Stop-Process -ModuleName OrphanKiller
        }

        It 'Should not stop when using WhatIf mode' {
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 4000 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'orphan' -Force
                @($proc)
            }

            $result = Stop-WinOpsOrphanedProcess -ProcessId 4000 -WhatIf

            # Should not invoke Stop-Process in WhatIf mode
            Should -Not -Invoke Stop-Process -ModuleName OrphanKiller
        }

        It 'Should support graceful shutdown first' {
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 5000 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'orphan' -Force
                $proc | Add-Member -NotePropertyName 'MainWindowHandle' -NotePropertyValue ([IntPtr]::new(5000)) -Force
                $proc | Add-Member -MemberType ScriptMethod -Name 'CloseMainWindow' -Value { $true } -Force
                @($proc)
            }
            Mock Start-Sleep -ModuleName OrphanKiller {}
            Mock Stop-Process -ModuleName OrphanKiller {}

            $result = Stop-WinOpsOrphanedProcess -ProcessId 5000 -GracefulFirst -Force

            # Should attempt graceful close
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should not stop protected processes' {
            Mock Get-Process -ModuleName OrphanKiller {
                $proc = New-MockObject -Type 'System.Diagnostics.Process'
                $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 6000 -Force
                $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'lsass' -Force
                @($proc)
            }
            Mock Test-WinOpsProcessProtected -ModuleName OrphanKiller { return $true }

            $result = Stop-WinOpsOrphanedProcess -ProcessId 6000 -Force

            $result[0].Success | Should -Be $false
            $result[0].Message | Should -Be 'Protected process'
            Should -Not -Invoke Stop-Process -ModuleName OrphanKiller
        }

        It 'Should filter by process name' {
            Mock Get-Process -ModuleName OrphanKiller {
                param($Name)
                if ($Name -eq 'target') {
                    $proc = New-MockObject -Type 'System.Diagnostics.Process'
                    $proc | Add-Member -NotePropertyName 'Id' -NotePropertyValue 7000 -Force
                    $proc | Add-Member -NotePropertyName 'ProcessName' -NotePropertyValue 'target' -Force
                    @($proc)
                }
            }
            Mock Stop-Process -ModuleName OrphanKiller {}

            $result = Stop-WinOpsOrphanedProcess -ProcessName 'target' -Force

            # Should only stop target
            $result | Should -Not -BeNullOrEmpty
            $result[0].ProcessName | Should -Be 'target'
        }
    }

    Context 'Get-WinOpsProcessTree' {

        It 'Should build process parent-child tree' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 1000
                        Name = 'parent.exe'
                        ParentProcessId = 0
                        CommandLine = 'parent.exe'
                        CreationDate = (Get-Date).AddHours(-5)
                        WorkingSetSize = 100MB
                        HandleCount = 50
                    }
                    [PSCustomObject]@{
                        ProcessId = 2000
                        Name = 'child.exe'
                        ParentProcessId = 1000
                        CommandLine = 'child.exe'
                        CreationDate = (Get-Date).AddHours(-4)
                        WorkingSetSize = 50MB
                        HandleCount = 25
                    }
                )
            }

            $result = Get-WinOpsProcessTree

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Should identify parent-child relationships' {
            Mock Get-CimInstance -ModuleName OrphanKiller {
                @(
                    [PSCustomObject]@{
                        ProcessId = 100
                        Name = 'parent.exe'
                        ParentProcessId = 0
                        CommandLine = 'parent.exe'
                        CreationDate = (Get-Date).AddHours(-2)
                        WorkingSetSize = 80MB
                        HandleCount = 40
                    }
                    [PSCustomObject]@{
                        ProcessId = 200
                        Name = 'child.exe'
                        ParentProcessId = 100
                        CommandLine = 'child.exe'
                        CreationDate = (Get-Date).AddHours(-1)
                        WorkingSetSize = 40MB
                        HandleCount = 20
                    }
                )
            }

            $result = Get-WinOpsProcessTree

            $child = $result | Where-Object { $_.ProcessId -eq 200 }
            $child.ParentProcessId | Should -Be 100
            $child.ParentExists | Should -Be $true
        }
    }
}

Describe 'OrphanKiller Integration Tests' -Tag 'Integration', 'Module' {

    Context 'Process Parent Detection' {

        It 'Should query process parent information via WMI' {
            $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
                Select-Object -First 5

            $processes | Should -Not -BeNullOrEmpty
            $processes[0].ProcessId | Should -BeGreaterThan 0
            $processes[0].ParentProcessId | Should -BeGreaterThan -1
        }

        It 'Should detect current PowerShell parent' {
            $currentPid = $PID
            $currentProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $currentPid"

            $currentProcess | Should -Not -BeNullOrEmpty
            $currentProcess.ParentProcessId | Should -BeGreaterThan 0
        }

        It 'Should identify orphaned processes in real system' {
            $allProcesses = Get-CimInstance -ClassName Win32_Process

            $processMap = @{}
            foreach ($proc in $allProcesses) {
                $processMap[$proc.ProcessId] = $proc
            }

            $orphans = $allProcesses | Where-Object {
                $_.ParentProcessId -ne 0 -and
                -not $processMap.ContainsKey($_.ParentProcessId) -and
                $_.ProcessId -notin @(0, 4)
            }

            # May or may not have orphans, but should complete without error
            $orphans | Should -BeOfType [Object]
        }
    }

    Context 'Process Age Calculation' {

        It 'Should calculate process runtime' {
            $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $PID"

            if ($proc.CreationDate) {
                $age = (Get-Date) - $proc.CreationDate
                $age.TotalMinutes | Should -BeGreaterThan 0
            }
        }
    }
}
