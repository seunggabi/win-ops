#Requires -Version 7.0

<#
.SYNOPSIS
    Parallel execution module for WinOps cleanup operations.

.DESCRIPTION
    Provides parallel execution capabilities for cleanup modules using PowerShell 7's
    ForEach-Object -Parallel feature with timeout monitoring and statistics collection.

.NOTES
    Requires PowerShell 7.0 or later for -Parallel support.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Executes multiple cleanup modules in parallel.

.DESCRIPTION
    Runs multiple WinOps cleanup modules concurrently using PowerShell 7's parallel
    execution capabilities. Includes timeout monitoring, error handling, and statistics
    collection.

.PARAMETER Modules
    Array of module names to execute in parallel.
    Examples: 'Cache', 'Tmp', 'Log', 'Browser'

.PARAMETER ThrottleLimit
    Maximum number of concurrent module executions.
    Default: 4

.PARAMETER TimeoutSeconds
    Timeout in seconds for each individual module execution.
    Default: 300 (5 minutes)

.PARAMETER ModulePath
    Base path where cleanup modules are located.
    Default: "$PSScriptRoot\..\modules"

.EXAMPLE
    Invoke-WinOpsParallelModules -Modules @('Cache','Tmp','Log')

    Executes Cache, Tmp, and Log cleanup modules in parallel with default settings.

.EXAMPLE
    Invoke-WinOpsParallelModules -Modules @('Cache','Tmp','Log','Browser') -ThrottleLimit 2 -TimeoutSeconds 600

    Executes modules with maximum 2 concurrent operations and 10-minute timeout.

.OUTPUTS
    PSCustomObject with execution statistics including:
    - TotalDurationSeconds: Total elapsed time
    - SuccessCount: Number of successfully completed modules
    - FailureCount: Number of failed modules
    - ModuleResults: Detailed per-module results
#>
function Invoke-WinOpsParallelModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Modules,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]$ThrottleLimit = 4,

        [Parameter(Mandatory = $false)]
        [ValidateRange(30, 3600)]
        [int]$TimeoutSeconds = 300,

        [Parameter(Mandatory = $false)]
        [string]$ModulePath = "$PSScriptRoot\..\modules"
    )

    Write-Verbose "Starting parallel execution of $($Modules.Count) modules with ThrottleLimit=$ThrottleLimit"

    $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    try {
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            throw "PowerShell 7.0 or later is required for parallel execution. Current version: $($PSVersionTable.PSVersion)"
        }

        # Validate module path exists
        if (-not (Test-Path -Path $ModulePath -PathType Container)) {
            throw "Module path does not exist: $ModulePath"
        }

        # Validate all module files exist
        $missingModules = @()
        foreach ($module in $Modules) {
            $modulePath = Join-Path -Path $ModulePath -ChildPath "$module.psm1"
            if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
                $missingModules += $module
            }
        }

        if ($missingModules.Count -gt 0) {
            throw "Missing module files: $($missingModules -join ', ')"
        }

        # Execute modules in parallel
        $Modules | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $moduleName = $_
            $moduleBasePath = $using:ModulePath
            $timeout = $using:TimeoutSeconds
            $resultBag = $using:results

            $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = [PSCustomObject]@{
                ModuleName = $moduleName
                Success = $false
                DurationSeconds = 0
                ItemsCleaned = 0
                SpaceFreedBytes = 0
                ErrorMessage = $null
                TimedOut = $false
            }

            try {
                Write-Progress -Activity "Parallel Cleanup" -Status "Processing: $moduleName" -Id ($moduleName.GetHashCode())

                # Create a runspace to execute with timeout
                $ps = [powershell]::Create()
                $null = $ps.AddScript({
                    param($ModulePath, $ModuleName)

                    $moduleFile = Join-Path -Path $ModulePath -ChildPath "$ModuleName.psm1"
                    Import-Module $moduleFile -Force -ErrorAction Stop

                    # Execute the cleanup function (assuming each module has Invoke-{ModuleName}Cleanup)
                    $functionName = "Invoke-${ModuleName}Cleanup"
                    if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                        & $functionName
                    } else {
                        throw "Function $functionName not found in module $ModuleName"
                    }
                }).AddArgument($moduleBasePath).AddArgument($moduleName)

                # Start async execution
                $asyncResult = $ps.BeginInvoke()

                # Wait with timeout
                $completed = $asyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($timeout))

                if (-not $completed) {
                    # Timeout occurred
                    $ps.Stop()
                    $result.TimedOut = $true
                    $result.ErrorMessage = "Module execution timed out after $timeout seconds"
                } else {
                    # Get results
                    $output = $ps.EndInvoke($asyncResult)

                    if ($ps.HadErrors) {
                        $result.ErrorMessage = ($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                    } else {
                        $result.Success = $true

                        # Extract statistics from output if available
                        if ($output -and $output.Count -gt 0) {
                            $lastOutput = $output[-1]
                            if ($lastOutput.PSObject.Properties['ItemsCleaned']) {
                                $result.ItemsCleaned = $lastOutput.ItemsCleaned
                            }
                            if ($lastOutput.PSObject.Properties['SpaceFreedBytes']) {
                                $result.SpaceFreedBytes = $lastOutput.SpaceFreedBytes
                            }
                        }
                    }
                }

                $ps.Dispose()

            } catch {
                $result.ErrorMessage = $_.Exception.Message
            } finally {
                $moduleStopwatch.Stop()
                $result.DurationSeconds = [Math]::Round($moduleStopwatch.Elapsed.TotalSeconds, 2)
                $resultBag.Add($result)

                Write-Progress -Activity "Parallel Cleanup" -Status "Completed: $moduleName" -Id ($moduleName.GetHashCode()) -Completed
            }
        }

        $totalStopwatch.Stop()

        # Collect and aggregate results
        $allResults = $results.ToArray() | Sort-Object -Property ModuleName
        $successCount = ($allResults | Where-Object { $_.Success }).Count
        $failureCount = $allResults.Count - $successCount
        $totalItemsCleaned = ($allResults | Measure-Object -Property ItemsCleaned -Sum).Sum
        $totalSpaceFreedBytes = ($allResults | Measure-Object -Property SpaceFreedBytes -Sum).Sum
        $totalSpaceFreedMB = [Math]::Round($totalSpaceFreedBytes / 1MB, 2)

        # Display summary
        Write-Host "`n=== Parallel Cleanup Summary ===" -ForegroundColor Cyan
        Write-Host "Total Duration: $([Math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor White
        Write-Host "Modules Executed: $($allResults.Count)" -ForegroundColor White
        Write-Host "Success: $successCount" -ForegroundColor Green
        Write-Host "Failures: $failureCount" -ForegroundColor $(if ($failureCount -gt 0) { 'Red' } else { 'White' })
        Write-Host "Total Items Cleaned: $totalItemsCleaned" -ForegroundColor White
        Write-Host "Total Space Freed: $totalSpaceFreedMB MB" -ForegroundColor White
        Write-Host ""

        # Display per-module results
        Write-Host "Module Results:" -ForegroundColor Cyan
        foreach ($moduleResult in $allResults) {
            $status = if ($moduleResult.Success) {
                "SUCCESS"
            } elseif ($moduleResult.TimedOut) {
                "TIMEOUT"
            } else {
                "FAILED"
            }

            $statusColor = switch ($status) {
                "SUCCESS" { 'Green' }
                "TIMEOUT" { 'Yellow' }
                "FAILED" { 'Red' }
            }

            Write-Host "  [$status] " -ForegroundColor $statusColor -NoNewline
            Write-Host "$($moduleResult.ModuleName) " -NoNewline
            Write-Host "($($moduleResult.DurationSeconds)s, $($moduleResult.ItemsCleaned) items, $([Math]::Round($moduleResult.SpaceFreedBytes / 1MB, 2)) MB)" -ForegroundColor Gray

            if ($moduleResult.ErrorMessage) {
                Write-Host "    Error: $($moduleResult.ErrorMessage)" -ForegroundColor Red
            }
        }

        # Return statistics object
        return [PSCustomObject]@{
            TotalDurationSeconds = [Math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2)
            SuccessCount = $successCount
            FailureCount = $failureCount
            TotalItemsCleaned = $totalItemsCleaned
            TotalSpaceFreedMB = $totalSpaceFreedMB
            ModuleResults = $allResults
        }

    } catch {
        $totalStopwatch.Stop()
        Write-Error "Parallel execution failed: $_"
        throw
    }
}

Export-ModuleMember -Function Invoke-WinOpsParallelModules
