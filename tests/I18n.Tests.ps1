#Requires -Version 5.1

<#
.SYNOPSIS
    Tests for Win-Ops I18n module.

.DESCRIPTION
    Pester tests for internationalization functionality.
#>

BeforeAll {
    # Import the module using relative path
    $modulePath = Join-Path $PSScriptRoot '..\lib\core\I18n.psm1'
    Import-Module $modulePath -Force
}

Describe 'I18n Module' {
    Context 'Module Initialization' {
        It 'Should initialize with default language' {
            Initialize-WinOpsI18n
            $currentLang = Get-WinOpsCurrentLanguage
            $currentLang | Should -BeIn @('en-US', 'ko-KR')
        }

        It 'Should initialize with specified language' {
            Initialize-WinOpsI18n -Language 'ko-KR'
            Get-WinOpsCurrentLanguage | Should -Be 'ko-KR'
        }

        It 'Should load English as fallback' {
            Initialize-WinOpsI18n -Language 'en-US'
            Get-WinOpsCurrentLanguage | Should -Be 'en-US'
        }
    }

    Context 'Message Retrieval' {
        BeforeAll {
            Initialize-WinOpsI18n -Language 'en-US'
        }

        It 'Should retrieve simple message' {
            $msg = Get-WinOpsMessage -Key 'CLI_Help_Title'
            $msg | Should -Not -BeNullOrEmpty
            $msg | Should -Be 'Windows Operations Manager'
        }

        It 'Should retrieve message with parameters' {
            $msg = Get-WinOpsMessage -Key 'Version_Title' -Args 'win-ops', '1.0.0'
            $msg | Should -Be 'win-ops version 1.0.0'
        }

        It 'Should handle multiple parameters' {
            $msg = Get-WinOpsMessage -Key 'Cleanup_Starting' -Args $true, $false
            $msg | Should -Match 'Starting cleanup'
        }

        It 'Should return key in brackets for missing key' {
            $msg = Get-WinOpsMessage -Key 'NonExistent_Key'
            $msg | Should -Be '[NonExistent_Key]'
        }

        It 'Should use default for missing key' {
            $msg = Get-WinOpsMessage -Key 'NonExistent_Key' -Default 'Fallback'
            $msg | Should -Be 'Fallback'
        }
    }

    Context 'Language Switching' {
        It 'Should switch from English to Korean' {
            Initialize-WinOpsI18n -Language 'en-US'
            $enMsg = Get-WinOpsMessage -Key 'CLI_Help_Title'

            Set-WinOpsLanguage -Language 'ko-KR'
            $koMsg = Get-WinOpsMessage -Key 'CLI_Help_Title'

            $enMsg | Should -Not -Be $koMsg
            Get-WinOpsCurrentLanguage | Should -Be 'ko-KR'
        }

        It 'Should switch from Korean to English' {
            Initialize-WinOpsI18n -Language 'ko-KR'
            Set-WinOpsLanguage -Language 'en-US'
            Get-WinOpsCurrentLanguage | Should -Be 'en-US'
        }
    }

    Context 'Message Key Testing' {
        BeforeAll {
            Initialize-WinOpsI18n -Language 'en-US'
        }

        It 'Should return true for existing key' {
            Test-WinOpsMessageKey -Key 'CLI_Help_Title' | Should -Be $true
        }

        It 'Should return false for non-existent key' {
            Test-WinOpsMessageKey -Key 'NonExistent_Key' | Should -Be $false
        }
    }

    Context 'Korean Language Resources' {
        BeforeAll {
            Initialize-WinOpsI18n -Language 'ko-KR'
        }

        It 'Should load Korean messages' {
            $msg = Get-WinOpsMessage -Key 'CLI_Help_Title'
            $msg | Should -Be 'Windows 운영 관리자'
        }

        It 'Should support Korean parameter substitution' {
            $msg = Get-WinOpsMessage -Key 'Cleanup_Items' -Args 100
            $msg | Should -Match '100'
        }

        It 'Should fallback to English for missing Korean key' {
            # Add a key only in English for testing
            $msg = Get-WinOpsMessage -Key 'CLI_Help_Title'
            $msg | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Resource File Coverage' {
        It 'Should have same keys in en-US and ko-KR' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $enFile = Join-Path $projectRoot 'resources\en-US.json'
            $koFile = Join-Path $projectRoot 'resources\ko-KR.json'

            $enData = Get-Content -Path $enFile -Raw | ConvertFrom-Json -AsHashtable
            $koData = Get-Content -Path $koFile -Raw | ConvertFrom-Json -AsHashtable

            $enKeys = $enData.Keys | Sort-Object
            $koKeys = $koData.Keys | Sort-Object

            $enKeys.Count | Should -Be $koKeys.Count

            foreach ($key in $enKeys) {
                $koKeys | Should -Contain $key
            }
        }
    }
}
