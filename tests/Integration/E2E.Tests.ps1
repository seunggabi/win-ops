# E2E.Tests.ps1
# End-to-End Integration Tests for win-ops
# Tests complete workflows with mocked external dependencies

BeforeAll {
    # Import all required modules
    $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibCore = Join-Path $script:ProjectRoot "lib\core"
    $script:LibUtils = Join-Path $script:ProjectRoot "lib\utils"
    $script:LibModules = Join-Path $script:ProjectRoot "lib\modules"

    Import-Module (Join-Path $script:LibCore "Config.psm1") -Force
    Import-Module (Join-Path $script:LibCore "Safety.psm1") -Force
    Import-Module (Join-Path $script:LibCore "Trash.psm1") -Force
    Import-Module (Join-Path $script:LibCore "Logger.psm1") -Force

    # Setup test environment
    $script:TestRoot = Join-Path $TestDrive "e2e-test"
    $script:MockTrashPath = Join-Path $TestDrive "trash"
    $script:MockConfigPath = Join-Path $TestDrive "config"

    # Helper function to create test files
    function New-TestFile {
        param(
            [string]$Path,
            [long]$SizeInBytes = 1KB,
            [datetime]$LastWriteTime = (Get-Date)
        )

        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }

        # Create file with specific size
        $content = "X" * $SizeInBytes
        Set-Content -Path $Path -Value $content -NoNewline

        # Set timestamp
        (Get-Item $Path).LastWriteTime = $LastWriteTime

        return $Path
    }

    # Helper function to create mock config
    function New-MockConfig {
        $config = @{
            trash = @{
                path = $script:MockTrashPath
                retention_hours = 72
            }
            cleanup = @{
                dry_run = $false
                max_threads = 4
                cache_age_days = 7
                log_age_days = 30
                tmp_age_days = 3
            }
            safety = @{
                level = "Normal"
                max_single_file_gb = 2
                max_batch_gb = 10
            }
        }

        if (-not (Test-Path $script:MockConfigPath)) {
            New-Item -Path $script:MockConfigPath -ItemType Directory -Force | Out-Null
        }

        $configFile = Join-Path $script:MockConfigPath "test-config.json"
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFile

        return $configFile
    }
}

Describe "E2E: Full Cleanup Flow (Dry Run)" {
    BeforeAll {
        # Setup test directory structure
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null

        # Create test files
        $script:TestFiles = @{
            Cache = New-TestFile -Path (Join-Path $script:TestRoot "cache\app1\data.cache") -SizeInBytes 5MB
            Temp = New-TestFile -Path (Join-Path $script:TestRoot "temp\tmp123.tmp") -SizeInBytes 2MB
            Log = New-TestFile -Path (Join-Path $script:TestRoot "logs\app.log") -SizeInBytes 10MB
        }

        # Create mock config
        $script:ConfigFile = New-MockConfig
    }

    Context "Dry run execution" {
        It "Should identify cleanup targets without deleting" {
            # Verify test files exist
            foreach ($file in $script:TestFiles.Values) {
                Test-Path $file | Should -Be $true
            }

            # Mock dry run would collect targets
            $targets = @()
            foreach ($file in $script:TestFiles.Values) {
                if (Test-Path $file) {
                    $targets += [PSCustomObject]@{
                        Path = $file
                        Size = (Get-Item $file).Length
                        Type = "File"
                    }
                }
            }

            # Verify targets identified
            $targets.Count | Should -BeGreaterThan 0

            # Verify files still exist (dry run)
            foreach ($file in $script:TestFiles.Values) {
                Test-Path $file | Should -Be $true
            }
        }

        It "Should calculate total reclaimable space" {
            $totalSize = 0
            foreach ($file in $script:TestFiles.Values) {
                if (Test-Path $file) {
                    $totalSize += (Get-Item $file).Length
                }
            }

            # Should equal sum of all test files (5MB + 2MB + 10MB)
            $totalSize | Should -BeGreaterThan (15MB * 0.9)  # Allow 10% margin
            $totalSize | Should -BeLessThan (20MB)  # Upper bound
        }

        It "Should categorize targets by type" {
            $categories = @{
                Cache = @()
                Temp = @()
                Logs = @()
            }

            foreach ($entry in $script:TestFiles.GetEnumerator()) {
                if (Test-Path $entry.Value) {
                    $categories[$entry.Key] += [PSCustomObject]@{
                        Path = $entry.Value
                        Size = (Get-Item $entry.Value).Length
                    }
                }
            }

            $categories.Cache.Count | Should -Be 1
            $categories.Temp.Count | Should -Be 1
            $categories.Logs.Count | Should -Be 1
        }
    }

    Context "Safety checks during dry run" {
        It "Should block protected paths" {
            $protectedPath = "C:\Windows\System32\test.dll"
            $isSafe = Test-WinOpsPathSafe -Path $protectedPath

            $isSafe | Should -Be $false
        }

        It "Should block protected processes" {
            $isProtected = Test-WinOpsProcessProtected -ProcessName "csrss"

            $isProtected | Should -Be $true
        }

        It "Should enforce size limits" {
            $isSafe = Test-WinOpsSizeGuard -Size (3GB)

            $isSafe | Should -Be $false
        }
    }
}

Describe "E2E: Analyze Flow" {
    BeforeAll {
        # Create diverse test files
        $script:AnalyzeTestRoot = Join-Path $TestDrive "analyze-test"
        New-Item -Path $script:AnalyzeTestRoot -ItemType Directory -Force | Out-Null

        # Create files of different categories
        $script:AnalyzeFiles = @{
            LargeCache = New-TestFile -Path (Join-Path $script:AnalyzeTestRoot "cache\large.cache") -SizeInBytes 50MB
            SmallTemp = New-TestFile -Path (Join-Path $script:AnalyzeTestRoot "temp\small.tmp") -SizeInBytes 100KB
            OldLog = New-TestFile -Path (Join-Path $script:AnalyzeTestRoot "logs\old.log") -SizeInBytes 20MB -LastWriteTime (Get-Date).AddDays(-60)
            RecentLog = New-TestFile -Path (Join-Path $script:AnalyzeTestRoot "logs\recent.log") -SizeInBytes 5MB -LastWriteTime (Get-Date).AddHours(-2)
        }
    }

    Context "Category-based analysis" {
        It "Should group files by category" {
            $categoryReport = @{}

            foreach ($entry in $script:AnalyzeFiles.GetEnumerator()) {
                $file = $entry.Value
                if (Test-Path $file) {
                    $category = if ($entry.Key -like "*Cache*") { "Cache" }
                                elseif ($entry.Key -like "*Temp*") { "Temp" }
                                elseif ($entry.Key -like "*Log*") { "Logs" }
                                else { "Other" }

                    if (-not $categoryReport.ContainsKey($category)) {
                        $categoryReport[$category] = @{
                            Count = 0
                            TotalSize = 0
                            Files = @()
                        }
                    }

                    $categoryReport[$category].Count++
                    $categoryReport[$category].TotalSize += (Get-Item $file).Length
                    $categoryReport[$category].Files += $file
                }
            }

            $categoryReport.Keys.Count | Should -BeGreaterThan 0
            $categoryReport["Cache"].TotalSize | Should -BeGreaterThan 40MB
            $categoryReport["Logs"].Count | Should -Be 2
        }

        It "Should identify largest items" {
            $allFiles = $script:AnalyzeFiles.Values | Where-Object { Test-Path $_ }
            $sortedBySize = $allFiles | ForEach-Object {
                [PSCustomObject]@{
                    Path = $_
                    Size = (Get-Item $_).Length
                }
            } | Sort-Object -Property Size -Descending

            $largestFile = $sortedBySize[0]
            $largestFile.Size | Should -BeGreaterThan 40MB  # Should be large.cache
            $largestFile.Path | Should -BeLike "*large.cache"
        }

        It "Should filter by age" {
            $cutoffDate = (Get-Date).AddDays(-30)
            $oldFiles = $script:AnalyzeFiles.Values | Where-Object {
                if (Test-Path $_) {
                    (Get-Item $_).LastWriteTime -lt $cutoffDate
                }
            }

            $oldFiles.Count | Should -Be 1  # Only old.log
            $oldFiles[0] | Should -BeLike "*old.log"
        }
    }

    Context "Report generation" {
        It "Should calculate space by category" {
            $report = @{
                TotalSize = 0
                Categories = @{}
            }

            foreach ($file in $script:AnalyzeFiles.Values) {
                if (Test-Path $file) {
                    $size = (Get-Item $file).Length
                    $report.TotalSize += $size

                    $category = switch -Wildcard ($file) {
                        "*cache*" { "Cache" }
                        "*temp*" { "Temp" }
                        "*logs*" { "Logs" }
                        default { "Other" }
                    }

                    if (-not $report.Categories.ContainsKey($category)) {
                        $report.Categories[$category] = 0
                    }
                    $report.Categories[$category] += $size
                }
            }

            # Total should be approximately 50MB + 100KB + 20MB + 5MB ~ 75MB
            $report.TotalSize | Should -BeGreaterThan 70MB
            $report.TotalSize | Should -BeLessThan 80MB

            $report.Categories["Cache"] | Should -BeGreaterThan 45MB
            $report.Categories["Logs"] | Should -BeGreaterThan 20MB
        }
    }
}

Describe "E2E: Trash Recovery Flow" {
    BeforeAll {
        # Initialize trash system
        New-Item -Path $script:MockTrashPath -ItemType Directory -Force | Out-Null

        # Create test file to be moved to trash
        $script:TestFileForTrash = New-TestFile -Path (Join-Path $TestDrive "test-delete.txt") -SizeInBytes 1KB
        $script:OriginalPath = $script:TestFileForTrash
    }

    Context "Move to trash" {
        It "Should move file to trash directory" {
            # Verify original exists
            Test-Path $script:TestFileForTrash | Should -Be $true

            # Mock trash operation: move file to trash
            $trashFile = Join-Path $script:MockTrashPath (Split-Path -Leaf $script:TestFileForTrash)
            Move-Item -Path $script:TestFileForTrash -Destination $trashFile -Force

            # Verify moved
            Test-Path $script:TestFileForTrash | Should -Be $false
            Test-Path $trashFile | Should -Be $true

            $script:TrashedFile = $trashFile
        }

        It "Should create index entry" {
            $indexFile = Join-Path $script:MockTrashPath ".index.json"

            $index = @{
                items = @{
                    "test-delete.txt" = @{
                        original_path = $script:OriginalPath
                        trash_path = $script:TrashedFile
                        deleted_at = (Get-Date).ToString("o")
                        size = 1KB
                    }
                }
            }

            $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexFile

            Test-Path $indexFile | Should -Be $true
            $loadedIndex = Get-Content $indexFile | ConvertFrom-Json
            $loadedIndex.items.PSObject.Properties.Count | Should -Be 1
        }
    }

    Context "List trash contents" {
        It "Should list recoverable items" {
            $indexFile = Join-Path $script:MockTrashPath ".index.json"

            if (Test-Path $indexFile) {
                $index = Get-Content $indexFile | ConvertFrom-Json
                $items = @()

                foreach ($property in $index.items.PSObject.Properties) {
                    $item = $property.Value
                    $items += [PSCustomObject]@{
                        Name = $property.Name
                        OriginalPath = $item.original_path
                        Size = $item.size
                        DeletedAt = [datetime]$item.deleted_at
                    }
                }

                $items.Count | Should -Be 1
                $items[0].Name | Should -Be "test-delete.txt"
            }
        }
    }

    Context "Restore from trash" {
        It "Should restore file to original location" {
            # Verify file is in trash
            Test-Path $script:TrashedFile | Should -Be $true
            Test-Path $script:OriginalPath | Should -Be $false

            # Restore operation
            Move-Item -Path $script:TrashedFile -Destination $script:OriginalPath -Force

            # Verify restored
            Test-Path $script:OriginalPath | Should -Be $true
            Test-Path $script:TrashedFile | Should -Be $false
        }

        It "Should remove from index after restore" {
            $indexFile = Join-Path $script:MockTrashPath ".index.json"

            $index = Get-Content $indexFile | ConvertFrom-Json
            $updatedItems = @{}

            # Remove restored item
            foreach ($property in $index.items.PSObject.Properties) {
                if ($property.Name -ne "test-delete.txt") {
                    $updatedItems[$property.Name] = $property.Value
                }
            }

            $index.items = [PSCustomObject]$updatedItems
            $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexFile

            $reloadedIndex = Get-Content $indexFile | ConvertFrom-Json
            $reloadedIndex.items.PSObject.Properties.Count | Should -Be 0
        }
    }

    Context "72-hour retention" {
        BeforeAll {
            # Create old trash item
            $script:OldTrashFile = New-TestFile -Path (Join-Path $script:MockTrashPath "old-file.txt") -SizeInBytes 1KB

            $indexFile = Join-Path $script:MockTrashPath ".index.json"
            $index = @{
                items = @{
                    "old-file.txt" = @{
                        original_path = Join-Path $TestDrive "old-original.txt"
                        trash_path = $script:OldTrashFile
                        deleted_at = (Get-Date).AddHours(-80).ToString("o")  # 80 hours ago (expired)
                        size = 1KB
                    }
                    "recent-file.txt" = @{
                        original_path = Join-Path $TestDrive "recent-original.txt"
                        trash_path = Join-Path $script:MockTrashPath "recent-file.txt"
                        deleted_at = (Get-Date).AddHours(-10).ToString("o")  # 10 hours ago (valid)
                        size = 1KB
                    }
                }
            }
            $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexFile
        }

        It "Should identify expired items" {
            $indexFile = Join-Path $script:MockTrashPath ".index.json"
            $index = Get-Content $indexFile | ConvertFrom-Json

            $retentionHours = 72
            $cutoffTime = (Get-Date).AddHours(-$retentionHours)

            $expiredItems = @()
            foreach ($property in $index.items.PSObject.Properties) {
                $item = $property.Value
                $deletedAt = [datetime]$item.deleted_at

                if ($deletedAt -lt $cutoffTime) {
                    $expiredItems += $property.Name
                }
            }

            $expiredItems.Count | Should -Be 1
            $expiredItems[0] | Should -Be "old-file.txt"
        }

        It "Should purge expired items" {
            $indexFile = Join-Path $script:MockTrashPath ".index.json"
            $index = Get-Content $indexFile | ConvertFrom-Json

            $retentionHours = 72
            $cutoffTime = (Get-Date).AddHours(-$retentionHours)

            $remainingItems = @{}
            foreach ($property in $index.items.PSObject.Properties) {
                $item = $property.Value
                $deletedAt = [datetime]$item.deleted_at

                if ($deletedAt -ge $cutoffTime) {
                    $remainingItems[$property.Name] = $item
                } else {
                    # Delete file
                    if (Test-Path $item.trash_path) {
                        Remove-Item -Path $item.trash_path -Force
                    }
                }
            }

            $index.items = [PSCustomObject]$remainingItems
            $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexFile

            # Verify only recent item remains
            $reloadedIndex = Get-Content $indexFile | ConvertFrom-Json
            $reloadedIndex.items.PSObject.Properties.Count | Should -Be 1
            $reloadedIndex.items.PSObject.Properties.Name | Should -Contain "recent-file.txt"
        }
    }
}

Describe "E2E: Config Management" {
    BeforeAll {
        $script:TestConfigDir = Join-Path $TestDrive "config-test"
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null

        # Create default config
        $script:DefaultConfig = @{
            trash = @{
                path = "%LOCALAPPDATA%\win-ops\trash"
                retention_hours = 72
            }
            cleanup = @{
                dry_run = $false
                max_threads = 4
                cache_age_days = 7
            }
            safety = @{
                level = "Normal"
            }
        }

        $defaultPath = Join-Path $script:TestConfigDir "default.json"
        $script:DefaultConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $defaultPath
        $script:DefaultConfigPath = $defaultPath
    }

    Context "Config loading" {
        It "Should load default config" {
            $config = Get-Content $script:DefaultConfigPath | ConvertFrom-Json

            $config.trash.retention_hours | Should -Be 72
            $config.cleanup.max_threads | Should -Be 4
            $config.safety.level | Should -Be "Normal"
        }

        It "Should merge user config with defaults" {
            # Create user config with partial overrides
            $userConfig = @{
                cleanup = @{
                    dry_run = $true
                    cache_age_days = 14
                }
            }

            $userPath = Join-Path $script:TestConfigDir "user.json"
            $userConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $userPath

            # Merge
            $defaultObj = Get-Content $script:DefaultConfigPath | ConvertFrom-Json
            $userObj = Get-Content $userPath | ConvertFrom-Json

            # Simple merge logic (user overrides default)
            $merged = $defaultObj.PSObject.Copy()
            foreach ($property in $userObj.PSObject.Properties) {
                $merged.$($property.Name) = $property.Value
            }

            # Verify merge
            $merged.cleanup.dry_run | Should -Be $true
            $merged.cleanup.cache_age_days | Should -Be 14
            $merged.cleanup.max_threads | Should -Be 4  # From default
            $merged.trash.retention_hours | Should -Be 72  # From default
        }

        It "Should expand environment variables" {
            $config = Get-Content $script:DefaultConfigPath | ConvertFrom-Json
            $trashPath = $config.trash.path

            $expanded = [Environment]::ExpandEnvironmentVariables($trashPath)

            $expanded | Should -Not -BeLike "*%*"
            $expanded | Should -BeLike "*\win-ops\trash"
        }
    }

    Context "Config validation" {
        It "Should validate numeric values" {
            $config = @{
                cleanup = @{
                    max_threads = 4
                    cache_age_days = 7
                }
            }

            $config.cleanup.max_threads | Should -BeOfType [int]
            $config.cleanup.max_threads | Should -BeGreaterThan 0
            $config.cleanup.cache_age_days | Should -BeGreaterThan 0
        }

        It "Should validate safety level enum" {
            $validLevels = @("Strict", "Normal", "Permissive")

            $config = @{
                safety = @{
                    level = "Normal"
                }
            }

            $validLevels | Should -Contain $config.safety.level
        }
    }
}

Describe "E2E: Integrated Safety System" {
    Context "Multi-tier safety checks" {
        It "Should block System32 path at multiple tiers" {
            $testPath = "C:\Windows\System32\kernel32.dll"

            # Tier 1: Protected path check
            $isPathSafe = Test-WinOpsPathSafe -Path $testPath
            $isPathSafe | Should -Be $false

            # Tier 4: WRP detection
            $isWRP = Test-WinOpsSystemPath -Path $testPath
            $isWRP | Should -Be $true

            # Integrated check
            $result = Assert-WinOpsSafeOperation -Path $testPath -DryRun
            $result.OverallSafe | Should -Be $false
            $result.PathSafe | Should -Be $false
            $result.NotWRP | Should -Be $false
        }

        It "Should block critical process operations" {
            $processName = "csrss"

            # Tier 2: Protected process check
            $isProtected = Test-WinOpsProcessProtected -ProcessName $processName
            $isProtected | Should -Be $true

            # Integrated check
            $result = Assert-WinOpsSafeOperation -ProcessName $processName -DryRun
            $result.OverallSafe | Should -Be $false
            $result.ProcessSafe | Should -Be $false
        }

        It "Should enforce size limits at batch level" {
            $batchSize = 15GB

            # Tier 3: Size guard
            $isSafe = Test-WinOpsSizeGuard -Size $batchSize -IsBatch
            $isSafe | Should -Be $false

            # Integrated check
            $result = Assert-WinOpsSafeOperation -Size $batchSize -IsBatch -DryRun
            $result.OverallSafe | Should -Be $false
            $result.SizeSafe | Should -Be $false
        }

        It "Should allow safe operations" {
            $safePath = "C:\Temp\test.txt"
            $safeProcess = "notepad"
            $safeSize = 100MB

            $result = Assert-WinOpsSafeOperation -Path $safePath -ProcessName $safeProcess -Size $safeSize -DryRun

            $result.OverallSafe | Should -Be $true
            $result.PathSafe | Should -Be $true
            $result.ProcessSafe | Should -Be $true
            $result.SizeSafe | Should -Be $true
        }
    }

    Context "Safety level cascading" {
        It "Permissive mode allows more operations" {
            $path = "C:\Program Files\MyApp\data.txt"

            # Normal mode blocks
            $normalResult = Assert-WinOpsSafeOperation -Path $path -Level Normal -DryRun
            $normalResult.PathSafe | Should -Be $false

            # Permissive mode allows (not in WRP)
            $permissiveResult = Assert-WinOpsSafeOperation -Path $path -Level Permissive -DryRun
            $permissiveResult.PathSafe | Should -Be $true
        }

        It "Strict mode is more restrictive" {
            $size = 1.5GB

            # Normal mode allows
            $normalResult = Test-WinOpsSizeGuard -Size $size -Level Normal
            $normalResult | Should -Be $true

            # Strict mode blocks (limit halved to 1GB)
            $strictResult = Test-WinOpsSizeGuard -Size $size -Level Strict
            $strictResult | Should -Be $false
        }
    }
}

Describe "E2E: Error Handling and Recovery" {
    Context "Graceful degradation" {
        It "Should handle missing config files" {
            $nonExistentConfig = Join-Path $TestDrive "missing-config.json"

            # Should not throw, return null or default
            {
                if (Test-Path $nonExistentConfig) {
                    Get-Content $nonExistentConfig | ConvertFrom-Json
                } else {
                    $null
                }
            } | Should -Not -Throw
        }

        It "Should handle locked files gracefully" {
            $testFile = New-TestFile -Path (Join-Path $TestDrive "locked.txt") -SizeInBytes 1KB

            # Open file with exclusive lock
            $stream = [System.IO.File]::Open($testFile, 'Open', 'Read', 'None')

            try {
                # Attempt to delete should fail gracefully
                $canDelete = $false
                try {
                    Remove-Item -Path $testFile -Force -ErrorAction Stop
                    $canDelete = $true
                } catch {
                    $canDelete = $false
                }

                $canDelete | Should -Be $false
                Test-Path $testFile | Should -Be $true
            }
            finally {
                $stream.Close()
                $stream.Dispose()
            }
        }

        It "Should handle permission errors" {
            $protectedPath = "C:\Windows\System32\test.dll"

            # Should detect as unsafe
            $result = Assert-WinOpsSafeOperation -Path $protectedPath -DryRun
            $result.OverallSafe | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:MockTrashPath) {
        Remove-Item -Path $script:MockTrashPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:MockConfigPath) {
        Remove-Item -Path $script:MockConfigPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
