# Creates a new Azure RM Role Definition named "RunSchedule Operator".
$InputFile = 'C:\ARMRunSchedule\RBACPolicy.json'

$RoleDefinitionName = 'RunSchedule Operator'
$SubId = (Get-AzureRmContext).Subscription.Id
$Scope = "/subscriptions/" + $SubId
$sp = Get-AzureRMADServicePrincipal | Where-Object DisplayName -eq "ARMRunSchedule-66529817-27b2-428c-b719-b5d953714024"
Get-AzureRMRoleAssignment -RoleDefinitionName $RoleDefinitionName | Remove-AzureRMRoleAssignment
Get-AzureRMRoleDefinition -Name $RoleDefinitionName | Remove-AzureRMRoleDefinition -Force
$d = New-AzureRMRoleDefinition -InputFile $InputFile
if ($d) {
    New-AzureRMRoleAssignment -RoleDefinitionName $RoleDefinitionName -ServicePrincipalName $sp.ApplicationId -Scope $Scope
    (Get-AzureRmRoleDefinition -Name 'RunSchedule Operator' | Select-Object Actions).Actions
}