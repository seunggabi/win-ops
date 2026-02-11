#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\BrowserCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName BrowserCleanup {}
    Mock Move-WinOpsToTrash -ModuleName BrowserCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'BrowserCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Get-WinOpsBrowserDataInfo' {

        It 'Should return browser data info for all browsers' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 5MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsBrowserDataInfo -Browser All

            $result | Should -Not -BeNullOrEmpty
            $result[0].Browser | Should -Not -BeNullOrEmpty
            $result[0].DataType | Should -Not -BeNullOrEmpty
        }

        It 'Should return info for specific browser' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsBrowserDataInfo -Browser Chrome

            $result | Should -Not -BeNullOrEmpty
            $result[0].Browser | Should -Be 'Google Chrome'
        }

        It 'Should detect if browser is running' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup {
                [PSCustomObject]@{ Name = 'chrome'; Id = 1234 }
            }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 5MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsBrowserDataInfo -Browser Chrome

            $result[0].IsRunning | Should -Be $true
        }

        It 'Should skip browsers that are not installed' {
            Mock Test-Path -ModuleName BrowserCleanup { return $false }

            $result = Get-WinOpsBrowserDataInfo -Browser Opera

            $result | Should -BeNullOrEmpty
        }

        It 'Should include all required properties' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        Length = 15MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Get-WinOpsBrowserDataInfo -Browser Edge

            $result[0].Browser | Should -Not -BeNullOrEmpty
            $result[0].DataType | Should -Not -BeNullOrEmpty
            $result[0].Description | Should -Not -BeNullOrEmpty
            $result[0].TotalSize | Should -BeGreaterThan -1
            $result[0].TotalSizeMB | Should -BeGreaterThan -1
            $result[0].IsRunning | Should -BeFalse
            $result[0].BasePath | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-WinOpsBrowserData' {

        It 'Should clear browser data for specified browser and type' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\Browser\cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName BrowserCleanup {}

            $result = Clear-WinOpsBrowserData -Browser Chrome -DataType Cache -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Browser | Should -Be 'Google Chrome'
            $result.DataType | Should -Be 'Cache'
        }

        It 'Should support DryRun mode' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cookies.dat'
                        Length = 2MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsBrowserData -Browser Chrome -DataType Cookies -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName BrowserCleanup
        }

        It 'Should close browser when Force is specified' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup {
                [PSCustomObject]@{ Name = 'chrome'; Id = 1234 }
            } -ParameterFilter { $Name -eq 'chrome' }
            Mock Stop-Process -ModuleName BrowserCleanup {}
            Mock Start-Sleep -ModuleName BrowserCleanup {}
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'history.dat'
                        FullName = 'C:\Browser\history.dat'
                        Length = 5MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName BrowserCleanup {}

            # Mock to return null after stop
            Mock Get-Process -ModuleName BrowserCleanup { return $null } -ParameterFilter { $Name -eq 'chrome' }

            $result = Clear-WinOpsBrowserData -Browser Chrome -DataType History -Force -Confirm:$false

            Should -Invoke Stop-Process -ModuleName BrowserCleanup -Times 1
        }

        It 'Should warn if browser is running and Force is not specified' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup {
                [PSCustomObject]@{ Name = 'edge'; Id = 1234 }
            }
            Mock Write-Warning -ModuleName BrowserCleanup {}

            $result = Clear-WinOpsBrowserData -Browser Edge -DataType Cache -Confirm:$false

            Should -Invoke Write-Warning -ModuleName BrowserCleanup
            $result | Should -BeNullOrEmpty
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\Browser\cache.dat'
                        Length = 10MB
                        PSIsContainer = $false
                    }
                )
            }

            $result = Clear-WinOpsBrowserData -Browser Chrome -DataType Cache -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName BrowserCleanup
        }

        It 'Should clean all data types when DataType is All' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'data.dat'
                        FullName = 'C:\Browser\data.dat'
                        Length = 5MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName BrowserCleanup {}

            $result = Clear-WinOpsBrowserData -Browser Chrome -DataType All -Force -Confirm:$false

            $result.Count | Should -BeGreaterThan 1
        }

        It 'Should clean all browsers when Browser is All' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }
            Mock Get-ChildItem -ModuleName BrowserCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'cache.dat'
                        FullName = 'C:\Browser\cache.dat'
                        Length = 5MB
                        PSIsContainer = $false
                    }
                )
            }
            Mock Remove-Item -ModuleName BrowserCleanup {}

            $result = Clear-WinOpsBrowserData -Browser All -DataType Cache -Force -Confirm:$false

            # Should attempt multiple browsers
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-WinOpsBrowserInstalled' {

        It 'Should detect installed browsers' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }

            $result = Test-WinOpsBrowserInstalled -Browser Chrome

            $result | Should -Not -BeNullOrEmpty
            $result.Browser | Should -Be 'Google Chrome'
            $result.Installed | Should -Be $true
        }

        It 'Should detect browser running status' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup {
                [PSCustomObject]@{ Name = 'chrome'; Id = 1234 }
            }

            $result = Test-WinOpsBrowserInstalled -Browser Chrome

            $result.Running | Should -Be $true
        }

        It 'Should detect non-installed browsers' {
            Mock Test-Path -ModuleName BrowserCleanup { return $false }

            $result = Test-WinOpsBrowserInstalled -Browser Brave

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -Be $false
            $result.Running | Should -Be $false
        }

        It 'Should check all browsers when Browser is All' {
            Mock Test-Path -ModuleName BrowserCleanup { return $true }
            Mock Get-Process -ModuleName BrowserCleanup { return $null }

            $result = Test-WinOpsBrowserInstalled -Browser All

            $result.Count | Should -BeGreaterThan 1
            $result[0].Browser | Should -Not -BeNullOrEmpty
            $result[0].Key | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'BrowserCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test browser directory structure
        $script:TestBrowserDir = Join-Path $TestDrive 'TestBrowser'
        $script:CacheDir = Join-Path $script:TestBrowserDir 'Cache'
        $script:CookiesDir = Join-Path $script:TestBrowserDir 'Cookies'

        New-Item -Path $script:CacheDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:CookiesDir -ItemType Directory -Force | Out-Null

        # Create test cache files
        Set-Content -Path (Join-Path $script:CacheDir 'cache1.dat') -Value ('x' * 1MB)
        Set-Content -Path (Join-Path $script:CacheDir 'cache2.dat') -Value ('x' * 2MB)

        # Create test cookie files
        Set-Content -Path (Join-Path $script:CookiesDir 'cookies.db') -Value 'cookie data'
    }

    It 'Should calculate total cache size correctly' {
        $cacheSize = (Get-ChildItem $script:CacheDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $cacheSize | Should -BeGreaterThan 3MB
    }

    It 'Should enumerate all data types' {
        $cacheFiles = Get-ChildItem $script:CacheDir -File
        $cookieFiles = Get-ChildItem $script:CookiesDir -File

        $cacheFiles.Count | Should -Be 2
        $cookieFiles.Count | Should -Be 1
    }

    It 'Should support recursive cleanup' {
        # Create nested structure
        $nestedDir = Join-Path $script:CacheDir 'Nested'
        New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $nestedDir 'nested.cache') -Value 'nested data'

        $allFiles = Get-ChildItem $script:CacheDir -Recurse -File
        $allFiles.Count | Should -Be 3
    }
}
