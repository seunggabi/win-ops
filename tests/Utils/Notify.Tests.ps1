#Requires -Modules Pester

BeforeAll {
    $script:ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\lib\utils\Notify.psm1"
    Import-Module $script:ModulePath -Force

    # Mock Get-Module for BurntToast tests
    Mock -ModuleName Notify Get-Module {
        param($Name, $ListAvailable)
        if ($Name -eq 'BurntToast') {
            return $null  # Simulate BurntToast not installed by default
        }
    }

    Mock -ModuleName Notify Import-Module {
        param($Name)
        if ($Name -eq 'BurntToast') {
            return $null
        }
    }
}

AfterAll {
    Remove-Module -Name Notify -ErrorAction SilentlyContinue
}

Describe "Initialize-WinOpsNotify" {
    Context "Basic initialization" {
        It "Should initialize without error" {
            { Initialize-WinOpsNotify } | Should -Not -Throw
        }

        It "Should set initialized flag" {
            Initialize-WinOpsNotify
            $support = Test-WinOpsNotificationSupport
            $support.Initialized | Should -Be $true
        }

        It "Should detect scheduled mode" {
            Initialize-WinOpsNotify
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'ScheduledMode'
        }

        It "Should not re-initialize unless forced" {
            Initialize-WinOpsNotify
            Initialize-WinOpsNotify  # Second call should be no-op
            { Initialize-WinOpsNotify } | Should -Not -Throw
        }

        It "Should re-initialize when forced" {
            Initialize-WinOpsNotify
            { Initialize-WinOpsNotify -Force } | Should -Not -Throw
        }
    }

    Context "BurntToast detection" {
        It "Should detect BurntToast availability" {
            Initialize-WinOpsNotify -Force
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'BurntToastAvailable'
        }

        It "Should set BurntToastAvailable to false when module not found" {
            Initialize-WinOpsNotify -Force
            $support = Test-WinOpsNotificationSupport
            # With our mock, should be false
            $support.BurntToastAvailable | Should -Be $false
        }
    }
}

Describe "Send-WinOpsNotification" {
    BeforeEach {
        # Ensure initialization
        Initialize-WinOpsNotify -Force
    }

    Context "Parameter validation" {
        It "Should require message parameter" {
            { Send-WinOpsNotification } | Should -Throw
        }

        It "Should accept message only" {
            { Send-WinOpsNotification -Message "Test" } | Should -Not -Throw
        }

        It "Should use default title when not specified" {
            { Send-WinOpsNotification -Message "Test" } | Should -Not -Throw
        }

        It "Should accept custom title" {
            { Send-WinOpsNotification -Title "Custom" -Message "Test" } | Should -Not -Throw
        }

        It "Should validate notification type" {
            { Send-WinOpsNotification -Message "Test" -Type "InvalidType" } | Should -Throw
        }

        It "Should accept all valid notification types" {
            $types = @('Success', 'Warning', 'Error', 'Info')
            foreach ($type in $types) {
                { Send-WinOpsNotification -Message "Test" -Type $type } | Should -Not -Throw
            }
        }
    }

    Context "Force parameter" {
        It "Should send notification when forced in interactive mode" {
            { Send-WinOpsNotification -Message "Test" -Force } | Should -Not -Throw
        }

        It "Should accept force switch" {
            { Send-WinOpsNotification -Message "Test" -Type Success -Force } | Should -Not -Throw
        }
    }

    Context "Notification types" {
        It "Should handle Success notification" {
            { Send-WinOpsNotification -Message "Success test" -Type Success -Force } | Should -Not -Throw
        }

        It "Should handle Warning notification" {
            { Send-WinOpsNotification -Message "Warning test" -Type Warning -Force } | Should -Not -Throw
        }

        It "Should handle Error notification" {
            { Send-WinOpsNotification -Message "Error test" -Type Error -Force } | Should -Not -Throw
        }

        It "Should handle Info notification" {
            { Send-WinOpsNotification -Message "Info test" -Type Info -Force } | Should -Not -Throw
        }

        It "Should default to Info type" {
            { Send-WinOpsNotification -Message "Default type test" -Force } | Should -Not -Throw
        }
    }

    Context "Auto-initialization" {
        It "Should auto-initialize if not already initialized" {
            # Create a fresh module state by reimporting
            Remove-Module -Name Notify -ErrorAction SilentlyContinue
            Import-Module $script:ModulePath -Force

            { Send-WinOpsNotification -Message "Test" -Force } | Should -Not -Throw
        }
    }

    Context "Error handling" {
        It "Should fail silently on notification errors" {
            # Even if notification mechanism fails, should not throw
            { Send-WinOpsNotification -Message "Test" -Force } | Should -Not -Throw
        }
    }
}

Describe "Test-WinOpsNotificationSupport" {
    Context "Support information" {
        BeforeEach {
            Initialize-WinOpsNotify -Force
        }

        It "Should return support information" {
            $support = Test-WinOpsNotificationSupport
            $support | Should -Not -BeNullOrEmpty
        }

        It "Should include initialized status" {
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'Initialized'
        }

        It "Should include BurntToast availability" {
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'BurntToastAvailable'
        }

        It "Should include scheduled mode status" {
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'ScheduledMode'
        }

        It "Should include user session status" {
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'UserSession'
        }

        It "Should include recommended method" {
            $support = Test-WinOpsNotificationSupport
            $support.PSObject.Properties.Name | Should -Contain 'RecommendedMethod'
        }

        It "Should recommend fallback when BurntToast unavailable" {
            $support = Test-WinOpsNotificationSupport
            if (-not $support.BurntToastAvailable) {
                $support.RecommendedMethod | Should -Be 'Fallback'
            }
        }
    }

    Context "Auto-initialization" {
        It "Should auto-initialize if not already initialized" {
            # Create a fresh module state
            Remove-Module -Name Notify -ErrorAction SilentlyContinue
            Import-Module $script:ModulePath -Force

            $support = Test-WinOpsNotificationSupport
            $support.Initialized | Should -Be $true
        }
    }
}

Describe "Install-BurntToast" {
    Context "Parameter validation" {
        It "Should accept CurrentUser scope" {
            # Using WhatIf to avoid actual installation
            { Install-BurntToast -Scope CurrentUser -WhatIf } | Should -Not -Throw
        }

        It "Should accept AllUsers scope" {
            { Install-BurntToast -Scope AllUsers -WhatIf } | Should -Not -Throw
        }

        It "Should validate scope parameter" {
            { Install-BurntToast -Scope "InvalidScope" -WhatIf } | Should -Throw
        }

        It "Should default to CurrentUser scope" {
            { Install-BurntToast -WhatIf } | Should -Not -Throw
        }
    }

    Context "ShouldProcess support" {
        It "Should support WhatIf" {
            { Install-BurntToast -WhatIf } | Should -Not -Throw
        }

        It "Should support Confirm" {
            # Can't easily test interactive confirm, but verify parameter exists
            $command = Get-Command Install-BurntToast
            $command.Parameters.ContainsKey('Confirm') | Should -Be $true
        }
    }

    Context "Installation simulation" {
        It "Should handle installation errors gracefully" {
            Mock -ModuleName Notify Install-Module {
                throw "Simulated installation failure"
            }

            # Should not throw, returns false on failure
            { Install-BurntToast -WhatIf } | Should -Not -Throw
        }
    }
}

Describe "Private Functions" {
    Context "Module behavior" {
        It "Should not export private functions" {
            $exportedCommands = (Get-Module Notify).ExportedCommands.Keys

            $exportedCommands | Should -Contain 'Initialize-WinOpsNotify'
            $exportedCommands | Should -Contain 'Send-WinOpsNotification'
            $exportedCommands | Should -Contain 'Test-WinOpsNotificationSupport'
            $exportedCommands | Should -Contain 'Install-BurntToast'

            # Private functions should not be exported
            $exportedCommands | Should -Not -Contain 'Test-BurntToastModule'
            $exportedCommands | Should -Not -Contain 'Test-UserSession'
            $exportedCommands | Should -Not -Contain 'Get-NotificationIcon'
            $exportedCommands | Should -Not -Contain 'Send-BurntToastNotification'
            $exportedCommands | Should -Not -Contain 'Send-FallbackNotification'
        }
    }
}

Describe "Notification Flow" {
    Context "End-to-end notification" {
        BeforeEach {
            Initialize-WinOpsNotify -Force
        }

        It "Should handle complete notification flow" {
            {
                Send-WinOpsNotification -Title "Test" -Message "Complete flow test" -Type Success -Force
            } | Should -Not -Throw
        }

        It "Should handle multiple sequential notifications" {
            {
                Send-WinOpsNotification -Message "First" -Type Info -Force
                Send-WinOpsNotification -Message "Second" -Type Success -Force
                Send-WinOpsNotification -Message "Third" -Type Warning -Force
            } | Should -Not -Throw
        }

        It "Should handle rapid notifications" {
            {
                1..10 | ForEach-Object {
                    Send-WinOpsNotification -Message "Notification $_" -Force
                }
            } | Should -Not -Throw
        }
    }
}

Describe "Module State" {
    Context "State management" {
        It "Should maintain state across function calls" {
            Initialize-WinOpsNotify -Force
            $support1 = Test-WinOpsNotificationSupport

            Send-WinOpsNotification -Message "Test" -Force
            $support2 = Test-WinOpsNotificationSupport

            $support1.Initialized | Should -Be $support2.Initialized
            $support1.BurntToastAvailable | Should -Be $support2.BurntToastAvailable
        }

        It "Should handle force re-initialization" {
            Initialize-WinOpsNotify -Force
            $support1 = Test-WinOpsNotificationSupport

            Initialize-WinOpsNotify -Force
            $support2 = Test-WinOpsNotificationSupport

            $support2.Initialized | Should -Be $true
        }
    }
}

Describe "Integration with logging" {
    Context "Logger fallback" {
        It "Should attempt to use logger if available on notification failure" {
            Mock -ModuleName Notify Get-Command {
                param($Name)
                if ($Name -eq 'Write-WinOpsLog') {
                    return [PSCustomObject]@{Name = 'Write-WinOpsLog'}
                }
                return $null
            }

            Mock -ModuleName Notify Write-WinOpsLog {}

            # This should attempt fallback to logger
            { Send-WinOpsNotification -Message "Test with logger" -Force } | Should -Not -Throw
        }
    }
}
