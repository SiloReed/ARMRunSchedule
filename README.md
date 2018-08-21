# ARMRunSchedule

## Overview

This set of PowerShell scripts is used automate the stating and stopping of Azure Resource Manager virtual machines, SQL Databases, and Analysis Services servers.

## Prerequisites

An Azure Service Principal account is required by the Compare-ARMRunSchedule.ps1 script. An "always running" Windows computer is intended to run the Compare-ARMRunSchedule.ps1 as a scheduled task.

## Script Overview

|Script|Description|
| --- | --- |
| ARMRunSchedule.psm1 | This PowerShell Script Module exports functions for getting, setting, and removing the RunSchedule tag from AzureRM resources. |
| Compare-ARMRunSchedule.ps1 | This script imports the ARMRunSchedule.psm1 module and reads the RunSchedule tag on each resource to determine if the resource is "in schedule". |
| Install-ARMRunSchedule.ps1 | Installs the ARMRunSchedule.psm1 and ARMRunSchedule.psd1 files into the PowerShell modules path under %ProgramFiles%
| New-ARMServicePrincipal.ps1 | Creates an Azure Application and Service Principal with the 'Virtual Machine Contributor' role. |
| UnitTests.ps1 | Demonstrates the various command line methods for calling the cmdlets in the ARMRunSchedule module. |

### Module CmdLet Overview

| CmdLet | Description |
| --- | --- |
| Get-ARMRunSchedule | Gets the RunSchedule tag for the specified resource and displays it in a user friendly format. |
| Remove-ARMRunSchedule | Removes the RunSchedule tag for the specified resource. |
| Set-ARMRunSchedule | Sets the RunSchedule tag for the specified resource. |
| Wait-BackgroundJobs | Loops for up to 15 minutes until Background jobs have completed |
| Find-Resources | Finds resources in the current subscription by pattern, either from command line parameters or JSON filter file. |
| Connect-AzureRM | Signs into AzureRM if the user is not already signed in. |
| Select-Subscription | Sets the Azure RM Context to the Azure subscription specified. |
| Set-Tag | Sets the tag on a resource starting a background job in the process. |
| Set-ResourceState | Starts (resumes) or stops (pauses) an Azure RM resouce. | 

## Setup

### Create an Azure Automation Account

The scripts work best if authenticating to Azure as an Automation account with certificate authentication. See:
[Use Azure PowerShell to create a service principal to access resources](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-authenticate-service-principal)

1. You will need an "always running" Windows computer that will execute the Compare-ARMRunSchedule.ps1 as a scheduled task. The computer can be either on-premises or in an IaaS cloud.
1. Create a local account on the Windows computer with a name such as "svcRunSchedule". 
1. Grant the svcRunSchedule local account the "Run as a batch job":
    1. Run the Local Security Policy application.
    1. Drill down to Security Settings\Local Policies\User Rights Assignment.
    1. Add the svcRunSchedule user to the "Log on as a batch job" policy.
1. Download all of the files from this solution into a directory on the Windows computer such as "C:\ARMRunSchedule"
1. Create a subdirectory named "Logs" under "C:\ARMRunSchedule". The Compare-ARMRunSchedule.ps1 will write it's log files to this subdirectory.
1. Start an elevated PowerShell session (as Administrator) and execute:

    ```powershell
    cacls.exe C:\ARMRunSchedule\Logs /E /T /G svcRunSchedule:C
    Set-ExecutionPolicy RemoteSigned
    C:\ARMRunSchedule\Install-ARMRunSchedule.ps1
    ```

    The first command grants the svcRunSchedule "Change" access to the C:\ARMRunSchedule\Logs and its children.
    The second command ensures that local PowerShell scripts are allowed to execute.
    The third command installs the ARMRunSchedule module in %ProgramFiles%\WindowsPowerShell\Modules. This makes the ARMRunSchedule's exported functions available to other scripts. Close the elevated PowerShell session when the script completes.
1. In a non-elevated PowerShell session, execute:

    ```powershell
    runas.exe /user:svcRunSchedule powershell.exe

    ```
1. In the new PowerShell session running as svcRunSchedule execute these commands:

    ```powershell
    cd \ARMRunSchedule
    C:\ARMRunSchedule\New-ARMServicePrincipal.ps1
    ```

    * When this script is run without parameters, it will prompt the user to sign into AzureRM and prompt for a subscription. Sign in using your AzureAD account that has the Contributor role in the selected subscription.
    * The script will also prompt for a password that will be used to protect the .pfx file that will be exported by the script.  
    * A new Azure AD Application and Azure Service Principal will be created in the selected subscription with the 'Virtual Machine Contributor' role. This role allows this Service Principal to start and stop virtual machines in the subscription. The Service Principal will also have the permission to create, remove and update tags on the virtual machines in the subscription. 
    * The DisplayName property of the Application and Service Principal will be set to "ARMRunSchedule-*\<SubscriptionId\>*", where *\<SubscriptionId\>* is the SubscriptionId of the selected subscription.
    * A new self-signed certificate with be installed in the svcRunSchedule user's personal certificate store. This certificate is tied to the Service Principal in Azure AD. This configuration allows the local svcRunScheduler user to "RunAs" the AD Service Principal.
1. Leave the PowerShell window open and note the output of the New-ARMServicePrincipal.ps1 script.
1. Edit the Compare-ARMRunSchedule.json file
    1. Update the Tenant, SubscriptionId, ApplicationId, CertificateThumbprint values with the values output by the New-ARMServicePrincipal.ps1 script. 
    1. Update the FilterPath, if necessary, to the actual path of this ARMRunSchedule.json file. The FilterPath is used by Compare-ARMRunSchedule.ps1 to locate this .json file and load these values as variables.
    1. Update the TableName value to the name of the Azure table that the Compare-ARMRunSchedule.ps1 will log to.
    1. Update the TableSAName value to the name of the Azure Storage Account that contains the Azure Table.
    1. Update the TableRGName value to the name of the Azure Resource Group containing the Azure Storage account and Azure Table.
    1. Update the SMTPServer value, if necessary. The Compare-ARMRunSchedule.ps1 will send email via this SMTP server when a fatal error occurs.
    1. Update the To value to the email recipient list that will receive mail sent when a fatal error occurs. Use semi-colons to separate email addresseses. 
1. In an elevated PowerShell (or cmd.exe) session execute:

    ```powershell
    schtasks.exe /Create /XML C:\ARMRunSchedule\ARMRunSchedule.xml /RU svcRunSchedule /RP * /TN "ARMRunSchedule"
    schtasks.exe /Run /TN ARMRunSchedule
    ```

    This creates the scheduled task that will execute the Compare-ARMRunSchedule.ps1 script every 15 minutes. It runs as svcRunSchedule.
1. Monitor the task in the Task Scheduler app. In the Actions pane, enable the Enable All Tasks History.
1. View the output in C:\ARMRunSchedule\Logs\Compare-ARMRunSchedule*\<Date\>*. A new log file is created each day.
1. View the output in the Azure table. The Azure Storage Explorer application is the easiest way to view the Azure table.
1. Once you are confident that the schedule task executes correctly, reboot the Windows computer so that the task will execute every 15 minutes. 

## Managing the RunSchedule tag on virtual machines

The ARMRunSchedule module contains functions for getting, setting, enabling, disabling and removing the RunSchedule tag from one or more virtual machines. The ARMRunSchedule module executes some of the AzureRM commands in background jobs (multiple threads of execution). In order to provide credentials for the background job the module uses the Save-AzureRmContext and Import-AzureRmContext cmdlets from the AzureRm.Profile module. There is a [bug](https://github.com/Azure/azure-powershell/issues/3954) in AzureRm.Profile ver 3.0.0 where interactive credentials don't work with the Save-AzureRmContext and Import-AzureRmContext cmdlets. As a workaround, it is recommended that certificate sign in be used instead of interactive sign in to work around the problem. 

In order to sign in with certificate credentials and RunAs the Service Principal that was created by the New-ARMServicePrincipal.ps1 script, you'll need to import the .pfx file that was exported by the New-ARMServicePrincipal.ps1 script. The .pfx file was exported by the script to the svcRunSchedule user's home directory. Once the certificate is imported into another user's certificate store, then that user can RunAs the Service Principal with the permissions of the Service Principal. For this reason, it is important to protect the certificate and the access to the computer where the Compare-ARMRunSchedule.ps1 script is running.

After importing the certificate, you could leverage the technique in the UnitTests.ps1 script to sign in using the certificate. The code looks like this:

```powershell
    $paramsCred = @{
        ServicePrincipal = $True
        Tenant = $Tenant
        SubscriptionId = $SubscriptionId
        ApplicationId = $ApplicationId
        CertificateThumbprint = $CertificateThumbprint
    }

    $AzureRMAccount = Add-AzureRMAccount @paramsCred
```

The $paramsCred is a hashtable of the command line arguments that were passed to the UnitTests.ps1 script. The Add-AzureRMAccount is then executed with the hashtable passed using splatting.

One way to invoke UnitTests.ps1 is to write a script like this, replacing the values with the values appropriate for your environment:

```powershell
$paramsCred = @{
    Tenant = "########-####-####-####-############"
    SubscriptionId = "########-####-####-####-############"
    ApplicationId = "########-####-####-####-############"
    CertificateThumbprint = "########################################"
}

$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

& (Join-Path $ScriptDir "UnitTests.ps1") @paramsCred
```

Notice that UnitTests.ps1 shows the variety of ways that the ARMRunSchedule cmdlets can be executed.

## RunSchedule Tag Design

The RunSchedule tag shall be applied to any resource that is indended to be stopped in an automated fashion. Virtual machines may be optionally started in an automated fashion. The RunSchedule tag is compound tag - it is a minified (single line) JSON document. In "pretty" format it looks like this:

```json
{
    "AutoStart": true,
    "Enabled":  true,
    "RunDays": [
        1,
        2,
        3,
        4,
        5
    ],
    "RunHours": 10,
    "StartHourUTC": 14,
}
```

### Tag Field descriptions

#### AutoStart

If this value is present and evaluates to [bool] true then the resource will be automatically started when it is considered "in schedule". If it is not present or evaluates to false, then the machine will not be started automatically if it is considered "in schedule" and not running.

#### Enabled

If this evaluates to [bool] true, then the resource will be processed by the Compare-ARMRunSchedule.ps1 script. It if evaluates to [bool] false then the resource will be ignored by the Compare-ARMRunSchedule.ps1 script. Setting it to false is handy for preserving the schedule but temporarily removing the resource from processing. 

#### RunDays

This is an array of integers with valid values 0 - 6 that correspond to the days of the week that the resource is intended to be running. 
RunDays is cast to an array of [System.DayOfWeek] internally by the PowerShell scripts. 

#### RunHours

The number of hours after StartHourUTC that the machine will be allowed to run.

#### StartHourUTC

The time in UTC that the resource's schedule starts each day in RunDays. 

## CmdLet Details

### Get-ARMRunSchedule

#### Get-ARMRunSchedule Description

Gets the run schedule for a given Azure RM resource.

#### Get-ARMRunSchedule Examples

```powershell
Get-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -ResourceGroupName "rg-ubuntu01" -Name "ubuntu01"
Get-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -ResourceGroupName "rg-ubuntu*" -Name "ubuntu*"
Get-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -FilterPath 'C:\ARMRunSchedule\VMList1.json'
```

#### Get-ARMRunSchedule Output (defaults to list view)

```powershell
Name           : ubuntu01
AutoStart      : False
StartHourUTC   : 13
StartHourLocal : 8
RunHours       : 10
RunDays        : Monday, Tuesday, Wednesday, Thursday, Friday
Schedule       : 8:00 AM to 6:00 PM, Eastern Standard Time
Status         : 2017-05-19 15:32:07Z Run schedule set by
```

### Set-ARMRunSchedule

#### Set-ARMRunSchedule Description

Sets the run schedule for a given Azure RM resource.

#### Set-ARMRunSchedule Example

Using the integer values for the RunDays parameter:

```powershell
Set-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -ResourceGroupName "rg-ubuntu01" -Name "ubuntu01" -AutoStart -RunHours 10 -RunDays 1,2,3,4,5 -StartHourUTC 13
```

Or that names days of the week can be used with the RunDays parameter:

```powershell
Set-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -ResourceGroupName "rg-ubuntu01" -Name "ubuntu01" -AutoStart -RunHours 10 -RunDays Monday,Tuesday,Wednesday,Thursday,Friday -StartHourUTC 13
```

#### Set-ARMRunSchedule Output

This cmdlet does not output to StdOut. Use the '-Verbose' parameter to see verbose output. This can be useful as the cmdlet won't return until all background jobs are finished. 

### Remove-ARMRunSchedule

#### Remove-ARMRunSchedule Description

Remove the run schedule for a given Azure RM resource.

#### Remove-ARMRunSchedule Example

```powershell
Remove-ARMRunSchedule -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f" -ResourceGroupName "rg-ubuntu01" -Name "ubuntu01"
```

#### Remove-ARMRunSchedule Output

This cmdlet does not output to StdOut. Use the '-Verbose' parameter to see verbose output. This can be useful as the cmdlet won't return until all background jobs are finished. 

### Compare-ARMRunSchedule.ps1 Script

#### Compare-ARMRunSchedule.ps1 Description

The Compare-ARMRunSchedule.ps1 script is where the magic happens - is actually starts and stops resources based on the contents of each resource's RunSchedule tag. It is intended to be run as a scheduled task on a Windows machine that is "always on". The machine could be on-premises on in the cloud. The scheduled task could be configured to run every 15 minutes.

#### Compare-ARMRunSchedule.ps1 Design

The Compare-ARMRunSchedule.ps1 script has no command line parameters. Instead, it reads the Compare-ARMRunSchedule.json which defines script-wide variables used by the script.

##### The Compare-ARMRunSchedule.json file

 An example Compare-ARMRunSchedule.json:

```json
{
    "Variables":  [
        {
            "name": "ApplicationId",
            "value": "ca2f8c44-91f3-4101-bb3b-4f6d599357f0"
        },
        {
            "name": "SubscriptionId",
            "value": "24f94295-8632-4f38-bb71-4aa30c639634"
        },
        {
            "name": "TenantId",
            "value": "335836de-42ef-43a2-b145-348c2ee9ca5b"
        },
        {
            "name": "FilterPath",
            "value": "C:\\ARMRunSchedule\\ARMRunSchedule.json"
        },
        {
            "name": "TableName",
            "value": "tableScriptLog"
        },
        {
            "name": "TableSAName",
            "value": "farunschedulecta598"
        },
        {
            "name": "TableRGName",
            "value": "rg-runschedule-itea"
        },
        {
            "name": "SMTPServer",
            "value": "mail.mydomain.com"
        },
        {
            "name": "Domain",
            "value": "mydomain.com"
        },
        {
            "name": "To",
            "value": "siloreed@hotmail.com"
        }
    ]
}
```

##### Variables

* ApplicationId: The ApplicationId is the ID of the serice principal.
* SubscriptionId: The Subscription ID of the resources
* TenantId: The Tenant ID of the service principal and resources
* FilterPath: An optional JSON file that specifies a filter of resources, so that all resources in a subscription are not examined. 
* TableName: The name of a table in Azure Table storage
* TableSAName: The Azure Storage Account of the Azure Table
* TableRGName: The Azure Resource Group that contains the Storage Account the contains the Azure Table
* SMTPServer: The name or IP address of an SMTP that will be used for sending fatal errors via email
* To: The recipient list of email addresses (semi-colon separated)

#### Compare-ARMRunSchedule.ps1 Example

.\Compare-ARMRunSchedule.ps1

## Example resource filter list

The Get-ARMRunSchedule, Set-ARMRunSchedule, and Remove-ARMRunSchedule cmdlet have an optional -FilterPath command line argument that can be used to specify a list of resource groups and virtual machines to act upon. The FilterPath file is a JSON document that may also contain the RunSchedule for virtual machines, which is handy for setting the RunSchedule for many machines at one time. The example of this file looks like this (although location is not currently implemented in the code):

```json
{
    "name": "Dev Test RunSchedule Filter",
    "comment": "This is the list of virtual machines, Analysis Services Servers, and SQL databases that could be checked by the Compare-ARMVMRunSchedule script.",
    "resourceGroups": [
        {
            "name": "rg-HCAZEU1SQLE01",
            "resources": [
                {
                    "name": "HCAZEU1SQLE01",
                    "resourceType": "Microsoft.Compute/virtualMachines",
                    "RunSchedule": {
                        "Enabled":  true,
                        "AutoStart": false,
                        "RunDays": [
                            1,
                            2,
                            3,
                            4,
                            5
                        ],
                        "RunHours": 10,
                        "StartHourUTC": 13
                    }
                }
            ]
        },
        {
            "name": "rg-csmainDatabase",
            "resources": [
                {
                    "name": "hcazeu1asql01/empty",
                    "resourceType": "Microsoft.Sql/servers/databases",
                    "RunSchedule": {
                        "Enabled":  true,
                        "AutoStart": false,
                        "RunDays": [
                            1,
                            2,
                            3,
                            4,
                            5
                        ],
                        "RunHours": 10,
                        "StartHourUTC": 13
                    }
                }
            ]
        }
    ]
}
```