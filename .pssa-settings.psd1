@{
    # Only report Error and Warning severity
    Severity = @('Error', 'Warning')

    # Exclude non-critical rules
    ExcludeRules = @(
        'PSUseSingularNouns',  # WinOps is a proper name, not a plural
        'PSUseShouldProcessForStateChangingFunctions'  # Many functions are wrappers
    )

    # Use default PSScriptAnalyzer rules
    IncludeDefaultRules = $true
}
