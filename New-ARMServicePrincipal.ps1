<#
.SYNOPSIS
    Displays a gridview of available Azure subscription in order for the user to select a subscription
    to act on.
.DESCRIPTION
    Displays a gridview of available Azure subscription in order for the user to select a subscription
    to act on.
.PARAMETER ResourceGroup
    Use to set scope to resource group. If no value is provided, scope is set to subscription.
.PARAMETER SubscriptionId
    Use to set subscription. If no value is provided, default subscription is used.
.PARAMETER DisplayName
    The DisplayName for the service principal. The Subscription Id will be appended to the DisplayName
    to form the DisplayName of the Azure AD Application and Service Principal
.PARAMETER RoleDefinitionName 
    The RBAC role definition desired. Defaults to 'Virtual Machine Contributor'.
.PARAMETER Password
    The password to use to protect the .pfx file that will be exported by this script into
    the user's home directory. 
.EXAMPLE
    .\New-ARMServicePrincipal.ps1
.EXAMPLE
    .\New-ARMServicePrincipal.ps1 -SubscriptionId 'f1bb2e3d-fbec-4dd8-9e46-fb998a30246f' -DisplayName 'ARMRunSchedule' -RoleDefinitionName 'Virtual Machine Contributor' 
.NOTES
    Based on: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal
#>

#Requires -Version 5.0
#Requires -modules AzureRM.Profile, AzureRM.Resources, ARMRunSchedule

[CmdletBinding()]
Param (
    # Use to set scope to resource group. If no value is provided, scope is set to subscription.
    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The Azure Resource Group that will be the scope of the Service Principal."
    )]
    [String] $ResourceGroup,

    # Use to set subscription. If no value is provided, default subscription is used. 
    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The Azure subscription ID that will be the scope of the Service Principal."
    )]
    [String] $SubscriptionId,

    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The DisplayName for the service principal."
    )]
    [String] $DisplayName='ARMRunSchedule',

    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The RBAC role definition desired."
    )]
    [String] $RoleDefinitionName='RunSchedule Operator',

    [Parameter(
        Mandatory=$false,
        ValueFromPipelineByPropertyName=$false,
        HelpMessage="The password for the exported self signed certificate."
    )]
    [String] $Password

)

Connect-AzureRM
if (-not ($PSBoundParameters.ContainsKey("SubscriptionId") ) ) {
    Select-Subscription
}

$TenantId = (Get-AzureRmContext).Tenant.Id
$SubId = (Get-AzureRmContext).Subscription.Id 

# Define some variables used for creating and exporting the new self-signed certificate
$AppDisplayName = $DisplayName + "-" + $SubId
$CertPathPfx = Join-Path ~ ($AppDisplayName + ".pfx")
$CertPathCer = Join-Path ~ ($AppDisplayName + ".cer")
$CertStoreLocation = 'Cert:\CurrentUser\My'

if (-not ($PSBoundParameters.ContainsKey("Password") ) ) {
    $cred = Get-Credential -UserName $AppDisplayName -Message "Please enter a password to protect the exported .pfx file"
    $CertPassword = $cred.Password
} else {
    $CertPassword = ConvertTo-SecureString $Password -AsPlainText -Force
}

# Create a hashtable of parameters for the New-SelfSignedCertificate cmdlet
$params = @{
    Subject = "CN=" + $AppDisplayName
    CertStoreLocation = $CertStoreLocation
    KeySpec = "KeyExchange"
}
# Create the new self-signed certificate in this user's certificate store
$Cert = New-SelfSignedCertificate @params
$keyValue = [System.Convert]::ToBase64String($Cert.GetRawCertData())

# Export the certificate with the private key to a .pfx file
Export-PfxCertificate -Cert (Join-Path $CertStoreLocation $Cert.Thumbprint) -FilePath $CertPathPfx -Password $CertPassword -Force | Write-Verbose
    
if ($ResourceGroup -eq "") {
    $Scope = "/subscriptions/" + $SubId
}
else {
    $Scope = (Get-AzureRmResourceGroup -Name $ResourceGroup -ErrorAction Stop).ResourceId
}

# Create Azure Active Directory application with password
$HomePage = "http://" + $AppDisplayName
$Application = New-AzureRmADApplication -DisplayName $AppDisplayName -HomePage $HomePage -IdentifierUris $HomePage 

# Create Service Principal for the AD app with the certificate that was created locally
$ServicePrincipal = New-AzureRMADServicePrincipal -ApplicationId $Application.ApplicationId -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore

$NewRole = $null
$Retries = 0;
$seconds = 5
# Loop for 2 minutes sleeping for 5 seconds after each retry
While ($NewRole -eq $null -and $Retries -le 24) {
        # Check if the service principal has been created
    if ((Get-AzureRmADServicePrincipal -ObjectId $ServicePrincipal.Id) -ne $Null) {
        # Service Principal is created
        New-AzureRMRoleAssignment -RoleDefinitionName $RoleDefinitionName -ServicePrincipalName $Application.ApplicationId -Scope $Scope -ErrorAction SilentlyContinue | Write-Verbose
        $NewRole =  Get-AzureRMRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        if ($NewRole -ne $Null) {
            # Role assignment is set. This will skip the sleep by returning to the top of the while loop.
            Continue
        }
    }
    $Retries++
    # Service principal is not ready. Sleep for a bit
    Write-Output ("Waiting for Service Principal to accept New-AzureRMRoleAssignment. Sleeping for {0} seconds" -f $seconds)
    Start-Sleep -Seconds $seconds
}

Write-Output "Use these properties to RunAs this Service Principal:"
Write-Output ("`nTenant: {0}" -f $TenantId)
Write-Output ("SubscriptionId: {0}" -f $SubId)
Write-Output ("ApplicationId: {0}" -f $Application.ApplicationId)
Write-Output ("CertificateThumbprint: {0}" -f $Cert.Thumbprint)
Write-Output ("`nThe certificate is stored on this machine in {0}" -f $CertStoreLocation)
Write-Output ("For your convenience it was exported to: {0}" -f (Get-Item $CertPathPfx).FullName)
Write-Output "The .pfx file is protected with the password that was specified to this script"