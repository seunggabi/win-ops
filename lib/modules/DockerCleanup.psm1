#Requires -Version 5.1

<#
.SYNOPSIS
    Docker cleanup module for containers, images, volumes, and build cache.

.DESCRIPTION
    Provides Docker cleanup operations:
    - Remove stopped containers
    - Remove dangling images
    - Remove unused volumes
    - Clean build cache
    - Prune entire system
    - WSL2 compact virtual disk

.NOTES
    Module: WinOps.Modules.DockerCleanup
    Requires: Core modules (Config, Logger, Safety)
    Requires: Docker Desktop installed
#>

# Import required core modules
$coreModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lib\core'
Import-Module (Join-Path $coreModulePath 'Config.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Logger.psm1') -Force
Import-Module (Join-Path $coreModulePath 'Safety.psm1') -Force

#region Private Functions

function Test-DockerInstalled {
    <#
    .SYNOPSIS
        Checks if Docker is installed and running.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue

    if (-not $dockerCommand) {
        return @{
            Installed = $false
            Running = $false
            Version = $null
        }
    }

    try {
        $versionOutput = docker version --format '{{.Server.Version}}' 2>&1
        $isRunning = $LASTEXITCODE -eq 0

        return @{
            Installed = $true
            Running = $isRunning
            Version = if ($isRunning) { $versionOutput } else { $null }
        }
    }
    catch {
        return @{
            Installed = $true
            Running = $false
            Version = $null
        }
    }
}

function Get-DockerDiskUsage {
    <#
    .SYNOPSIS
        Gets Docker disk usage information.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $output = docker system df --format '{{json .}}' 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Docker system df failed: $output"
        }

        $usage = @{
            Images = @{ Count = 0; Active = 0; Size = 0; Reclaimable = 0 }
            Containers = @{ Count = 0; Active = 0; Size = 0; Reclaimable = 0 }
            Volumes = @{ Count = 0; Active = 0; Size = 0; Reclaimable = 0 }
            BuildCache = @{ Count = 0; Active = 0; Size = 0; Reclaimable = 0 }
        }

        foreach ($line in $output) {
            $data = $line | ConvertFrom-Json

            $type = $data.Type
            $count = $data.Total
            $active = $data.Active
            $size = $data.Size
            $reclaimable = $data.Reclaimable

            # Parse size (e.g., "1.5GB", "500MB")
            $sizeBytes = Convert-DockerSize -SizeString $size
            $reclaimableBytes = Convert-DockerSize -SizeString $reclaimable

            switch ($type) {
                'Images' {
                    $usage.Images = @{
                        Count = $count
                        Active = $active
                        Size = $sizeBytes
                        Reclaimable = $reclaimableBytes
                    }
                }
                'Containers' {
                    $usage.Containers = @{
                        Count = $count
                        Active = $active
                        Size = $sizeBytes
                        Reclaimable = $reclaimableBytes
                    }
                }
                'Local Volumes' {
                    $usage.Volumes = @{
                        Count = $count
                        Active = $active
                        Size = $sizeBytes
                        Reclaimable = $reclaimableBytes
                    }
                }
                'Build Cache' {
                    $usage.BuildCache = @{
                        Count = $count
                        Active = $active
                        Size = $sizeBytes
                        Reclaimable = $reclaimableBytes
                    }
                }
            }
        }

        return [PSCustomObject]$usage
    }
    catch {
        Write-Error "Failed to get Docker disk usage: $_"
        return $null
    }
}

function Convert-DockerSize {
    <#
    .SYNOPSIS
        Converts Docker size string to bytes.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [string]$SizeString
    )

    if ($SizeString -match '^(\d+\.?\d*)\s*([KMGT]?B)') {
        $value = [double]$matches[1]
        $unit = $matches[2]

        switch ($unit) {
            'B' { return [long]$value }
            'KB' { return [long]($value * 1KB) }
            'MB' { return [long]($value * 1MB) }
            'GB' { return [long]($value * 1GB) }
            'TB' { return [long]($value * 1TB) }
            default { return 0 }
        }
    }

    return 0
}

function Invoke-DockerCommand {
    <#
    .SYNOPSIS
        Executes Docker command and returns result.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [string]$Description
    )

    try {
        Write-Verbose "Executing: docker $Command"

        $output = Invoke-Expression "docker $Command" 2>&1
        $exitCode = $LASTEXITCODE

        return [PSCustomObject]@{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $output
            Description = $Description
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            ExitCode = -1
            Output = $_.Exception.Message
            Description = $Description
            Error = $_
        }
    }
}

#endregion

#region Public Functions

function Clear-WinOpsDockerResources {
    <#
    .SYNOPSIS
        Cleans Docker resources (containers, images, volumes, cache).

    .DESCRIPTION
        Removes unused Docker resources to free up disk space.

    .PARAMETER ResourceType
        Type of resource to clean:
        - Containers: Remove stopped containers
        - Images: Remove dangling images
        - Volumes: Remove unused volumes
        - BuildCache: Remove build cache
        - Networks: Remove unused networks
        - All: Clean all resources

    .PARAMETER Force
        Force removal without confirmation.

    .PARAMETER DryRun
        Show what would be removed without actually removing.

    .EXAMPLE
        Clear-WinOpsDockerResources -ResourceType Containers
        # Removes all stopped containers

    .EXAMPLE
        Clear-WinOpsDockerResources -ResourceType All -Force
        # Aggressively cleans all unused Docker resources
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Containers', 'Images', 'Volumes', 'BuildCache', 'Networks', 'All')]
        [string]$ResourceType,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DryRun
    )

    Write-WinOpsLog -Level INFO -Message "Starting Docker cleanup: $ResourceType"

    # Check if Docker is running
    $dockerStatus = Test-DockerInstalled

    if (-not $dockerStatus.Installed) {
        throw "Docker is not installed"
    }

    if (-not $dockerStatus.Running) {
        throw "Docker is not running. Please start Docker Desktop."
    }

    # Get current disk usage
    $beforeUsage = Get-DockerDiskUsage

    $results = @()

    switch ($ResourceType) {
        'Containers' {
            Write-Verbose "Cleaning stopped containers..."

            if ($DryRun) {
                $output = docker ps -a --filter "status=exited" --format "{{.ID}} {{.Names}}" 2>&1
                $containerCount = ($output | Measure-Object).Count

                $results += [PSCustomObject]@{
                    Resource = 'Containers'
                    Action = 'DryRun'
                    Count = $containerCount
                    Success = $true
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("Stopped containers", "Remove")) {
                    $result = Invoke-DockerCommand -Command "container prune -f" -Description "Remove stopped containers"
                    $results += [PSCustomObject]@{
                        Resource = 'Containers'
                        Action = 'Removed'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }

        'Images' {
            Write-Verbose "Cleaning dangling images..."

            if ($DryRun) {
                $output = docker images -f "dangling=true" -q 2>&1
                $imageCount = ($output | Measure-Object).Count

                $results += [PSCustomObject]@{
                    Resource = 'Images'
                    Action = 'DryRun'
                    Count = $imageCount
                    Success = $true
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("Dangling images", "Remove")) {
                    $result = Invoke-DockerCommand -Command "image prune -f" -Description "Remove dangling images"
                    $results += [PSCustomObject]@{
                        Resource = 'Images'
                        Action = 'Removed'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }

        'Volumes' {
            Write-Verbose "Cleaning unused volumes..."

            if ($DryRun) {
                $output = docker volume ls -f "dangling=true" -q 2>&1
                $volumeCount = ($output | Measure-Object).Count

                $results += [PSCustomObject]@{
                    Resource = 'Volumes'
                    Action = 'DryRun'
                    Count = $volumeCount
                    Success = $true
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("Unused volumes", "Remove")) {
                    $result = Invoke-DockerCommand -Command "volume prune -f" -Description "Remove unused volumes"
                    $results += [PSCustomObject]@{
                        Resource = 'Volumes'
                        Action = 'Removed'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }

        'BuildCache' {
            Write-Verbose "Cleaning build cache..."

            if (-not $DryRun) {
                if ($PSCmdlet.ShouldProcess("Build cache", "Remove")) {
                    $result = Invoke-DockerCommand -Command "builder prune -f" -Description "Remove build cache"
                    $results += [PSCustomObject]@{
                        Resource = 'BuildCache'
                        Action = 'Removed'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }

        'Networks' {
            Write-Verbose "Cleaning unused networks..."

            if (-not $DryRun) {
                if ($PSCmdlet.ShouldProcess("Unused networks", "Remove")) {
                    $result = Invoke-DockerCommand -Command "network prune -f" -Description "Remove unused networks"
                    $results += [PSCustomObject]@{
                        Resource = 'Networks'
                        Action = 'Removed'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }

        'All' {
            Write-Warning "This will remove all stopped containers, dangling images, unused volumes, networks, and build cache"

            if (-not $DryRun) {
                if ($Force -or $PSCmdlet.ShouldProcess("All unused Docker resources", "Remove")) {
                    $command = if ($Force) { "system prune -a -f --volumes" } else { "system prune -f --volumes" }
                    $result = Invoke-DockerCommand -Command $command -Description "Prune Docker system"
                    $results += [PSCustomObject]@{
                        Resource = 'All'
                        Action = 'Pruned'
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            }
        }
    }

    # Get disk usage after cleanup
    if (-not $DryRun) {
        $afterUsage = Get-DockerDiskUsage

        $spaceReclaimed = $beforeUsage.Images.Size + $beforeUsage.Containers.Size + $beforeUsage.Volumes.Size + $beforeUsage.BuildCache.Size -
                          ($afterUsage.Images.Size + $afterUsage.Containers.Size + $afterUsage.Volumes.Size + $afterUsage.BuildCache.Size)

        Write-WinOpsLog -Level INFO -Message "Docker cleanup complete: Reclaimed $([math]::Round($spaceReclaimed / 1GB, 2)) GB"
    }

    return $results
}

function Optimize-WinOpsDockerWSL {
    <#
    .SYNOPSIS
        Optimizes Docker WSL2 virtual disk by compacting it.

    .DESCRIPTION
        Compacts the Docker Desktop WSL2 virtual disk (ext4.vhdx) to reclaim unused space.
        This can significantly reduce disk usage after cleaning Docker resources.

    .EXAMPLE
        Optimize-WinOpsDockerWSL
        # Compacts Docker WSL2 virtual disk
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param()

    Write-WinOpsLog -Level INFO -Message "Starting Docker WSL2 disk optimization"

    # Check if WSL2 is installed
    $wslCommand = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wslCommand) {
        throw "WSL is not installed"
    }

    # Find Docker WSL2 virtual disk
    $dockerWSLPath = "$env:LOCALAPPDATA\Docker\wsl\data\ext4.vhdx"

    if (-not (Test-Path $dockerWSLPath)) {
        throw "Docker WSL2 virtual disk not found at: $dockerWSLPath"
    }

    $beforeSize = (Get-Item $dockerWSLPath).Length

    Write-Verbose "Docker WSL2 disk size before optimization: $([math]::Round($beforeSize / 1GB, 2)) GB"

    if (-not $PSCmdlet.ShouldProcess("Docker WSL2 virtual disk ($([math]::Round($beforeSize / 1GB, 2)) GB)", "Optimize")) {
        return [PSCustomObject]@{
            Success = $false
            Message = "Cancelled by user"
        }
    }

    try {
        # Safety check: verify path is safe to modify
        if (-not (Test-WinOpsPathSafe -Path $dockerWSLPath)) {
            throw "Docker WSL2 virtual disk path is in a protected location: $dockerWSLPath"
        }

        # Shutdown Docker WSL2 distributions
        Write-Verbose "Shutting down Docker WSL2 distributions..."
        wsl --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        # Compact the virtual disk using diskpart
        Write-Verbose "Compacting virtual disk..."

        $diskpartScript = @"
select vdisk file="$dockerWSLPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@

        $scriptPath = Join-Path $env:TEMP "docker-compact-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

        $output = diskpart /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue

        $afterSize = (Get-Item $dockerWSLPath).Length
        $spaceReclaimed = $beforeSize - $afterSize

        Write-WinOpsLog -Level INFO -Message "Docker WSL2 disk optimized: Reclaimed $([math]::Round($spaceReclaimed / 1GB, 2)) GB"

        return [PSCustomObject]@{
            Success = $true
            BeforeSizeGB = [math]::Round($beforeSize / 1GB, 2)
            AfterSizeGB = [math]::Round($afterSize / 1GB, 2)
            SpaceReclaimedGB = [math]::Round($spaceReclaimed / 1GB, 2)
            Output = $output
        }
    }
    catch {
        Write-WinOpsLog -Level ERROR -Message "Failed to optimize Docker WSL2 disk" -Exception $_

        return [PSCustomObject]@{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-WinOpsDockerInfo {
    <#
    .SYNOPSIS
        Gets Docker installation and resource usage information.

    .DESCRIPTION
        Retrieves Docker status, version, and disk usage details.

    .EXAMPLE
        Get-WinOpsDockerInfo
        # Shows Docker installation status and resource usage
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $dockerStatus = Test-DockerInstalled

    if (-not $dockerStatus.Installed) {
        return [PSCustomObject]@{
            Installed = $false
            Running = $false
            Version = $null
            DiskUsage = $null
        }
    }

    $diskUsage = if ($dockerStatus.Running) {
        Get-DockerDiskUsage
    } else {
        $null
    }

    # Check for Docker WSL2 disk
    $dockerWSLPath = "$env:LOCALAPPDATA\Docker\wsl\data\ext4.vhdx"
    $wslDiskSize = if (Test-Path $dockerWSLPath) {
        (Get-Item $dockerWSLPath).Length
    } else {
        0
    }

    return [PSCustomObject]@{
        Installed = $dockerStatus.Installed
        Running = $dockerStatus.Running
        Version = $dockerStatus.Version
        DiskUsage = $diskUsage
        WSLDiskPath = $dockerWSLPath
        WSLDiskSizeGB = [math]::Round($wslDiskSize / 1GB, 2)
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Clear-WinOpsDockerResources',
    'Optimize-WinOpsDockerWSL',
    'Get-WinOpsDockerInfo'
)
