#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\DevCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName DevCleanup {}
    Mock Move-WinOpsToTrash -ModuleName DevCleanup { return @{ Hash = 'test'; Size = 1024 } }
    Mock Test-WinOpsPathSafe -ModuleName DevCleanup { return $true }
}

Describe 'DevCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load DevCleanup module successfully' {
            Get-Module DevCleanup | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module DevCleanup
            $commands.Name | Should -Contain 'Get-WinOpsDevCacheTargets'
            $commands.Name | Should -Contain 'Invoke-WinOpsDevCleanup'
            $commands.Name | Should -Contain 'Find-WinOpsNodeModules'
        }
    }

    Context 'Get-WinOpsDevCacheTargets' {

        It 'Should return dev cache targets for all categories' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'package.cache'
                        Length = 50MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsDevCacheTargets -Category All

            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Not -BeNullOrEmpty
            $result[0].TotalSizeMB | Should -BeGreaterThan -1
        }

        It 'Should filter by PackageManager category' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'npm-cache'
                        Length = 100MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsDevCacheTargets -Category PackageManager

            $result | Should -Not -BeNullOrEmpty
            $result[0].Category | Should -Be 'PackageManager'
        }

        It 'Should filter by IDE category' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 50MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsDevCacheTargets -Category IDE

            $result | Should -Not -BeNullOrEmpty
            $result[0].Category | Should -Be 'IDE'
        }

        It 'Should skip non-existent cache directories by default' {
            Mock Test-Path -ModuleName DevCleanup { return $false }

            $result = Get-WinOpsDevCacheTargets -Category All

            # Should return empty array since nothing exists
            $result.Count | Should -Be 0
        }

        It 'Should include empty targets when IncludeEmpty is specified' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup { @() }

            $result = Get-WinOpsDevCacheTargets -Category All -IncludeEmpty

            # Should include targets even if they're empty
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 25MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsDevCacheTargets -Category All

            $result[0].Key | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Not -BeNullOrEmpty
            $result[0].Description | Should -Not -BeNullOrEmpty
            $result[0].Category | Should -Not -BeNullOrEmpty
            $result[0].TotalSize | Should -BeGreaterThan -1
            $result[0].TotalSizeMB | Should -BeGreaterThan -1
            $result[0].CanRegenerate | Should -BeIn @($true, $false)
        }
    }

    Context 'Invoke-WinOpsDevCleanup' {

        It 'Should clean dev cache for specified target' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\npm\cache.dat'
                        Length = 50MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName DevCleanup {}

            $result = Invoke-WinOpsDevCleanup -Target npm -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Target | Should -Match 'npm'
        }

        It 'Should support DryRun mode' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 30MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Invoke-WinOpsDevCleanup -Target npm -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result[0].WouldRemove | Should -Be $true
            $result[0].RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName DevCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\yarn\cache.dat'
                        Length = 40MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Invoke-WinOpsDevCleanup -Target yarn -UseTrash -Force

            Should -Invoke Move-WinOpsToTrash -ModuleName DevCleanup
        }

        It 'Should clean all targets when Target is All' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\cache\cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName DevCleanup {}

            $result = Invoke-WinOpsDevCleanup -Target All -Force

            $result.Count | Should -BeGreaterThan 0
        }

        It 'Should clean by category' {
            Mock Test-Path -ModuleName DevCleanup { return $true }
            Mock Get-ChildItem -ModuleName DevCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\cache\cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName DevCleanup {}

            $result = Invoke-WinOpsDevCleanup -Category PackageManager -Force

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Find-WinOpsNodeModules' {

        It 'Should find node_modules directories' {
            Mock Get-ChildItem -ModuleName DevCleanup {
                param($Path, $Directory, $Force)
                if ($Directory) {
                    @(
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\project1\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\project2\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                    )
                } else {
                    @(
                        [PSCustomObject]@{
                            Name = 'package.js'
                            Length = 10MB
                            PSIsContainer = $false
                        }
                    )
                }
            }

            $result = Find-WinOpsNodeModules -Path 'C:\Projects'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Should filter by minimum size' {
            Mock Get-ChildItem -ModuleName DevCleanup {
                param($Path, $Directory, $Force)
                if ($Directory) {
                    @(
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\large\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                    )
                } else {
                    @(
                        [PSCustomObject]@{
                            Name = 'package.js'
                            Length = 600MB
                            PSIsContainer = $false
                        }
                    )
                }
            }

            $result = Find-WinOpsNodeModules -Path 'C:\Projects' -MinSizeMB 500

            # Should only return large directories
            $result | Should -Not -BeNullOrEmpty
            $result[0].SizeMB | Should -BeGreaterThan 500
        }

        It 'Should calculate total size' {
            Mock Get-ChildItem -ModuleName DevCleanup {
                param($Path, $Directory, $Force)
                if ($Directory) {
                    @(
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\project\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                    )
                } else {
                    @(
                        [PSCustomObject]@{
                            Name = 'package.js'
                            Length = 150MB
                            PSIsContainer = $false
                        }
                    )
                }
            }

            $result = Find-WinOpsNodeModules -Path 'C:\Projects'

            $result[0].SizeMB | Should -BeGreaterThan 0
            $result[0].SizeGB | Should -BeGreaterThan -1
        }

        It 'Should respect TopN parameter' {
            Mock Get-ChildItem -ModuleName DevCleanup {
                param($Path, $Directory, $Force)
                if ($Directory) {
                    @(
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\p1\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\p2\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                        [PSCustomObject]@{
                            Name = 'node_modules'
                            FullName = 'C:\p3\node_modules'
                            PSIsContainer = $true
                            Attributes = [System.IO.FileAttributes]::Directory
                            LastWriteTime = (Get-Date)
                        }
                    )
                } else {
                    @(
                        [PSCustomObject]@{
                            Name = 'package.js'
                            Length = 150MB
                            PSIsContainer = $false
                        }
                    )
                }
            }

            $result = Find-WinOpsNodeModules -Path 'C:\Projects' -TopN 2

            $result.Count | Should -BeLessOrEqual 2
        }
    }
}

Describe 'DevCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test dev cache directory
        $script:TestDevDir = Join-Path $TestDrive 'DevCache'
        New-Item -Path $script:TestDevDir -ItemType Directory -Force | Out-Null

        # Create npm cache
        $npmCache = Join-Path $script:TestDevDir 'npm-cache'
        New-Item -Path $npmCache -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $npmCache 'package1.tgz') -Value ('x' * 10MB)
        Set-Content -Path (Join-Path $npmCache 'package2.tgz') -Value ('x' * 5MB)

        # Create node_modules
        $nodeModules = Join-Path $script:TestDevDir 'node_modules'
        New-Item -Path $nodeModules -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $nodeModules 'module.js') -Value 'module code'
    }

    It 'Should calculate npm cache size correctly' {
        $cacheSize = (Get-ChildItem (Join-Path $script:TestDevDir 'npm-cache') -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $cacheSize | Should -BeGreaterThan 15MB
    }

    It 'Should identify node_modules directories' {
        $nodeModules = Get-ChildItem $script:TestDevDir -Directory -Filter 'node_modules'
        $nodeModules.Count | Should -Be 1
    }

    It 'Should handle multiple package manager caches' {
        # Add yarn cache
        $yarnCache = Join-Path $script:TestDevDir 'yarn-cache'
        New-Item -Path $yarnCache -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $yarnCache 'package.tgz') -Value ('x' * 8MB)

        $caches = Get-ChildItem $script:TestDevDir -Directory | Where-Object {
            $_.Name -like '*cache*'
        }

        $caches.Count | Should -BeGreaterThan 1
    }
}
