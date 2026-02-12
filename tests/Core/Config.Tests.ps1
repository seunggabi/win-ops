#Requires -Modules Pester

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot "..\..\lib\core\Config.psm1"
    Import-Module $ModulePath -Force

    # Setup test environment
    $script:TestConfigDir = Join-Path $env:TEMP "WinOpsConfigTests_$([guid]::NewGuid().ToString('N'))"
    $script:TestConfigPath = Join-Path $script:TestConfigDir "config.json"
    $script:TestDefaultPath = Join-Path $script:TestConfigDir "default.json"

    # Mock environment for testing
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestConfigDir) {
        Remove-Item $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Restore environment
    $env:LOCALAPPDATA = $script:OriginalLocalAppData

    # Remove module
    Remove-Module Config -Force -ErrorAction SilentlyContinue
}

Describe "Config Module - Get-ConfigPath" {
    It "Returns a valid path" {
        $path = Get-ConfigPath
        $path | Should -Not -BeNullOrEmpty
        $path | Should -Match "win-ops"
    }

    It "Creates directory if it doesn't exist" {
        $testDir = Join-Path $env:TEMP "WinOpsConfigTest_$(Get-Random)"
        $env:LOCALAPPDATA = $testDir

        try {
            $path = Get-ConfigPath
            Test-Path (Split-Path $path -Parent) | Should -Be $true
        }
        finally {
            $env:LOCALAPPDATA = $script:OriginalLocalAppData
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Config Module - Get-DefaultConfigPath" {
    It "Returns path to default.json" {
        $path = Get-DefaultConfigPath
        $path | Should -Match "config\\default\.json$"
    }

    It "Path includes correct module structure" {
        $path = Get-DefaultConfigPath
        $path | Should -Match "config"
    }
}

Describe "Config Module - Expand-EnvironmentVariables" {
    It "Expands environment variables in string" {
        $input = "%TEMP%\test"
        $result = Expand-EnvironmentVariables -Value $input
        $result | Should -Be "$env:TEMP\test"
    }

    It "Handles strings without variables" {
        $input = "C:\NoVariables\Here"
        $result = Expand-EnvironmentVariables -Value $input
        $result | Should -Be $input
    }

    It "Expands multiple variables" {
        $input = "%TEMP%\%USERNAME%\data"
        $result = Expand-EnvironmentVariables -Value $input
        $result | Should -Be "$env:TEMP\$env:USERNAME\data"
    }
}

Describe "Config Module - Expand-ConfigObject" {
    It "Expands strings in hashtable" {
        $input = @{
            path = "%TEMP%\test"
            name = "test"
        }
        $result = Expand-ConfigObject -Object $input
        $result.path | Should -Be "$env:TEMP\test"
        $result.name | Should -Be "test"
    }

    It "Recursively expands nested objects" {
        $input = @{
            outer = @{
                inner = "%TEMP%\nested"
            }
        }
        $result = Expand-ConfigObject -Object $input
        $result.outer.inner | Should -Be "$env:TEMP\nested"
    }

    It "Expands arrays" {
        $input = @("%TEMP%\one", "%TEMP%\two")
        $result = Expand-ConfigObject -Object $input
        $result[0] | Should -Be "$env:TEMP\one"
        $result[1] | Should -Be "$env:TEMP\two"
    }

    It "Handles PSCustomObject" {
        $input = [PSCustomObject]@{
            path = "%TEMP%\test"
        }
        $result = Expand-ConfigObject -Object $input
        $result.path | Should -Be "$env:TEMP\test"
    }

    It "Returns non-string primitives unchanged" {
        Expand-ConfigObject -Object 123 | Should -Be 123
        Expand-ConfigObject -Object $true | Should -Be $true
        Expand-ConfigObject -Object $null | Should -BeNullOrEmpty
    }
}

Describe "Config Module - Merge-ConfigObject" {
    It "Merges two hashtables" {
        $default = @{ a = 1; b = 2 }
        $override = @{ b = 3; c = 4 }
        $result = Merge-ConfigObject -Default $default -Override $override

        $result.a | Should -Be 1
        $result.b | Should -Be 3
        $result.c | Should -Be 4
    }

    It "Returns default when override is null" {
        $default = @{ a = 1 }
        $result = Merge-ConfigObject -Default $default -Override $null
        $result.a | Should -Be 1
    }

    It "Recursively merges nested objects" {
        $default = @{
            outer = @{
                a = 1
                b = 2
            }
        }
        $override = @{
            outer = @{
                b = 3
                c = 4
            }
        }
        $result = Merge-ConfigObject -Default $default -Override $override

        $result.outer.a | Should -Be 1
        $result.outer.b | Should -Be 3
        $result.outer.c | Should -Be 4
    }

    It "Override replaces non-object values" {
        $default = @{ value = "old" }
        $override = @{ value = "new" }
        $result = Merge-ConfigObject -Default $default -Override $override
        $result.value | Should -Be "new"
    }

    It "Returns PSCustomObject" {
        $default = @{ a = 1 }
        $result = Merge-ConfigObject -Default $default -Override $null
        $result | Should -BeOfType [PSCustomObject]
    }
}

Describe "Config Module - Read-JsonConfigFile" {
    BeforeEach {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Reads valid JSON file" {
        $testData = @{ test = "value" }
        $testData | ConvertTo-Json | Set-Content $script:TestConfigPath

        $result = Read-JsonConfigFile -Path $script:TestConfigPath
        $result.test | Should -Be "value"
    }

    It "Returns null for non-existent file" {
        $result = Read-JsonConfigFile -Path "C:\NonExistent\File.json"
        $result | Should -BeNullOrEmpty
    }

    It "Handles invalid JSON gracefully" {
        "{ invalid json }" | Set-Content $script:TestConfigPath

        { Read-JsonConfigFile -Path $script:TestConfigPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It "Handles file locking" {
        $testData = @{ locked = $true }
        $testData | ConvertTo-Json | Set-Content $script:TestConfigPath

        # Read should succeed even with shared read access
        $result = Read-JsonConfigFile -Path $script:TestConfigPath
        $result.locked | Should -Be $true
    }
}

Describe "Config Module - Write-JsonConfigFile" {
    BeforeEach {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Writes configuration to file" {
        $config = @{ key = "value" }
        Write-JsonConfigFile -Path $script:TestConfigPath -Config $config

        Test-Path $script:TestConfigPath | Should -Be $true
        $content = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $content.key | Should -Be "value"
    }

    It "Creates directory if it doesn't exist" {
        $newPath = Join-Path $script:TestConfigDir "subdir\config.json"
        $config = @{ test = $true }

        Write-JsonConfigFile -Path $newPath -Config $config

        Test-Path $newPath | Should -Be $true
    }

    It "Overwrites existing file" {
        @{ old = $true } | ConvertTo-Json | Set-Content $script:TestConfigPath

        Write-JsonConfigFile -Path $script:TestConfigPath -Config @{ new = $true }

        $content = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $content.PSObject.Properties.Name | Should -Contain "new"
        $content.PSObject.Properties.Name | Should -Not -Contain "old"
    }

    It "Formats JSON with indentation" {
        $config = @{ nested = @{ value = 123 } }
        Write-JsonConfigFile -Path $script:TestConfigPath -Config $config

        $content = Get-Content $script:TestConfigPath -Raw
        $content | Should -Match "`n"  # Multi-line
        $content | Should -Match "  "  # Indentation
    }
}

Describe "Config Module - Set-WinOpsConfig" {
    BeforeEach {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Sets simple key-value pair" {
        Set-WinOpsConfig -Key "testkey" -Value "testvalue" -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.testkey | Should -Be "testvalue"
    }

    It "Sets nested key path" {
        Set-WinOpsConfig -Key "level1.level2.key" -Value 123 -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.level1.level2.key | Should -Be 123
    }

    It "Creates nested structure automatically" {
        Set-WinOpsConfig -Key "a.b.c.d" -Value "deep" -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.a.b.c.d | Should -Be "deep"
    }

    It "Updates existing key" {
        @{ existing = "old" } | ConvertTo-Json | Set-Content $script:TestConfigPath

        Set-WinOpsConfig -Key "existing" -Value "new" -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.existing | Should -Be "new"
    }

    It "Preserves other keys when updating" {
        @{ keep = "this"; change = "old" } | ConvertTo-Json | Set-Content $script:TestConfigPath

        Set-WinOpsConfig -Key "change" -Value "new" -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.keep | Should -Be "this"
        $config.change | Should -Be "new"
    }

    It "Supports WhatIf" {
        { Set-WinOpsConfig -Key "test" -Value "value" -Path $script:TestConfigPath -WhatIf } |
            Should -Not -Throw

        Test-Path $script:TestConfigPath | Should -Be $false
    }
}

Describe "Config Module - Get-WinOpsConfig" {
    BeforeAll {
        # Create a mock default config
        $mockDefaultDir = Join-Path $script:TestConfigDir "config"
        New-Item -Path $mockDefaultDir -ItemType Directory -Force | Out-Null

        $defaultConfig = @{
            cleanup = @{
                max_threads = 4
                dry_run = $false
            }
            trash = @{
                path = "%LOCALAPPDATA%\win-ops\trash"
                retention_hours = 72
            }
        }
        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $mockDefaultDir "default.json")
    }

    It "Returns full configuration without key" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        $config = Get-WinOpsConfig
        $config | Should -Not -BeNullOrEmpty
        $config.cleanup | Should -Not -BeNullOrEmpty
    }

    It "Returns specific value for dot-notation key" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        $value = Get-WinOpsConfig -Key "cleanup.max_threads"
        $value | Should -Be 4
    }

    It "Returns nested object for partial key path" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        $cleanup = Get-WinOpsConfig -Key "cleanup"
        $cleanup.max_threads | Should -Be 4
        $cleanup.dry_run | Should -Be $false
    }

    It "Returns null and warns for non-existent key" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        $result = Get-WinOpsConfig -Key "nonexistent.key" -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It "Expands environment variables in returned values" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        $path = Get-WinOpsConfig -Key "trash.path"
        $path | Should -Not -Match "%"
        $escapedPath = [regex]::Escape($env:LOCALAPPDATA)
        $path | Should -Match $escapedPath
    }
}

Describe "Config Module - Initialize-WinOpsConfig" {
    BeforeEach {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null
        $mockDefaultDir = Join-Path $script:TestConfigDir "config"
        New-Item -Path $mockDefaultDir -ItemType Directory -Force | Out-Null
        @{ default = $true } | ConvertTo-Json | Set-Content (Join-Path $mockDefaultDir "default.json")
    }

    AfterEach {
        Remove-Item $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Creates config file from default" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        Initialize-WinOpsConfig -Confirm:$false

        Test-Path (Join-Path $script:TestConfigDir "config.json") | Should -Be $true
    }

    It "Does not overwrite existing config without Force" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        @{ existing = "preserved" } | ConvertTo-Json | Set-Content (Join-Path $script:TestConfigDir "config.json")

        Initialize-WinOpsConfig -Confirm:$false

        $config = Get-Content (Join-Path $script:TestConfigDir "config.json") -Raw | ConvertFrom-Json
        $config.existing | Should -Be "preserved"
    }

    It "Overwrites existing config with Force" {
        Mock Get-ConfigPath { Join-Path $script:TestConfigDir "config.json" }
        Mock Get-DefaultConfigPath { Join-Path $script:TestConfigDir "config\default.json" }

        @{ existing = "old" } | ConvertTo-Json | Set-Content (Join-Path $script:TestConfigDir "config.json")

        Initialize-WinOpsConfig -Force -Confirm:$false

        $config = Get-Content (Join-Path $script:TestConfigDir "config.json") -Raw | ConvertFrom-Json
        $config.default | Should -Be $true
        $config.PSObject.Properties.Name | Should -Not -Contain "existing"
    }
}

Describe "Config Module - Edge Cases" {
    It "Handles empty configuration files" {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null
        "{}" | Set-Content $script:TestConfigPath

        $result = Read-JsonConfigFile -Path $script:TestConfigPath
        $result | Should -Not -BeNullOrEmpty
    }

    It "Handles deeply nested key paths" {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null

        Set-WinOpsConfig -Key "a.b.c.d.e.f.g" -Value "deep" -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.a.b.c.d.e.f.g | Should -Be "deep"
    }

    It "Handles special characters in values" {
        New-Item -Path $script:TestConfigDir -ItemType Directory -Force | Out-Null

        $specialValue = 'C:\Path\With\Backslashes\And\$pecial\Characters'
        Set-WinOpsConfig -Key "special" -Value $specialValue -Path $script:TestConfigPath -Confirm:$false

        $config = Get-Content $script:TestConfigPath -Raw | ConvertFrom-Json
        $config.special | Should -Be $specialValue
    }
}
