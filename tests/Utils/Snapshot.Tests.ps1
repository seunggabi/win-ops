#Requires -Modules Pester

BeforeAll {
    $script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\lib\utils\Snapshot.psm1"
    Import-Module $script:ModulePath -Force

    # Mock CIM data for testing
    Mock -ModuleName Snapshot New-CimSession {
        return [PSCustomObject]@{
            Id = 1
            Name = 'MockCimSession'
        }
    }

    Mock -ModuleName Snapshot Get-CimInstance {
        param($CimSession, $ClassName, $Filter)

        switch ($ClassName) {
            'Win32_LogicalDisk' {
                return @(
                    [PSCustomObject]@{
                        DeviceID = 'C:'
                        Size = 500GB
                        FreeSpace = 200GB
                        VolumeName = 'System'
                        DriveType = 3
                    },
                    [PSCustomObject]@{
                        DeviceID = 'D:'
                        Size = 1TB
                        FreeSpace = 500GB
                        VolumeName = 'Data'
                        DriveType = 3
                    }
                )
            }
            'Win32_OperatingSystem' {
                return [PSCustomObject]@{
                    TotalVisibleMemorySize = 16GB / 1KB  # In KB
                    FreePhysicalMemory = 8GB / 1KB       # In KB
                }
            }
            'Win32_Processor' {
                return @(
                    [PSCustomObject]@{
                        NumberOfCores = 8
                        NumberOfLogicalProcessors = 16
                        LoadPercentage = 45
                    }
                )
            }
        }
    }

    Mock -ModuleName Snapshot Remove-CimSession {}
}

AfterAll {
    Remove-Module -Name Snapshot -ErrorAction SilentlyContinue
}

Describe "Get-WinOpsSnapshot" {
    Context "Basic functionality" {
        It "Should capture snapshot without error" {
            { Get-WinOpsSnapshot } | Should -Not -Throw
        }

        It "Should return hashtable by default" {
            $snapshot = Get-WinOpsSnapshot
            $snapshot | Should -BeOfType [hashtable]
        }

        It "Should include timestamp" {
            $snapshot = Get-WinOpsSnapshot
            $snapshot.Timestamp | Should -Not -BeNullOrEmpty
            $snapshot.TimestampUtc | Should -Not -BeNullOrEmpty
        }

        It "Should capture all components by default" {
            $snapshot = Get-WinOpsSnapshot
            $snapshot.Keys | Should -Contain 'Disk'
            $snapshot.Keys | Should -Contain 'Memory'
            $snapshot.Keys | Should -Contain 'CPU'
        }
    }

    Context "Selective component capture" {
        It "Should capture only disk when specified" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $snapshot.Keys | Should -Contain 'Disk'
            $snapshot.Keys | Should -Not -Contain 'Memory'
            $snapshot.Keys | Should -Not -Contain 'CPU'
        }

        It "Should capture only memory when specified" {
            $snapshot = Get-WinOpsSnapshot -IncludeMemory
            $snapshot.Keys | Should -Not -Contain 'Disk'
            $snapshot.Keys | Should -Contain 'Memory'
            $snapshot.Keys | Should -Not -Contain 'CPU'
        }

        It "Should capture only CPU when specified" {
            $snapshot = Get-WinOpsSnapshot -IncludeCPU
            $snapshot.Keys | Should -Not -Contain 'Disk'
            $snapshot.Keys | Should -Not -Contain 'Memory'
            $snapshot.Keys | Should -Contain 'CPU'
        }

        It "Should capture multiple components when specified" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk -IncludeMemory
            $snapshot.Keys | Should -Contain 'Disk'
            $snapshot.Keys | Should -Contain 'Memory'
            $snapshot.Keys | Should -Not -Contain 'CPU'
        }
    }

    Context "Disk snapshot" {
        It "Should capture disk information" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $snapshot.Disk | Should -Not -BeNullOrEmpty
        }

        It "Should capture multiple drives" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $snapshot.Disk.Count | Should -BeGreaterOrEqual 2
            $snapshot.Disk.Keys | Should -Contain 'C:'
            $snapshot.Disk.Keys | Should -Contain 'D:'
        }

        It "Should include drive details" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $drive = $snapshot.Disk['C:']

            $drive.Keys | Should -Contain 'TotalBytes'
            $drive.Keys | Should -Contain 'UsedBytes'
            $drive.Keys | Should -Contain 'FreeBytes'
            $drive.Keys | Should -Contain 'TotalGB'
            $drive.Keys | Should -Contain 'UsedGB'
            $drive.Keys | Should -Contain 'FreeGB'
            $drive.Keys | Should -Contain 'UsedPercent'
            $drive.Keys | Should -Contain 'VolumeName'
        }

        It "Should calculate used space correctly" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $drive = $snapshot.Disk['C:']

            $drive.UsedBytes | Should -Be ($drive.TotalBytes - $drive.FreeBytes)
        }

        It "Should calculate percentage correctly" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $drive = $snapshot.Disk['C:']

            $expectedPercent = [math]::Round(($drive.UsedBytes / $drive.TotalBytes) * 100, 2)
            $drive.UsedPercent | Should -Be $expectedPercent
        }

        It "Should convert to GB correctly" {
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $drive = $snapshot.Disk['C:']

            $drive.TotalGB | Should -Be ([math]::Round($drive.TotalBytes / 1GB, 2))
            $drive.FreeGB | Should -Be ([math]::Round($drive.FreeBytes / 1GB, 2))
        }
    }

    Context "Memory snapshot" {
        It "Should capture memory information" {
            $snapshot = Get-WinOpsSnapshot -IncludeMemory
            $snapshot.Memory | Should -Not -BeNullOrEmpty
        }

        It "Should include memory details" {
            $snapshot = Get-WinOpsSnapshot -IncludeMemory
            $mem = $snapshot.Memory

            $mem.Keys | Should -Contain 'TotalBytes'
            $mem.Keys | Should -Contain 'UsedBytes'
            $mem.Keys | Should -Contain 'FreeBytes'
            $mem.Keys | Should -Contain 'TotalGB'
            $mem.Keys | Should -Contain 'UsedGB'
            $mem.Keys | Should -Contain 'FreeGB'
            $mem.Keys | Should -Contain 'UsedPercent'
        }

        It "Should calculate used memory correctly" {
            $snapshot = Get-WinOpsSnapshot -IncludeMemory
            $mem = $snapshot.Memory

            $mem.UsedBytes | Should -Be ($mem.TotalBytes - $mem.FreeBytes)
        }

        It "Should calculate memory percentage correctly" {
            $snapshot = Get-WinOpsSnapshot -IncludeMemory
            $mem = $snapshot.Memory

            $expectedPercent = [math]::Round(($mem.UsedBytes / $mem.TotalBytes) * 100, 2)
            $mem.UsedPercent | Should -Be $expectedPercent
        }
    }

    Context "CPU snapshot" {
        It "Should capture CPU information" {
            $snapshot = Get-WinOpsSnapshot -IncludeCPU
            $snapshot.CPU | Should -Not -BeNullOrEmpty
        }

        It "Should include CPU details" {
            $snapshot = Get-WinOpsSnapshot -IncludeCPU
            $cpu = $snapshot.CPU

            $cpu.Keys | Should -Contain 'Cores'
            $cpu.Keys | Should -Contain 'LogicalProcessors'
            $cpu.Keys | Should -Contain 'LoadPercent'
            $cpu.Keys | Should -Contain 'ProcessorCount'
        }

        It "Should capture processor count" {
            $snapshot = Get-WinOpsSnapshot -IncludeCPU
            $snapshot.CPU.ProcessorCount | Should -BeGreaterThan 0
        }

        It "Should capture load percentage" {
            $snapshot = Get-WinOpsSnapshot -IncludeCPU
            $snapshot.CPU.LoadPercent | Should -BeGreaterOrEqual 0
            $snapshot.CPU.LoadPercent | Should -BeLessOrEqual 100
        }
    }

    Context "Output formats" {
        It "Should return raw format by default" {
            $snapshot = Get-WinOpsSnapshot
            $snapshot | Should -BeOfType [hashtable]
        }

        It "Should return formatted text" {
            $snapshot = Get-WinOpsSnapshot -Format Formatted
            $snapshot | Should -BeOfType [string]
            $snapshot | Should -Match "System Snapshot"
        }

        It "Should return JSON format" {
            $snapshot = Get-WinOpsSnapshot -Format JSON
            $snapshot | Should -BeOfType [string]
            { $snapshot | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should validate format parameter" {
            { Get-WinOpsSnapshot -Format "InvalidFormat" } | Should -Throw
        }
    }
}

Describe "Compare-WinOpsSnapshot" {
    Context "Basic comparison" {
        It "Should compare snapshots without error" {
            $before = Get-WinOpsSnapshot
            $after = Get-WinOpsSnapshot

            { Compare-WinOpsSnapshot -Before $before -After $after } | Should -Not -Throw
        }

        It "Should require before parameter" {
            $after = Get-WinOpsSnapshot
            { Compare-WinOpsSnapshot -After $after } | Should -Throw
        }

        It "Should require after parameter" {
            $before = Get-WinOpsSnapshot
            { Compare-WinOpsSnapshot -Before $before } | Should -Throw
        }

        It "Should include timestamps in comparison" {
            $before = Get-WinOpsSnapshot
            $after = Get-WinOpsSnapshot

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.BeforeTimestamp | Should -Be $before.Timestamp
            $comparison.AfterTimestamp | Should -Be $after.Timestamp
        }
    }

    Context "Disk comparison" {
        It "Should compare disk usage" {
            $before = Get-WinOpsSnapshot -IncludeDisk

            # Simulate disk space freed
            Mock -ModuleName Snapshot Get-CimInstance {
                param($CimSession, $ClassName, $Filter)
                if ($ClassName -eq 'Win32_LogicalDisk') {
                    return @(
                        [PSCustomObject]@{
                            DeviceID = 'C:'
                            Size = 500GB
                            FreeSpace = 250GB  # 50GB more free
                            VolumeName = 'System'
                            DriveType = 3
                        }
                    )
                }
            }

            $after = Get-WinOpsSnapshot -IncludeDisk
            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.Disk['C:'].FreedBytes | Should -BeGreaterThan 0
        }

        It "Should calculate freed space" {
            $before = @{
                Timestamp = '2024-01-01 10:00:00'
                Disk = @{
                    'C:' = @{
                        FreeBytes = 100GB
                        FreeGB = 100
                        UsedPercent = 80
                    }
                }
            }

            $after = @{
                Timestamp = '2024-01-01 10:30:00'
                Disk = @{
                    'C:' = @{
                        FreeBytes = 120GB
                        FreeGB = 120
                        UsedPercent = 76
                    }
                }
            }

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.Disk['C:'].FreedBytes | Should -Be 20GB
            $comparison.Disk['C:'].FreedGB | Should -Be 20
            $comparison.Disk['C:'].UsedPercentChange | Should -Be -4
        }

        It "Should handle multiple drives" {
            $before = Get-WinOpsSnapshot -IncludeDisk
            $after = Get-WinOpsSnapshot -IncludeDisk

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.Disk.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Memory comparison" {
        It "Should compare memory usage" {
            $before = @{
                Timestamp = '2024-01-01 10:00:00'
                Memory = @{
                    FreeBytes = 4GB
                    FreeGB = 4
                    UsedPercent = 75
                }
            }

            $after = @{
                Timestamp = '2024-01-01 10:30:00'
                Memory = @{
                    FreeBytes = 6GB
                    FreeGB = 6
                    UsedPercent = 62.5
                }
            }

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.Memory.FreedBytes | Should -Be 2GB
            $comparison.Memory.FreedGB | Should -Be 2
            $comparison.Memory.UsedPercentChange | Should -Be -12.5
        }

        It "Should handle memory increase" {
            $before = @{
                Timestamp = '2024-01-01 10:00:00'
                Memory = @{
                    FreeBytes = 8GB
                    FreeGB = 8
                    UsedPercent = 50
                }
            }

            $after = @{
                Timestamp = '2024-01-01 10:30:00'
                Memory = @{
                    FreeBytes = 6GB
                    FreeGB = 6
                    UsedPercent = 62.5
                }
            }

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.Memory.FreedBytes | Should -Be -2GB
            $comparison.Memory.UsedPercentChange | Should -BeGreaterThan 0
        }
    }

    Context "CPU comparison" {
        It "Should compare CPU load" {
            $before = @{
                Timestamp = '2024-01-01 10:00:00'
                CPU = @{
                    LoadPercent = 80
                }
            }

            $after = @{
                Timestamp = '2024-01-01 10:30:00'
                CPU = @{
                    LoadPercent = 45
                }
            }

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.CPU.BeforeLoadPercent | Should -Be 80
            $comparison.CPU.AfterLoadPercent | Should -Be 45
            $comparison.CPU.LoadPercentChange | Should -Be -35
        }

        It "Should handle CPU load increase" {
            $before = @{
                Timestamp = '2024-01-01 10:00:00'
                CPU = @{
                    LoadPercent = 30
                }
            }

            $after = @{
                Timestamp = '2024-01-01 10:30:00'
                CPU = @{
                    LoadPercent = 60
                }
            }

            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison.CPU.LoadPercentChange | Should -Be 30
        }
    }

    Context "Output formats" {
        It "Should return formatted text by default" {
            $before = Get-WinOpsSnapshot
            $after = Get-WinOpsSnapshot

            $result = Compare-WinOpsSnapshot -Before $before -After $after
            $result | Should -BeOfType [string]
            $result | Should -Match "Snapshot Comparison"
        }

        It "Should return raw format" {
            $before = Get-WinOpsSnapshot
            $after = Get-WinOpsSnapshot

            $result = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw
            $result | Should -BeOfType [hashtable]
        }

        It "Should return JSON format" {
            $before = Get-WinOpsSnapshot
            $after = Get-WinOpsSnapshot

            $result = Compare-WinOpsSnapshot -Before $before -After $after -Format JSON
            $result | Should -BeOfType [string]
            { $result | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}

Describe "Export-WinOpsSnapshot" {
    Context "Basic export" {
        It "Should export snapshot to file" {
            $snapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"

            { Export-WinOpsSnapshot -Snapshot $snapshot -Path $path } | Should -Not -Throw
            Test-Path -Path $path | Should -Be $true
        }

        It "Should create directory if not exists" {
            $snapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "subdir\snapshot.json"

            Export-WinOpsSnapshot -Snapshot $snapshot -Path $path
            Test-Path -Path $path | Should -Be $true
        }

        It "Should write valid JSON" {
            $snapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"

            Export-WinOpsSnapshot -Snapshot $snapshot -Path $path
            $content = Get-Content -Path $path -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should accept pipeline input" {
            $snapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"

            { $snapshot | Export-WinOpsSnapshot -Path $path } | Should -Not -Throw
        }

        It "Should require snapshot parameter" {
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"
            { Export-WinOpsSnapshot -Path $path } | Should -Throw
        }

        It "Should require path parameter" {
            $snapshot = Get-WinOpsSnapshot
            { Export-WinOpsSnapshot -Snapshot $snapshot } | Should -Throw
        }
    }
}

Describe "Import-WinOpsSnapshot" {
    Context "Basic import" {
        It "Should import snapshot from file" {
            $originalSnapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"
            Export-WinOpsSnapshot -Snapshot $originalSnapshot -Path $path

            $importedSnapshot = Import-WinOpsSnapshot -Path $path
            $importedSnapshot | Should -Not -BeNullOrEmpty
        }

        It "Should throw if file does not exist" {
            $path = Join-Path -Path $TestDrive -ChildPath "nonexistent.json"
            { Import-WinOpsSnapshot -Path $path } | Should -Throw "*not found*"
        }

        It "Should require path parameter" {
            { Import-WinOpsSnapshot } | Should -Throw
        }

        It "Should preserve snapshot data" {
            $originalSnapshot = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "snapshot.json"
            Export-WinOpsSnapshot -Snapshot $originalSnapshot -Path $path

            $importedSnapshot = Import-WinOpsSnapshot -Path $path

            $importedSnapshot.Timestamp | Should -Be $originalSnapshot.Timestamp
        }
    }

    Context "Round-trip export/import" {
        It "Should maintain data integrity through export/import" {
            $original = Get-WinOpsSnapshot
            $path = Join-Path -Path $TestDrive -ChildPath "roundtrip.json"

            Export-WinOpsSnapshot -Snapshot $original -Path $path
            $imported = Import-WinOpsSnapshot -Path $path

            $imported.Timestamp | Should -Be $original.Timestamp
            $imported.Keys.Count | Should -Be $original.Keys.Count
        }
    }
}

Describe "Module cleanup" {
    Context "CIM session cleanup" {
        It "Should cleanup CIM session on module removal" {
            # Create snapshot to initialize CIM session
            Get-WinOpsSnapshot | Out-Null

            # Remove module should trigger cleanup
            { Remove-Module -Name Snapshot -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}

Describe "Error handling" {
    Context "CIM failures" {
        It "Should handle CIM session creation failure" {
            Mock -ModuleName Snapshot New-CimSession {
                throw "CIM session failed"
            }

            # Should handle gracefully
            { Get-WinOpsSnapshot -IncludeDisk } | Should -Not -Throw
        }

        It "Should handle Get-CimInstance failure" {
            Mock -ModuleName Snapshot Get-CimInstance {
                throw "CIM query failed"
            }

            # Should return empty data rather than throw
            $snapshot = Get-WinOpsSnapshot -IncludeDisk
            $snapshot.Disk | Should -BeNullOrEmpty
        }
    }
}

Describe "Integration scenarios" {
    Context "Before/after cleanup workflow" {
        It "Should support typical cleanup workflow" {
            # Capture before
            $before = Get-WinOpsSnapshot

            # Simulate cleanup (would happen here)
            Start-Sleep -Milliseconds 100

            # Capture after
            $after = Get-WinOpsSnapshot

            # Compare
            $comparison = Compare-WinOpsSnapshot -Before $before -After $after -Format Raw

            $comparison | Should -Not -BeNullOrEmpty
            $comparison.BeforeTimestamp | Should -Not -Be $comparison.AfterTimestamp
        }

        It "Should support export workflow for audit trail" {
            $before = Get-WinOpsSnapshot
            $beforePath = Join-Path -Path $TestDrive -ChildPath "before.json"
            Export-WinOpsSnapshot -Snapshot $before -Path $beforePath

            $after = Get-WinOpsSnapshot
            $afterPath = Join-Path -Path $TestDrive -ChildPath "after.json"
            Export-WinOpsSnapshot -Snapshot $after -Path $afterPath

            Test-Path -Path $beforePath | Should -Be $true
            Test-Path -Path $afterPath | Should -Be $true

            # Can load and compare later
            $loadedBefore = Import-WinOpsSnapshot -Path $beforePath
            $loadedAfter = Import-WinOpsSnapshot -Path $afterPath

            { Compare-WinOpsSnapshot -Before $loadedBefore -After $loadedAfter } | Should -Not -Throw
        }
    }
}
