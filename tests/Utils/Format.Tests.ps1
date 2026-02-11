#Requires -Modules Pester

BeforeAll {
    $script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\lib\utils\Format.psm1"
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module -Name Format -ErrorAction SilentlyContinue
}

Describe "Format-WinOpsBytes" {
    Context "Edge cases" {
        It "Should handle zero bytes" {
            Format-WinOpsBytes -Bytes 0 | Should -Be "0 B"
        }

        It "Should handle negative bytes" {
            Format-WinOpsBytes -Bytes -100 | Should -Be "0 B"
        }

        It "Should handle null bytes" {
            Format-WinOpsBytes -Bytes $null | Should -Be "0 B"
        }
    }

    Context "Byte formatting" {
        It "Should format bytes less than 1KB" {
            Format-WinOpsBytes -Bytes 512 | Should -Be "512 B"
        }

        It "Should format bytes at 1KB boundary" {
            Format-WinOpsBytes -Bytes 1KB | Should -Be "1.0 KB"
        }

        It "Should format KB values" {
            $result = Format-WinOpsBytes -Bytes (5.5 * 1KB)
            $result | Should -Match "^5\.[0-9] KB$"
        }

        It "Should format MB values" {
            $result = Format-WinOpsBytes -Bytes (100 * 1MB)
            $result | Should -Match "^100\.[0-9] MB$"
        }

        It "Should format GB values" {
            $result = Format-WinOpsBytes -Bytes (2.5 * 1GB)
            $result | Should -Match "^2\.[0-9] GB$"
        }

        It "Should format TB values" {
            $result = Format-WinOpsBytes -Bytes (1.2 * 1TB)
            $result | Should -Match "^1\.[0-9] TB$"
        }

        It "Should format large TB values" {
            $result = Format-WinOpsBytes -Bytes (50 * 1TB)
            $result | Should -Match "^50\.[0-9] TB$"
        }
    }

    Context "Pipeline support" {
        It "Should accept input from pipeline" {
            $result = 1GB | Format-WinOpsBytes
            $result | Should -Match "^1\.[0-9] GB$"
        }

        It "Should process multiple values from pipeline" {
            $results = @(1KB, 1MB, 1GB) | Format-WinOpsBytes
            $results.Count | Should -Be 3
            $results[0] | Should -Match "KB"
            $results[1] | Should -Match "MB"
            $results[2] | Should -Match "GB"
        }
    }
}

Describe "Format-WinOpsDuration" {
    Context "Edge cases" {
        It "Should handle zero seconds" {
            Format-WinOpsDuration -Seconds 0 | Should -Be "0s"
        }

        It "Should handle negative seconds" {
            Format-WinOpsDuration -Seconds -100 | Should -Be "0s"
        }

        It "Should handle null seconds" {
            Format-WinOpsDuration -Seconds $null | Should -Be "0s"
        }
    }

    Context "Duration formatting" {
        It "Should format seconds less than 60" {
            Format-WinOpsDuration -Seconds 30 | Should -Be "30s"
        }

        It "Should format minutes and seconds" {
            Format-WinOpsDuration -Seconds 90 | Should -Be "1m 30s"
        }

        It "Should format minutes without seconds" {
            Format-WinOpsDuration -Seconds 120 | Should -Be "2m 0s"
        }

        It "Should format hours, minutes, and seconds" {
            Format-WinOpsDuration -Seconds 3665 | Should -Be "1h 1m 5s"
        }

        It "Should format hours and minutes without seconds" {
            Format-WinOpsDuration -Seconds 7200 | Should -Be "2h 0m"
        }

        It "Should format hours with minutes but no seconds" {
            Format-WinOpsDuration -Seconds 3660 | Should -Be "1h 1m"
        }

        It "Should format large durations" {
            Format-WinOpsDuration -Seconds 86400 | Should -Be "24h 0m"
        }
    }

    Context "Pipeline support" {
        It "Should accept input from pipeline" {
            $result = 90 | Format-WinOpsDuration
            $result | Should -Be "1m 30s"
        }

        It "Should process multiple values from pipeline" {
            $results = @(30, 90, 3665) | Format-WinOpsDuration
            $results.Count | Should -Be 3
            $results[0] | Should -Be "30s"
            $results[1] | Should -Be "1m 30s"
            $results[2] | Should -Be "1h 1m 5s"
        }
    }
}

Describe "Write-WinOpsColor" {
    Context "Basic functionality" {
        It "Should write colored text without error" {
            { Write-WinOpsColor -Text "Test" -Color Red } | Should -Not -Throw
        }

        It "Should accept all valid colors" {
            $colors = @('Red', 'Green', 'Yellow', 'Blue', 'Cyan', 'Magenta', 'White', 'Bold', 'Reset')
            foreach ($color in $colors) {
                { Write-WinOpsColor -Text "Test" -Color $color } | Should -Not -Throw
            }
        }

        It "Should handle NoNewline switch" {
            { Write-WinOpsColor -Text "Test" -Color Green -NoNewline } | Should -Not -Throw
        }

        It "Should default to White color" {
            { Write-WinOpsColor -Text "Test" } | Should -Not -Throw
        }
    }

    Context "Pipeline support" {
        It "Should accept input from pipeline" {
            { "Test" | Write-WinOpsColor -Color Green } | Should -Not -Throw
        }

        It "Should process multiple values from pipeline" {
            { @("Line1", "Line2", "Line3") | Write-WinOpsColor -Color Cyan } | Should -Not -Throw
        }
    }

    Context "Parameter validation" {
        It "Should reject invalid color" {
            { Write-WinOpsColor -Text "Test" -Color "InvalidColor" } | Should -Throw
        }
    }
}

Describe "Format-WinOpsTable" {
    Context "Basic functionality" {
        It "Should handle empty data array" {
            { Format-WinOpsTable -Data @() } | Should -Not -Throw
        }

        It "Should format simple table data" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=100}
                [PSCustomObject]@{Name="File2"; Size=200}
            )
            { Format-WinOpsTable -Data $data } | Should -Not -Throw
        }

        It "Should auto-detect properties" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=100; Date="2024-01-01"}
            )
            { Format-WinOpsTable -Data $data } | Should -Not -Throw
        }

        It "Should accept specific properties" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=100; Date="2024-01-01"}
            )
            { Format-WinOpsTable -Data $data -Properties Name,Size } | Should -Not -Throw
        }

        It "Should accept custom column widths" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=100}
            )
            $widths = @{Name=20; Size=10}
            { Format-WinOpsTable -Data $data -Width $widths } | Should -Not -Throw
        }

        It "Should handle null values in data" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=$null}
                [PSCustomObject]@{Name=$null; Size=200}
            )
            { Format-WinOpsTable -Data $data } | Should -Not -Throw
        }
    }

    Context "Pipeline support" {
        It "Should accept input from pipeline" {
            $data = @(
                [PSCustomObject]@{Name="File1"; Size=100}
            )
            { $data | Format-WinOpsTable } | Should -Not -Throw
        }
    }
}

Describe "Write-WinOpsHeader" {
    Context "Basic functionality" {
        It "Should write header without error" {
            { Write-WinOpsHeader -Title "Test Header" } | Should -Not -Throw
        }

        It "Should require title parameter" {
            { Write-WinOpsHeader } | Should -Throw
        }

        It "Should handle long titles" {
            { Write-WinOpsHeader -Title ("A" * 100) } | Should -Not -Throw
        }

        It "Should handle empty title" {
            { Write-WinOpsHeader -Title "" } | Should -Not -Throw
        }
    }
}

Describe "Write-WinOpsSummary" {
    Context "Basic functionality" {
        It "Should write summary without error" {
            { Write-WinOpsSummary } | Should -Not -Throw
        }

        It "Should handle zero values" {
            { Write-WinOpsSummary -CleanedCount 0 -CleanedBytes 0 -KilledProcs 0 } | Should -Not -Throw
        }

        It "Should handle non-zero cleaned count" {
            { Write-WinOpsSummary -CleanedCount 10 -CleanedBytes 1GB } | Should -Not -Throw
        }

        It "Should handle non-zero killed processes" {
            { Write-WinOpsSummary -KilledProcs 5 } | Should -Not -Throw
        }

        It "Should handle all parameters" {
            { Write-WinOpsSummary -CleanedCount 42 -CleanedBytes (5 * 1GB) -KilledProcs 3 } | Should -Not -Throw
        }
    }
}

Describe "Write-WinOpsReport" {
    Context "Basic functionality" {
        It "Should write report without error" {
            $before = @{
                DiskUsagePct = 75
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            $after = @{
                DiskUsagePct = 70
                DiskFreeBytes = 12GB
                MemUsedBytes = 7GB
                MemTotalBytes = 16GB
            }
            { Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after } | Should -Not -Throw
        }

        It "Should handle positive deltas (improvement)" {
            $before = @{
                DiskUsagePct = 80
                DiskFreeBytes = 5GB
                MemUsedBytes = 10GB
                MemTotalBytes = 16GB
            }
            $after = @{
                DiskUsagePct = 70
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            { Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after } | Should -Not -Throw
        }

        It "Should handle negative deltas (degradation)" {
            $before = @{
                DiskUsagePct = 70
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            $after = @{
                DiskUsagePct = 75
                DiskFreeBytes = 8GB
                MemUsedBytes = 10GB
                MemTotalBytes = 16GB
            }
            { Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after } | Should -Not -Throw
        }

        It "Should handle zero delta" {
            $before = @{
                DiskUsagePct = 70
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            $after = @{
                DiskUsagePct = 70
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            { Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after } | Should -Not -Throw
        }

        It "Should handle cleanup statistics" {
            $before = @{
                DiskUsagePct = 75
                DiskFreeBytes = 10GB
                MemUsedBytes = 8GB
                MemTotalBytes = 16GB
            }
            $after = @{
                DiskUsagePct = 70
                DiskFreeBytes = 12GB
                MemUsedBytes = 7GB
                MemTotalBytes = 16GB
            }
            { Write-WinOpsReport -BeforeSnapshot $before -AfterSnapshot $after -CleanedCount 100 -CleanedBytes 2GB -KilledProcs 5 } | Should -Not -Throw
        }
    }
}
