@{

# Script module or binary module file associated with this manifest.
# RootModule = ''

# Version number of this module.
ModuleVersion = '1.5.0.0'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '15fa7a13-478e-4111-bba6-e9e3e6b6cd01'

# Author of this module
Author = 'Jeff Reed'

# Company or vendor of this module
CompanyName = 'Jeff Reed'

# Copyright statement for this module
Copyright = '(c) 2018 Jeff Reed All rights reserved.'

# Description of the functionality provided by this module
Description = 'Functions shared with the family of scripts in the ARMRunSchedule solution.'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0'

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
CLRVersion = '2.0'

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @(    'AzureRm.Compute',
                        'AzureRm.Profile',
                        'AzureRM.Resources'
                        )

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @('ARMRunSchedule.psm1')

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(  'Connect-AzureRM',
                        'Select-Subscription', 
                        'Find-Resources',
                        'Wait-BackgroundJobs',
                        'Set-Tag',
                        'Get-ARMRunSchedule',
                        'Set-ARMRunSchedule',
                        'Remove-ARMRunSchedule',
                        'Set-ResourceState'
                        )

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

}

