# This script can be used to pass Azure RM credential parameters to UnitTest.ps1 

$paramsCred = @{
    Tenant = "########-####-####-####-############"
    SubscriptionId = "########-####-####-####-############"
    ApplicationId = "########-####-####-####-############"
    CertificateThumbprint = "########################################"
}

$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "UnitTests.ps1") @paramsCred
