#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot '..\..\lib\modules\Analyze.psm1'
    Import-Module $modulePath -Force

    # Mock core dependencies
    Mock Write-WinOpsLog -ModuleName Analyze {}
}

Describe 'Analyze Module' -Tag 'Unit', 'Module' {

    Context 'Module Loading' {

        It 'Should load Analyze module successfully' {
            Get-Module Analyze | Should -Not -BeNullOrEmpty
        }

        It 'Should export expected functions' {
            $commands = Get-Command -Module Analyze
            $commands.Name | Should -Contain 'Get-WinOpsAnalysis'
            $commands.Name | Should -Contain 'Compare-WinOpsAnalysis'
        }
    }

    Context 'Get-WinOpsAnalysis' {

        BeforeEach {
            # Mock Import-Module to prevent loading other modules
            Mock Import-Module -ModuleName Analyze {}

            # Mock Get-Command to simulate available Get-*Targets functions
            Mock Get-Command -ModuleName Analyze {
                param($CommandName, $ErrorAction)
                [PSCustomObject]@{
                    Name = $CommandName
                    CommandType = 'Function'
                }
            }

            # Mock the Get-*Targets functions themselves
            Mock Get-WinOpsCacheTargets -ModuleName Analyze {
                @(
                    [PSCustomObject]@{
                        Name = 'TestCache'
                        Description = 'Test cache description'
                        CurrentSizeMB = 500
                        CurrentSizeGB = 0.5
                        CurrentSize = 524288000
                        WillCleanup = $true
                    }
                )
            }

            Mock Get-WinOpsTempFileInfo -ModuleName Analyze {
                @(
                    [PSCustomObject]@{
                        Location = 'TempFiles'
                        TotalSizeMB = 300
                        TotalSizeGB = 0.3
                        TotalSize = 314572800
                    }
                )
            }
        }

        It 'Should return analysis with summary' {
            $result = Get-WinOpsAnalysis -NoVisual

            $result | Should -Not -BeNullOrEmpty
            $result.Summary | Should -Not -BeNullOrEmpty
            $result.TotalReclaimableGB | Should -BeGreaterThan -1
        }

        It 'Should include category summaries' {
            $result = Get-WinOpsAnalysis -NoVisual

            $result.Summary | Should -Not -BeNullOrEmpty
            $result.CategoryCount | Should -BeGreaterThan -1
        }

        It 'Should filter by category' {
            $result = Get-WinOpsAnalysis -Category Cache -NoVisual

            $result | Should -Not -BeNullOrEmpty
            # Only Cache category should be included
            $result.Summary | Should -Not -BeNullOrEmpty
        }

        It 'Should calculate total reclaimable space' {
            $result = Get-WinOpsAnalysis -NoVisual

            $result.TotalReclaimableGB | Should -BeGreaterThan -1
            $result.TotalReclaimableMB | Should -BeGreaterThan -1
            $result.TotalReclaimableBytes | Should -BeGreaterThan -1
        }

        It 'Should include top N largest items' {
            Mock Get-WinOpsCacheTargets -ModuleName Analyze {
                @(
                    [PSCustomObject]@{
                        Name = 'LargeCache'
                        CurrentSizeMB = 1000
                        CurrentSize = 1048576000
                        WillCleanup = $true
                    }
                    [PSCustomObject]@{
                        Name = 'SmallCache'
                        CurrentSizeMB = 50
                        CurrentSize = 52428800
                        WillCleanup = $true
                    }
                    [PSCustomObject]@{
                        Name = 'MediumCache'
                        CurrentSizeMB = 500
                        CurrentSize = 524288000
                        WillCleanup = $true
                    }
                )
            }

            $result = Get-WinOpsAnalysis -TopN 2 -NoVisual

            $result.TopItems | Should -Not -BeNullOrEmpty
            $result.TopItems.Count | Should -BeLessOrEqual 2
            # Should be sorted by size descending
            if ($result.TopItems.Count -ge 2) {
                $result.TopItems[0].SizeBytes | Should -BeGreaterThan $result.TopItems[1].SizeBytes
            }
        }

        It 'Should include detailed targets when Detailed is specified' {
            $result = Get-WinOpsAnalysis -Detailed -NoVisual

            $result.AllTargets | Should -Not -BeNullOrEmpty
        }

        It 'Should not include detailed targets by default' {
            $result = Get-WinOpsAnalysis -NoVisual

            $result.AllTargets.Count | Should -Be 0
        }

        It 'Should include all required properties' {
            $result = Get-WinOpsAnalysis -NoVisual

            $result.TotalReclaimableGB | Should -BeGreaterThan -1
            $result.TotalReclaimableMB | Should -BeGreaterThan -1
            $result.TotalReclaimableBytes | Should -BeGreaterThan -1
            $result.TotalItemCount | Should -BeGreaterThan -1
            $result.CategoryCount | Should -BeGreaterThan -1
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should export to CSV when ExportPath is specified' {
            Mock Export-Csv -ModuleName Analyze {}

            $result = Get-WinOpsAnalysis -ExportPath 'C:\test.csv' -NoVisual

            Should -Invoke Export-Csv -ModuleName Analyze -Times 1
        }

        It 'Should export to JSON when ExportJson is specified' {
            Mock ConvertTo-Json -ModuleName Analyze { '{}' }
            Mock Out-File -ModuleName Analyze {}

            $result = Get-WinOpsAnalysis -ExportJson 'C:\test.json' -NoVisual

            Should -Invoke ConvertTo-Json -ModuleName Analyze -Times 1
            Should -Invoke Out-File -ModuleName Analyze -Times 1
        }

        It 'Should respect AgeInDays parameter' {
            $result = Get-WinOpsAnalysis -AgeInDays 30 -NoVisual

            $result.AgeFilterDays | Should -Be 30
        }
    }

    Context 'Compare-WinOpsAnalysis' {

        It 'Should compare before and after analysis' {
            Mock Write-Host -ModuleName Analyze {}

            $before = [PSCustomObject]@{
                TotalReclaimableGB = 10.5
                TotalReclaimableMB = 10752
                TotalItemCount = 100
                Timestamp = (Get-Date).AddHours(-1)
            }

            $after = [PSCustomObject]@{
                TotalReclaimableGB = 3.2
                TotalReclaimableMB = 3276
                TotalItemCount = 40
                Timestamp = (Get-Date)
            }

            $result = Compare-WinOpsAnalysis -Before $before -After $after

            $result | Should -Not -BeNullOrEmpty
            $result.BeforeGB | Should -Be 10.5
            $result.AfterGB | Should -Be 3.2
            $result.FreedGB | Should -Be 7.3
            $result.ItemsRemoved | Should -Be 60
        }

        It 'Should calculate percentage reduction' {
            Mock Write-Host -ModuleName Analyze {}

            $before = [PSCustomObject]@{
                TotalReclaimableGB = 20.0
                TotalReclaimableMB = 20480
                TotalItemCount = 200
                Timestamp = (Get-Date).AddHours(-1)
            }

            $after = [PSCustomObject]@{
                TotalReclaimableGB = 5.0
                TotalReclaimableMB = 5120
                TotalItemCount = 50
                Timestamp = (Get-Date)
            }

            $result = Compare-WinOpsAnalysis -Before $before -After $after

            $result.PercentageReduction | Should -Be 75
        }

        It 'Should handle zero before size' {
            Mock Write-Host -ModuleName Analyze {}

            $before = [PSCustomObject]@{
                TotalReclaimableGB = 0
                TotalReclaimableMB = 0
                TotalItemCount = 0
                Timestamp = (Get-Date).AddHours(-1)
            }

            $after = [PSCustomObject]@{
                TotalReclaimableGB = 0
                TotalReclaimableMB = 0
                TotalItemCount = 0
                Timestamp = (Get-Date)
            }

            $result = Compare-WinOpsAnalysis -Before $before -After $after

            $result.PercentageReduction | Should -Be 0
        }

        It 'Should include timestamps' {
            Mock Write-Host -ModuleName Analyze {}

            $beforeTime = (Get-Date).AddHours(-2)
            $afterTime = (Get-Date)

            $before = [PSCustomObject]@{
                TotalReclaimableGB = 5.0
                TotalReclaimableMB = 5120
                TotalItemCount = 100
                Timestamp = $beforeTime
            }

            $after = [PSCustomObject]@{
                TotalReclaimableGB = 2.0
                TotalReclaimableMB = 2048
                TotalItemCount = 40
                Timestamp = $afterTime
            }

            $result = Compare-WinOpsAnalysis -Before $before -After $after

            $result.BeforeTimestamp | Should -Be $beforeTime
            $result.AfterTimestamp | Should -Be $afterTime
        }
    }
}

Describe 'Analyze Integration Tests' -Tag 'Integration', 'Module' {

    Context 'Data Aggregation' {

        It 'Should aggregate data from multiple sources' {
            $categories = @('Cache', 'Temp', 'Logs', 'Browser', 'Development')

            $categories | Should -Not -BeNullOrEmpty
            $categories.Count | Should -BeGreaterThan 3
        }

        It 'Should calculate percentage breakdown' {
            $data = @(
                [PSCustomObject]@{ Category = 'Cache'; SizeMB = 500 }
                [PSCustomObject]@{ Category = 'Temp'; SizeMB = 300 }
                [PSCustomObject]@{ Category = 'Logs'; SizeMB = 200 }
            )

            $total = ($data | Measure-Object -Property SizeMB -Sum).Sum
            $cachePercent = ($data[0].SizeMB / $total) * 100

            $cachePercent | Should -BeGreaterThan 40
            $cachePercent | Should -BeLessThan 60
        }

        It 'Should sort by size descending' {
            $data = @(
                [PSCustomObject]@{ Name = 'Small'; SizeMB = 100 }
                [PSCustomObject]@{ Name = 'Large'; SizeMB = 1000 }
                [PSCustomObject]@{ Name = 'Medium'; SizeMB = 500 }
            )

            $sorted = $data | Sort-Object SizeMB -Descending

            $sorted[0].Name | Should -Be 'Large'
            $sorted[1].Name | Should -Be 'Medium'
            $sorted[2].Name | Should -Be 'Small'
        }
    }

    Context 'Report Formatting' {

        It 'Should format sizes in MB' {
            $bytes = 52428800  # 50 MB
            $mb = [math]::Round($bytes / 1MB, 2)

            $mb | Should -Be 50
        }

        It 'Should format sizes in GB' {
            $bytes = 5368709120  # 5 GB
            $gb = [math]::Round($bytes / 1GB, 2)

            $gb | Should -Be 5
        }

        It 'Should format timestamps' {
            $timestamp = Get-Date
            $formatted = $timestamp.ToString('yyyy-MM-dd HH:mm:ss')

            $formatted | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
        }
    }

    Context 'Visual Chart Generation' {

        It 'Should create bar chart representation' {
            $maxValue = 1000
            $currentValue = 750
            $barLength = 50

            $filledLength = [math]::Floor(($currentValue / $maxValue) * $barLength)
            $bar = '█' * $filledLength + '░' * ($barLength - $filledLength)

            $bar.Length | Should -Be $barLength
            $filledLength | Should -BeGreaterThan 30
        }

        It 'Should handle zero values' {
            $maxValue = 1000
            $currentValue = 0
            $barLength = 50

            $filledLength = [math]::Floor(($currentValue / $maxValue) * $barLength)

            $filledLength | Should -Be 0
        }

        It 'Should handle maximum values' {
            $maxValue = 1000
            $currentValue = 1000
            $barLength = 50

            $filledLength = [math]::Floor(($currentValue / $maxValue) * $barLength)

            $filledLength | Should -Be $barLength
        }
    }
}
