# tests/lib/utils/Format.Tests.ps1
# Unit tests for Format utility module

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot ".." ".." ".." "lib" "utils" "Format.psm1"
    Import-Module $modulePath -Force
}

Describe "Format-WinOpsBytes" {
    It "Formats bytes correctly" {
        Format-WinOpsBytes -Bytes 512 | Should -Be "512 B"
    }

    It "Formats kilobytes correctly" {
        Format-WinOpsBytes -Bytes 1024 | Should -Be "1.0 KB"
        Format-WinOpsBytes -Bytes 2048 | Should -Be "2.0 KB"
    }

    It "Formats megabytes correctly" {
        Format-WinOpsBytes -Bytes 1048576 | Should -Be "1.0 MB"
        Format-WinOpsBytes -Bytes 5242880 | Should -Be "5.0 MB"
    }

    It "Formats gigabytes correctly" {
        Format-WinOpsBytes -Bytes 1073741824 | Should -Be "1.0 GB"
        Format-WinOpsBytes -Bytes 5368709120 | Should -Be "5.0 GB"
    }

    It "Formats terabytes correctly" {
        Format-WinOpsBytes -Bytes 1099511627776 | Should -Be "1.0 TB"
        Format-WinOpsBytes -Bytes 2199023255552 | Should -Be "2.0 TB"
    }

    It "Handles zero bytes" {
        Format-WinOpsBytes -Bytes 0 | Should -Be "0 B"
    }

    It "Handles negative bytes" {
        Format-WinOpsBytes -Bytes -1 | Should -Be "0 B"
    }

    It "Works with pipeline input" {
        1024 | Format-WinOpsBytes | Should -Be "1.0 KB"
    }
}

Describe "Format-WinOpsDuration" {
    It "Formats seconds only" {
        Format-WinOpsDuration -Seconds 45 | Should -Be "45s"
    }

    It "Formats minutes and seconds" {
        Format-WinOpsDuration -Seconds 90 | Should -Be "1m 30s"
        Format-WinOpsDuration -Seconds 125 | Should -Be "2m 5s"
    }

    It "Formats hours, minutes, and seconds" {
        Format-WinOpsDuration -Seconds 3665 | Should -Be "1h 1m 5s"
        Format-WinOpsDuration -Seconds 7325 | Should -Be "2h 2m 5s"
    }

    It "Formats hours and minutes without seconds" {
        Format-WinOpsDuration -Seconds 3600 | Should -Be "1h 0m"
        Format-WinOpsDuration -Seconds 7200 | Should -Be "2h 0m"
    }

    It "Handles zero seconds" {
        Format-WinOpsDuration -Seconds 0 | Should -Be "0s"
    }

    It "Handles negative seconds" {
        Format-WinOpsDuration -Seconds -1 | Should -Be "0s"
    }

    It "Works with pipeline input" {
        90 | Format-WinOpsDuration | Should -Be "1m 30s"
    }
}

Describe "Write-WinOpsColor" {
    It "Writes colored text without error" {
        { Write-WinOpsColor -Text "Test" -Color Red } | Should -Not -Throw
        { Write-WinOpsColor -Text "Test" -Color Green } | Should -Not -Throw
        { Write-WinOpsColor -Text "Test" -Color Yellow } | Should -Not -Throw
        { Write-WinOpsColor -Text "Test" -Color Blue } | Should -Not -Throw
        { Write-WinOpsColor -Text "Test" -Color Bold } | Should -Not -Throw
    }

    It "Supports NoNewline switch" {
        { Write-WinOpsColor -Text "Test" -Color Red -NoNewline } | Should -Not -Throw
    }

    It "Defaults to White color" {
        { Write-WinOpsColor -Text "Test" } | Should -Not -Throw
    }

    It "Works with pipeline input" {
        { "Test" | Write-WinOpsColor -Color Green } | Should -Not -Throw
    }
}

Describe "Format-WinOpsTable" {
    BeforeEach {
        $script:testData = @(
            [PSCustomObject]@{Name = "File1.txt"; Size = 1024; Date = "2024-01-01" }
            [PSCustomObject]@{Name = "File2.txt"; Size = 2048; Date = "2024-01-02" }
            [PSCustomObject]@{Name = "File3.txt"; Size = 4096; Date = "2024-01-03" }
        )
    }

    It "Formats table without error" {
        { Format-WinOpsTable -Data $testData } | Should -Not -Throw
    }

    It "Formats table with specific properties" {
        { Format-WinOpsTable -Data $testData -Properties Name, Size } | Should -Not -Throw
    }

    It "Formats table with custom widths" {
        $widths = @{Name = 40; Size = 15; Date = 15 }
        { Format-WinOpsTable -Data $testData -Width $widths } | Should -Not -Throw
    }

    It "Handles empty data array" {
        { Format-WinOpsTable -Data @() } | Should -Not -Throw
    }

    It "Works with pipeline input" {
        { $testData | Format-WinOpsTable } | Should -Not -Throw
    }
}

Describe "Write-WinOpsHeader" {
    It "Writes header without error" {
        { Write-WinOpsHeader -Title "Test Header" } | Should -Not -Throw
    }

    It "Handles empty title" {
        { Write-WinOpsHeader -Title "" } | Should -Not -Throw
    }

    It "Handles long title" {
        { Write-WinOpsHeader -Title ("Test " * 20) } | Should -Not -Throw
    }
}

Describe "Write-WinOpsSummary" {
    It "Writes summary without error" {
        { Write-WinOpsSummary -CleanedCount 10 -CleanedBytes 1048576 -KilledProcs 2 } | Should -Not -Throw
    }

    It "Handles zero values" {
        { Write-WinOpsSummary -CleanedCount 0 -CleanedBytes 0 -KilledProcs 0 } | Should -Not -Throw
    }

    It "Works with partial parameters" {
        { Write-WinOpsSummary -CleanedCount 5 } | Should -Not -Throw
        { Write-WinOpsSummary -KilledProcs 3 } | Should -Not -Throw
    }

    It "Works without parameters" {
        { Write-WinOpsSummary } | Should -Not -Throw
    }
}

Describe "Write-WinOpsReport" {
    BeforeEach {
        $script:beforeSnapshot = @{
            DiskUsagePct  = 75
            DiskFreeBytes = 10GB
            MemUsedBytes  = 8GB
            MemTotalBytes = 16GB
        }

        $script:afterSnapshot = @{
            DiskUsagePct  = 70
            DiskFreeBytes = 12GB
            MemUsedBytes  = 7GB
            MemTotalBytes = 16GB
        }
    }

    It "Writes report without error" {
        {
            Write-WinOpsReport `
                -BeforeSnapshot $beforeSnapshot `
                -AfterSnapshot $afterSnapshot `
                -CleanedCount 10 `
                -CleanedBytes 2GB `
                -KilledProcs 2
        } | Should -Not -Throw
    }

    It "Handles zero cleanup values" {
        {
            Write-WinOpsReport `
                -BeforeSnapshot $beforeSnapshot `
                -AfterSnapshot $afterSnapshot `
                -CleanedCount 0 `
                -CleanedBytes 0 `
                -KilledProcs 0
        } | Should -Not -Throw
    }

    It "Handles negative deltas" {
        $afterWorse = @{
            DiskUsagePct  = 80
            DiskFreeBytes = 8GB
            MemUsedBytes  = 10GB
            MemTotalBytes = 16GB
        }

        {
            Write-WinOpsReport `
                -BeforeSnapshot $beforeSnapshot `
                -AfterSnapshot $afterWorse
        } | Should -Not -Throw
    }

    It "Handles same before/after values" {
        {
            Write-WinOpsReport `
                -BeforeSnapshot $beforeSnapshot `
                -AfterSnapshot $beforeSnapshot
        } | Should -Not -Throw
    }
}

AfterAll {
    # Clean up
    Remove-Module Format -ErrorAction SilentlyContinue
}
