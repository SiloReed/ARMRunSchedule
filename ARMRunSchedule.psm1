#Requires -Modules AzureRM.Compute, AzureRM.Resources
#Requires -Version 5

<#
.SYNOPSIS
   This PowerShell module contains functions related to manipuliating the RunSchedule tag on Azure RM resources.
.DESCRIPTION
    This PowerShell module contains functions related to manipuliating the RunSchedule tag on Azure RM resources.
.NOTES
    Author: Jeff Reed
    Name: RunSchedule.psm1
    Created: 2018-08-20
    Email: siloreed@hotmail.com
#>

# Start Module Functions
function Connect-AzureRM {
    <#
    .SYNOPSIS
       Signs into AzureRM if the user is not already signed in.
    .DESCRIPTION
       Signs into AzureRM if the user is not already signed in.
    .EXAMPLE
       Login-AzureRM
    #>
    [CmdletBinding()]
    param()
    # login into your azure account
    try
    {
        $AzureRMContext = Get-AzureRMContext
    } 
    catch
    {
        try {
            $a = Add-AzureRMAccount
        }
        catch {
            $command = $_.InvocationInfo.MyCommand.Name        
            $ex = $_.Exception
            $m =("{0} failed: {1}" -f $command, $ex.Message)
            Throw $m 
        }
    }
    if ($AzureRMContext.Account -eq $Null) {
        $a = Add-AzureRMAccount
    }

} # End function Login-AzureRM

function Select-Subscription {
    <#
    .SYNOPSIS
        Sets the Azure RM Context to the Azure subscription specified.
    .DESCRIPTION
        Sets the Azure RM Context to the Azure subscription specified. If the SubscriptionId is
        not specified, a gridview of available Azure subscriptions will be presented in order 
        for the user to select a subscription.
    .PARAMETER SubscriptionId
        An Azure subscription ID.
    .EXAMPLE
       Select-Subscription
    .EXAMPLE
       Select-Subscription -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f"
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="An Azure subscription ID."
        )]
        [string] $SubscriptionId
    )
    # Check if SubscriptionId parameter was set
    if (-not ($PSBoundParameters.ContainsKey("SubscriptionId") ) ) {
        # Parameter wasn't set. Get the subscriptions enabled for this user
        
        # In AzureRM.Profile 2.8.0 the property is SubscriptionId. In 3.0.0 it is changed to Id
        $s = Get-AzureRmSubscription | Where-Object State -eq "Enabled" | Out-GridView -Title "Select an Azure Subscription" -OutputMode Single
        if ($s.Id -eq $Null) {
            $SubscriptionId = $s.SubscriptionId
        }
        else {
            $SubscriptionId = $s.Id
        }        

    }

    try {
        # Change the subscription context
        $AzureRMContext = Set-AzureRmContext -SubscriptionId $SubscriptionId
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m =("{0} failed: {1}" -f $command, $ex.Message)
        Throw $m 
    }

} # End function Select-Subscription

function Save-ARMContext {
    <#
    .SYNOPSIS
        Saves the Azure RM Context to a file in the interactive user's profile.
    .DESCRIPTION
        Saves the Azure RM Context to a file in the interactive user's profile
    .PARAMETER SubscriptionId
        An Azure subscription ID.
    .EXAMPLE
       Save-ARMContext
    .EXAMPLE
       Save-ARMContext -SubscriptionId "f1bb2e3d-fbec-4dd8-9e46-fb998a30246f"
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Position=0,        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID."
        )]
        [string] $SubscriptionId
    )
    # Make sure we are signed into Azure
    Connect-AzureRM
    if ($PSBoundParameters.ContainsKey("SubscriptionId") )  {
        Select-Subscription -SubscriptionId $SubscriptionId
    }
    else {
        Select-Subscription
    }

    # Save the interactive Azure profile to a file in the user's home directory
    # This is necessary in order to start background jobs using this users creds
    Save-AzureRmContext -Path $script:AzureProfile -Force | Out-Null
}

function Find-Resources {
    <#  
    .SYNOPSIS
        Returns an array of resources based on JSON input file
    .DESCRIPTION
        Returns an array of resources based on JSON input file
    .PARAMETER ResourceGroupName
        The name of the resource group containing the resource.
    .PARAMETER Name
        The name of the resource.
    .PARAMETER Tag
        If specified the tag will be updated on the resource.
        If specified but a null string, the tag will be removed.
        If not specified no action is taken on the tag. 
    .PARAMETER FilterPath
        An optional JSON file that specifies a filter of resources, so that all resources in a subscription are not examined.
    .PARAMETER Action
        The action to the perfom the resources, either Get, Set, or Remove.
    .EXAMPLE
        Find-Resources -FilterPath "C:\Temp\resource-Filter.json"
    .OUTPUTS
        An array of AzureRM resource objects that match the input filter
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]
    Param (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource group containing the resource."
        )]
        [string] $ResourceGroupName,
    
        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource."
        )]
        [string] $Name,

        [Parameter(
            Position=0,
            ParameterSetName='JSONFile',        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="JSON file that specifies a filter of resources."
        )]
        [string] $FilterPath,
        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The action to perform on the RunSchedule tag, either Get, Set, or Remove."
        )]
        [Parameter(
            Position=2,
            ParameterSetName='CmdLine',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The action to perform on the RunSchedule tag, either Get, Set, Enable, Disable, or Remove."
        )]
        [ValidateSet("Get", "Set", "Enable", "Disable", "Remove")] 
        [string] $Action,

        [Parameter(
            Position=3,
            ParameterSetName='CmdLine',        
            Mandatory=$False,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The new tag value."
        )]
        [string] $Tag
    )

    # Build an array of resource types currently supported.
    $ResourceTypes = @("Microsoft.Compute/virtualMachines")
    $ResourceTypes += "Microsoft.Sql/servers/databases"
    $ResourceTypes += "Microsoft.AnalysisServices/servers"
    
    # Get all of the resources in the subscription for the resource types supported
    $allResources = @()
    try { 
        $ResourceTypes | ForEach-Object {
            $allResources += Get-AzureRMResource -WarningAction SilentlyContinue | Where-Object ResourceType -eq $_
        }
        # Get all of the resource groups in the subscription
        $allResourceGroups = Get-AzureRmResourceGroup
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m =("{0} failed: {1}" -f $command, $ex.Message)
        Throw $m 
    }

    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {
        $filteredResources = $allResources | Where-Object {$_.ResourceGroupName -like $ResourceGroupName -and $_.Name -like $Name}
        foreach ($resource in $filteredResources) {
            # Retrieve the current tag on the resource
            $tags = (Get-AzureRMResource -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name).Tags
            switch ($Action) {
                "Set" {
                    if ($Tag.Length -gt 0) {
                        Set-Tag -Resource $resource -Tag $Tag
                    }
                }
                "Remove" {
                    Set-Tag -Resource $resource -Tag ""
                }
                "Enable" {
                    # Check if the RunSchedule tag does not exist
                    if ( ($tags -eq $Null) -or (-not ($tags.ContainsKey($script:TagRS))) ) {
                        # The tag doesn't exist
                        Write-Warning ("Can't enable! The {0} tag is not set for the resource {1}. Set the tag first." -f $script:TagRS, $resource.Name)
                    }
                    else {
                        $o = $tags.$script:TagRS | ConvertFrom-Json
                        # Only update the tag if enabled was disabled
                        if (-not ($o.Enabled) ) {
                            $o.Enabled = $true
                            $Tag = $o | ConvertTo-Json -Compress
                            Set-Tag -Resource $resource -Tag $Tag
                        }
                    }
                }
                "Disable" {
                    # Check if the RunSchedule tag does not exist
                    if ( ($tags -eq $Null) -or (-not ($tags.ContainsKey($script:TagRS))) ) {
                        # The tag doesn't exist
                        Write-Warning ("Can't disable! The {0} tag is not set for the resource {1}. Set the tag first." -f $script:TagRS, $resource.Name)
                    }
                    else {
                        $o = $tags.$script:TagRS | ConvertFrom-Json
                        # Only update the tag if enabled was enabled
                        if ($o.Enabled) {
                            $o.Enabled = $false
                            $Tag = $o | ConvertTo-Json -Compress
                            Set-Tag -Resource $resource -Tag $Tag
                        }
                    }
                }
                default {}
            }
        }
    }
    else {
        # Initially set the filtered resources to all of the resources in the subscription
        $filteredResources = $allResources

        if ($FilterPath.Length -gt 0) {
            if (Test-Path $FilterPath) {
                # Import the JSON document
                try {
                    $resourceJSON = Get-Content -Path $FilterPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $command = $_.InvocationInfo.MyCommand.Name        
                    $ex = $_.Exception
                    Throw  ("{0} failed: {1}" -f $command, $ex.Message)
                }
                # Create a filtered list of resources only if we have valid JSON data imported from the filter file
                if ($resourceJSON -ne $null) {
                    # Reset the filtered list of resources to an empty array
                    $filteredResources = @()

                    foreach ($r in $resourceJSON.resourceGroups) {
                        $resourceGroups = $allResourceGroups | Where-Object {$_.ResourceGroupName -like $r.Name}
                        foreach ($rg in $resourceGroups) {
                            foreach ($res in $r.resources) {
                                $json = ""
                                # Get the RunSchedule JSON data if it exists for this resource node
                                if ([bool] ($res.PSObject.Properties.Name -match "RunSchedule") ) {
                                    # The Status data is irrelevant in the filter file, so update the values in case the Action is Set
                                    # Convert the object back to JSON
                                    $json = $res.RunSchedule | ConvertTo-Json -Compress
                                }
                                $resources = $allResources | Where-Object {($_.ResourceGroupName -ieq $rg.ResourceGroupName -and $_.Name -ilike $res.Name -and $_.ResourceType -eq $res.resourceType)}
                                foreach ($resource in $resources) {
                                    # Set the RunSchedule as it's set in the JSON file and the function was called with Action=Set
                                    if ( ($json -ne $null) -and ($Action -eq "Set") ) {
                                        Set-Tag -Resource $resource -Tag $json
                                    }
                                    # Remove the RunSchedule tag as the fuction was called with Action=Remove
                                    if ($Action -eq "Remove") {
                                        Set-Tag -Resource $resource -Tag ""
                                    }
                                }
                                $filteredResources += $resources
                            }
                        }
                    }
                }
            }
        }
    }
    # Output the array of resources that match the filter
    $filteredResources
} # End function Find-Resources

function Wait-BackgroundJobs {
    <#  
    .SYNOPSIS
        Loops until Background jobs have completed
    .DESCRIPTION
        Loops until Background jobs have completed
    .EXAMPLE
        Wait-BackgroundJobs 
    .OUTPUTS
        Output of Receive-Job cmdlet
    #>

    [CmdletBinding()]
    Param()

    # Set the maximum minutes before we give up and exit the while loop to avoid be stuck forever
    $TimeOut = 15

    # Get the current time
    $StartTime = Get-Date

    # Create an empty array list
    [System.Collections.ArrayList] $Jobs = @()
    # Add each job to the arraylist. Later they will be remove from the list one by one as they complete.
    Get-Job | ForEach-Object {
        $Jobs += $_
    }

    # Check job state in a loop. This script will not terminate until all jobs have completed or the timeout has expired. 
    while ($Jobs.Count -gt 0) {
        # Check if timeout expired
        if ( (New-TimeSpan $StartTime (Get-Date)).TotalMinutes -ge $TimeOut ) {
            Write-Verbose ("{0} timed out. Returning to caller after {1} minutes" -f $MyInvocation.MyCommand, $TimeOut)
            break
        }
        else {
            for ($i = 0; $i -lt $Jobs.Count; $i++) {
                switch ($Jobs[$i].State) {
                    "Completed" {
                        $ts = New-TimeSpan $Jobs[$i].PSBeginTime $Jobs[$i].PSEndTime
                        Write-Verbose  ("Job id {0} completed in {1} seconds." -f $Jobs[$i].Id, $ts.TotalSeconds)
                        # Return job output to caller
                        Get-Job $Jobs[$i].Id | Receive-Job 
                        Write-Debug ("Removing job id {0}" -f $Jobs[$i].id)
                        $Jobs[$i] | Remove-Job
                        $Jobs.RemoveAt($i)
                        $i--
                    }

                    "Failed" {
                        $ts = New-TimeSpan $Jobs[$i].PSBeginTime $Jobs[$i].PSEndTime
                        Write-Verbose  ("Job id {0} failed in {1} seconds. Reason: {2}" -f $Jobs[$i].Id, $ts.TotalSeconds, $Jobs[$i].ChildJobs[0].JobStateInfo.Reason.Message)
                        # Return job output to caller
                        Get-Job $Jobs[$i].Id | Receive-Job 
                        Write-Debug ("Removing job id {0}" -f $Jobs[$i].id)
                        $Jobs[$i] | Remove-Job
                        $Jobs.RemoveAt($i)
                        $i--
                    }

                    "Running" {
                        Write-Debug ("Job id {0} is still running." -f $Jobs[$i].Id)
                    }
                    default {
                        Write-Debug ("Job id {0} state is {1}." -f $Jobs[$i].Id, $Jobs[$i].State)
                    }
                }
            }
            # Only sleep if there are still background jobs running.
            if ($Jobs.Count -gt 0) {
                # Sleep for a bit before checking jobs again. Some Azure actions take minutes to complete!
                $seconds = 60
                Write-Debug ("Sleeping for {0} seconds" -f $seconds)
                Start-Sleep -Seconds $seconds
            }
        }    
    }
}
function Set-Tag {
    <#  
    .SYNOPSIS
        Sets the tag on a resource starting a background job in the process
    .DESCRIPTION
        Sets the tag on a resource starting a background job in the process
    .PARAMETER Resource
        A resource object
    .PARAMETER Tag
        The RunSchedule tag data in JSON compressed (minified) format.
        If specified the tag will be updated on the resource.
        If specified but a null string, the tag will be removed.
        If not specified no action is taken on the tag.
    .PARAMETER Wait
        A switch argument. If specified, the tag will be set without starting a background job.
    .EXAMPLE
        Set-Tag -Resource $resource -Tag $Tag
    .OUTPUTS
        No outputs other than Write-Verbose
    #>

    [CmdletBinding()]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The resource object."
        )]
        [object] $Resource,

        [Parameter(
            Position=1,
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Update the tag with a new value. If null the tag will be removed."
        )]
        [string] $Tag
        
    )

    Write-Verbose ("Set-Tag called for Resource Id: {0}" -f $Resource.ResourceId)
    Write-Debug ("New tag value: {0}" -f $Tag)

    # Determine if the tag should be removed or set to a new value
    $Remove = $False
    if (-not ($PSBoundParameters.ContainsKey("Tag") ) ) {
        Write-Debug "No tag was set"
        return
    }
    else {
        Write-Debug "Tag exists"
        if ($Tag.Length -gt 0) {
            Write-Debug "Tag is $Tag"
            $Remove = $False
        }
        else {
            $Remove = $True
        }
    }

    $Tags = $Resource.Tags

    if ($Remove) {
        if ($Tags -eq $Null) {
            Write-Verbose ("Nothing to do: There are no tags set for the resource {1}" -f $script:TagRS, $Resource.Name)
            return
        }
        else {
            # Check if the RunSchedule tag does not exist
            if (-not ($Tags.ContainsKey($script:TagRS))) {
                # The tag doesn't exist
                Write-Verbose ("Nothing to do: The {0} tag is not set for the resource {1}" -f $script:TagRS, $Resource.Name)
                return
            }
        }
        # The tag exists so remove it
        $Tags.Remove($script:TagRS)
    }
    else {
        # Check if the tags property exists    
        if ($Tags -eq $Null) {
            # Tags property didn't exist so set the tags to the single tag passed as a parameter
            $Tags = @{$script:TagRS = $Tag}
        }
        else {
            # Check if the RunSchedule tag already exists
            if ($Tags.ContainsKey($script:TagRS) )  {
                # The tag exists so update it
                $Tags.Set_Item($script:TagRS, $Tag)
            }
            else {
                # The tag doesn't exist in the tags collection so add a new tag
                $Tags.Add($script:TagRS, $Tag)
            }
        }
    }

    # Get the path to the users credentials
    $AProfile = $script:AzureProfile

    Write-Debug ("Profile: {0}" -f $AProfile)

    <# 
        Note that there are some problems with using the Set-AzureRmResource cmdlet to update tags:
        1. Set-AzureRmResource hangs when an Analysis Services server is paused: https://github.com/Azure/azure-powershell/issues/4107
        2. It takes longer to update tags with Set-AzureRmResource
        3. Analysis Services and SQL databases must be running in order to update tags.
    #>

    # Create a script block unique to each resource type
    switch ($Resource.ResourceType) {
        "Microsoft.Compute/virtualMachines" {
            $params = @{
                ResourceGroupName = $Resource.ResourceGroupName
                Name = $Resource.Name
            }
            $scriptBlock = Get-JobScriptBlock -Cmdlet Update-AzureRmVM
        }
        "Microsoft.Sql/servers/databases" {
            # Split the ResourceName into the ServerName and DatabaseName components
            $Name = $Resource.Name.Split("/")
            $params = @{
                ResourceGroupName = $Resource.ResourceGroupName
                ServerName = $Name[0]
                DatabaseName = $Name[1]
            }
            $scriptBlock = Get-JobScriptBlock -Cmdlet Set-AzureRmSqlDatabase
        }
        "Microsoft.AnalysisServices/servers" {
            $params = @{
                ResourceGroupName = $Resource.ResourceGroupName
                Name = $Resource.Name
            }
            $scriptBlock = Get-JobScriptBlock -Cmdlet Set-AzureRmAnalysisServicesServer
        }
    }
    if ($PSBoundParameters.ContainsKey("Wait") ) {
        # Function was called with Wait switch - don't set the tag in a background job. 
        # Remove the "using" directive in the script block because it is not applicable to the Invoke-Command cmdlet
        $sb = $scriptBlock.ToString() -replace '\$using\:', '$'
        $sb = $sb -replace '\@using\:', '@'
        $scriptBlock = [scriptblock]::Create($sb)
        Invoke-Command -ScriptBlock $scriptBlock
    }
    else {
        # Start a background job so that script doesn't block waiting for tag to be set
        try {
            $job = Start-Job -ScriptBlock $scriptBlock
        } catch {
            $command = $_.InvocationInfo.MyCommand.Name        
            $ex = $_.Exception
            $m = ("{0} failed: {1}" -f $command, $ex.Message)
            Throw $m
        }
        Write-Verbose  ("Started job id {0} to update tags on Resource ID {1}." -f $job.Id, $Resource.ResourceId)
    }
} # End function Set-Tag

function Get-ARMRunSchedule {
    <#
    .SYNOPSIS
        Gets the run schedule for a given Azure RM resource.
    .DESCRIPTION
        Gets the run schedule for a given Azure RM resource.
    .EXAMPLE
        Get-ARMRunSchedule -SubscriptionId "24f94295-8632-4f38-bb71-4aa30c639634" -ResourceGroupName "rg-ubuntu01" -Name "ubuntu*"
    .EXAMPLE
        Get-ARMRunSchedule -SubscriptionId "24f94295-8632-4f38-bb71-4aa30c639634" -FilterPath ".\resourceFilter.json"
    .PARAMETER SubscriptionId
        The Azure subscription ID containing the resource.
    .PARAMETER ResourceGroupName
        The name of the resource group containing the resource.
    .PARAMETER Name
        The name of the resource.
    .PARAMETER FilterPath
        An optional JSON file that specifies a filter of resources, so that all resources in a subscription are not examined.
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [Parameter(
            Position=0,        
            ParameterSetName='JSONFile',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [string] $SubscriptionId,

        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource group containing the resource."
        )]
        [string] $ResourceGroupName,
        
        [Parameter(
            Position=2,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource."
        )]
        [string] $Name,

        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of resources."
        )]
        [string] $FilterPath
    )

    # Make sure Azure sign on profile exists
    if ($PSBoundParameters.ContainsKey("SubscriptionId") )  {
        Save-ARMContext -SubscriptionId $SubscriptionId
    }
    else {
        Save-ARMContext
    }


    # Determine which parameter set script was called with
    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {
        $resources = Find-Resources -ResourceGroupName $ResourceGroupName -Name $Name -Action Get
        # Make sure resources were found else display a warning message
        if ($resources -eq $Null) {
            Throw ("No resources were found where the resource group name was '{0}' and the resource name was '{1}'" -f $ResourceGroupName, $Name)
        }
    }
    else {
        if ( ($FilterPath -eq $Null) -or ($FilterPath -eq "") ) {
            # Find all resources in the subscription since no filter file was specified.
            $resources = Find-Resources -ResourceGroupName * -Name * -Action Get
        } 
        else {
            if (-not (Test-Path $FilterPath) ) {
                Throw ("{0} is not a valid path." -f $FilterPath)
            }
            else {
                # Find resources in the subscription that match the JSON in the filter file.
                $resources = Find-Resources -FilterPath $FilterPath -Action Get
            }
            # Make sure resources were found else display a warning message
            if ($resources -eq $Null) {
                Write-Warning ("No resources were found. Check the JSON document '{0}'" -f $FilterPath)
                return
            }
        }
    }
    # Create an empty array for the output
    $resourceSchedules = @()

    foreach ($resource in $resources) {
        # Get the tags on the resource
        $Tags = $resource.Tags

        # Check if the RunSchedule tag does not exist
        if ( ($Tags -eq $Null) -or (-not ($Tags.ContainsKey($script:TagRS))) ) {
            # The tag doesn't exist
            $object = New-Object psobject -Property @{
                Name = $resource.Name
                ResourceGroupName = $resource.ResourceGroupName
                ResourceType = $resource.ResourceType
                Enabled = $Null
                AutoStart = $Null
                RunDays = $Null
                StartHourUTC = $Null
                StartHourLocal = $Null
                RunHours = $Null
                Schedule = $Null
            }
            $resourceSchedules += $object

        }
        else {
            # The tag exists so output the tag info
            $o = $Tags.$script:TagRS | ConvertFrom-Json
            # RunDays are special because they are stored as in array of ints. Cast them back to an array of System.DayOfWeek
            $RunDays = [System.DayOfWeek[]] $o.RunDays
            # Sort the RunDays because the script author has OCD
            $RunDays = $RunDays | Sort-Object
            # Get the name of the local time zone
            $tzName = (Get-TimeZone).StandardName
            # Get the current offset of local time from UTC time - this works for standard and daylight savings time.
            $OffsetFromUTC = (Get-Date).Hour - ((Get-Date).ToUniversalTime()).Hour
            # Convert the UTC hour to local hour
            $StartHourLocal = $o.StartHourUTC + $OffsetFromUTC
            if ($StartHourLocal -ge 24) {$StartHourLocal = $StartHourLocal - 24}
            if ($StartHourLocal -lt 0) {$StartHourLocal = 24 + $StartHourLocal}
            $dtStartLocal = [datetime] $($StartHourLocal.ToString() + ":00")
            $EndHourLocal = $StartHourLocal + $o.RunHours
            if ($EndHourLocal -ge 24) {$EndHourLocal = $EndHourLocal - 24 }
            if ($EndHourLocal -lt 0) {$EndHourLocal = 24 + $EndHourLocal}
            $dtEndLocal = [datetime] $($EndHourLocal.ToString() + ":00")
            $Schedule = ("{0} to {1}, {2}" -f $dtStartLocal.ToShortTimeString(), $dtEndLocal.ToShortTimeString(), $tzName)
            $object = New-Object psobject -Property @{
                Name = $resource.Name
                ResourceGroupName = $resource.ResourceGroupName
                ResourceType = $resource.ResourceType
                AutoStart = $o.AutoStart
                Enabled = $o.Enabled
                RunDays = [string]::Join(", ", $RunDays)
                StartHourUTC = $o.StartHourUTC
                StartHourLocal = $StartHourLocal
                RunHours = $o.RunHours
                Schedule = $Schedule
            }

            $resourceSchedules += $object
        }
    }

    $resourceSchedules | Select-Object Name, ResourceGroupName, ResourceType, Enabled, AutoStart, StartHourUTC, StartHourLocal, RunHours, RunDays, Schedule
} # End function Get-ARMRunSchedule

function Set-ARMRunSchedule {
    <#
    .SYNOPSIS
        Sets the run schedule for a given Azure RM resource.
    .DESCRIPTION
        Sets the run schedule for a given Azure RM resource.
    .EXAMPLE
        Set-ARMRunSchedule -SubscriptionId "24f94295-8632-4f38-bb71-4aa30c639634" `
          -ResourceGroupName "rg-Management" -Name "AZEU1JEFFR01" -Enabled -AutoStart `
          -RunHours 13 -RunDays Monday, Tuesday, Wednesday, Thursday, Friday -StartHourUTC 13
    .EXAMPLE
        Set-ARMRunSchedule -ResourceGroupName "rg-Management" -Name AZEU1JEFFR01 `
          -Enabled -AutoStart -RunHours 13 -RunDays 1,2,3,4,5 -StartHourUTC 13
    .PARAMETER SubscriptionId
        The Azure subscription ID containing the resource.
    .PARAMETER ResourceGroupName
        The name of the resource group containing the resource.
    .PARAMETER Name
        The name of the resource.
    .PARAMETER AutoStart
        If this is set, the resource will be started each time it is "in schedule"
    .PARAMETER Enabled
        If this is set, the schedule is enabled, else it's disabled (will be preserved but ignored)
    .PARAMETER RunHours
        The number of hours the resource should run. RunHours+StartHourUTC 
        defines the hours of operation that the resource is considered 
        "in schedule".
    .PARAMETER RunDays
        The days of the week the resource should run
    .PARAMETER StartHourUTC
        The hour (in UTC) that the resource should be started.
    .PARAMETER FilterPath
        An optional JSON file that specifies a list of resources, so that all resources in a subscription are affected.
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]

        [Parameter(
            Position=0,        
            ParameterSetName='JSONFile',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [string] $SubscriptionId,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource group containing the resource."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]
        [string] $ResourceGroupName,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]
        [string] $Name,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]
        [switch] $AutoStart,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]
        [Parameter(
            ParameterSetName='CmdLineEnabledOnly',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="Set this argument to true in order to automatically start the resource."
        )]
        [switch] $Enabled,
    
        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The number of hours the resource should run."
        )]
        [int] $RunHours,
    
        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The days of the week the resource should run.")]
        [System.DayOfWeek[]] $RunDays,

        [Parameter(
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The hour (in UTC) that the resource should be started."
        )]
        [int] $StartHourUTC,
    
        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of resources."
        )]
        [string] $FilterPath
    )

    # Make sure Azure sign on profile exists
    if ($PSBoundParameters.ContainsKey("SubscriptionId") )  {
        Save-ARMContext -SubscriptionId $SubscriptionId
    }
    else {
        Save-ARMContext
    }

    # Determine which parameter set function was called with
    switch ($PSCmdlet.ParameterSetName) {
        "CmdLineEnabledOnly" {
            if ($Enabled) {
                $resources = Find-Resources -ResourceGroupName $ResourceGroupName -Name $Name -Action Enable
            }
            else {
                $resources = Find-Resources -ResourceGroupName $ResourceGroupName -Name $Name -Action Disable
            }
        }

        "JSONFile" {
            # Check if filterpath exists
            if  ( $FilterPath.Length -gt 0) {
                if (-not (Test-Path $FilterPath) ) {
                    Throw ("{0} is not a valid path." -f $FilterPath)
                }
            }
   
            # Find resources in the subscription that match the JSON in the filter file.
            $resources = Find-Resources -FilterPath $FilterPath -Action Set

            # Make sure resources were found else display a warning message
            if ($resources -eq $Null) {
                Throw ("No resources were found. Check the JSON document '{0}'" -f $FilterPath)
            }
        }

        "CmdLine" {
            # Sort the RunDays because the script author has OCD
            $RunDays = $RunDays | Sort-Object

            # Create a hashtable of the parameters
            $ht = @{
                AutoStart = $AutoStart.IsPresent
                Enabled = $Enabled.IsPresent
                RunHours = $RunHours
                RunDays = $RunDays
                StartHourUTC = $StartHourUTC
            }

            # Convert the hashtable to JSON minified
            $json = $ht | ConvertTo-Json -Compress

            $resources = Find-Resources -ResourceGroupName $ResourceGroupName -Name $Name -Tag $json -Action Set

            # Make sure resources were found else display a warning message
            if ($resources -eq $Null) {
                Throw ("No resources were found where the resource group name was '{0}' and the resource name was '{1}'" -f $ResourceGroupName, $Name)
            }
        }
    }
}# End function Set-ARMRunSchedule

Function Remove-ARMRunSchedule {
    <#
    .SYNOPSIS
        Removes the run schedule for a given Azure RM resource.
    .DESCRIPTION
        Removes the run schedule for a given Azure RM resource.
    .EXAMPLE
        > .\Remove-ARMRunSchedule.ps1 -SubscriptionId "24f94295-8632-4f38-bb71-4aa30c639634" `
          -ResourceGroupName "rg-Management" -Name "AZEU1JEFFR01"
    .PARAMETER SubscriptionId
        The Azure subscription ID containing the resource.
    .PARAMETER ResourceGroupName
        The name of the resource group containing the resource.
    .PARAMETER Name
        The name of the resource.
    .PARAMETER FilterPath
        An optional JSON file that specifies a filter of resources, so that all resources in a subscription are not affected.
    #>

    [CmdletBinding(
        DefaultParameterSetName="JSONFile"
    )]

    Param
    (
        [Parameter(
            Position=0,
            ParameterSetName='CmdLine',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [Parameter(
            Position=0,        
            ParameterSetName='JSONFile',
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [string] $SubscriptionId,

        [Parameter(
            Position=1,
            ParameterSetName='CmdLine',
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource group containing the resource."
        )]
        [string] $ResourceGroupName,
    
        [Parameter(
            Position=2,
            ParameterSetName='CmdLine',    
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The name of the resource."
        )]
        [string] $Name,

        [Parameter(
            Position=1,
            ParameterSetName='JSONFile',        
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="A JSON file that specifies a list of resources."
        )]
        [string] $FilterPath
    )

    # Make sure Azure sign on profile exists
    if ($PSBoundParameters.ContainsKey("SubscriptionId") )  {
        Save-ARMContext -SubscriptionId $SubscriptionId
    }
    else {
        Save-ARMContext
    }

    # Determine which parameter set script was called with
    if ($PSCmdlet.ParameterSetName -eq "CmdLine") {
        # Set the tag parameter to an empty string and the Find-Resources cmdlet will remove the tag
        $resources = Find-Resources -ResourceGroupName $ResourceGroupName -Name $Name -Action Remove
        # Make sure resources were found else display a warning message
        if ($resources -eq $Null) {
            Write-Debug ("No resources were found where the resource group name was '{0}' and the resource name was '{1}'" -f $ResourceGroupName, $Name)
        }
    }
    else {
        # Check if filterpath exists
        if  ( $FilterPath.Length -gt 0) {
            if (-not (Test-Path $FilterPath) ) {
                Throw ("{0} is not a valid path." -f $FilterPath)
            }
        }
   
        # Find resources in the subscription that match the JSON in the filter file.
        $resources = Find-Resources -FilterPath $FilterPath -Action Remove

        # Make sure resources were found else display a warning message
        if ($resources -eq $Null) {
            Write-Debug ("No resources were found. Check the JSON document '{0}'" -f $FilterPath)
         }
    }
} # End function Remove-ARMRunSchedule

function Set-ResourceState {
    <#
    .SYNOPSIS
        Starts (resumes) or stops (pauses) an Azure RM resouce.
    .DESCRIPTION
        Starts (resumes) or stops (pauses) an Azure RM resouce. 
        In the case of virtual machines, the "Start" action will change the virtual machine to the running state.
        In the case of virtual machines, the "Stop" action will "deallocate" the virtual machine.
        In the case of SQL (PaaS) Databases, the "Start" action will change the database to the online state.
        In the case of SQL (PaaS) Databases, the "Stop" action will change the database to the paused state.
        In the case of Analysis Services (PaaS), the "Start" action will change the server to the online state.
        In the case of Analysis Services (PaaS), the "Stop" action will change the server to the paused state.
    .PARAMETER Action
        The action that will be performed on the Azure resource. 
        Either 'Start' or 'Stop'
    .PARAMETER Resource
        The Azure RM resource object 
    .PARAMETER Tag
        The current RunSchedule tag
    .OUTPUTS
        No output other than Write-Verbose
    #>
    
    Param
    (
        [Parameter(
            Position=0,        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The Azure subscription ID containing the resource."
        )]
        [string] $SubscriptionId,

        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$false,
                    HelpMessage="The action that will be performed on the virtual machine.",
                    Position=1)]
        [ValidateSet("Start","Stop")]
        [string] $Action,
 
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$false,
                    HelpMessage="The virtual machine object.",
                    Position=2)]
        [object] $Resource

    )

    # Make sure Azure sign on profile exists
    if ($PSBoundParameters.ContainsKey("SubscriptionId") )  {
        Save-ARMContext -SubscriptionId $SubscriptionId
    }
    else {
        Save-ARMContext
    }
    # Get the path to the users credentials
    $AProfile = $script:AzureProfile
    $Tags = $Resource.Tags
    try {
        $RunSchedule = $Tags.$scriptTag | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message)
        Throw $m
    }

    # These parameters work for virtual machines and Analysis Services. 
    $params = @{
        ResourceGroupName = $Resource.ResourceGroupName
        Name = $Resource.Name
    }
    if ($Action -eq "Stop") {
        # Create a script block unique to each resource type
        switch ($Resource.ResourceType) {
            # virtualMachines
            "Microsoft.Compute/virtualMachines" {
                $json = $RunSchedule | ConvertTo-Json -Compress
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Stop-AzureRmVM'
            }
            # SQL databases
            "Microsoft.Sql/servers/databases" {
                # Split the ResourceName into the ServerName and DatabaseName components
                $Name = $Resource.Name.Split("/")
                # SQL Database parameters are different than VMs and AS
                $params = @{
                    ResourceGroupName = $Resource.ResourceGroupName
                    ServerName = $Name[0]
                    DatabaseName = $Name[1]
                }
                # Suspend-AzureRmSqlDatabase
                $json = $RunSchedule | ConvertTo-Json -Compress
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Suspend-AzureRmSqlDatabase'
            }
            # Analysis Services servers
            "Microsoft.AnalysisServices/servers" {
                # Suspend-AzureRmAnalysisServicesServer
                $json = $RunSchedule | ConvertTo-Json -Compress
                $Tags.Set_Item($script:TagRS, $json)                
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Suspend-AzureRmAnalysisServicesServer'
            }
        }            
    } 
    else {
        switch ($Resource.ResourceType) {
            # virtualMachines
            "Microsoft.Compute/virtualMachines" {
                $json = $RunSchedule | ConvertTo-Json -Compress
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Start-AzureRmVM'
            }
            # SQL databases
            "Microsoft.Sql/servers/databases" {
                # Split the ResourceName into the ServerName and DatabaseName components
                $Name = $Resource.Name.Split("/")
                $params = @{
                    ResourceGroupName = $Resource.ResourceGroupName
                    ServerName = $Name[0]
                    DatabaseName = $Name[1]
                }                
                $json = $RunSchedule | ConvertTo-Json -Compress
                # Resume-AzureRmSqlDatabase
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Resume-AzureRmSqlDatabase'
            }
            # Analysis Services servers
            "Microsoft.AnalysisServices/servers" {            
                #Resume-AzureRmAnalysisServicesServer
                $json = $RunSchedule | ConvertTo-Json -Compress
                $scriptBlock = Get-JobScriptBlock -Cmdlet 'Resume-AzureRmAnalysisServicesServer'
            }
        }            
    }

    # Start a background job so that script doesn't block waiting for start or stop to finish
    try {
        $job = Start-Job -ScriptBlock $scriptBlock
        Write-Verbose  ("Started job id {0} to {1} {2}." -f $job.Id, $Action.ToLower(), $Resource.ResourceId)
    } catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message)
        Throw $m 
    }
} 
function Get-JobScriptBlock {
    <#
    .SYNOPSIS
    Returns a scriptblock object for the Set-ResourceState function    
    .DESCRIPTION
    Returns a scriptblock object for the Set-ResourceState function    
    .PARAMETER Cmdlet
    The AzureRM Cmdlet that will be called by the scriptblock
    .PARAMETER Params
    The parameters for the AzureRM Cmdlet
    .OUTPUTS
    [ScriptBlock]
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Position=0,        
            Mandatory=$false,
            ValueFromPipelineByPropertyName=$false,
            HelpMessage="The AzureRM Cmdlet that will be called by the scriptblock."
        )]
        [ValidateSet(
            "Stop-AzureRmVM",
            "Start-AzureRmVM", 
            "Suspend-AzureRmSqlDatabase", 
            "Suspend-AzureRmAnalysisServicesServer", 
            "Resume-AzureRmSqlDatabase", 
            "Resume-AzureRmAnalysisServicesServer",
            "Update-AzureRmVM",
            "Set-AzureRmSqlDatabase",
            "Set-AzureRmAnalysisServicesServer")]
        [string] $Cmdlet            
    )
    <# Create a here-string literal for the beginning of the scriptblock. 
       This is common to all cmdlets and connects to Azure using the stored profile.
       This line: $ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)
       , is the workaround for the bug in https://github.com/Azure/azure-powershell/issues/3954
    #>
    $sbBegin = @'
    try {
        $ctx = Import-AzureRmContext -Path $using:AProfile
        $ctx.Context.TokenCache.Deserialize($ctx.Context.TokenCache.CacheData)
'@
    # Create a here-string literal for the end of the scriptblock. 
    # This is common to all cmdlets. It terminates the try block and includes the catch block.
    $sbEnd = @'
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message)
        Write-Verbose $m
        Throw $m
    }
'@
    # Switch statement to create the middle of the try block portion of the scriptblock specific to each cmdlet
    switch ($Cmdlet) {
        
        # Stop-AzureRmVM
        'Stop-AzureRmVM' {
            $sbMiddle = @'
        $ts = Measure-Command {$o = Stop-AzureRmVM @using:params -Force -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Stop-AzureRmVM completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Stop-AzureRmVM  completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }
'@
        }
        
        # Start-AzureRmVM
        'Start-AzureRmVM' {
            $sbMiddle = @'
        $ts = Measure-Command {$o = Start-AzureRmVM @using:params -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Start-AzureRmVM completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Start-AzureRmVM completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }
'@
        }

        # Suspend-AzureRmSqlDatabase
        'Suspend-AzureRmSqlDatabase' {
            $sbMiddle = @'
        $ts = Measure-Command {Suspend-AzureRmSqlDatabase @using:params -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }
'@
        }
        # Resume-AzureRmSqlDatabase
        'Resume-AzureRmSqlDatabase' {
            $sbMiddle = @'
        $ts = Measure-Command {Resume-AzureRmSqlDatabase @using:params -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Resume-AzureRmSqlDatabase completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Resume-AzureRmSqlDatabasecompleted in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }                           
'@
        }
        
        # Suspend-AzureRmAnalysisServicesServer
        'Suspend-AzureRmAnalysisServicesServer' {
            $sbMiddle = @'
        $ts = Measure-Command {Suspend-AzureRmAnalysisServicesServer @using:params -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Suspend-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Suspend-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }                        
'@
        }

        # Resume-AzureRmAnalysisServicesServer 
        'Resume-AzureRmAnalysisServicesServer' {
            $sbMiddle = @'
        $ts = Measure-Command {Resume-AzureRmAnalysisServicesServer @using:params -ErrorAction Stop}
        if ($o -eq $Null) {
            Write-Output ("Resume-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Resume-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }                        
'@
        }

        # Update-AzureRmVM
        'Update-AzureRmVM' {
            $sbMiddle = @'
        $vm = Get-AzureRmVM @using:params
        $ts = Measure-Command {$o = Update-AzureRmVM -VM $vm -ResourceGroupName $vm.ResourceGroupName -Tag $using:Tags}
        if ($o -eq $Null) {
            Write-Output ("Update-AzureRmVM completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Update-AzureRmVM completed in {0:hh\:mm\:ss}. StatusCode: {1}." -f $ts, $o.StatusCode)
        }
'@
        }

        # Set-AzureRmSqlDatabase
        'Set-AzureRmSqlDatabase' {
            $sbMiddle = @'
        $db = Get-AzureRmSqlDatabase @using:params
        # Check if the database is paused or pausing.
        if ( ($db.Status -ieq "Paused") -or ($db.Status -ieq "Pausing") ) {
            $WasOffline = $True
            # Start the database so the tag can be set.
            $ts = Measure-Command {$o = $db | Resume-AzureRmSqlDatabase}
            if ($o -eq $Null) {
                Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss} with no status." -f $ts)
            }
            else {
                Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
            }
        }
        $ts = Measure-Command {$o = Set-AzureRmSqlDatabase @using:params -Tags $using:Tags}
        if ($o -eq $Null) {
            Write-Output ("Set-AzureRmSqlDatabase completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Set-AzureRmSqlDatabase completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }
        if ($WasOffline) {
            # Database was previously offline so suspend it
            $ts = Measure-Command {$o = $db | Suspend-AzureRmSqlDatabase}
            if ($o -eq $Null) {
                Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss} with no status." -f $ts)
            }
            else {
                Write-Output ("Suspend-AzureRmSqlDatabase completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
            }
        }
'@            
        }

        # Set-AzureRmAnalysisServicesServer
        'Set-AzureRmAnalysisServicesServer' {
            $sbMiddle = @'
        $as = Get-AzureRmAnalysisServicesServer @using:params
        # Check if the server is paused or pausing.
        if ( ($as.State -ieq "Paused") -or ($as.State -ieq "Pausing") ) {
            $WasOffline = $True
            # Start the server so the tag can be set.
            $ts = Measure-Command {$o =$as | Resume-AzureRmAnalysisServicesServer}
            if ($o -eq $Null) {
                Write-Output ("Resume-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss} with no status." -f $ts)
            }
            else {
                Write-Output ("Resume-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
            }
        }
        # This cmdlet uses singular "Tag" not "Tags"!
        $ts = Measure-Command {$o = Set-AzureRmAnalysisServicesServer @using:params -Tag $using:Tags}
        if ($o -eq $Null) {
            Write-Output ("Set-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss} with no status." -f $ts)
        }
        else {
            Write-Output ("Set-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
        }

        if ($WasOffline) {
            # Server was previously offline so suspend it
            $ts = Measure-Command {$o = $as | Suspend-AzureRmAnalysisServicesServer}
            if ($o -eq $Null) {
                Write-Output ("Suspend-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss} with no status." -f $ts)
            }
            else {
                Write-Output ("Suspend-AzureRmAnalysisServicesServer completed in {0:hh\:mm\:ss}. Status: {1}." -f $ts, $o.Status)
            }

        }
'@
        }

    }

    $sb = $sbBegin + "`n" + $sbMiddle + "`n" + $sbEnd
    # Output the scriptblock
    [scriptblock]::Create($sb)
}

# End Module Functions

# This defines the name of the tag on the resource for all functions in the script 
$script:TagRS = "RunSchedule"

# Sets the path to a file in the user's home directory that will store the current users credentials. 
# This is necessary in order to start background jobs using this users creds
$script:AzureProfile = Join-Path (Get-Item ~) "RunScheduleProfile.json"

Export-ModuleMember -Function Connect-AzureRM
Export-ModuleMember -Function Select-Subscription
Export-ModuleMember -Function Find-Resources
Export-ModuleMember -Function Wait-BackgroundJobs
Export-ModuleMember -Function Set-Tag
Export-ModuleMember -Function Get-ARMRunSchedule
Export-ModuleMember -Function Set-ARMRunSchedule
Export-ModuleMember -Function Remove-ARMRunSchedule
Export-ModuleMember -Function Set-ResourceState