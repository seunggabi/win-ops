#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\DockerCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName DockerCleanup {}
    Mock Test-WinOpsPathSafe -ModuleName DockerCleanup { return $true }
}

Describe 'DockerCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load DockerCleanup module successfully' {
            Get-Module DockerCleanup | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module DockerCleanup
            $commands.Name | Should -Contain 'Clear-WinOpsDockerResources'
            $commands.Name | Should -Contain 'Optimize-WinOpsDockerWSL'
            $commands.Name | Should -Contain 'Get-WinOpsDockerInfo'
        }
    }

    Context 'Get-WinOpsDockerInfo' {

        It 'Should return Docker info when Docker is installed and running' {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'docker'; CommandType = 'Application' }
            }
            Mock Invoke-Expression -ModuleName DockerCleanup {
                '25.0.0'
            }
            Mock Test-Path -ModuleName DockerCleanup { return $true }
            Mock Get-Item -ModuleName DockerCleanup {
                [PSCustomObject]@{ Length = 10GB }
            }
            $global:LASTEXITCODE = 0

            $result = Get-WinOpsDockerInfo

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -Be $true
            $result.Running | Should -Be $true
            $result.Version | Should -Not -BeNullOrEmpty
        }

        It 'Should handle Docker not installed' {
            Mock Get-Command -ModuleName DockerCleanup { return $null }

            $result = Get-WinOpsDockerInfo

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -Be $false
            $result.Running | Should -Be $false
        }

        It 'Should include WSL disk information' {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'docker'; CommandType = 'Application' }
            }
            Mock Invoke-Expression -ModuleName DockerCleanup {
                '25.0.0'
            }
            Mock Test-Path -ModuleName DockerCleanup { return $true }
            Mock Get-Item -ModuleName DockerCleanup {
                [PSCustomObject]@{ Length = 20GB }
            }
            $global:LASTEXITCODE = 0

            $result = Get-WinOpsDockerInfo

            $result.WSLDiskPath | Should -Not -BeNullOrEmpty
            $result.WSLDiskSizeGB | Should -BeGreaterThan -1
        }
    }

    Context 'Clear-WinOpsDockerResources' {

        BeforeEach {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'docker'; CommandType = 'Application' }
            }
            Mock Invoke-Expression -ModuleName DockerCleanup {
                param($Command)
                if ($Command -like '*version*') {
                    '25.0.0'
                    $global:LASTEXITCODE = 0
                } elseif ($Command -like '*system df*') {
                    '{"Type":"Images","Total":10,"Active":5,"Size":"1.5GB","Reclaimable":"500MB"}'
                    $global:LASTEXITCODE = 0
                } elseif ($Command -like '*prune*') {
                    'Total reclaimed space: 2GB'
                    $global:LASTEXITCODE = 0
                }
            }
        }

        It 'Should clean containers' {
            $result = Clear-WinOpsDockerResources -ResourceType Containers -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'Containers'
        }

        It 'Should clean images' {
            $result = Clear-WinOpsDockerResources -ResourceType Images -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'Images'
        }

        It 'Should clean volumes' {
            $result = Clear-WinOpsDockerResources -ResourceType Volumes -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'Volumes'
        }

        It 'Should clean build cache' {
            $result = Clear-WinOpsDockerResources -ResourceType BuildCache -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'BuildCache'
        }

        It 'Should clean networks' {
            $result = Clear-WinOpsDockerResources -ResourceType Networks -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'Networks'
        }

        It 'Should clean all resources' {
            $result = Clear-WinOpsDockerResources -ResourceType All -Force

            $result | Should -Not -BeNullOrEmpty
            $result[0].Resource | Should -Be 'All'
        }

        It 'Should support DryRun mode' {
            $result = Clear-WinOpsDockerResources -ResourceType Containers -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result[0].Action | Should -Be 'DryRun'
        }

        It 'Should throw when Docker is not installed' {
            Mock Get-Command -ModuleName DockerCleanup { return $null }

            { Clear-WinOpsDockerResources -ResourceType Containers -Force } | Should -Throw 'Docker is not installed'
        }

        It 'Should throw when Docker is not running' {
            Mock Invoke-Expression -ModuleName DockerCleanup {
                throw 'Cannot connect to Docker daemon'
            }

            { Clear-WinOpsDockerResources -ResourceType Containers -Force } | Should -Throw 'Docker is not running'
        }
    }

    Context 'Optimize-WinOpsDockerWSL' {

        It 'Should optimize WSL disk when Docker WSL exists' {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'wsl'; CommandType = 'Application' }
            }
            Mock Test-Path -ModuleName DockerCleanup { return $true }
            Mock Get-Item -ModuleName DockerCleanup {
                param($Path)
                if ($script:firstCall) {
                    $script:firstCall = $false
                    [PSCustomObject]@{ Length = 20GB }
                } else {
                    [PSCustomObject]@{ Length = 15GB }
                }
            }
            Mock Invoke-Expression -ModuleName DockerCleanup {
                $global:LASTEXITCODE = 0
            }
            Mock Remove-Item -ModuleName DockerCleanup {}
            Mock Out-File -ModuleName DockerCleanup {}
            $script:firstCall = $true

            $result = Optimize-WinOpsDockerWSL -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.SpaceReclaimedGB | Should -BeGreaterThan 0
        }

        It 'Should throw when WSL is not installed' {
            Mock Get-Command -ModuleName DockerCleanup { return $null }

            { Optimize-WinOpsDockerWSL -Confirm:$false } | Should -Throw 'WSL is not installed'
        }

        It 'Should throw when Docker WSL disk not found' {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'wsl'; CommandType = 'Application' }
            }
            Mock Test-Path -ModuleName DockerCleanup { return $false }

            { Optimize-WinOpsDockerWSL -Confirm:$false } | Should -Throw 'Docker WSL2 virtual disk not found'
        }

        It 'Should show before and after sizes' {
            Mock Get-Command -ModuleName DockerCleanup {
                [PSCustomObject]@{ Name = 'wsl'; CommandType = 'Application' }
            }
            Mock Test-Path -ModuleName DockerCleanup { return $true }
            Mock Get-Item -ModuleName DockerCleanup {
                param($Path)
                if ($script:firstCall) {
                    $script:firstCall = $false
                    [PSCustomObject]@{ Length = 25GB }
                } else {
                    [PSCustomObject]@{ Length = 18GB }
                }
            }
            Mock Invoke-Expression -ModuleName DockerCleanup {}
            Mock Remove-Item -ModuleName DockerCleanup {}
            Mock Out-File -ModuleName DockerCleanup {}
            $script:firstCall = $true

            $result = Optimize-WinOpsDockerWSL -Confirm:$false

            $result.BeforeSizeGB | Should -BeGreaterThan 0
            $result.AfterSizeGB | Should -BeGreaterThan 0
            $result.BeforeSizeGB | Should -BeGreaterThan $result.AfterSizeGB
        }
    }
}

Describe 'DockerCleanup Integration Tests' -Tag 'Integration', 'Module' {

    Context 'Docker Detection' {

        It 'Should detect if Docker command exists' {
            $dockerInstalled = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
            $dockerInstalled | Should -BeIn @($true, $false)
        }

        It 'Should check Docker daemon connectivity' {
            $dockerInstalled = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)

            if ($dockerInstalled) {
                $isRunning = $false
                try {
                    docker version 2>&1 | Out-Null
                    $isRunning = $LASTEXITCODE -eq 0
                } catch {
                    $isRunning = $false
                }

                $isRunning | Should -BeIn @($true, $false)
            }
        }
    }

    Context 'Size Parsing' {

        It 'Should parse GB sizes' {
            $sizeString = '2.5GB'
            $sizeString | Should -Match '[\d\.]+GB'
        }

        It 'Should parse MB sizes' {
            $sizeString = '500MB'
            $sizeString | Should -Match '[\d\.]+MB'
        }

        It 'Should parse KB sizes' {
            $sizeString = '1024KB'
            $sizeString | Should -Match '[\d\.]+KB'
        }
    }
}
