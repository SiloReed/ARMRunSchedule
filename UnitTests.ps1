<#
.SYNOPSIS
    Use this script to unit test cmdlets in the ARMRunSchedule module
.DESCRIPTION
    Use this script to unit test cmdlets in the ARMRunSchedule module. 
    This script accepts parameters to sign into AzureRM as the 
    interactive user, or optionally use certificate based sign on.
.PARAMETER SubscriptionId
    The SubscriptionId of the AzureRM account
.PARAMETER Tenant
    The Tenant Id of the AzureRM account
.PARAMETER ApplicationId
    The Application Id of the Azure AD Service Principal
.PARAMETER CertificateThumbprint
    The certificate thumbprint of the locally installed certificate associated with the Azure AD Service Principal
.EXAMPLE
    .\UnitTest.ps1
.EXAMPLE
    .\UnitTest.ps1 -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f"
.EXAMPLE
    .\UnitTest.ps1 -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -Tenant "335836de-42ef-43a2-b145-348c2ee9ca5b" -ApplicationId "2b95ca40-9619-410a-86af-a2f30ee63ab9" -CertificateThumbprint "58E3D3BE1C426317D2A01005BF5D49B053745EBE"
.NOTES
    There is a bug in the AzureRm.Profile ver 3.0.0 where interactive credentials don't work with 
    the Save-AzureRmContext and Import-AzureRmContext cmdlets. As a workaround use certificate sign in.
    See: https://github.com/Azure/azure-powershell/issues/3954
#>
[CmdletBinding(
    DefaultParameterSetName="Interactive"
)]

Param
(
    [Parameter(
        Position=0,
        ParameterSetName='Interactive',
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The SubscriptionId of the AzureRM account."
    )]
    [Parameter(
        Position=1,        
        ParameterSetName='Certificate',
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The SubscriptionId of the AzureRM account."
    )]
    [string] $SubscriptionId,

    [Parameter(
        Position=0,        
        ParameterSetName='Certificate',
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The Tenant Id of the AzureRM account."
    )]
    [string] $Tenant,

    [Parameter(
        Position=2,        
        ParameterSetName='Certificate',
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The Azure Application ID of the Azure AD Service Principal."
    )]
    [string] $ApplicationId,

    [Parameter(
        Position=3,        
        ParameterSetName='Certificate',
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The certificate thumbprint of the locally installed certificate associated with the Azure AD Service Principal."
    )]
    [string] $CertificateThumbprint

)
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir "ARMRunSchedule.psm1")
if ($PSCmdlet.ParameterSetName -eq "Interactive") {
    Connect-AzureRM
}
else {
    $paramsCred = @{
        ServicePrincipal = $True
        Tenant = $Tenant
        SubscriptionId = $SubscriptionId
        ApplicationId = $ApplicationId
        CertificateThumbprint = $CertificateThumbprint
    }

    $AzureRMAccount = Add-AzureRMAccount @paramsCred
}

if (-not ($PSBoundParameters.ContainsKey("SubscriptionId") ) ) {
    Select-Subscription
    $SubscriptionId = (Get-AzureRmContext).Subscription.Id
}

# Create the custom RBAC role "RunSchedule Operator"
# New-AzureRMRoleDefinition -InputFile $(Join-Path $ScriptDir RBACPolicy.json)

$FilterPath = Join-Path $ScriptDir 'RunScheduleFilter.json'

$title = "Choose a command to execute"
$commands = @()

$commands += "Get-ARMRunSchedule -SubscriptionId $SubscriptionId -FilterPath $FilterPath -Verbose"
$commands += "Get-ARMRunSchedule -FilterPath $FilterPath"
$commands += "Get-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu*"
$commands += "Get-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ASTest -Name azrastst01"
$commands += "Get-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ODSTest -Name 'azrodstst01/AZDWTST01'"
$commands += "Get-ARMRunSchedule -SubscriptionId $SubscriptionId"

$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -FilterPath $FilterPath -Verbose"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu01 -Name ubuntu01 -Verbose -Enabled -RunHours 10 -RunDays 1,2,3,4,5 -StartHourUTC 13 -AutoStart"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu* -Verbose -Enabled -RunHours 13 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu* -Verbose -RunHours 13 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu* -Verbose -Enabled"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu* -Verbose -Enabled:`$false"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ASTest -Name azrastst01 -Verbose -RunHours 1 -RunDays Monday,Wednesday,Friday -StartHourUTC 13 -AutoStart"
$commands += "Set-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ODSTest -Name 'azrodstst01/AZDWTST01' -Verbose -RunHours 1 -RunDays Monday,Wednesday,Friday -StartHourUTC 17 -AutoStart"


$commands += "Remove-ARMRunSchedule -SubscriptionId $SubscriptionId -FilterPath $FilterPath -Verbose"
$commands += "Remove-ARMRunSchedule -FilterPath $FilterPath -Verbose"
$commands += "Remove-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu* -Name ubuntu* -Verbose"
$commands += "Remove-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ubuntu01 -Name ubuntu01 -Verbose"
$commands += "Remove-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ASTest -Name azrastst01 -Verbose"
$commands += "Remove-ARMRunSchedule -SubscriptionId $SubscriptionId -ResourceGroupName rg-ODSTest -Name 'azrodstst01/AZDWTST01' -Verbose"

$c = $commands | Out-GridView -Title $title -OutputMode Single
Write-Output "Executing: $c"
Invoke-Expression $c

Wait-BackgroundJobs -Verbose

Remove-Module ARMRunSchedule