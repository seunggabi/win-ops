# lib/core/Trash.psm1
# 72-hour recovery system with JSON index and SHA256 hash keys

using namespace System.IO
using namespace System.Security.Cryptography

# Module-level variables
$script:TrashRoot = Join-Path $env:LOCALAPPDATA "win-ops\trash"
$script:IndexFile = Join-Path $script:TrashRoot ".index.json"
$script:RetentionHours = 72
$script:IndexLock = $null

#region Private Functions

function Initialize-TrashDirectory {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:TrashRoot)) {
        New-Item -Path $script:TrashRoot -ItemType Directory -Force | Out-Null
        Write-Verbose "Created trash directory: $script:TrashRoot"
    }

    if (-not (Test-Path $script:IndexFile)) {
        $emptyIndex = @{
            items = @{}
        }
        $emptyIndex | ConvertTo-Json -Depth 10 | Set-Content -Path $script:IndexFile -Encoding UTF8
        Write-Verbose "Created index file: $script:IndexFile"
    }
}

function Get-FileHash256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Use path-based hash for consistency (not content hash)
    # This allows tracking files even if content changes
    $normalizedPath = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $hashInput = "$normalizedPath|$timestamp"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $sha256 = [SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
        return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Lock-IndexFile {
    [CmdletBinding()]
    param()

    $lockFile = "$script:IndexFile.lock"
    $maxWaitSeconds = 30
    $startTime = [DateTime]::UtcNow

    while ((Test-Path $lockFile) -and (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $maxWaitSeconds)) {
        Start-Sleep -Milliseconds 100
    }

    if (Test-Path $lockFile) {
        # Check if lock is stale (older than 5 minutes)
        $lockAge = (Get-Item $lockFile).LastWriteTime
        if (([DateTime]::Now - $lockAge).TotalMinutes -gt 5) {
            Remove-Item $lockFile -Force
            Write-Warning "Removed stale lock file"
        }
        else {
            throw "Index file is locked after $maxWaitSeconds seconds"
        }
    }

    New-Item -Path $lockFile -ItemType File -Force | Out-Null
    $script:IndexLock = $lockFile
}

function Unlock-IndexFile {
    [CmdletBinding()]
    param()

    if ($script:IndexLock -and (Test-Path $script:IndexLock)) {
        Remove-Item $script:IndexLock -Force -ErrorAction SilentlyContinue
        $script:IndexLock = $null
    }
}

function Read-TrashIndex {
    [CmdletBinding()]
    param()

    Initialize-TrashDirectory

    try {
        $content = Get-Content -Path $script:IndexFile -Raw -Encoding UTF8 -ErrorAction Stop
        $index = $content | ConvertFrom-Json -AsHashtable

        if (-not $index.ContainsKey('items')) {
            $index['items'] = @{}
        }

        return $index
    }
    catch {
        Write-Warning "Failed to read index file: $_. Creating new index."
        return @{ items = @{} }
    }
}

function Write-TrashIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Index
    )

    try {
        $json = $Index | ConvertTo-Json -Depth 10 -Compress:$false
        Set-Content -Path $script:IndexFile -Value $json -Encoding UTF8 -Force
    }
    catch {
        throw "Failed to write index file: $_"
    }
}

function Get-ExpiredTrashItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Index
    )

    $expirationTime = [DateTimeOffset]::UtcNow.AddHours(-$script:RetentionHours)
    $expired = @()

    foreach ($hash in $Index.items.Keys) {
        $item = $Index.items[$hash]
        $deletedAt = [DateTimeOffset]::Parse($item.deleted_at)

        if ($deletedAt -lt $expirationTime) {
            $expired += @{
                hash = $hash
                item = $item
            }
        }
    }

    return $expired
}

#endregion

#region Public Functions

function Move-WinOpsToTrash {
    <#
    .SYNOPSIS
    Moves a file or directory to the trash with 72-hour recovery.

    .DESCRIPTION
    Moves items to the trash directory with metadata tracking for recovery.
    Uses SHA256 hash for unique identification and collision handling.

    .PARAMETER Path
    Path to the file or directory to trash.

    .PARAMETER Module
    Optional module name that initiated the trash operation.

    .EXAMPLE
    Move-WinOpsToTrash -Path "C:\temp\old-cache" -Module "CacheCleanup"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,

        [Parameter()]
        [string]$Module = "Manual"
    )

    begin {
        Initialize-TrashDirectory
    }

    process {
        if (-not (Test-Path $Path)) {
            Write-Error "Path not found: $Path"
            return
        }

        $item = Get-Item $Path
        $hash = Get-FileHash256 -Path $item.FullName

        try {
            Lock-IndexFile
            $index = Read-TrashIndex

            # Generate unique trash path
            $trashName = "$hash-$($item.Name)"
            $trashPath = Join-Path $script:TrashRoot $trashName

            # Handle collision (rare but possible)
            $counter = 1
            while (Test-Path $trashPath) {
                $trashName = "$hash-$counter-$($item.Name)"
                $trashPath = Join-Path $script:TrashRoot $trashName
                $counter++
            }

            if ($PSCmdlet.ShouldProcess($item.FullName, "Move to trash")) {
                # Calculate size
                $size = if ($item.PSIsContainer) {
                    (Get-ChildItem -Path $item.FullName -Recurse -File |
                        Measure-Object -Property Length -Sum).Sum
                } else {
                    $item.Length
                }

                # Move to trash
                Move-Item -Path $item.FullName -Destination $trashPath -Force

                # Update index
                $index.items[$hash] = @{
                    original_path = $item.FullName
                    trash_path = $trashPath
                    deleted_at = [DateTimeOffset]::UtcNow.ToString("o")
                    size = if ($size) { $size } else { 0 }
                    module = $Module
                }

                Write-TrashIndex -Index $index

                Write-Verbose "Moved to trash: $($item.FullName) -> $trashPath (hash: $hash)"

                return [PSCustomObject]@{
                    Hash = $hash
                    OriginalPath = $item.FullName
                    TrashPath = $trashPath
                    Size = $size
                }
            }
        }
        catch {
            Write-Error "Failed to move to trash: $_"
        }
        finally {
            Unlock-IndexFile
        }
    }
}

function Remove-WinOpsExpiredTrash {
    <#
    .SYNOPSIS
    Permanently deletes trash items older than 72 hours.

    .DESCRIPTION
    Removes expired items from trash and updates the index.

    .EXAMPLE
    Remove-WinOpsExpiredTrash
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Initialize-TrashDirectory

    try {
        Lock-IndexFile
        $index = Read-TrashIndex
        $expired = Get-ExpiredTrashItems -Index $index

        $totalSize = 0
        $count = 0

        foreach ($entry in $expired) {
            $hash = $entry.hash
            $item = $entry.item

            if ($PSCmdlet.ShouldProcess($item.trash_path, "Permanently delete")) {
                if (Test-Path $item.trash_path) {
                    Remove-Item -Path $item.trash_path -Recurse -Force
                    $totalSize += $item.size
                    $count++
                }

                $index.items.Remove($hash)
            }
        }

        Write-TrashIndex -Index $index

        Write-Verbose "Removed $count expired items ($([math]::Round($totalSize / 1MB, 2)) MB)"

        return [PSCustomObject]@{
            RemovedCount = $count
            ReclaimedBytes = $totalSize
            ReclaimedMB = [math]::Round($totalSize / 1MB, 2)
        }
    }
    catch {
        Write-Error "Failed to remove expired trash: $_"
    }
    finally {
        Unlock-IndexFile
    }
}

function Restore-WinOpsFromTrash {
    <#
    .SYNOPSIS
    Restores a file or directory from trash to its original location.

    .DESCRIPTION
    Restores items using the hash key or original path.
    Handles conflicts if the original location is occupied.

    .PARAMETER Hash
    SHA256 hash of the trashed item.

    .PARAMETER OriginalPath
    Original path of the trashed item (alternative to Hash).

    .PARAMETER Force
    Overwrite existing file at original location.

    .EXAMPLE
    Restore-WinOpsFromTrash -Hash "abc123..."

    .EXAMPLE
    Restore-WinOpsFromTrash -OriginalPath "C:\temp\file.txt"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByHash')]
        [string]$Hash,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$OriginalPath,

        [Parameter()]
        [switch]$Force
    )

    Initialize-TrashDirectory

    try {
        Lock-IndexFile
        $index = Read-TrashIndex

        # Find item by hash or path
        $targetHash = $null
        $targetItem = $null

        if ($PSCmdlet.ParameterSetName -eq 'ByHash') {
            if ($index.items.ContainsKey($Hash)) {
                $targetHash = $Hash
                $targetItem = $index.items[$Hash]
            }
        }
        else {
            $normalizedPath = [System.IO.Path]::GetFullPath($OriginalPath).ToLowerInvariant()
            foreach ($h in $index.items.Keys) {
                $item = $index.items[$h]
                $itemPath = [System.IO.Path]::GetFullPath($item.original_path).ToLowerInvariant()
                if ($itemPath -eq $normalizedPath) {
                    $targetHash = $h
                    $targetItem = $item
                    break
                }
            }
        }

        if (-not $targetItem) {
            Write-Error "Item not found in trash"
            return
        }

        if (-not (Test-Path $targetItem.trash_path)) {
            Write-Error "Trash file not found: $($targetItem.trash_path)"
            $index.items.Remove($targetHash)
            Write-TrashIndex -Index $index
            return
        }

        $originalPath = $targetItem.original_path

        # Handle conflict
        if ((Test-Path $originalPath) -and -not $Force) {
            Write-Error "Original location is occupied: $originalPath. Use -Force to overwrite."
            return
        }

        if ($PSCmdlet.ShouldProcess($originalPath, "Restore from trash")) {
            # Ensure parent directory exists
            $parentDir = Split-Path $originalPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            # Remove existing if Force
            if ((Test-Path $originalPath) -and $Force) {
                Remove-Item -Path $originalPath -Recurse -Force
            }

            # Restore
            Move-Item -Path $targetItem.trash_path -Destination $originalPath -Force

            # Update index
            $index.items.Remove($targetHash)
            Write-TrashIndex -Index $index

            Write-Verbose "Restored: $originalPath"

            return [PSCustomObject]@{
                Hash = $targetHash
                RestoredPath = $originalPath
                Size = $targetItem.size
            }
        }
    }
    catch {
        Write-Error "Failed to restore from trash: $_"
    }
    finally {
        Unlock-IndexFile
    }
}

function Get-WinOpsTrashList {
    <#
    .SYNOPSIS
    Lists all items currently in trash.

    .DESCRIPTION
    Returns information about all trashed items including age and expiration.

    .PARAMETER IncludeExpired
    Include items that have expired but not yet been cleaned.

    .EXAMPLE
    Get-WinOpsTrashList | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeExpired
    )

    Initialize-TrashDirectory

    try {
        Lock-IndexFile
        $index = Read-TrashIndex
        $now = [DateTimeOffset]::UtcNow
        $expirationTime = $now.AddHours(-$script:RetentionHours)

        $results = foreach ($hash in $index.items.Keys) {
            $item = $index.items[$hash]
            $deletedAt = [DateTimeOffset]::Parse($item.deleted_at)
            $age = $now - $deletedAt
            $expiresIn = $deletedAt.AddHours($script:RetentionHours) - $now
            $isExpired = $deletedAt -lt $expirationTime

            if ($isExpired -and -not $IncludeExpired) {
                continue
            }

            [PSCustomObject]@{
                Hash = $hash
                OriginalPath = $item.original_path
                TrashPath = $item.trash_path
                DeletedAt = $deletedAt.LocalDateTime
                AgeHours = [math]::Round($age.TotalHours, 1)
                ExpiresInHours = [math]::Round($expiresIn.TotalHours, 1)
                SizeMB = [math]::Round($item.size / 1MB, 2)
                Module = $item.module
                IsExpired = $isExpired
                Exists = (Test-Path $item.trash_path)
            }
        }

        return $results | Sort-Object DeletedAt -Descending
    }
    catch {
        Write-Error "Failed to list trash: $_"
    }
    finally {
        Unlock-IndexFile
    }
}

function Clear-WinOpsTrash {
    <#
    .SYNOPSIS
    Empties the entire trash directory.

    .DESCRIPTION
    Permanently deletes all items in trash regardless of age.
    Requires confirmation unless -Force is specified.

    .PARAMETER Force
    Skip confirmation prompt.

    .EXAMPLE
    Clear-WinOpsTrash -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [switch]$Force
    )

    Initialize-TrashDirectory

    try {
        Lock-IndexFile
        $index = Read-TrashIndex

        $totalSize = ($index.items.Values | Measure-Object -Property size -Sum).Sum
        $count = $index.items.Count

        if ($Force -or $PSCmdlet.ShouldProcess("$count items ($([math]::Round($totalSize / 1MB, 2)) MB)", "Permanently delete all trash")) {
            foreach ($hash in $index.items.Keys) {
                $item = $index.items[$hash]
                if (Test-Path $item.trash_path) {
                    Remove-Item -Path $item.trash_path -Recurse -Force
                }
            }

            # Reset index
            $index.items = @{}
            Write-TrashIndex -Index $index

            Write-Verbose "Cleared trash: $count items ($([math]::Round($totalSize / 1MB, 2)) MB)"

            return [PSCustomObject]@{
                RemovedCount = $count
                ReclaimedBytes = $totalSize
                ReclaimedMB = [math]::Round($totalSize / 1MB, 2)
            }
        }
    }
    catch {
        Write-Error "Failed to clear trash: $_"
    }
    finally {
        Unlock-IndexFile
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Move-WinOpsToTrash',
    'Remove-WinOpsExpiredTrash',
    'Restore-WinOpsFromTrash',
    'Get-WinOpsTrashList',
    'Clear-WinOpsTrash'
)
