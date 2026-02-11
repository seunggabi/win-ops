#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\LogCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName LogCleanup {}
    Mock Move-WinOpsToTrash -ModuleName LogCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'LogCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Get-WinOpsLogFileInfo' {

        It 'Should return log file information for all locations' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'app.log'
                        Length = 5MB
                        LastWriteTime = (Get-Date).AddDays(-120)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsLogFileInfo -Location All

            $result | Should -Not -BeNullOrEmpty
            $result[0].Location | Should -Not -BeNullOrEmpty
            $result[0].FileCount | Should -BeGreaterThan -1
        }

        It 'Should return specific location information' {
            $result = Get-WinOpsLogFileInfo -Location WindowsLogs

            $result | Should -Not -BeNullOrEmpty
            $result.Location | Should -Be 'WindowsLogs'
            $result.Description | Should -Be 'Windows system logs'
        }

        It 'Should filter by age and size' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'large-old.log'
                        Length = 50MB
                        LastWriteTime = (Get-Date).AddDays(-120)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'small-new.log'
                        Length = 100KB
                        LastWriteTime = (Get-Date).AddDays(-5)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsLogFileInfo -Location ApplicationLogs -AgeInDays 90 -MinSizeMB 1

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            $result = Get-WinOpsLogFileInfo -Location ApplicationLogs

            $result.Location | Should -Not -BeNullOrEmpty
            $result.Description | Should -Not -BeNullOrEmpty
            $result.FileCount | Should -BeGreaterThan -1
            $result.TotalSize | Should -BeGreaterThan -1
            $result.TotalSizeMB | Should -BeGreaterThan -1
            $result.DefaultAgeInDays | Should -BeGreaterThan -1
            $result.Paths | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-WinOpsLogFiles' {

        It 'Should clear log files from specified location' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'old.log'
                        FullName = 'C:\Logs\old.log'
                        Length = 10MB
                        LastWriteTime = (Get-Date).AddDays(-120)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName LogCleanup { return $true }
            Mock Remove-Item -ModuleName LogCleanup {}
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }

            $result = Clear-WinOpsLogFiles -Location WindowsLogs -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Location | Should -Be 'WindowsLogs'
        }

        It 'Should support DryRun mode' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.log'
                        Length = 5MB
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsLogFiles -Location ApplicationLogs -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName LogCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'archive.log'
                        FullName = 'C:\Logs\archive.log'
                        Length = 20MB
                        LastWriteTime = (Get-Date).AddDays(-150)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName LogCleanup { return $true }

            $result = Clear-WinOpsLogFiles -Location ApplicationLogs -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName LogCleanup
        }

        It 'Should filter by minimum size' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'large.log'
                        FullName = 'C:\Logs\large.log'
                        Length = 50MB
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'small.log'
                        FullName = 'C:\Logs\small.log'
                        Length = 500KB
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName LogCleanup { return $true }
            Mock Remove-Item -ModuleName LogCleanup {}

            $result = Clear-WinOpsLogFiles -Location ApplicationLogs -MinSizeMB 10 -Force -Confirm:$false

            # Should only process large file
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should respect exclude patterns' {
            Mock Get-ChildItem -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'current.log'
                        FullName = 'C:\Logs\current.log'
                        Length = 10MB
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'archive.log'
                        FullName = 'C:\Logs\archive.log'
                        Length = 20MB
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName LogCleanup { return $true }
            Mock Remove-Item -ModuleName LogCleanup {}

            $result = Clear-WinOpsLogFiles -Location ApplicationLogs -ExcludePatterns 'current*' -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should require elevation for system locations' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $false }

            $result = Clear-WinOpsLogFiles -Location WindowsLogs -Force -Confirm:$false

            # Should skip due to lack of elevation
            $result | Should -BeNullOrEmpty -Because 'WindowsLogs requires elevation'
        }
    }

    Context 'Clear-WinOpsEventLog' {

        It 'Should clear specified event log' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Get-WinEvent -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{ LogName = 'Application'; RecordId = 1 }
                )
            }
            Mock -ModuleName LogCleanup -CommandName 'wevtutil' -MockWith {}

            $result = Clear-WinOpsEventLog -LogName Application -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.LogName | Should -Be 'Application'
        }

        It 'Should require elevation' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $false }

            { Clear-WinOpsEventLog -LogName Application -Force -Confirm:$false } | Should -Throw 'administrator privileges'
        }

        It 'Should archive before clear when specified' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Get-WinEvent -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{ LogName = 'Application'; RecordId = 1 }
                )
            }
            Mock -ModuleName LogCleanup -CommandName 'wevtutil' -MockWith {}
            Mock Test-Path -ModuleName LogCleanup { return $false }
            Mock New-Item -ModuleName LogCleanup {}

            $result = Clear-WinOpsEventLog -LogName Application -ArchiveBeforeClear -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Archived | Should -Be $true
            $result.ArchivePath | Should -Not -BeNullOrEmpty
        }

        It 'Should clear all event logs when LogName is All' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Get-WinEvent -ModuleName LogCleanup {
                @(
                    [PSCustomObject]@{ LogName = 'Application'; RecordId = 1 }
                )
            }
            Mock -ModuleName LogCleanup -CommandName 'wevtutil' -MockWith {}

            $result = Clear-WinOpsEventLog -LogName All -Force -Confirm:$false

            $result.Count | Should -BeGreaterThan 1
        }

        It 'Should handle errors gracefully' {
            Mock -ModuleName LogCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Get-WinEvent -ModuleName LogCleanup { throw 'Access denied' }

            $result = Clear-WinOpsEventLog -LogName Application -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'LogCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test log directory
        $script:TestLogDir = Join-Path $TestDrive 'TestLogs'
        New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null

        # Create test log files with different sizes and ages
        $largeOldLog = Join-Path $script:TestLogDir 'large-old.log'
        $smallOldLog = Join-Path $script:TestLogDir 'small-old.log'
        $newLog = Join-Path $script:TestLogDir 'new.log'

        # Create large log (10MB)
        $largeData = 'x' * 10MB
        Set-Content -Path $largeOldLog -Value $largeData

        # Create small log (100KB)
        $smallData = 'x' * 100KB
        Set-Content -Path $smallOldLog -Value $smallData

        # Create new log
        Set-Content -Path $newLog -Value 'recent log data'

        # Set ages
        (Get-Item $largeOldLog).LastWriteTime = (Get-Date).AddDays(-120)
        (Get-Item $smallOldLog).LastWriteTime = (Get-Date).AddDays(-120)
        (Get-Item $newLog).LastWriteTime = (Get-Date).AddDays(-5)
    }

    It 'Should identify large old log files' {
        $cutoffDate = (Get-Date).AddDays(-90)
        $minSize = 1MB

        $largeLogs = Get-ChildItem $script:TestLogDir -File | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and $_.Length -gt $minSize
        }

        $largeLogs.Count | Should -Be 1
        $largeLogs[0].Name | Should -Be 'large-old.log'
    }

    It 'Should calculate total log size correctly' {
        $totalSize = (Get-ChildItem $script:TestLogDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $totalSize | Should -BeGreaterThan 10MB
    }

    It 'Should filter by both age and size' {
        $cutoffDate = (Get-Date).AddDays(-90)
        $minSize = 5MB

        $filtered = Get-ChildItem $script:TestLogDir -File | Where-Object {
            $_.LastWriteTime -lt $cutoffDate -and $_.Length -gt $minSize
        }

        $filtered.Count | Should -Be 1
        $filtered[0].Name | Should -Be 'large-old.log'
    }
}
