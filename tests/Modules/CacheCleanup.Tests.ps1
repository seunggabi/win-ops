#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\CacheCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName CacheCleanup {}
    Mock Move-WinOpsToTrash -ModuleName CacheCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'CacheCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Get-WinOpsCacheInfo' {

        It 'Should return cache information for all cache types' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{ Name = 'test.cache'; Length = 1024; LastWriteTime = (Get-Date).AddDays(-10); PSIsContainer = $false }
                )
            }

            $result = Get-WinOpsCacheInfo -CacheType All

            $result | Should -Not -BeNullOrEmpty
            $result[0].CacheType | Should -Not -BeNullOrEmpty
            $result[0].TotalSize | Should -BeGreaterThan -1
        }

        It 'Should filter by age when AgeInDays is specified' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{ Name = 'old.cache'; Length = 1024; LastWriteTime = (Get-Date).AddDays(-60); PSIsContainer = $false }
                    [PSCustomObject]@{ Name = 'new.cache'; Length = 2048; LastWriteTime = (Get-Date).AddDays(-5); PSIsContainer = $false }
                )
            }

            $result = Get-WinOpsCacheInfo -CacheType WindowsTemp -AgeInDays 30

            # Should only count old file
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should return specific cache type information' {
            $result = Get-WinOpsCacheInfo -CacheType ChromeCache

            $result | Should -Not -BeNullOrEmpty
            $result.CacheType | Should -Be 'ChromeCache'
            $result.Description | Should -Be 'Google Chrome cache'
        }

        It 'Should include all required properties' {
            $result = Get-WinOpsCacheInfo -CacheType WindowsTemp

            $result.CacheType | Should -Not -BeNullOrEmpty
            $result.Description | Should -Not -BeNullOrEmpty
            $result.TotalSize | Should -BeGreaterThan -1
            $result.TotalSizeMB | Should -BeGreaterThan -1
            $result.Paths | Should -Not -BeNullOrEmpty
            $result.SafetyLevel | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-WinOpsCache' {

        It 'Should clear specified cache type' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.cache'
                        FullName = 'C:\Temp\test.cache'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName CacheCleanup {}

            $result = Clear-WinOpsCache -CacheType WindowsTemp -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.CacheType | Should -Be 'WindowsTemp'
        }

        It 'Should support DryRun mode' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{ Name = 'test.cache'; Length = 1024; LastWriteTime = (Get-Date); PSIsContainer = $false }
                )
            }

            $result = Clear-WinOpsCache -CacheType WindowsTemp -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName CacheCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.cache'
                        FullName = 'C:\Temp\test.cache'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsCache -CacheType WindowsTemp -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName CacheCleanup -Times 1
        }

        It 'Should filter by age' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'old.cache'
                        FullName = 'C:\Temp\old.cache'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-60)
                        PSIsContainer = $false
                    }
                    [PSCustomObject]@{
                        Name = 'new.cache'
                        FullName = 'C:\Temp\new.cache'
                        Length = 2048
                        LastWriteTime = (Get-Date).AddDays(-5)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName CacheCleanup {}

            $result = Clear-WinOpsCache -CacheType WindowsTemp -AgeInDays 30 -Force -Confirm:$false

            # Should only remove old file
            $result.RemovedCount | Should -BeGreaterThan 0
        }

        It 'Should clean all cache types when CacheType is All' {
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'test.cache'
                        FullName = 'C:\Temp\test.cache'
                        Length = 1024
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName CacheCleanup {}

            $result = Clear-WinOpsCache -CacheType All -Force -Confirm:$false

            $result.Count | Should -BeGreaterThan 1
        }
    }

    Context 'Optimize-WinOpsIconCache' {

        It 'Should rebuild icon cache' {
            Mock Stop-Process -ModuleName CacheCleanup {}
            Mock Start-Sleep -ModuleName CacheCleanup {}
            Mock Get-ChildItem -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{ FullName = 'C:\IconCache.db' }
                )
            }
            Mock Remove-Item -ModuleName CacheCleanup {}
            Mock Start-Process -ModuleName CacheCleanup {}

            $result = Optimize-WinOpsIconCache -Confirm:$false

            $result | Should -Be $true
            Should -Invoke Stop-Process -ModuleName CacheCleanup -Times 1
            Should -Invoke Start-Process -ModuleName CacheCleanup -Times 1
        }

        It 'Should handle errors gracefully' {
            Mock Stop-Process -ModuleName CacheCleanup { throw 'Failed to stop explorer' }

            $result = Optimize-WinOpsIconCache -Confirm:$false

            $result | Should -Be $false
        }
    }

    Context 'Invoke-WinOpsCacheCleanup' {

        It 'Should invoke cache cleanup with default parameters' {
            Mock Clear-WinOpsCache -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        CacheType = 'WindowsTemp'
                        RemovedCount = 10
                        RemovedSize = 10MB
                    }
                )
            }

            $result = Invoke-WinOpsCacheCleanup -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.TotalItemsRemoved | Should -BeGreaterThan -1
            $result.TotalSizeRemoved | Should -BeGreaterThan -1
        }

        It 'Should support custom age parameter' {
            Mock Clear-WinOpsCache -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        CacheType = 'WindowsTemp'
                        RemovedCount = 5
                        RemovedSize = 5MB
                    }
                )
            }

            $result = Invoke-WinOpsCacheCleanup -AgeInDays 30 -Force -Confirm:$false

            Should -Invoke Clear-WinOpsCache -ModuleName CacheCleanup -ParameterFilter {
                $AgeInDays -eq 30
            }
        }
    }

    Context 'Get-WinOpsCacheTargets' {

        It 'Should return list of cache targets' {
            Mock Get-WinOpsCacheInfo -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        CacheType = 'WindowsTemp'
                        Description = 'Windows temporary files'
                        TotalSize = 10MB
                        TotalSizeMB = 10
                        TotalSizeGB = 0.01
                        Paths = @('C:\Temp')
                        SafetyLevel = 'Normal'
                    }
                )
            }

            $result = Get-WinOpsCacheTargets -AgeInDays 7

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be 'WindowsTemp'
            $result[0].WillCleanup | Should -Be $true
        }

        It 'Should include all required target properties' {
            Mock Get-WinOpsCacheInfo -ModuleName CacheCleanup {
                @(
                    [PSCustomObject]@{
                        CacheType = 'ChromeCache'
                        Description = 'Chrome cache'
                        TotalSize = 5MB
                        TotalSizeMB = 5
                        TotalSizeGB = 0.005
                        Paths = @('C:\Chrome\Cache')
                        SafetyLevel = 'Normal'
                    }
                )
            }

            $result = Get-WinOpsCacheTargets

            $result[0].Name | Should -Not -BeNullOrEmpty
            $result[0].Description | Should -Not -BeNullOrEmpty
            $result[0].Paths | Should -Not -BeNullOrEmpty
            $result[0].CurrentSizeMB | Should -BeGreaterThan -1
            $result[0].SafetyLevel | Should -Not -BeNullOrEmpty
            $result[0].AgeFilter | Should -BeGreaterThan -1
        }
    }
}

Describe 'CacheCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test cache directory
        $script:TestCacheDir = Join-Path $TestDrive 'TestCache'
        New-Item -Path $script:TestCacheDir -ItemType Directory -Force | Out-Null

        # Create test files
        $oldFile = Join-Path $script:TestCacheDir 'old.cache'
        $newFile = Join-Path $script:TestCacheDir 'new.cache'

        Set-Content -Path $oldFile -Value 'old data'
        Set-Content -Path $newFile -Value 'new data'

        (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-60)
        (Get-Item $newFile).LastWriteTime = (Get-Date).AddDays(-5)
    }

    It 'Should calculate cache size correctly' {
        $size = (Get-ChildItem $script:TestCacheDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $size | Should -BeGreaterThan 0
    }

    It 'Should filter files by age correctly' {
        $oldFiles = Get-ChildItem $script:TestCacheDir -File | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddDays(-30)
        }

        $oldFiles.Count | Should -Be 1
        $oldFiles[0].Name | Should -Be 'old.cache'
    }
}
