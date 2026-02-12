@{
    # Only report Error severity (ignore all warnings)
    Severity = @('Error')

    # Exclude non-critical rules
    ExcludeRules = @(
        'PSUseSingularNouns',  # WinOps is a proper name, not a plural
        'PSUseShouldProcessForStateChangingFunctions',  # Many functions are wrappers
        'PSAvoidUsingWriteHost'  # CLI scripts need Write-Host for user interaction
    )

    # Use default PSScriptAnalyzer rules
    IncludeDefaultRules = $true
}
