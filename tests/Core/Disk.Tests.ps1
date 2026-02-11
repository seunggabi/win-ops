#Requires -Modules Pester

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot "..\..\lib\core\Disk.psm1"
    Import-Module $ModulePath -Force

    # Setup test environment
    $script:TestDiskDir = Join-Path $env:TEMP "WinOpsDiskTests_$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $script:TestDiskDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestDiskDir) {
        Remove-Item $script:TestDiskDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove module
    Remove-Module Disk -Force -ErrorAction SilentlyContinue
}

Describe "Disk Module - ConvertTo-HumanReadableSize" {
    It "Converts bytes correctly" {
        ConvertTo-HumanReadableSize -Bytes 512 | Should -Be "512.00 B"
    }

    It "Converts kilobytes correctly" {
        ConvertTo-HumanReadableSize -Bytes 1024 | Should -Be "1.00 KB"
    }

    It "Converts megabytes correctly" {
        ConvertTo-HumanReadableSize -Bytes (1024 * 1024) | Should -Be "1.00 MB"
    }

    It "Converts gigabytes correctly" {
        ConvertTo-HumanReadableSize -Bytes (1024 * 1024 * 1024) | Should -Be "1.00 GB"
    }

    It "Converts terabytes correctly" {
        $size = [long]1024 * 1024 * 1024 * 1024
        ConvertTo-HumanReadableSize -Bytes $size | Should -Be "1.00 TB"
    }

    It "Handles zero bytes" {
        ConvertTo-HumanReadableSize -Bytes 0 | Should -Be "0 B"
    }

    It "Respects precision parameter" {
        ConvertTo-HumanReadableSize -Bytes 1500 -Precision 0 | Should -Match "1 KB"
        ConvertTo-HumanReadableSize -Bytes 1500 -Precision 3 | Should -Match "1.464 KB"
    }

    It "Handles large values" {
        $size = [long]5 * 1024 * 1024 * 1024 * 1024  # 5 TB
        $result = ConvertTo-HumanReadableSize -Bytes $size
        $result | Should -Match "5\.\d+ TB"
    }

    It "Supports pipeline input" {
        $result = 2048 | ConvertTo-HumanReadableSize
        $result | Should -Match "2\.\d+ KB"
    }

    It "Rounds values appropriately" {
        $result = ConvertTo-HumanReadableSize -Bytes 1536
        $result | Should -Be "1.50 KB"
    }
}

Describe "Disk Module - Get-WinOpsDiskUsage" {
    It "Returns disk usage information" {
        $result = Get-WinOpsDiskUsage
        $result | Should -Not -BeNullOrEmpty
    }

    It "Includes system drive" {
        $result = Get-WinOpsDiskUsage
        $result.Drive | Should -Contain "C:"
    }

    It "Returns all required properties" {
        $result = Get-WinOpsDiskUsage | Select-Object -First 1

        $result.Drive | Should -Not -BeNullOrEmpty
        $result.DriveType | Should -Not -BeNullOrEmpty
        $result.TotalSizeBytes | Should -BeGreaterThan 0
        $result.FreeSizeBytes | Should -BeGreaterOrEqual 0
        $result.UsedSizeBytes | Should -BeGreaterOrEqual 0
        $result.UsagePercent | Should -BeGreaterOrEqual 0
    }

    It "Calculates usage percentage correctly" {
        $result = Get-WinOpsDiskUsage -DriveLetter "C:"

        $expectedPercent = ($result.UsedSizeBytes / $result.TotalSizeBytes) * 100
        [Math]::Abs($result.UsagePercent - $expectedPercent) | Should -BeLessThan 0.1
    }

    It "Filters by drive letter" {
        $result = Get-WinOpsDiskUsage -DriveLetter "C:"
        $result.Drive | Should -Be "C:"
    }

    It "Accepts drive letter without colon" {
        $result = Get-WinOpsDiskUsage -DriveLetter "C"
        $result.Drive | Should -Be "C:"
    }

    It "Returns human readable sizes when flag is set" {
        $result = Get-WinOpsDiskUsage -DriveLetter "C:" -AsHumanReadable

        $result.TotalSize | Should -Match "GB|TB"
        $result.FreeSpace | Should -Match "GB|TB|MB"
        $result.UsedSpace | Should -Match "GB|TB|MB"
    }

    It "Excludes network drives when flag is set" {
        $result = Get-WinOpsDiskUsage -ExcludeNetworkDrives
        $result | Where-Object { $_.DriveType -eq "Network" } | Should -BeNullOrEmpty
    }

    It "Excludes removable drives when flag is set" {
        $result = Get-WinOpsDiskUsage -ExcludeRemovableDrives
        $result | Where-Object { $_.DriveType -eq "Removable" } | Should -BeNullOrEmpty
    }

    It "Skips drives with no media" {
        # Should not throw on empty CD drives
        { Get-WinOpsDiskUsage } | Should -Not -Throw
    }

    It "Returns correct drive types" {
        $result = Get-WinOpsDiskUsage
        $validTypes = @('Local', 'Removable', 'Network', 'CD-ROM', 'RAM Disk', 'Unknown')
        foreach ($drive in $result) {
            $validTypes | Should -Contain $drive.DriveType
        }
    }

    It "Includes volume label and file system" {
        $result = Get-WinOpsDiskUsage -DriveLetter "C:"
        # FileSystem should be NTFS or similar
        $result.FileSystem | Should -Not -BeNullOrEmpty
    }

    It "Has custom type name" {
        $result = Get-WinOpsDiskUsage | Select-Object -First 1
        $result.PSObject.TypeNames[0] | Should -Be 'WinOps.DiskUsage'
    }

    It "Supports multiple drive letters" {
        $result = Get-WinOpsDiskUsage -DriveLetter @("C:", "D:")
        # Should return C: and D: if both exist, or just C:
        $result.Count | Should -BeGreaterOrEqual 1
    }
}

Describe "Disk Module - Test-WinOpsDiskSpace" {
    It "Returns true when sufficient space exists" {
        $result = Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredGB 0.1
        $result | Should -Be $true
    }

    It "Checks space by bytes" {
        $result = Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredBytes 1MB
        $result | Should -Not -BeNullOrEmpty
    }

    It "Checks space by gigabytes" {
        $result = Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredGB 1
        $result | Should -Not -BeNullOrEmpty
    }

    It "Checks space by percentage" {
        $result = Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredPercent 5
        $result | Should -Not -BeNullOrEmpty
    }

    It "Returns false for non-existent drive" {
        $result = Test-WinOpsDiskSpace -DriveLetter "Z:" -RequiredGB 1 -ErrorAction SilentlyContinue
        $result | Should -Be $false
    }

    It "Handles very large requirements" {
        $result = Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredGB 999999
        $result | Should -Be $false
    }

    It "Uses default of 1GB when RequiredBytes is 0" {
        { Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredBytes 0 } | Should -Not -Throw
    }

    It "Validates percentage range" {
        # Should not accept invalid percentages
        { Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredPercent 150 } | Should -Throw
        { Test-WinOpsDiskSpace -DriveLetter "C:" -RequiredPercent -10 } | Should -Throw
    }

    It "Supports pipeline input" {
        $result = "C:" | Test-WinOpsDiskSpace -RequiredGB 1
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Disk Module - Get-WinOpsLargestFiles" {
    BeforeEach {
        # Create test files
        1..5 | ForEach-Object {
            $file = Join-Path $script:TestDiskDir "file$_.txt"
            $content = "x" * ($_ * 1000)
            $content | Set-Content $file
        }
    }

    AfterEach {
        Get-ChildItem $script:TestDiskDir | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It "Returns largest files" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 3

        $result.Count | Should -Be 3
        # Files should be sorted by size descending
        $result[0].SizeBytes | Should -BeGreaterOrEqual $result[1].SizeBytes
    }

    It "Includes all required properties" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 1

        $result.FileName | Should -Not -BeNullOrEmpty
        $result.FullPath | Should -Not -BeNullOrEmpty
        $result.SizeBytes | Should -BeGreaterThan 0
        $result.LastModified | Should -Not -BeNullOrEmpty
        $result.Extension | Should -Not -BeNullOrEmpty
    }

    It "Returns human readable sizes when flag is set" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 1 -AsHumanReadable

        $result.Size | Should -Match "B|KB|MB"
    }

    It "Filters by minimum size in GB" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -MinimumSizeGB 1

        # Our test files are small, so should return empty
        $result | Should -BeNullOrEmpty
    }

    It "Filters by minimum size in MB" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -MinimumSizeMB 1

        # Our test files are small, so should return empty
        $result | Should -BeNullOrEmpty
    }

    It "Excludes system files when flag is set" {
        { Get-WinOpsLargestFiles -Path $script:TestDiskDir -ExcludeSystemFiles } |
            Should -Not -Throw
    }

    It "Handles empty directories" {
        $emptyDir = Join-Path $script:TestDiskDir "empty"
        New-Item -Path $emptyDir -ItemType Directory | Out-Null

        $result = Get-WinOpsLargestFiles -Path $emptyDir

        $result | Should -BeNullOrEmpty
    }

    It "Throws on non-existent path" {
        { Get-WinOpsLargestFiles -Path "C:\NonExistent\Path" -ErrorAction Stop } |
            Should -Throw
    }

    It "Throws on file path instead of directory" {
        $filePath = Join-Path $script:TestDiskDir "file1.txt"
        { Get-WinOpsLargestFiles -Path $filePath -ErrorAction Stop } | Should -Throw
    }

    It "Respects Top parameter" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 2

        $result.Count | Should -Be 2
    }

    It "Includes file attributes" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 1

        $result.IsReadOnly | Should -Not -BeNullOrEmpty
        $result.Attributes | Should -Not -BeNullOrEmpty
    }

    It "Has custom type name" {
        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 1
        $result.PSObject.TypeNames[0] | Should -Be 'WinOps.LargeFile'
    }

    It "Recursively scans subdirectories" {
        $subDir = Join-Path $script:TestDiskDir "subdir"
        New-Item -Path $subDir -ItemType Directory | Out-Null
        "large content" | Set-Content (Join-Path $subDir "sublarge.txt")

        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir

        $result.FileName | Should -Contain "sublarge.txt"
    }

    It "Supports pipeline input" {
        $result = $script:TestDiskDir | Get-WinOpsLargestFiles -Top 1
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Disk Module - Get-WinOpsDirectorySize" {
    BeforeEach {
        # Create test structure
        1..3 | ForEach-Object {
            $file = Join-Path $script:TestDiskDir "file$_.txt"
            $content = "x" * ($_ * 1000)
            $content | Set-Content $file
        }

        $subDir = Join-Path $script:TestDiskDir "subdir"
        New-Item -Path $subDir -ItemType Directory | Out-Null
        "subcontent" | Set-Content (Join-Path $subDir "subfile.txt")
    }

    AfterEach {
        Get-ChildItem $script:TestDiskDir -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Calculates directory size" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir

        $result.TotalSizeBytes | Should -BeGreaterThan 0
        $result.FileCount | Should -BeGreaterThan 0
    }

    It "Includes all required properties" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir

        $result.Path | Should -Be $script:TestDiskDir
        $result.TotalSizeBytes | Should -BeGreaterThan 0
        $result.FileCount | Should -BeGreaterThan 0
    }

    It "Returns human readable size when flag is set" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir -AsHumanReadable

        $result.TotalSize | Should -Match "B|KB|MB"
    }

    It "Includes subdirectory breakdown when flag is set" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir -IncludeSubdirectories

        $result.Subdirectories | Should -Not -BeNullOrEmpty
        $result.Subdirectories.Count | Should -BeGreaterThan 0
    }

    It "Subdirectory info includes all properties" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir -IncludeSubdirectories

        $subdir = $result.Subdirectories | Select-Object -First 1
        $subdir.Name | Should -Not -BeNullOrEmpty
        $subdir.Path | Should -Not -BeNullOrEmpty
        $subdir.SizeBytes | Should -BeGreaterOrEqual 0
        $subdir.FileCount | Should -BeGreaterOrEqual 0
    }

    It "Excludes system files when flag is set" {
        { Get-WinOpsDirectorySize -Path $script:TestDiskDir -ExcludeSystemFiles } |
            Should -Not -Throw
    }

    It "Handles empty directories" {
        $emptyDir = Join-Path $script:TestDiskDir "empty"
        New-Item -Path $emptyDir -ItemType Directory | Out-Null

        $result = Get-WinOpsDirectorySize -Path $emptyDir

        $result.TotalSizeBytes | Should -Be 0
        $result.FileCount | Should -Be 0
    }

    It "Throws on non-existent path" {
        { Get-WinOpsDirectorySize -Path "C:\NonExistent\Path" -ErrorAction Stop } |
            Should -Throw
    }

    It "Throws on file path instead of directory" {
        $filePath = Join-Path $script:TestDiskDir "file1.txt"
        { Get-WinOpsDirectorySize -Path $filePath -ErrorAction Stop } | Should -Throw
    }

    It "Recursively includes all nested files" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir

        # Should include files in root and subdirectories
        $result.FileCount | Should -BeGreaterThan 3
    }

    It "Has custom type name" {
        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir
        $result.PSObject.TypeNames[0] | Should -Be 'WinOps.DirectorySize'
    }

    It "Supports pipeline input" {
        $result = $script:TestDiskDir | Get-WinOpsDirectorySize
        $result | Should -Not -BeNullOrEmpty
    }

    It "Supports FullName alias for pipeline" {
        $dirItem = Get-Item $script:TestDiskDir
        $result = $dirItem | Get-WinOpsDirectorySize
        $result | Should -Not -BeNullOrEmpty
    }

    It "Handles deeply nested directories" {
        $deep = Join-Path $script:TestDiskDir "a\b\c\d\e"
        New-Item -Path $deep -ItemType Directory -Force | Out-Null
        "deep" | Set-Content (Join-Path $deep "deep.txt")

        { Get-WinOpsDirectorySize -Path $script:TestDiskDir } | Should -Not -Throw
    }
}

Describe "Disk Module - CIM Session Management" {
    It "Uses CIM for disk queries" {
        # Should not throw and should use CIM internally
        { Get-WinOpsDiskUsage } | Should -Not -Throw
    }

    It "Handles CIM session failures gracefully" {
        # Even if CIM fails, the functions should not throw
        { Get-WinOpsDiskUsage } | Should -Not -Throw
    }
}

Describe "Disk Module - Edge Cases" {
    It "Handles zero-byte files" {
        $emptyFile = Join-Path $script:TestDiskDir "empty.txt"
        New-Item -Path $emptyFile -ItemType File | Out-Null

        $result = Get-WinOpsLargestFiles -Path $script:TestDiskDir -Top 10
        $empty = $result | Where-Object { $_.FileName -eq "empty.txt" }
        $empty.SizeBytes | Should -Be 0
    }

    It "Handles directories with special characters" {
        $specialDir = Join-Path $script:TestDiskDir "dir[special](chars)"
        New-Item -Path $specialDir -ItemType Directory -Force | Out-Null
        "test" | Set-Content (Join-Path $specialDir "file.txt")

        { Get-WinOpsDirectorySize -Path $specialDir } | Should -Not -Throw
    }

    It "Handles very large file counts" {
        # Create many small files
        1..50 | ForEach-Object {
            $file = Join-Path $script:TestDiskDir "many$_.txt"
            "x" | Set-Content $file
        }

        $result = Get-WinOpsDirectorySize -Path $script:TestDiskDir
        $result.FileCount | Should -BeGreaterThan 50
    }

    It "Handles access denied errors gracefully" {
        # Should not throw on inaccessible directories
        { Get-WinOpsLargestFiles -Path "C:\System Volume Information" -ErrorAction SilentlyContinue } |
            Should -Not -Throw
    }
}

Describe "Disk Module - Performance" {
    It "Completes disk usage query within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Get-WinOpsDiskUsage -DriveLetter "C:"
        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
    }

    It "Completes directory size calculation within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Get-WinOpsDirectorySize -Path $script:TestDiskDir
        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000
    }
}
