@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'bin/win-ops.ps1'

    # Version number of this module.
    ModuleVersion = '0.7.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = '8f6a9c5d-2e4b-4a7f-9d3e-1c8b5f7a2d4e'

    # Author of this module
    Author = 'Seunggabi'

    # Company or vendor of this module
    CompanyName = 'Unknown'

    # Copyright statement for this module
    Copyright = '(c) 2026 Seunggabi. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Windows Operations Manager - Automated system maintenance and optimization toolkit'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Invoke-WinOps',
        'Get-WinOpsVersion',
        'Get-WinOpsHelp',
        'Start-WinOpsAnalysis',
        'Start-WinOpsCleanup',
        'Get-WinOpsStatus',
        'Get-TrashItems',
        'Restore-TrashItem',
        'Install-WinOps',
        'Uninstall-WinOps',
        'Set-WinOpsSchedule',
        'Remove-WinOpsSchedule'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Windows', 'Operations', 'Maintenance', 'Cleanup', 'Automation', 'System')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/seunggabi/win-ops/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/seunggabi/win-ops'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'win-ops v0.7.0 - Code refactoring, PackageManagerCleanup fix, README rewrite'

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
