#Requires -Version 5.1

<#
.SYNOPSIS
    Task Scheduler integration module for Win-Ops.

.DESCRIPTION
    Provides functions to install, uninstall, and manage Win-Ops scheduled tasks.

.NOTES
    Module: WinOps.Scheduler
    Requires: Administrator privileges for task installation
#>

#region Private Functions

function Test-IsElevated {
    <#
    .SYNOPSIS
    Checks if current session is running with administrator privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinOpsTaskXmlPath {
    <#
    .SYNOPSIS
    Gets the path to the task XML template.
    #>
    [CmdletBinding()]
    param()

    return Join-Path $PSScriptRoot 'WinOpsTask.xml'
}

function Get-WinOpsScheduledScriptPath {
    <#
    .SYNOPSIS
    Gets the path to the scheduled script.
    #>
    [CmdletBinding()]
    param()

    return Join-Path $PSScriptRoot 'Invoke-WinOpsScheduled.ps1'
}

#endregion

#region Public Functions

function Install-WinOpsScheduledTask {
    <#
    .SYNOPSIS
    Installs the Win-Ops scheduled task.

    .DESCRIPTION
    Creates a Windows scheduled task that runs Win-Ops cleanup operations hourly.

    .PARAMETER TaskName
    Name of the scheduled task. Default: "Win-Ops System Cleanup"

    .PARAMETER Interval
    Interval for task execution. Valid values: Hourly, Daily, Weekly. Default: Hourly

    .PARAMETER StartTime
    Time when task should first run. Default: current time + 5 minutes

    .PARAMETER RunAsSystem
    Run task as SYSTEM account (requires admin). Default: current user

    .PARAMETER Force
    Overwrite existing task without confirmation

    .EXAMPLE
    Install-WinOpsScheduledTask
    # Installs task with default hourly schedule

    .EXAMPLE
    Install-WinOpsScheduledTask -Interval Daily -StartTime "02:00"
    # Installs task to run daily at 2 AM

    .EXAMPLE
    Install-WinOpsScheduledTask -RunAsSystem -Force
    # Installs task as SYSTEM, overwriting existing task
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TaskName = "Win-Ops System Cleanup",

        [Parameter()]
        [ValidateSet('Hourly', 'Daily', 'Weekly')]
        [string]$Interval = 'Hourly',

        [Parameter()]
        [string]$StartTime,

        [Parameter()]
        [switch]$RunAsSystem,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-IsElevated)) {
        throw "Administrator privileges required to install scheduled tasks"
    }

    Write-Verbose "Installing Win-Ops scheduled task: $TaskName"

    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        if (-not $Force) {
            throw "Task '$TaskName' already exists. Use -Force to overwrite."
        }

        Write-Verbose "Removing existing task: $TaskName"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Get paths
    $scriptPath = Get-WinOpsScheduledScriptPath
    $workingDir = Split-Path $scriptPath -Parent

    if (-not (Test-Path $scriptPath)) {
        throw "Scheduled script not found: $scriptPath"
    }

    # Determine start time
    if (-not $StartTime) {
        $StartTime = (Get-Date).AddMinutes(5).ToString("yyyy-MM-ddTHH:mm:ss")
    } else {
        # Parse time string
        try {
            $parsedTime = [DateTime]::Parse($StartTime)
            $StartTime = $parsedTime.ToString("yyyy-MM-ddTHH:mm:ss")
        } catch {
            throw "Invalid StartTime format. Use 'HH:mm' or valid DateTime string."
        }
    }

    # Create task action
    $action = New-ScheduledTaskAction `
        -Execute "pwsh.exe" `
        -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -WorkingDirectory $workingDir

    # Create task trigger based on interval
    switch ($Interval) {
        'Hourly' {
            $trigger = New-ScheduledTaskTrigger -Once -At $StartTime -RepetitionInterval (New-TimeSpan -Hours 1)
        }
        'Daily' {
            $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
        }
        'Weekly' {
            $trigger = New-ScheduledTaskTrigger -Weekly -At $StartTime -DaysOfWeek Monday, Wednesday, Friday
        }
    }

    # Create task settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries:$false `
        -DontStopIfGoingOnBatteries:$false `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -MultipleInstances IgnoreNew `
        -Priority 7

    # Create task principal
    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    }

    # Register task
    if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task")) {
        try {
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Description "Automated Windows cleanup and optimization task. Runs $Interval to maintain system performance and free up disk space." `
                -ErrorAction Stop | Out-Null

            Write-Host "Successfully installed scheduled task: $TaskName" -ForegroundColor Green
            Write-Host "  Interval: $Interval" -ForegroundColor Gray
            Write-Host "  Start Time: $StartTime" -ForegroundColor Gray
            Write-Host "  Script: $scriptPath" -ForegroundColor Gray
            Write-Host "  Run As: $(if ($RunAsSystem) { 'SYSTEM' } else { $env:USERNAME })" -ForegroundColor Gray

            return $true
        } catch {
            Write-Error "Failed to register scheduled task: $_"
            throw
        }
    }
}

function Uninstall-WinOpsScheduledTask {
    <#
    .SYNOPSIS
    Uninstalls the Win-Ops scheduled task.

    .DESCRIPTION
    Removes the Win-Ops scheduled task from Windows Task Scheduler.

    .PARAMETER TaskName
    Name of the scheduled task to remove. Default: "Win-Ops System Cleanup"

    .PARAMETER Force
    Skip confirmation prompt

    .EXAMPLE
    Uninstall-WinOpsScheduledTask
    # Removes the default Win-Ops task

    .EXAMPLE
    Uninstall-WinOpsScheduledTask -Force
    # Removes task without confirmation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$TaskName = "Win-Ops System Cleanup",

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-IsElevated)) {
        throw "Administrator privileges required to uninstall scheduled tasks"
    }

    Write-Verbose "Uninstalling Win-Ops scheduled task: $TaskName"

    # Check if task exists
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        Write-Warning "Task '$TaskName' not found"
        return $false
    }

    if ($Force -or $PSCmdlet.ShouldProcess($TaskName, "Unregister scheduled task")) {
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "Successfully uninstalled scheduled task: $TaskName" -ForegroundColor Green
            return $true
        } catch {
            Write-Error "Failed to unregister scheduled task: $_"
            throw
        }
    }

    return $false
}

function Test-WinOpsScheduledTask {
    <#
    .SYNOPSIS
    Tests if Win-Ops scheduled task is installed.

    .DESCRIPTION
    Checks if the Win-Ops scheduled task exists and returns its status.

    .PARAMETER TaskName
    Name of the scheduled task. Default: "Win-Ops System Cleanup"

    .OUTPUTS
    PSCustomObject with task status information

    .EXAMPLE
    Test-WinOpsScheduledTask
    # Returns status of default Win-Ops task

    .EXAMPLE
    if (Test-WinOpsScheduledTask).Installed) { "Task is installed" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$TaskName = "Win-Ops System Cleanup"
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        return [PSCustomObject]@{
            TaskName = $TaskName
            Installed = $false
            Enabled = $false
            State = 'NotFound'
            LastRunTime = $null
            NextRunTime = $null
            LastResult = $null
        }
    }

    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        TaskName = $TaskName
        Installed = $true
        Enabled = $task.State -eq 'Ready'
        State = $task.State
        LastRunTime = $taskInfo.LastRunTime
        NextRunTime = $taskInfo.NextRunTime
        LastResult = $taskInfo.LastTaskResult
        TaskPath = $task.TaskPath
        Actions = $task.Actions
        Triggers = $task.Triggers
    }
}

function Start-WinOpsScheduledTask {
    <#
    .SYNOPSIS
    Manually runs the Win-Ops scheduled task.

    .DESCRIPTION
    Triggers an immediate execution of the Win-Ops scheduled task.

    .PARAMETER TaskName
    Name of the scheduled task. Default: "Win-Ops System Cleanup"

    .PARAMETER Wait
    Wait for task completion

    .EXAMPLE
    Start-WinOpsScheduledTask
    # Runs the task immediately

    .EXAMPLE
    Start-WinOpsScheduledTask -Wait
    # Runs the task and waits for completion
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TaskName = "Win-Ops System Cleanup",

        [Parameter()]
        [switch]$Wait
    )

    Write-Verbose "Starting scheduled task: $TaskName"

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        throw "Task '$TaskName' not found. Install it first using Install-WinOpsScheduledTask."
    }

    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-Host "Started scheduled task: $TaskName" -ForegroundColor Green

        if ($Wait) {
            Write-Host "Waiting for task completion..." -ForegroundColor Gray

            do {
                Start-Sleep -Seconds 2
                $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
            } while ($taskInfo.LastTaskResult -eq 267009) # 267009 = Task is currently running

            $lastResult = $taskInfo.LastTaskResult
            if ($lastResult -eq 0) {
                Write-Host "Task completed successfully" -ForegroundColor Green
            } else {
                Write-Warning "Task completed with result code: $lastResult"
            }
        }

        return $true
    } catch {
        Write-Error "Failed to start scheduled task: $_"
        throw
    }
}

function Get-WinOpsScheduledTaskLog {
    <#
    .SYNOPSIS
    Gets the log output from the scheduled task.

    .DESCRIPTION
    Retrieves the log file generated by Win-Ops scheduled executions.

    .PARAMETER Lines
    Number of lines to retrieve (from end of file). Default: 50

    .PARAMETER Path
    Custom log file path. Default: auto-detected

    .EXAMPLE
    Get-WinOpsScheduledTaskLog
    # Shows last 50 lines of scheduled task log

    .EXAMPLE
    Get-WinOpsScheduledTaskLog -Lines 100
    # Shows last 100 lines
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Lines = 50,

        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $Path = Join-Path $env:LOCALAPPDATA 'win-ops\logs\scheduled.log'
    }

    if (-not (Test-Path $Path)) {
        Write-Warning "Log file not found: $Path"
        return
    }

    try {
        Get-Content $Path -Tail $Lines | Write-Output
    } catch {
        Write-Error "Failed to read log file: $_"
        throw
    }
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Install-WinOpsScheduledTask',
    'Uninstall-WinOpsScheduledTask',
    'Test-WinOpsScheduledTask',
    'Start-WinOpsScheduledTask',
    'Get-WinOpsScheduledTaskLog'
)

#endregion
