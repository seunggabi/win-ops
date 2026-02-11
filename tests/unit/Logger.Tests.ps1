# Logger.Tests.ps1 - Unit tests for Logger module

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\lib\core\Logger.psm1'
    Import-Module $modulePath -Force

    # Create temporary test directory
    $script:TestLogDir = Join-Path -Path $env:TEMP -ChildPath "win-ops-logger-tests-$(Get-Random)"
    New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup
    if (Test-Path -Path $script:TestLogDir) {
        Remove-Item -Path $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module Logger -ErrorAction SilentlyContinue
}

Describe 'Logger Module' {
    Context 'Module Import' {
        It 'Should export required functions' {
            $commands = Get-Command -Module Logger
            $commands.Name | Should -Contain 'Initialize-WinOpsLogger'
            $commands.Name | Should -Contain 'Write-WinOpsLog'
            $commands.Name | Should -Contain 'Set-WinOpsLogLevel'
            $commands.Name | Should -Contain 'Get-WinOpsLogPath'
            $commands.Name | Should -Contain 'Get-WinOpsLogLevel'
            $commands.Name | Should -Contain 'Clear-WinOpsLogs'
        }
    }

    Context 'Logger Initialization' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "test-$(Get-Random).log"
        }

        It 'Should initialize logger with default settings' {
            Initialize-WinOpsLogger -LogPath $script:TestLogPath
            $logPath = Get-WinOpsLogPath
            $logPath | Should -Be $script:TestLogPath
        }

        It 'Should create log directory if not exists' {
            $newLogPath = Join-Path -Path $script:TestLogDir -ChildPath "subdir\test.log"
            Initialize-WinOpsLogger -LogPath $newLogPath
            $parentDir = Split-Path -Path $newLogPath -Parent
            Test-Path -Path $parentDir | Should -Be $true
        }

        It 'Should set custom log level' {
            Initialize-WinOpsLogger -LogPath $script:TestLogPath -LogLevel 'DEBUG'
            $level = Get-WinOpsLogLevel
            $level | Should -Be 'DEBUG'
        }
    }

    Context 'Log Writing' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "test-$(Get-Random).log"
            Initialize-WinOpsLogger -LogPath $script:TestLogPath -LogLevel 'DEBUG'
        }

        AfterEach {
            if (Test-Path -Path $script:TestLogPath) {
                Remove-Item -Path $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should write INFO log message' {
            Write-WinOpsLog -Level INFO -Message 'Test info message'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match '\[INFO\] Test info message'
        }

        It 'Should write ERROR log message' {
            Write-WinOpsLog -Level ERROR -Message 'Test error message'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match '\[ERROR\] Test error message'
        }

        It 'Should write WARN log message' {
            Write-WinOpsLog -Level WARN -Message 'Test warning message'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match '\[WARN\] Test warning message'
        }

        It 'Should write DEBUG log message' {
            Write-WinOpsLog -Level DEBUG -Message 'Test debug message'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match '\[DEBUG\] Test debug message'
        }

        It 'Should include timestamp in log format' {
            Write-WinOpsLog -Level INFO -Message 'Timestamp test'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
        }

        It 'Should log with context data' {
            $context = @{
                UserId = 'user123'
                Action = 'login'
            }
            Write-WinOpsLog -Level INFO -Message 'User action' -Context $context
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match 'Context:'
            $content | Should -Match 'UserId'
        }

        It 'Should log exception information' {
            try {
                throw 'Test exception'
            } catch {
                Write-WinOpsLog -Level ERROR -Message 'Exception caught' -Exception $_
            }
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match 'Test exception'
        }
    }

    Context 'Log Level Filtering' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "test-$(Get-Random).log"
            Initialize-WinOpsLogger -LogPath $script:TestLogPath -LogLevel 'WARN'
        }

        AfterEach {
            if (Test-Path -Path $script:TestLogPath) {
                Remove-Item -Path $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should not log messages below threshold' {
            Write-WinOpsLog -Level INFO -Message 'Should not appear'
            Write-WinOpsLog -Level DEBUG -Message 'Should not appear either'
            Start-Sleep -Milliseconds 100

            if (Test-Path -Path $script:TestLogPath) {
                $content = Get-Content -Path $script:TestLogPath -Raw
                $content | Should -Not -Match 'Should not appear'
            }
        }

        It 'Should log messages at or above threshold' {
            Write-WinOpsLog -Level WARN -Message 'Should appear'
            Write-WinOpsLog -Level ERROR -Message 'Should also appear'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match 'Should appear'
            $content | Should -Match 'Should also appear'
        }

        It 'Should update log level dynamically' {
            Set-WinOpsLogLevel -Level 'DEBUG'
            Write-WinOpsLog -Level DEBUG -Message 'Now visible'
            Start-Sleep -Milliseconds 100
            $content = Get-Content -Path $script:TestLogPath -Raw
            $content | Should -Match 'Now visible'
        }
    }

    Context 'Log Rotation' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "rotation-$(Get-Random).log"
            # Initialize with small file size for testing
            Initialize-WinOpsLogger -LogPath $script:TestLogPath -LogLevel 'INFO' -MaxLogSizeBytes 1KB -MaxLogFiles 3
        }

        AfterEach {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:TestLogPath)
            $directory = Split-Path -Path $script:TestLogPath -Parent
            Get-ChildItem -Path $directory -Filter "$baseName*" | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'Should rotate log file when size exceeds limit' {
            # Write enough logs to exceed 1KB
            for ($i = 0; $i -lt 50; $i++) {
                Write-WinOpsLog -Level INFO -Message "Log entry $i - Adding some extra content to increase size quickly"
            }
            Start-Sleep -Milliseconds 200

            # Check if rotation occurred
            $rotatedFile = "$($script:TestLogPath -replace '\.log$', '.1.log')"
            $rotationOccurred = (Test-Path -Path $rotatedFile) -or ((Get-Item -Path $script:TestLogPath -ErrorAction SilentlyContinue).Length -lt 1KB)
            $rotationOccurred | Should -Be $true
        }

        It 'Should maintain maximum number of log files' {
            # Force multiple rotations
            for ($round = 0; $round -lt 5; $round++) {
                for ($i = 0; $i -lt 30; $i++) {
                    Write-WinOpsLog -Level INFO -Message "Round $round Entry $i - Extra padding text here to reach size limit"
                }
                Start-Sleep -Milliseconds 100
            }

            $directory = Split-Path -Path $script:TestLogPath -Parent
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:TestLogPath)
            $logFiles = Get-ChildItem -Path $directory -Filter "$baseName*"
            $logFiles.Count | Should -BeLessOrEqual 4  # Current + 3 rotated
        }
    }

    Context 'Utility Functions' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "util-$(Get-Random).log"
            Initialize-WinOpsLogger -LogPath $script:TestLogPath
        }

        AfterEach {
            if (Test-Path -Path $script:TestLogPath) {
                Remove-Item -Path $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should return correct log path' {
            $path = Get-WinOpsLogPath
            $path | Should -Be $script:TestLogPath
        }

        It 'Should return current log level' {
            $level = Get-WinOpsLogLevel
            $level | Should -BeIn @('DEBUG', 'INFO', 'WARN', 'ERROR')
        }

        It 'Should clear all log files' {
            Write-WinOpsLog -Level INFO -Message 'Test before clear'
            Start-Sleep -Milliseconds 100
            Clear-WinOpsLogs -Confirm:$false

            if (Test-Path -Path $script:TestLogPath) {
                $size = (Get-Item -Path $script:TestLogPath).Length
                $size | Should -BeLessOrEqual 100  # Should be empty or minimal
            }
        }
    }

    Context 'Thread Safety' {
        BeforeEach {
            $script:TestLogPath = Join-Path -Path $script:TestLogDir -ChildPath "thread-$(Get-Random).log"
            Initialize-WinOpsLogger -LogPath $script:TestLogPath -LogLevel 'INFO'
        }

        AfterEach {
            if (Test-Path -Path $script:TestLogPath) {
                Remove-Item -Path $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should handle concurrent writes' {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($LogPath, $Index, $ModulePath)
                    Import-Module $ModulePath -Force
                    Initialize-WinOpsLogger -LogPath $LogPath
                    for ($i = 0; $i -lt 10; $i++) {
                        Write-WinOpsLog -Level INFO -Message "Job $Index Message $i"
                        Start-Sleep -Milliseconds 10
                    }
                } -ArgumentList $script:TestLogPath, $_, $modulePath
            }

            $jobs | Wait-Job | Remove-Job

            Start-Sleep -Milliseconds 500
            Test-Path -Path $script:TestLogPath | Should -Be $true
            $content = Get-Content -Path $script:TestLogPath
            $content.Count | Should -BeGreaterThan 0
        }
    }
}
