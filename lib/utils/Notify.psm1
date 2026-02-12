# Notify.psm1 - Win-Ops Notification Module
# Provides Windows Toast notifications with BurntToast support and fallback mechanisms

#region Module Variables

$script:NotifyConfig = @{
    BurntToastAvailable = $false
    Initialized = $false
    ScheduledMode = $false
}

#endregion

#region Private Functions

function Test-BurntToastModule {
    <#
    .SYNOPSIS
    Tests if BurntToast module is available.

    .DESCRIPTION
    Checks if the BurntToast module is installed and can be imported.

    .OUTPUTS
    Boolean indicating BurntToast availability
    #>
    [CmdletBinding()]
    param()

    try {
        $module = Get-Module -Name BurntToast -ListAvailable -ErrorAction SilentlyContinue
        if ($module) {
            Import-Module -Name BurntToast -ErrorAction SilentlyContinue
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Test-UserSession {
    <#
    .SYNOPSIS
    Tests if code is running in an interactive user session.

    .DESCRIPTION
    Determines if the current PowerShell session is interactive or scheduled/service mode.

    .OUTPUTS
    Boolean indicating if running in user session
    #>
    [CmdletBinding()]
    param()

    try {
        # Check if running as a scheduled task or service
        $sessionName = (Get-Process -Id $PID).SessionId

        # Session 0 is typically services/scheduled tasks
        if ($sessionName -eq 0) {
            return $false
        }

        # Check if user is logged in
        $userLoggedIn = [Environment]::UserInteractive

        # Check if console is attached
        $hasConsole = -not [console]::IsOutputRedirected

        return ($userLoggedIn -or $hasConsole)
    }
    catch {
        # If we can't determine, assume scheduled mode (safer)
        return $false
    }
}

function Get-NotificationIcon {
    <#
    .SYNOPSIS
    Gets the appropriate notification icon path based on type.

    .DESCRIPTION
    Returns the system icon path for different notification types.

    .PARAMETER Type
    Notification type (Success, Warning, Error, Info)

    .OUTPUTS
    String path to icon file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type
    )

    # Map to Windows system icons
    $iconMap = @{
        Success = 'imageres.dll,-1024'  # Green checkmark
        Warning = 'imageres.dll,-1026'  # Yellow warning
        Error   = 'imageres.dll,-1027'  # Red X
        Info    = 'imageres.dll,-1023'  # Blue info
    }

    return $iconMap[$Type]
}

function Send-BurntToastNotification {
    <#
    .SYNOPSIS
    Sends notification using BurntToast module.

    .DESCRIPTION
    Uses the BurntToast module to display a Windows Toast notification.

    .PARAMETER Title
    Notification title

    .PARAMETER Message
    Notification message

    .PARAMETER Type
    Notification type

    .OUTPUTS
    Boolean indicating success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type
    )

    try {
        # Determine the app logo based on type
        $appLogo = switch ($Type) {
            'Success' { 'ms-appx:///Assets/success.png' }
            'Warning' { 'ms-appx:///Assets/warning.png' }
            'Error'   { 'ms-appx:///Assets/error.png' }
            'Info'    { 'ms-appx:///Assets/info.png' }
        }

        # Create notification parameters
        $params = @{
            Text = @($Title, $Message)
            AppLogo = $appLogo
            Silent = $false
        }

        # Add sound based on type
        switch ($Type) {
            'Error'   { $params['Sound'] = 'Alarm' }
            'Warning' { $params['Sound'] = 'IM' }
            'Success' { $params['Sound'] = 'Default' }
            'Info'    { $params['Sound'] = 'Default' }
        }

        New-BurntToastNotification @params -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "BurntToast notification failed: $_"
        return $false
    }
}

function Send-FallbackNotification {
    <#
    .SYNOPSIS
    Sends notification using fallback method.

    .DESCRIPTION
    Uses Windows Forms balloon tip or console output as fallback.

    .PARAMETER Title
    Notification title

    .PARAMETER Message
    Notification message

    .PARAMETER Type
    Notification type
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type
    )

    try {
        # Try Windows Forms balloon tip (legacy)
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

        if ([System.Windows.Forms.SystemInformation]::TerminalServerSession -eq $false) {
            $balloon = New-Object System.Windows.Forms.NotifyIcon
            $balloon.Icon = [System.Drawing.SystemIcons]::Information
            $balloon.BalloonTipTitle = $Title
            $balloon.BalloonTipText = $Message

            # Map type to icon
            $iconType = switch ($Type) {
                'Success' { 'Info' }
                'Warning' { 'Warning' }
                'Error'   { 'Error' }
                'Info'    { 'Info' }
            }
            $balloon.BalloonTipIcon = $iconType

            $balloon.Visible = $true
            $balloon.ShowBalloonTip(5000)

            # Cleanup after delay
            Start-Sleep -Seconds 6
            $balloon.Dispose()

            return
        }
    }
    catch {
        # Silently continue to console fallback
    }

    # Final fallback: console output only
    $symbol = switch ($Type) {
        'Success' { '[OK]' }
        'Warning' { '[!]' }
        'Error'   { '[FAIL]' }
        'Info'    { '[i]' }
    }

    Write-Host "$symbol $Title - $Message" -ForegroundColor $(
        switch ($Type) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Info'    { 'Cyan' }
        }
    )
}

#endregion

#region Public Functions

function Initialize-WinOpsNotify {
    <#
    .SYNOPSIS
    Initializes the Win-Ops notification system.

    .DESCRIPTION
    Detects available notification mechanisms and configures the module.

    .PARAMETER Force
    Force re-initialization even if already initialized

    .EXAMPLE
    Initialize-WinOpsNotify

    .EXAMPLE
    Initialize-WinOpsNotify -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:NotifyConfig.Initialized -and -not $Force) {
        return
    }

    # Test for BurntToast availability
    $script:NotifyConfig.BurntToastAvailable = Test-BurntToastModule

    # Detect if running in scheduled mode
    $script:NotifyConfig.ScheduledMode = -not (Test-UserSession)

    $script:NotifyConfig.Initialized = $true

    if ($script:NotifyConfig.BurntToastAvailable) {
        Write-Verbose "Notification system initialized with BurntToast support"
    }
    else {
        Write-Verbose "Notification system initialized with fallback mode (BurntToast not available)"
    }

    if ($script:NotifyConfig.ScheduledMode) {
        Write-Verbose "Running in scheduled mode - notifications enabled"
    }
}

function Send-WinOpsNotification {
    <#
    .SYNOPSIS
    Sends a Windows Toast notification.

    .DESCRIPTION
    Sends a notification using BurntToast if available, otherwise falls back to alternative methods.
    Automatically detects scheduled mode and only sends notifications when appropriate.

    .PARAMETER Title
    Notification title (default: "Win-Ops")

    .PARAMETER Message
    Notification message content

    .PARAMETER Type
    Notification type: Success, Warning, Error, Info (default: Info)

    .PARAMETER Force
    Force notification even in interactive mode (bypasses scheduled mode check)

    .EXAMPLE
    Send-WinOpsNotification -Message "Cleanup completed"

    .EXAMPLE
    Send-WinOpsNotification -Title "Win-Ops" -Message "Cleanup completed" -Type Success

    .EXAMPLE
    Send-WinOpsNotification -Message "Disk space low" -Type Warning

    .EXAMPLE
    Send-WinOpsNotification -Message "Operation failed" -Type Error
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Title = "Win-Ops",

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type = 'Info',

        [Parameter()]
        [switch]$Force
    )

    # Initialize if not already done
    if (-not $script:NotifyConfig.Initialized) {
        Initialize-WinOpsNotify
    }

    # Only send notifications in scheduled mode (or if forced)
    if (-not $script:NotifyConfig.ScheduledMode -and -not $Force) {
        Write-Verbose "Skipping notification (not in scheduled mode): $Title - $Message"
        return
    }

    try {
        # Try BurntToast first if available
        if ($script:NotifyConfig.BurntToastAvailable) {
            $success = Send-BurntToastNotification -Title $Title -Message $Message -Type $Type
            if ($success) {
                Write-Verbose "Notification sent via BurntToast: $Title - $Message"
                return
            }
        }

        # Fallback to alternative methods
        Send-FallbackNotification -Title $Title -Message $Message -Type $Type
        Write-Verbose "Notification sent via fallback: $Title - $Message"
    }
    catch {
        # Silent failure - notifications are non-critical
        Write-Verbose "Notification failed silently: $_"

        # Last resort: try to log if logger is available
        try {
            if (Get-Command -Name Write-WinOpsLog -ErrorAction SilentlyContinue) {
                Write-WinOpsLog -Level INFO -Message "Notification: $Title - $Message" -Context @{
                    Type = $Type
                    NotificationFailed = $true
                }
            }
        }
        catch {
            # Absolute final fallback: do nothing
        }
    }
}

function Test-WinOpsNotificationSupport {
    <#
    .SYNOPSIS
    Tests notification support capabilities.

    .DESCRIPTION
    Returns information about available notification methods and current configuration.

    .OUTPUTS
    Hashtable with notification support details

    .EXAMPLE
    Test-WinOpsNotificationSupport
    #>
    [CmdletBinding()]
    param()

    if (-not $script:NotifyConfig.Initialized) {
        Initialize-WinOpsNotify
    }

    return @{
        Initialized = $script:NotifyConfig.Initialized
        BurntToastAvailable = $script:NotifyConfig.BurntToastAvailable
        ScheduledMode = $script:NotifyConfig.ScheduledMode
        UserSession = Test-UserSession
        RecommendedMethod = if ($script:NotifyConfig.BurntToastAvailable) {
            'BurntToast'
        } else {
            'Fallback'
        }
    }
}

function Install-BurntToast {
    <#
    .SYNOPSIS
    Installs the BurntToast module.

    .DESCRIPTION
    Attempts to install the BurntToast module from PowerShell Gallery.

    .PARAMETER Scope
    Installation scope (CurrentUser or AllUsers, default: CurrentUser)

    .EXAMPLE
    Install-BurntToast

    .EXAMPLE
    Install-BurntToast -Scope AllUsers
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    if ($PSCmdlet.ShouldProcess("BurntToast module", "Install")) {
        try {
            Write-Host "Installing BurntToast module..." -ForegroundColor Cyan
            Install-Module -Name BurntToast -Scope $Scope -Force -AllowClobber -ErrorAction Stop
            Write-Host "BurntToast module installed successfully" -ForegroundColor Green

            # Re-initialize to detect new module
            Initialize-WinOpsNotify -Force

            return $true
        }
        catch {
            Write-Warning "Failed to install BurntToast: $_"
            return $false
        }
    }
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Initialize-WinOpsNotify',
    'Send-WinOpsNotification',
    'Test-WinOpsNotificationSupport',
    'Install-BurntToast'
)

#endregion
