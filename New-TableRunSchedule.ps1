<#  
.SYNOPSIS
    Creates an Azure Storage Table
.DESCRIPTION
    Creates an Azure Storage Table
.PARAMETER SubscriptionId
    The Azure subscription ID that will contain the Storage Table.
    If no value is provided, default subscription is used.
.PARAMETER TableRGName
    The name of the resource group that will contain the Storage Account for the Storage Table.
    The resource group must exist.
.PARAMETER TableSAName
    The name of the storage account that will contain the Storage Table.
    The storage account must exist.
.PARAMETER TableName
    The name of the Storage Table to be created.
.PARAMETER ApplicationId
    The ApplicationId of the Service Principal that will be granted Contributor role to the Storage Account.
    If no value is provided, the permissions of the Storage Account will not be altered.
.EXAMPLE
    New-TableRunSchedule.ps1 -SubscriptionId "########-####-####-####-############" -TableRGName "rg-runschedule-itea" -TableSAName farunschedulecta598 -TableName RunScheduleLog -ApplicationId "########-####-####-####-############"
.OUTPUTS
    [string] New-AzureStorageTableSASToken FullUri output
#>

#Requires -Version 5
#Requires -modules AzureRM.Profile, AzureRM.Resources, ARMRunSchedule

[CmdletBinding()]
Param (
    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The Azure subscription ID that will contain the Storage Table."
    )]
    [String] $SubscriptionId,    

    [Parameter(
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The name of the resource group that will contain the Storage Account for the Storage Table."
    )]
    [string] $TableRGName,

    [Parameter(
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The name of the storage account that will contain the Storage Table."
    )]
    [string] $TableSAName,

    [Parameter(
        Mandatory=$true,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The name of the Storage Table to be created."
    )]
    [string] $TableName,

    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$true,
        HelpMessage="The ApplicationId of the Service Principal that will be granted Contributor role to the Storage Account."
    )]
    [string] $ApplicationId
)

Connect-AzureRM
if (-not ($PSBoundParameters.ContainsKey("SubscriptionId") ) ) {
    Select-Subscription
}

$TenantId = (Get-AzureRmContext).Tenant.Id
$SubId = (Get-AzureRmContext).Subscription.Id 
$saContext = (Get-AzureRmStorageAccount -ResourceGroupName $TableRGName -Name $TableSAName).Context
$ctx = Set-AzureRmCurrentStorageAccount -context $saContext

$table = Get-AzureStorageTable -Name $TableName -Context $saContext -ErrorAction SilentlyContinue
if ($table) {
    Write-Debug ("{0} Table exists" -f $TableName)
}
else {
    $table = New-AzureStorageTable -Name $TableName -Context $saContext
}

# Assign 'Storage Account Contributor' to the service principal
$app = Get-AzureRmADApplication -ApplicationId $ApplicationId
$sp = Get-AzureRmADServicePrincipal -SearchString $app.DisplayName
New-AzureRmRoleAssignment -ObjectId $sp.Id -RoleDefinitionName 'Storage Account Contributor' -ResourceName $TableSAName -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceGroupName $TableRGName

