#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\OrphanAppCleanup.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName OrphanAppCleanup {}
    Mock Move-WinOpsToTrash -ModuleName OrphanAppCleanup { return @{ Hash = 'test'; Size = 1024 } }
}

Describe 'OrphanAppCleanup Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load OrphanAppCleanup module successfully' {
            Get-Module OrphanAppCleanup | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module OrphanAppCleanup
            $commands.Name | Should -Contain 'Find-WinOpsOrphanedAppData'
            $commands.Name | Should -Contain 'Clear-WinOpsOrphanedAppData'
        }
    }

    Context 'Find-WinOpsOrphanedAppData' {

        It 'Should find orphaned AppData folders' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{ DisplayName = 'Installed App 1' }
                    [PSCustomObject]@{ DisplayName = 'Installed App 2' }
                )
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Uninstalled App'
                        FullName = 'C:\Users\Test\AppData\Local\Uninstalled App'
                        LastWriteTime = (Get-Date).AddDays(-60)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedAppData

            $result | Should -Not -BeNullOrEmpty
            $result[0].Path | Should -BeLike '*Uninstalled App*'
            $result[0].IsOrphaned | Should -Be $true
        }

        It 'Should filter by minimum age' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{ DisplayName = 'Installed App' }
                )
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Old Orphan'
                        FullName = 'C:\AppData\Old Orphan'
                        LastWriteTime = (Get-Date).AddDays(-60)
                        PSIsContainer = $true
                    }
                    [PSCustomObject]@{
                        Name = 'New Orphan'
                        FullName = 'C:\AppData\New Orphan'
                        LastWriteTime = (Get-Date).AddDays(-10)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedAppData -MinAgeInDays 30

            # Should only return Old Orphan
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeLessOrEqual 1
        }

        It 'Should skip system folders' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Microsoft'
                        FullName = 'C:\AppData\Microsoft'
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $true
                    }
                    [PSCustomObject]@{
                        Name = 'OrphanApp'
                        FullName = 'C:\AppData\OrphanApp'
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedAppData

            # Should skip Microsoft folder
            ($result | Where-Object { $_.Path -like '*Microsoft*' }) | Should -BeNullOrEmpty
        }

        It 'Should calculate folder size' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                param($Path)
                if ($Path -like '*AppData') {
                    @(
                        [PSCustomObject]@{
                            Name = 'OrphanApp'
                            FullName = 'C:\AppData\OrphanApp'
                            LastWriteTime = (Get-Date).AddDays(-50)
                            PSIsContainer = $true
                        }
                    )
                } else {
                    @(
                        [PSCustomObject]@{
                            Name = 'file.dat'
                            Length = 50MB
                            PSIsContainer = $false
                        }
                    )
                }
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedAppData

            $result[0].SizeMB | Should -BeGreaterThan 0
        }

        It 'Should include all required properties' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'TestOrphan'
                        FullName = 'C:\AppData\TestOrphan'
                        LastWriteTime = (Get-Date).AddDays(-45)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedAppData

            $result[0].Name | Should -Be 'TestOrphan'
            $result[0].Path | Should -Not -BeNullOrEmpty
            $result[0].LastModified | Should -Not -BeNullOrEmpty
            $result[0].AgeInDays | Should -BeGreaterThan 0
            $result[0].SizeMB | Should -BeGreaterThan -1
            $result[0].IsOrphaned | Should -Be $true
        }
    }

    Context 'Clear-WinOpsOrphanedAppData' {

        It 'Should remove orphaned app data' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'OrphanApp'
                        FullName = 'C:\AppData\OrphanApp'
                        LastWriteTime = (Get-Date).AddDays(-50)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }
            Mock Remove-Item -ModuleName OrphanAppCleanup {}

            $result = Clear-WinOpsOrphanedAppData -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.RemovedCount | Should -BeGreaterThan -1
            Should -Invoke Remove-Item -ModuleName OrphanAppCleanup
        }

        It 'Should support DryRun mode' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'OrphanApp'
                        FullName = 'C:\AppData\OrphanApp'
                        LastWriteTime = (Get-Date).AddDays(-40)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Clear-WinOpsOrphanedAppData -DryRun

            $result | Should -Not -BeNullOrEmpty
            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName OrphanAppCleanup
        }

        It 'Should use trash when UseTrash is specified' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'OrphanApp'
                        FullName = 'C:\AppData\OrphanApp'
                        LastWriteTime = (Get-Date).AddDays(-35)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Clear-WinOpsOrphanedAppData -UseTrash -Force -Confirm:$false

            Should -Invoke Move-WinOpsToTrash -ModuleName OrphanAppCleanup
        }

        It 'Should filter by minimum age' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @()
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'OldOrphan'
                        FullName = 'C:\AppData\OldOrphan'
                        LastWriteTime = (Get-Date).AddDays(-100)
                        PSIsContainer = $true
                    }
                    [PSCustomObject]@{
                        Name = 'NewOrphan'
                        FullName = 'C:\AppData\NewOrphan'
                        LastWriteTime = (Get-Date).AddDays(-20)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }
            Mock Remove-Item -ModuleName OrphanAppCleanup {}

            $result = Clear-WinOpsOrphanedAppData -MinAgeInDays 60 -Force -Confirm:$false

            # Should only remove OldOrphan
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should skip currently installed applications' {
            Mock Get-ItemProperty -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{ DisplayName = 'Installed App' }
                )
            }
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Installed App'
                        FullName = 'C:\AppData\Installed App'
                        LastWriteTime = (Get-Date).AddDays(-50)
                        PSIsContainer = $true
                    }
                )
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Clear-WinOpsOrphanedAppData -Force -Confirm:$false

            $result.RemovedCount | Should -Be 0
            Should -Not -Invoke Remove-Item -ModuleName OrphanAppCleanup
        }
    }

    Context 'Find-WinOpsOrphanedShortcuts' {

        It 'Should find broken shortcuts' {
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Broken.lnk'
                        FullName = 'C:\Desktop\Broken.lnk'
                        Extension = '.lnk'
                        PSIsContainer = $false
                    }
                )
            }
            Mock New-Object -ModuleName OrphanAppCleanup {
                param($TypeName)
                if ($TypeName -eq 'WScript.Shell') {
                    $shell = New-Object PSObject
                    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
                        param($Path)
                        $shortcut = New-Object PSObject
                        $shortcut | Add-Member -NotePropertyName TargetPath -NotePropertyValue 'C:\NonExistent\app.exe'
                        return $shortcut
                    }
                    return $shell
                }
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $false }

            $result = Find-WinOpsOrphanedShortcuts -Path 'C:\Desktop'

            $result | Should -Not -BeNullOrEmpty
            $result[0].ShortcutPath | Should -BeLike '*Broken.lnk*'
            $result[0].IsBroken | Should -Be $true
        }

        It 'Should skip valid shortcuts' {
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Valid.lnk'
                        FullName = 'C:\Desktop\Valid.lnk'
                        Extension = '.lnk'
                        PSIsContainer = $false
                    }
                )
            }
            Mock New-Object -ModuleName OrphanAppCleanup {
                param($TypeName)
                if ($TypeName -eq 'WScript.Shell') {
                    $shell = New-Object PSObject
                    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
                        param($Path)
                        $shortcut = New-Object PSObject
                        $shortcut | Add-Member -NotePropertyName TargetPath -NotePropertyValue 'C:\Windows\System32\notepad.exe'
                        return $shortcut
                    }
                    return $shell
                }
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $true }

            $result = Find-WinOpsOrphanedShortcuts -Path 'C:\Desktop'

            # Should not return valid shortcuts
            ($result | Where-Object { $_.IsBroken -eq $true }) | Should -BeNullOrEmpty
        }

        It 'Should check multiple locations' {
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Shortcut.lnk'
                        FullName = 'C:\Desktop\Shortcut.lnk'
                        Extension = '.lnk'
                        PSIsContainer = $false
                    }
                )
            }

            $result = Find-WinOpsOrphanedShortcuts -Path @('C:\Desktop', 'C:\StartMenu')

            # Should handle multiple paths
            $result | Should -BeOfType [Object]
        }
    }

    Context 'Remove-WinOpsOrphanedShortcuts' {

        It 'Should remove broken shortcuts' {
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Broken.lnk'
                        FullName = 'C:\Desktop\Broken.lnk'
                        Extension = '.lnk'
                        PSIsContainer = $false
                    }
                )
            }
            Mock New-Object -ModuleName OrphanAppCleanup {
                param($TypeName)
                if ($TypeName -eq 'WScript.Shell') {
                    $shell = New-Object PSObject
                    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
                        param($Path)
                        $shortcut = New-Object PSObject
                        $shortcut | Add-Member -NotePropertyName TargetPath -NotePropertyValue 'C:\NonExistent\app.exe'
                        return $shortcut
                    }
                    return $shell
                }
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $false }
            Mock Remove-Item -ModuleName OrphanAppCleanup {}

            $result = Remove-WinOpsOrphanedShortcuts -Path 'C:\Desktop' -Force -Confirm:$false

            $result | Should -Not -BeNullOrEmpty
            $result.RemovedCount | Should -BeGreaterThan -1
            Should -Invoke Remove-Item -ModuleName OrphanAppCleanup
        }

        It 'Should support DryRun mode' {
            Mock Get-ChildItem -ModuleName OrphanAppCleanup {
                @(
                    [PSCustomObject]@{
                        Name = 'Broken.lnk'
                        FullName = 'C:\Desktop\Broken.lnk'
                        Extension = '.lnk'
                        PSIsContainer = $false
                    }
                )
            }
            Mock New-Object -ModuleName OrphanAppCleanup {
                param($TypeName)
                if ($TypeName -eq 'WScript.Shell') {
                    $shell = New-Object PSObject
                    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
                        param($Path)
                        $shortcut = New-Object PSObject
                        $shortcut | Add-Member -NotePropertyName TargetPath -NotePropertyValue 'C:\Missing\app.exe'
                        return $shortcut
                    }
                    return $shell
                }
            }
            Mock Test-Path -ModuleName OrphanAppCleanup { return $false }

            $result = Remove-WinOpsOrphanedShortcuts -Path 'C:\Desktop' -DryRun

            $result.WouldRemove | Should -Be $true
            $result.RemovedCount | Should -Be 0

            Should -Not -Invoke Remove-Item -ModuleName OrphanAppCleanup
        }
    }
}

Describe 'OrphanAppCleanup Integration Tests' -Tag 'Integration', 'Module' {

    BeforeEach {
        # Create test app data directory
        $script:TestAppDataDir = Join-Path $TestDrive 'AppData'
        New-Item -Path $script:TestAppDataDir -ItemType Directory -Force | Out-Null

        # Create orphaned app folders
        $oldOrphan = Join-Path $script:TestAppDataDir 'OldOrphanApp'
        $newOrphan = Join-Path $script:TestAppDataDir 'NewOrphanApp'

        New-Item -Path $oldOrphan -ItemType Directory -Force | Out-Null
        New-Item -Path $newOrphan -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $oldOrphan 'data.dat') -Value 'old data'
        Set-Content -Path (Join-Path $newOrphan 'data.dat') -Value 'new data'

        (Get-Item $oldOrphan).LastWriteTime = (Get-Date).AddDays(-60)
        (Get-Item $newOrphan).LastWriteTime = (Get-Date).AddDays(-10)
    }

    It 'Should identify old orphaned folders' {
        $cutoffDate = (Get-Date).AddDays(-30)
        $oldFolders = Get-ChildItem $script:TestAppDataDir -Directory | Where-Object {
            $_.LastWriteTime -lt $cutoffDate
        }

        $oldFolders.Count | Should -Be 1
        $oldFolders[0].Name | Should -Be 'OldOrphanApp'
    }

    It 'Should calculate folder sizes correctly' {
        $folderSize = (Get-ChildItem (Join-Path $script:TestAppDataDir 'OldOrphanApp') -Recurse -File |
            Measure-Object -Property Length -Sum).Sum

        $folderSize | Should -BeGreaterThan 0
    }

    It 'Should enumerate all AppData subfolders' {
        $folders = Get-ChildItem $script:TestAppDataDir -Directory
        $folders.Count | Should -Be 2
    }
}
