#Requires -Version 5.1
# Pester-free check: Remove-WinOpsExpiredTrash purges by move-to-trash time only.
# Runs in a temp LOCALAPPDATA; never touches the real trash.
#   powershell -NoProfile -File tests\Test-TrashPurge.ps1
#   pwsh -NoProfile -File tests\Test-TrashPurge.ps1

$ErrorActionPreference = 'Stop'
$realLocalAppData = $env:LOCALAPPDATA
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "WinOpsTrashPurge_$([guid]::NewGuid().ToString('N'))"
$env:LOCALAPPDATA = $tempRoot
$failures = 0

function Assert($Condition, $Message) {
    if ($Condition) { Write-Host "PASS $Message" -ForegroundColor Green }
    else { Write-Host "FAIL $Message" -ForegroundColor Red; $script:failures++ }
}

try {
    Import-Module (Join-Path $PSScriptRoot '..\lib\core\Trash.psm1') -Force
    $trash = Join-Path $tempRoot 'win-ops\trash'
    if ($trash -eq (Join-Path $realLocalAppData 'win-ops\trash')) { throw "Refusing to run against real trash: $trash" }
    New-Item -ItemType Directory -Path $trash -Force | Out-Null

    $old = (Get-Date).AddYears(-7)
    function New-Entry($Name, [switch]$File) {
        $p = Join-Path $trash $Name
        if ($File) { Set-Content -LiteralPath $p -Value 'x' }
        else { New-Item -ItemType Directory -Path $p | Out-Null; Set-Content -LiteralPath (Join-Path $p 'f.txt') -Value 'x' }
        return $p
    }

    # Moved long ago, but the item itself looks brand new.
    $expiredDir = New-Entry "aaa-Programs"
    $expiredFile = New-Entry "bbb-file[1].tmp" -File
    # Moved 1 hour ago, but the item keeps 2019-era timestamps.
    $freshDir = New-Entry "ccc-DiagOutputDir"
    (Get-Item -LiteralPath $freshDir).CreationTime = $old
    (Get-Item -LiteralPath $freshDir).LastWriteTime = $old
    # On disk with no index record and old timestamps.
    $unindexed = New-Entry "ddd-wsl-crashes"
    (Get-Item -LiteralPath $unindexed).LastWriteTime = $old

    $utc = [DateTimeOffset]::UtcNow
    @{ items = @{
        aaa = @{ original_path = 'C:\x\Programs'; trash_path = $expiredDir; deleted_at = $utc.AddHours(-73).ToString('o'); size = 1; module = 'Test' }
        bbb = @{ original_path = 'C:\x\file[1].tmp'; trash_path = $expiredFile; deleted_at = $utc.AddHours(-500).ToString('o'); size = 1; module = 'Test' }
        ccc = @{ original_path = 'C:\x\DiagOutputDir'; trash_path = $freshDir; deleted_at = $utc.AddHours(-1).ToString('o'); size = 1; module = 'Test' }
    } } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $trash '.index.json') -Encoding UTF8

    # Real move: must stamp deleted_at at move time even though the source is old.
    $src = Join-Path $tempRoot 'src\old-cache'
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    (Get-Item $src).CreationTime = $old
    $moved = Move-WinOpsToTrash -Path $src -Module 'Test'

    $result = Remove-WinOpsExpiredTrash -RetentionHours 72 -Confirm:$false

    Assert (-not (Test-Path -LiteralPath $expiredDir)) 'dir moved 73h ago is purged'
    Assert (-not (Test-Path -LiteralPath $expiredFile)) 'file with wildcard chars moved 500h ago is purged'
    Assert (Test-Path -LiteralPath $freshDir) 'dir moved 1h ago with 7-year-old timestamps is kept'
    Assert (Test-Path -LiteralPath $unindexed) 'unindexed entry is kept on first sight'
    Assert (Test-Path -LiteralPath $moved.TrashPath) 'freshly moved item is kept'
    Assert ($result.RemovedCount -eq 2) "RemovedCount is 2 (got $($result.RemovedCount))"
    Assert ($result.AdoptedCount -eq 1) "AdoptedCount is 1 (got $($result.AdoptedCount))"

    $index = Get-Content (Join-Path $trash '.index.json') -Raw | ConvertFrom-Json
    $records = @($index.items.PSObject.Properties | ForEach-Object { $_.Value })
    Assert ($records.Count -eq 3) "index keeps 3 records (got $($records.Count))"
    Assert (@($records | Where-Object { $_.trash_path -eq $unindexed }).Count -eq 1) 'unindexed entry now has an index record'

    # Second pass with 0h retention purges everything that is left.
    $result = Remove-WinOpsExpiredTrash -RetentionHours 0 -Confirm:$false
    Assert ($result.RemovedCount -eq 3) "0h retention removes the remaining 3 (got $($result.RemovedCount))"
}
finally {
    $env:LOCALAPPDATA = $realLocalAppData
    Remove-Module Trash -Force -ErrorAction SilentlyContinue
    if ($tempRoot -like "$([IO.Path]::GetTempPath())*" -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All trash purge checks passed' -ForegroundColor Green
