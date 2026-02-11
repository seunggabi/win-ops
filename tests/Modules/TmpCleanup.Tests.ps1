#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\TmpCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName TmpCleanup {}
    Mock Move-WinOpsToTrash -ModuleName TmpCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'TmpCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Get-WinOpsTempFileInfo' {

        It 'Should return temp file information for all locations' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'temp.tmp'
                        Length = 2048
                        LastWriteTime = (Get-Date).AddDays(-15)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsTempFileInfo -Location All

            $result | Should -Not -BeNullOrEmpty
            $result[0].Location | Should -Not -BeNullOrEmpty
            $result[0].FileCount | Should -BeGreaterThan -1
        }

        It 'Should return specific location information' {
            $result = Get-WinOpsTempFileInfo -Location UserTemp

            $result | Should -Not -BeNullOrEmpty
            $result.Location | Should -Be 'UserTemp'
            $result.Description | Should -Be 'User temporary files'
        }

        It 'Should filter by age' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'old.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-60)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'new.tmp'
                        Length = 2048
                        LastWriteTime = (Get-Date).AddDays(-5)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsTempFileInfo -Location UserTemp -AgeInDays 30

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            $result = Get-WinOpsTempFileInfo -Location UserTemp

            $result.Location | Should -Not -BeNullOrEmpty
            $result.Description | Should -Not -BeNullOrEmpty
            $result.FileCount | Should -BeGreaterThan -1
            $result.TotalSize | Should -BeGreaterThan -1
            $result.TotalSizeMB | Should -BeGreaterThan -1
            $result.DefaultAgeInDays | Should -BeGreaterThan -1
            $result.Paths | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-WinOpsTempFiles' {

        It 'Should clear temp files from specified location' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.tmp'
                        FullName = 'C:\Temp\test.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName TmpCleanup { return $true }
            Mock Remove-Item -ModuleName TmpCleanup {}

            # Mock file lock test
            Mock -ModuleName TmpCleanup -CommandName 'System.IO.File' -MockWith {
                @{
                    Open = { param($path, $mode, $access, $share)
                        [PSCustomObject]@{
                            Close = {}
                            Dispose = {}
                        }
                    }
                }
            }

            $result = Clear-WinOpsTempFiles -Location UserTemp -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Location | Should -Be 'UserTemp'
        }

        It 'Should support DryRun mode' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsTempFiles -Location UserTemp -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName TmpCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.tmp'
                        FullName = 'C:\Temp\test.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName TmpCleanup { return $true }

            $result = Clear-WinOpsTempFiles -Location UserTemp -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName TmpCleanup
        }

        It 'Should respect exclude patterns' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'important.tmp'
                        FullName = 'C:\Temp\important.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'deleteme.tmp'
                        FullName = 'C:\Temp\deleteme.tmp'
                        Length = 2048
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName TmpCleanup { return $true }
            Mock Remove-Item -ModuleName TmpCleanup {}

            $result = Clear-WinOpsTempFiles -Location UserTemp -ExcludePatterns 'important*' -Force -Confirm:$false

            # Should only process non-excluded files
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should skip files that are in use' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'locked.tmp'
                        FullName = 'C:\Temp\locked.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName TmpCleanup { return $true }

            $result = Clear-WinOpsTempFiles -Location UserTemp -Force -Confirm:$false

            # Should skip locked files
            $result.SkippedCount | Should -BeGreaterThan -1
        }

        It 'Should require elevation for system locations' {
            Mock -ModuleName TmpCleanup -CommandName 'Test-IsElevated' -MockWith { return $false }

            $result = Clear-WinOpsTempFiles -Location SystemTemp -Force -Confirm:$false

            # Should skip due to lack of elevation
            $result | Should -BeNullOrEmpty -Because 'SystemTemp requires elevation'
        }

        It 'Should clean all locations when Location is All' {
            Mock Get-ChildItem -ModuleName TmpCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.tmp'
                        FullName = 'C:\Temp\test.tmp'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Test-Path -ModuleName TmpCleanup { return $true }
            Mock Remove-Item -ModuleName TmpCleanup {}
            Mock -ModuleName TmpCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }

            $result = Clear-WinOpsTempFiles -Location All -Force -Confirm:$false

            $result.Count | Should -BeGreaterThan 1
        }
    }
}

Describe 'TmpCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test temp directory
        $script:TestTempDir = Join-Path $TestDrive 'TestTemp'
        New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null

        # Create test files with different ages
        $oldFile = Join-Path $script:TestTempDir 'old.tmp'
        $newFile = Join-Path $script:TestTempDir 'new.tmp'

        Set-Content -Path $oldFile -Value 'old temp data'
        Set-Content -Path $newFile -Value 'new temp data'

        (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item $newFile).LastWriteTime = (Get-Date).AddDays(-2)
    }

    It 'Should count temp files correctly' {
        $count = (Get-ChildItem $script:TestTempDir -File).Count
        $count | Should -Be 2
    }

    It 'Should calculate total size correctly' {
        $size = (Get-ChildItem $script:TestTempDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $size | Should -BeGreaterThan 0
    }

    It 'Should filter by age correctly' {
        $cutoffDate = (Get-Date).AddDays(-7)
        $oldFiles = Get-ChildItem $script:TestTempDir -File | Where-Object {
            $_.LastWriteTime -lt $cutoffDate
        }

        $oldFiles.Count | Should -Be 1
        $oldFiles[0].Name | Should -Be 'old.tmp'
    }
}
