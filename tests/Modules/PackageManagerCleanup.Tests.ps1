#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\PackageManagerCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName PackageManagerCleanup {}
    Mock Move-WinOpsToTrash -ModuleName PackageManagerCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'PackageManagerCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load PackageManagerCleanup module successfully' {
            Get-Module PackageManagerCleanup | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module PackageManagerCleanup
            $commands.Name | Should -Contain 'Clear-WinOpsPackageManagerCache'
            $commands.Name | Should -Contain 'Get-WinOpsPackageManagerInfo'
        }
    }

    Context 'Get-WinOpsPackageManagerInfo' {

        It 'Should return package manager info for all managers' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'package.cache'
                        Length = 25MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsPackageManagerInfo -PackageManager All

            $result | Should -Not -BeNullOrEmpty
            $result[0].PackageManager | Should -Not -BeNullOrEmpty
            $result[0].TotalSize | Should -BeGreaterThan -1
        }

        It 'Should return info for specific package manager' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'choco.cache'
                        Length = 50MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsPackageManagerInfo -PackageManager Chocolatey

            $result | Should -Not -BeNullOrEmpty
            $result.PackageManager | Should -Be 'Chocolatey'
            $result.Description | Should -Be 'Chocolatey package manager'
        }

        It 'Should detect if package manager is installed' {
            Mock Get-Command -ModuleName PackageManagerCleanup {
                [PSCustomObject]@{ Name = 'choco'; CommandType = 'Application' }
            }
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsPackageManagerInfo -PackageManager Chocolatey

            $result.IsInstalled | Should -Be $true
        }

        It 'Should include all required properties' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 30MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsPackageManagerInfo -PackageManager Scoop

            $result.PackageManager | Should -Not -BeNullOrEmpty
            $result.Description | Should -Not -BeNullOrEmpty
            $result.TotalSize | Should -BeGreaterThan -1
            $result.TotalSizeMB | Should -BeGreaterThan -1
            $result.CachePaths | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-WinOpsPackageManagerCache' {

        It 'Should clear package manager cache' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\choco\cache.dat'
                        Length = 40MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName PackageManagerCleanup {}
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }

            $result = Clear-WinOpsPackageManagerCache -PackageManager Chocolatey -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.PackageManager | Should -Be 'Chocolatey'
        }

        It 'Should support DryRun mode' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 20MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsPackageManagerCache -PackageManager Scoop -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName PackageManagerCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\winget\cache.dat'
                        Length = 35MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsPackageManagerCache -PackageManager Winget -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName PackageManagerCleanup
        }

        It 'Should require elevation for system package managers' {
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $false }

            $result = Clear-WinOpsPackageManagerCache -PackageManager WindowsUpdate -Force -Confirm:$false

            # Should skip due to lack of elevation
            $result | Should -BeNullOrEmpty -Because 'WindowsUpdate requires elevation'
        }

        It 'Should clean all package managers when PackageManager is All' {
            Mock Test-Path -ModuleName PackageManagerCleanup { return $true }
            Mock Get-ChildItem -ModuleName PackageManagerCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\cache\cache.dat'
                        Length = 15MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName PackageManagerCleanup {}
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }

            $result = Clear-WinOpsPackageManagerCache -PackageManager All -Force -Confirm:$false

            $result.Count | Should -BeGreaterThan 1
        }
    }

    Context 'Invoke-WinOpsComponentStoreCleanup' {

        It 'Should run DISM component cleanup' {
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Start-Process -ModuleName PackageManagerCleanup {
                [PSCustomObject]@{ ExitCode = 0 }
            }

            $result = Invoke-WinOpsComponentStoreCleanup -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }

        It 'Should require elevation' {
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $false }

            { Invoke-WinOpsComponentStoreCleanup -Force -Confirm:$false } | Should -Throw 'administrator privileges'
        }

        It 'Should support ResetBase option' {
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Start-Process -ModuleName PackageManagerCleanup {
                [PSCustomObject]@{ ExitCode = 0 }
            }

            $result = Invoke-WinOpsComponentStoreCleanup -ResetBase -Force -Confirm:$false

            Should -Invoke Start-Process -ModuleName PackageManagerCleanup -ParameterFilter {
                $ArgumentList -like '*ResetBase*'
            }
        }

        It 'Should handle DISM errors' {
            Mock -ModuleName PackageManagerCleanup -CommandName 'Test-IsElevated' -MockWith { return $true }
            Mock Start-Process -ModuleName PackageManagerCleanup {
                [PSCustomObject]@{ ExitCode = 1 }
            }

            $result = Invoke-WinOpsComponentStoreCleanup -Force -Confirm:$false

            $result.Success | Should -Be $false
        }
    }
}

Describe 'PackageManagerCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test package manager cache directory
        $script:TestPkgDir = Join-Path $TestDrive 'PackageCache'
        New-Item -Path $script:TestPkgDir -ItemType Directory -Force | Out-Null

        # Create Chocolatey cache
        $chocoCache = Join-Path $script:TestPkgDir 'chocolatey'
        New-Item -Path $chocoCache -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $chocoCache 'package1.nupkg') -Value ('x' * 20MB)
        Set-Content -Path (Join-Path $chocoCache 'package2.nupkg') -Value ('x' * 15MB)

        # Create Scoop cache
        $scoopCache = Join-Path $script:TestPkgDir 'scoop'
        New-Item -Path $scoopCache -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $scoopCache 'app.zip') -Value ('x' * 10MB)
    }

    It 'Should calculate Chocolatey cache size correctly' {
        $chocoSize = (Get-ChildItem (Join-Path $script:TestPkgDir 'chocolatey') -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $chocoSize | Should -BeGreaterThan 35MB
    }

    It 'Should calculate Scoop cache size correctly' {
        $scoopSize = (Get-ChildItem (Join-Path $script:TestPkgDir 'scoop') -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $scoopSize | Should -BeGreaterThan 10MB
    }

    It 'Should identify all package manager caches' {
        $caches = Get-ChildItem $script:TestPkgDir -Directory
        $caches.Count | Should -Be 2
    }

    It 'Should calculate total cache size across all managers' {
        $totalSize = (Get-ChildItem $script:TestPkgDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $totalSize | Should -BeGreaterThan 45MB
    }
}
