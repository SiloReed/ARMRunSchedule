<#
.SYNOPSIS
    Starts or stops Azure RM resources by comparing their RunSchedule
    to the current time in UTC.
.DESCRIPTION
    Starts or stops Azure RM resources by comparing their RunSchedule
    to the current time in UTC. 
.NOTES
    Author: Jeff Reed
    Name: Compare-ARMVMRunSchedule.ps1
    Created: 2018-08-20
    Email: siloreed@hotmail.com

    The script has no command line parameters. Instead, all script variables
    that would normally be passed as parameters are instead read from a 
    JSON file in the same directory as the script. This design makes it 
    much easier to debug the script and configure a scheduled task for 
    the script. 
#>

#requires -version 5
#requires -modules AzureRM.Compute, AzureRM.Resources, AzureRmStorageTable, ARMRunSchedule

[CmdletBinding()]
param()

function Out-Log {
    <#  
    .SYNOPSIS
        Writes output to the log file.
    .DESCRIPTION
        Writes output the Host and appends output to the log file with date/timestamp
    .PARAMETER Message
        The string that will be output to the log file
    .PARAMETER Level
        One of: "Info", "Warn", "Error", "Verbose", "Debug"
        Defaults to "Info" if not specified.
    .PARAMETER Resource
        One or more resource objects.
    .PARAMETER Schedule
        An object representing the parsed values of the RunSchedule tag
    .PARAMETER Action
        The action taken, if any. Defaults to "Log" if not specified.
    .NOTES    
        Requires that the $Script:log variable be set by the caller
    .EXAMPLE
        Out-Log "Test to write to log"
    .EXAMPLE
        Out-Log -Message "Test to write to log" -Level "Info"
    #>

    [CmdletBinding(DefaultParameterSetName="Standard")]
    param (
        [Parameter (
            Position=0,
            ParameterSetName='Standard', 
            Mandatory=$true,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [string] $Message,
        
        [Parameter (
            Position=1, 
            ParameterSetName='Standard', 
            Mandatory=$false,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [ValidateSet("Info", "Warn", "Error", "Verbose", "Debug")]
        [string] $Level = "Info",

        [Parameter(
            Position=2, 
            ParameterSetName='Standard', 
            Mandatory=$false, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$true)
        ]
        [object] $Resource,

        [Parameter(
            Position=3, 
            ParameterSetName='Standard', 
            Mandatory=$false, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Schedule,

        [Parameter (
            Position=4, 
            ParameterSetName='Standard', 
            Mandatory=$false,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [string] $Action = "Log",        
        
        [Parameter (
            Position=0,
            ParameterSetName='Pipeline', 
            Mandatory=$true,
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [object] $Object
    )

    begin {
        Write-Debug ("{0} ParameterSetName: {1}" -f $MyInvocation.MyCommand, $PSCmdlet.ParameterSetName)
    }

    process {
        $ts = $(Get-Date -format "s")
        if ($PSCmdlet.ParameterSetName -eq "Pipeline") {
            # Cast the object to a string. This is a handy way to collapse an object into one line for output to a file.
            $Message = [string] $Object
            switch ($Object.GetType().Name) {
                'String' {$Level = "Info"}

                'InformationRecord' {$Level = "Info"}

                'VerboseRecord' {
                    if ( $VerbosePreference -eq [System.Management.Automation.ActionPreference]::SilentlyContinue ) {                    
                        # Don't log verbose messages unless script is run with the verbose preference set
                        return
                    }
                    else {
                        $Level = "Verbose"
                    }
                }

                'WarningRecord' {$Level= "Warn"}

                'ErrorRecord' {$Level = "Error"}
                
                'DebugRecord' {$Level = "Debug"}
            }
        }

        $s = ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $ts, $Level, $Message, $Resource.ResourceType, $Resource.ResourceGroupName, $Resource.ResourceName)
        Write-Output $s
        Write-Output $s | Out-File -FilePath $script:log -Encoding utf8 -Append
        # Use the Get-PSCallStack cmdlet to determine the caller of this function
        $callStack = Get-PSCallStack
        # Don't call Out-AZTable if Out-AZTable was the caller to avoid a potential infinite loop if Out-AZTable fails
        if ( ($callStack[1].Command -ne 'Out-AZTable') -and ($script:table -ne $Null) ) {
           Out-AZTable -Level $Level -Message $Message -Resource $Resource -Schedule $Schedule -Action $Action
        }
    }

    end {
    }
}

function Out-AZTable {
    <#  
    .SYNOPSIS
        Writes output to a table in Azure Table Storage.
    .DESCRIPTION
        Writes output to a table in Azure Table Storage.
    .PARAMETER Message
        The string that will be output to the log file
    .PARAMETER Level
        One of: "Info", "Warn", "Error", "Verbose"
    .PARAMETER Resource
        One or more resource objects.
    .PARAMETER Schedule
        An object representing the parsed values of the RunSchedule tag
    .PARAMETER Action
        The action taken, if any. Defaults to "Log" if not specified.
    .NOTES    
        Requires that the $Script:table variable be set 
    .EXAMPLE
        Out-Log -Message "Test to write to table" -Level "Info"
    #>
    
    [CmdletBinding()]
    param (
        [Parameter (
            Position=0, 
            Mandatory=$true,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [string] $Message,
        [Parameter (
            Position=1, 
            Mandatory=$false,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [ValidateSet("Info", "Warn", "Error", "Verbose", "Debug")]
        [string] $Level = "Info",

        [Parameter(
            Position=2, 
            Mandatory=$false, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$true)
        ]
        [object] $Resource,

        [Parameter(
            Position=3, 
            Mandatory=$false, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Schedule,

        [Parameter (
            Position=4, 
            ParameterSetName='Standard', 
            Mandatory=$false,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False
        ) ]
        [string] $Action = "Log"        

    )

    if ($script:table -ne $null) {
        # Use the name of this script for the partition key
        $partitionKey = $scriptName
        # Use reverse ticks for the row key so we can get the most recent events using 'top' in the query
        $rowKey = "{0:D19}" -f ([System.DateTime]::MaxValue.Ticks - [System.DateTime]::UtcNow.Ticks)
        
        # Create a hash table of columns in the table
        <# #>
        $ht = @{
            Message = $Message
            Level = $Level
            Action = $Action
            RunEnvironment = $env:COMPUTERNAME
            Version = $script:Version
            AccountType = $script:AzureRMAccount.Context.Account.Type
            AccountId = $script:AzureRMAccount.Context.Account.Id
            SubscriptionId = $script:SubscriptionId
            ResourceType = $Resource.ResourceType
            ResourceGroupName = $Resource.ResourceGroupName
            ResourceName = $Resource.ResourceName
            Enabled = $Schedule.Enabled
            AutoStart = $Schedule.AutoStart
            StartHourUTC = $Schedule.StartHourUTC
            RunHours = $Schedule.RunHours
            RunDays = $Schedule.RunDaysList
            IsInSchedule = $Schedule.IsInSchedule
            # RunDaysList = $Schedule.RunDaysList
        }

        <# 
            Azure Storage Tables do not support null values. 
            This loop ensures there are no null values in the hashtable. 
            Notice that a clone of the hashtable is enumerated.
            This avoids the 'Collection was modified; enumeration operation may not execute' error.
        #>
        foreach ($kvp in $ht.Clone().GetEnumerator()) {
            if ($kvp.Value -eq $null) {
                # Storage table can't accept null values. Set this value to a zero length string
                $ht.Set_Item($kvp.Key, "")
            }
        }

        try {
            $tableResult = Add-StorageTableRow -table $script:table -partitionKey $partitionKey -rowKey $rowKey -property $ht 
        }
        catch {
            $command = $_.InvocationInfo.MyCommand.Name        
            $ex = $_.Exception
            $m = ("{0} failed: {1}" -f $command, $ex.Message)
            Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
            Continue        
        }
        if ( ($tableResult -eq $null) -or ($tableResult.HttpStatusCode -ne 204) ) {
            # Write to output log directly without calling Out-Log in order to avoid an endless loop
            $m = ("Failed to write to Azure table {0}. HttpStatusCode: {1}" -f $script:table, $tableResult.HttpStatusCode)
            $ts = $(Get-Date -format "s")
            $s = ("{0}`t{1}`t{2}" -f $ts, "Error", $m)
            Write-Warning $s
            Write-Warning $s | Out-File -FilePath $script:log -Encoding utf8 -Append
        }
    }
}
function Send-ErrorMessage {
    <#  
    .SYNOPSIS
        Sends an email containing the error message
    .DESCRIPTION
        Sends an email containing the error message
    .NOTES    
        Requires that the $script:To, $script:SmtpServer, and $script:Domain variables be set by the calling script
    .EXAMPLE
        Send-ErrorMessage "Some error message to email"
    .PARAMETER errorMsg
        The error message that will be emailed
    #>
    
    [CmdletBinding()]
	param ( 
        [Parameter(	Position=0, 
            Mandatory=$true,
            ValueFromPipeline=$False,
            ValueFromPipelineByPropertyName=$False) ]
		[string] $Message
	)
	
	$m = ("Sending email message to {0} via SMTP server {1}. Message: {2}" -f $script:To, $script:SMTPServer, $Message)
    Out-Log -Level Error -Message $m
	try {
        $subject = $($scriptName + " script FAILED")
    	$body = @"
<font Face="Calibri">$scriptName failed!<br>Script Server: $env:Computername<br>Error Message: $Message</Font>
"@
        $MailMessage = @{
            To = $script:To 
            Subject = $subject 
            From = "$env:Computername@$script:Domain"
            Body = $body 
            SmtpServer = $script:SMTPServer
            BodyAsHtml = $True			
            Encoding = ([System.Text.Encoding]::UTF8) 
            Priority = "High"		
        }     
        Send-MailMessage @MailMessage -ErrorAction Stop
    } catch {
        $ErrorMessage = $_.Exception.Message
        Out-Log -Level Error -Message "System.Net.Mail.SmtpClient:SmtpClient: $ErrorMessage"
    }
}

function Read-Variables {
    <#
    .SYNOPSIS
        Reads the contents of a JSON file in the same directory as the script in order to set 
        script wide variables.   
    .DESCRIPTION
        Reads the contents of a JSON file in the same directory as the script in order to set 
        script wide variables. The JSON filename must be <script_basename>.json
    #>

    # Define the variables required by the script that must be set in the JSON document
    $RequiredVars = @("TenantId", "SubscriptionId", "CertificateThumbprint", "TableRGName", "TableSAName", "TableName", "FilterPath", "SMTPServer", "Domain", "To")

    # Loop through vars and remove them if they were previously set.
    foreach ($v in $RequiredVars) {
        if (Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
        }
    }

    $jsonFile = Join-Path $scriptDir ($scriptBaseName + ".json")
    if (-not (Test-Path $jsonFile) ) {
        $m = ("{0} not found." -f $jsonFile)
        Send-ErrorMessage -Message $m
        Throw $m
    }
    $json = Get-Content $jsonFile | ConvertFrom-Json
    foreach ($var in $json.Variables) {
        try {
            New-Variable -Name $var.Name -Value $var.Value -Scope Script -ErrorAction Stop
        }
        catch {
            Set-Variable -Name $var.Name -Value $var.Value -Scope Script
        }
    }

    # Check that all required vars are set
    foreach ($v in $RequiredVars) {
        if ((Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue) -eq $Null) {
            $m = ("The variable '{0}' is not defined in {1}." -f $v, $jsonFile)
            Send-ErrorMessage -Message $m
            Throw $m          
        }
    }
}

function Compare-Resource {
    <#
        .SYNOPSIS
            Compares the RunSchedule tag to the current date and time. 
        .DESCRIPTION
            Compares the RunSchedule tag to the current date and time. 
            This is used to determine if the resource is considered
            "in schedule" or out of schedule. The resource will
            be started or deallocated based to the RunSchedule and 
            current date and time.
        .PARAMETER Resource
            One or more resource objects.
    #>

    param(  
    [Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [object] $Resource
    ) 
    begin {
        # Executes once at the start of the pipeline
        $CurrentTimeUTC = (Get-Date).ToUniversalTime()
        [int] $CurrentDayUTC = $CurrentTimeUTC.DayOfWeek.ToString("d")
        [int] $CurrentHourUTC = $CurrentTimeUTC.Hour
        $CurrentHoursSinceSun = ($CurrentDayUTC * 24) + $CurrentHourUTC
    }

    process {
        # Executes for each pipeline object
        foreach ($res in $Resource) {
            # Write-Verbose ("Checking Resource ID {0} " -f $res.ResourceId) 4>&1 | Out-Log -Verbose
            $m = ("Checking Resource ID {0} " -f $res.ResourceId)
            Out-Log -Level Verbose -Message $m -Resource $Resource -Verbose
            # Get AzureRMResource which contains the tags of the resource
            # $Resource = Get-AzureRMResource -ResourceGroupName $res.ResourceGroupName -Name $res.Name
            # Get the tags on the resource
            $tags = $res.Tags
            if ($tags -eq $Null) {
                $m = ("There are no tags set for the resource {0}" -f $res.Name)
                Out-Log -Level Warn -Message $m -Resource $Resource
                Continue
            }

            # Check if the RunSchedule tag does not exists
            if (-not ($tags.ContainsKey($scriptTag))) {
                # The tag doesn't exist
                $m = ("The {0} tag is not set for the resource {1}" -f $scriptTag, $res.Name)
                Out-Log -Level Info -Message $m -Resource $Resource
                Continue
            }
            else {
                # The tag exists
                try {
                    $RunSchedule = $tags.$scriptTag | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $command = $_.InvocationInfo.MyCommand.Name        
                    $ex = $_.Exception
                    $m = ("{0} failed: {1}" -f $command, $ex.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource
                    Continue
                }
            }
            # Get the Owner tag if it exists
            if ($tags.ContainsKey("Owner") ) {
                $Owner = $tags.Owner
            }
        
           # If the schedule is disable log it
            if (-not ($RunSchedule.Enabled) ) {
                $m = ("{0} is not enabled for {1}. Skipping." -f $scriptTag, $res.Name)
                Out-Log -Level Info -Message $m -Resource $Resource
                Continue
            }
            # Enabled property must be true and three schedule tags must have values else resource is skipped
            if ( ($RunSchedule.Enabled) -and ($RunSchedule.StartHourUTC -ne $Null) -and ($RunSchedule.RunHours -ne $Null) -and ($RunSchedule.RunDays -ne $Null)) 
            {
                try 
                {
                    $StartHourUTC = [int] $RunSchedule.StartHourUTC
                } 
                catch 
                {
                    $m = ("Conversion of StartHourUTC tag failed for {0}. The error message was: {2}" -f $res.Name, $_.Exception.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource 
                    Continue
                }

                try 
                {
                    $RunHours = [int] $RunSchedule.RunHours
                } 
                catch 
                {
                    $m = ("Conversion of RunHours tag failed for {0}. The error message was: {2}" -f $res.Name, $_.Exception.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource
                    Continue
                }

                try 
                {
                    # Make an array of the runnable days that the resource is allowed to run. Split the string on any of these characters: , ; tab space
                    $RunDays = [System.DayOfWeek[]] $RunSchedule.RunDays
                    # Sort the RunDays because the script author has OCD
                    $RunDays = $RunDays | Sort-Object
                    $RunDaysList = [string]::Join(",", $RunDays)
                } 
                catch 
                {
                    $m = ("Conversion of RunDays tag failed for {0}. The error message was: {2}" -f $res.Name, $_.Exception.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource
                    Continue
                }

                if ( ($StartHourUTC -lt 0) -or ($StartHourUTC -gt 23) ) 
                {
                    $m = ("StartHour tag is: {0} for resource {1}. Valid values are 0-23 inclusive. The error message was: {2}." + $StartHourUTC, $res.Name, $_.Exception.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource
                    Continue
                }

                if ( ($RunHours -lt 0) -or ($RunHours -gt 24) ) 
                {
                    $m = ("RunHours tag is: {0} for resource {1}. Valid values are 0-24 inclusive. The error message was: {2}." + $StartHourUTC, $res.Name, $_.Exception.Message)
                    Out-Log -Level Warn -Message $m -Resource $Resource
                    Continue
                }
                # Ensure these values are initially false
                $IsInSchedule = $False
                $IsShutdownInNextHour = $False
                # Loop through the $RunDays
                foreach ($rd in $RunDays)
                {
                    $intDay = $rd.value__
                    # For this particular day this is the number of hours since Sunday at midnight that the StartHour occurs
                    $ThisDayStart = ($intDay * 24) + $StartHourUTC
                    # For this particular day this is the number of hours since Sunday at midnight that the schedule end (i.e. StartHour + RunningHours)
                    $ThisDayEnd = $ThisDayStart + $RunHours
                    # This checks if the current hour is within the schedule for this particular day
                    if (($CurrentHoursSinceSun -ge $ThisDayStart) -and ($CurrentHoursSinceSun -lt $ThisDayEnd))
                    {
                        $IsInSchedule = $True
                        if ($ThisDayEnd - $CurrentHoursSinceSun -eq 1) {
                            # If the resource will be shutdown in the next hour, set the $IsShutdownInNextHour to $True
                            $IsShutdownInNextHour = $True
                        }
                        # Break out of the foreach loop since the VM is "in schedule"
                        Break
                    }
                    # This is the case where we wrap around on Sunday at midnight which is both hour 0 and hour 168
                    if ($ThisDayEnd -gt 167)
                    {
                        # Get hours after 168
                        $HoursAfterMidnightSun = $ThisDayEnd - 168
                        if ($CurrentHoursSinceSun -lt $HoursAfterMidnightSun) 
                        {
                            $IsInSchedule = $True
                            if ($HoursAfterMidnightSun - $CurrentHoursSinceSun -eq 1) {
                                # If the resource will be shutdown in the next hour, set the $IsShutdownInNextHour to $True
                                $IsShutdownInNextHour = $True
                            }
                        }
                    }
                }
                # Create a new object of RunSchedule values to pass to the Get-*Status functions
                $Schedule = New-Object PSObject -Property @{
                    Enabled = $RunSchedule.Enabled
                    AutoStart = $RunSchedule.AutoStart                    
                    IsInSchedule = $IsInSchedule
                    StartHourUTC = $StartHourUTC
                    RunHours = $RunHours
                    RunDays = $RunDays
                    RunDaysList = $RunDaysList
                    Owner = $Owner
                    IsShutdownInNextHour = $IsShutdownInNextHour
                }

                switch ($res.ResourceType){

                    "Microsoft.Compute/virtualMachines" {
                        Get-VMStatus -Resource $res -Schedule $Schedule
                    }
                    
                    "Microsoft.Sql/servers/databases" {
                        Get-DBStatus -Resource $res -Schedule $Schedule
                    }
                    
                    "Microsoft.AnalysisServices/servers" {
                        Get-ASStatus -Resource $res -Schedule $Schedule
                    }
                }
            }
        }
    }
    end {
        Write-Debug ("{0}: Finished processing the resource pipeline" -f $MyInvocation.MyCommand)
    }

} 

function Get-VMStatus {
    <#
    .SYNOPSIS
        Checks the current status of a virtual machine and starts or stops based on whether it is currently "in schedule"
    .DESCRIPTION
        Checks the current status of a virtual machine and starts or stops based on whether it is currently "in schedule"
    .PARAMETER Resource
        An Azure RM resource object of resource type "Microsoft.Compute/virtualMachines"
    .PARAMETER Schedule
        An object representing the parsed values of the RunSchedule tag
    .EXAMPLE
        Get-VMStatus -Resource $Resource -Schedule $Schedule
    #>
    param(  
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Resource,
        [Parameter(
            Position=1, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Schedule
    )
    
    # Get VM Status
    try {
        $VM = Get-AzureRmVM -ResourceGroupName $Resource.ResourceGroupName -Name $Resource.Name -Status -WarningAction SilentlyContinue
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message) 
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
        continue
    }
    $status = ($VM.Statuses | Where-object {$_.Code -like "PowerState/*"} | Select-Object -First 1) 
    if ($status -eq $null) {
        $m = ("Error: Unable to determine the status of {0}" -f $Resource.Name)
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
    }
    else {
        $state = $status.Code.Split("/")[1]
    }

    if ( $Schedule.IsInSchedule ) {
        if  ( $state -ine "running") {
            # Check if AutoStart tag is True
            if ($Schedule.AutoStart) {
                $m = ("Starting resource {0}. StartHourUTC is {1}. RunHours is {2}. RunDays is: [{3}]" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList)
                Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Start"
                Set-ResourceState -Subscription $script:SubscriptionId -Action "Start" -Resource $Resource *>&1 | Out-Log
            }
            else {
                $m =  ("{0} is in schedule but AutoStart is false. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
                # Write-Verbose $m 4>&1 | Out-Log
                Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
            }
        } else {
            $m = ("{0} should be running. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
            # Send direct Slack message if the resource will be shutdown in the next hour. 
            if ($Schedule.IsShutdownInNextHour) {
                Write-Debug "Shutdown is imminent"
            }
        }
    } else {
        if  ( ($state -ieq "running") -or ($state -ieq "starting") ) {
            $m = ("Deallocating {0}. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Stop"
            Set-ResourceState -Subscription $script:SubscriptionId -Action "Stop" -Resource $Resource *>&1 | Out-Log
        } else {
            $m = ("{0} should be stopped. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
        }
    }    
}

function Get-DBStatus {
    <#
    .SYNOPSIS
        Checks the current status of a SQL Database and resumes or pauses it based on whether it is currently "in schedule"
    .DESCRIPTION
        Checks the current status of a SQL Database and resumes or pauses it based on whether it is currently "in schedule"
    .PARAMETER Resource
        An Azure RM resource object of resource type "Microsoft.Sql/servers/databases"
    .PARAMETER Schedule
        An object representing the parsed values of the RunSchedule tag
    .EXAMPLE
        Get-VMStatus -Resource $Resource -Schedule $Schedule
    #>
    param(  
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Resource,
        [Parameter(
            Position=1, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Schedule
    )
    
    # Get SQL database Status
    $Name = $Resource.Name.Split("/")
    $params = @{
        ResourceGroupName = $Resource.ResourceGroupName
        ServerName = $Name[0]
        DatabaseName = $Name[1]
    }
    try {
        $db = Get-AzureRmSqlDatabase @params
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message)
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
        continue
    }

    # Valid status values are: Paused -> Resuming -> Online -> Pausing -> Paused -> ...   
    $status = $db.Status
    if ($status -eq $null) {
        $m = ("Error: Unable to determine the status of {0}" -f $Resource.Name)
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
        return
    }

    if ( $Schedule.IsInSchedule ) {
        if  ( $status -ine "Online") {
            # Check if AutoStart tag is True
            if ($Schedule.AutoStart) {
                $m = ("Resuming resource {0}. StartHourUTC is {1}. RunHours is {2}. RunDays is: [{3}]" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList)
                Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Start"
                Set-ResourceState -Subscription $script:SubscriptionId -Action "Start" -Resource $Resource *>&1 | Out-Log
            }
            else {
                $m =  ("{0} is in schedule but AutoStart is false. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
                # Write-Verbose $m 4>&1 | Out-Log
                Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
            }
        } else {
            $m = ("{0} should be running. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
        }
    } else {
        if ( ($status -ieq "Online") -or ($status -ieq "Resuming") ) {
            $m = ("Pausing {0}. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Stop"
            Set-ResourceState -Subscription $script:SubscriptionId -Action "Stop" -Resource $Resource *>&1 | Out-Log
        } else {
            $m = ("{0} should be paused. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
        }
    }    
}

function Get-ASStatus {
    <#
    .SYNOPSIS
        Checks the current status of an Analysis Services server and resumes or pauses it based on whether it is currently "in schedule"
    .DESCRIPTION
        Checks the current status of a Analysis Services server and resumes or pauses it based on whether it is currently "in schedule"
    .PARAMETER Resource
        An Azure RM resource object of resource type "Microsoft.AnalysisServices/servers"
    .PARAMETER Schedule
        An object representing the parsed values of the RunSchedule tag
    .EXAMPLE
        Get-VMStatus -Resource $Resource -Schedule $Schedule
    #>
    param(  
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Resource,
        [Parameter(
            Position=1, 
            Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)
        ]
        [object] $Schedule
    )
    
    # Get Analysis Services server Status
    try {
        $as = Get-AzureRmAnalysisServicesServer $Resource.ResourceGroupName $Resource.Name
    }
    catch {
        $command = $_.InvocationInfo.MyCommand.Name        
        $ex = $_.Exception
        $m = ("{0} failed: {1}" -f $command, $ex.Message)
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
        continue
    }

    # Valid states are: Paused -> Resuming -> Succeeded -> Pausing -> Paused -> ...
    $state = $as.State
    if ($state -eq $null) {
        $m = ("Error: Unable to determine the status of {0}" -f $Resource.Name)
        Out-Log -Level Warn -Message $m -Resource $Resource -Schedule $Schedule
        return
    }

    if ( $Schedule.IsInSchedule ) {
        if  ( $state -ine "Succeeded") {
            # Check if AutoStart tag is True
            if ($Schedule.AutoStart) {
                $m = ("Resuming resource {0}. StartHourUTC is {1}. RunHours is {2}. RunDays is: [{3}]" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList)
                Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Start"
                Set-ResourceState -Subscription $script:SubscriptionId -Action "Start" -Resource $Resource *>&1 | Out-Log
            }
            else {
                $m =  ("{0} is in schedule but AutoStart is false. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
                # Write-Verbose $m 4>&1 | Out-Log
                Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
            }
        } else {
            $m = ("{0} should be running. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
        }
    } else {
        if ( ($state -ieq "Succeeded") -or ($state -ieq "Resuming") ) {
            $m = ("Pausing {0}. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            Out-Log -Level Info -Message $m -Resource $Resource -Schedule $Schedule -Action "Stop"
            Set-ResourceState -Subscription $script:SubscriptionId -Action "Stop" -Resource $Resource *>&1 | Out-Log
        } else {
            $m = ("{0} should be paused. StartHourUTC: {1}. RunHours: {2}. RunDays: [{3}]. Current state: {4}" -f $Resource.Name, $Schedule.StartHourUTC, $Schedule.RunHours, $Schedule.RunDaysList, $state)
            # Write-Verbose $m 4>&1 | Out-Log
            Out-Log -Level Verbose -Message $m -Resource $Resource -Schedule $Schedule -Verbose
        }
    }    
}

# **** Script Body ****
# Log verbose messages
$VerbosePreference = "Continue"

# The version number of the ARMRunSchedule script module. This will be logged as the version in the Azure Table
$Version = (Get-Module -Name ARMRunSchedule).Version.ToString()

# This is the tag that this script will get from the resource
$scriptTag = "RunSchedule"

# Make sure table variable is not set when script starts
$table = $null


# Get this script
$ThisScript = $Script:MyInvocation.MyCommand
# Get the directory of this script
$scriptDir = Split-Path $ThisScript.Path -Parent
# Get the script file
$scriptFile = Get-Item $ThisScript.Path
# Get the name of this script
$scriptName = $scriptFile.Name
# Get the name of the script less the extension
$scriptBaseName = $scriptFile.BaseName

# Define folder where log files are written
$logDir = Join-Path $scriptDir "Logs"

if ((Test-Path $logDir) -eq $FALSE) {
    New-Item $logDir -type directory | Out-Null
}

# The new logfile will be created every day
$logdate = get-date -format "yyyy-MM-dd"
$log = Join-Path $logDir ($scriptBaseName +"_" + $logdate + ".log")
Write-Output "Log file: $log"

Out-Log -Level Info -Message ("{0} script started on {1}" -f $scriptName, $env:COMPUTERNAME)

# Read the script variables from a json file in the same directory as the script
Read-Variables

# Write-Verbose ("TenantId: {0}" -f $TenantId) 4>&1 | Out-Log
$m = ("TenantId: {0}" -f $TenantId)
Out-Log -Level Verbose -Message $m -Verbose

# Sign into AzureRM using certificate of Service Principal
$paramsCred = @{
    ServicePrincipal = $True
    Tenant = $TenantId
    SubscriptionId = $SubscriptionId
    ApplicationId = $ApplicationId
    CertificateThumbprint = $CertificateThumbprint
}
$AzureRMAccount = Add-AzureRMAccount @paramsCred

If ($AzureRMAccount -eq $null) { 
    $m = ("Error! The account failed to sign into AzureRM. The account was {0}" -f $ApplicationId)
    Send-ErrorMessage -Message $m
    Throw $m
}
else {
    # Get the Azure table if the vars exist
    if ( ($TableName -ne $null) -and ($TableSAName -ne $null) -and ($TableRGName -ne $null) ) {
        $saContext = (Get-AzureRmStorageAccount -ResourceGroupName $TableRGName -Name $TableSAName).Context
        $table = Get-AzureStorageTable -Name $TableName -Context $saContext
    }
    
    if (-not (Test-Path $FilterPath) ) {
            $m = ("FilterPath '{0}' is invalid." -f $FilterPath)
            Send-ErrorMessage -Message $m
            Throw $m    
    } 
    else {
        Find-Resources -FilterPath $FilterPath -Action Get | Compare-Resource
    }        

    Wait-BackgroundJobs *>&1 | Out-Log
    
    # Remove the module. This is really handy when testing new versions.
    Remove-Module ARMRunSchedule

    ("{0} script completed on {1}" -f $scriptName, $env:COMPUTERNAME) | Out-Log 
}
