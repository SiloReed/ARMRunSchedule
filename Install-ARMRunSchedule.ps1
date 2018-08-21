<#
.SYNOPSIS
    Installs the ARMRunSchedule module in the ProgramFiles directory
.DESCRIPTION
    Installs the ARMRunSchedule module in the ProgramFiles directory
.EXAMPLE
    .\Install-ARMRunSchedule.ps1
#>

#Requires -RunAsAdministrator

# Get the directory of this script
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

$ModulesDir = Join-Path $env:ProgramFiles "\WindowsPowerShell\Modules"

if (-not (Test-Path $ModulesDir) ) {
    Throw ("{0} does not exist!" -f $ModulesDir)
}

$ModulesPath = $env:PSModulePath.Split(";")
if ($ModulesPath -notcontains $ModulesDir) {
    # Try with a trailing backslash
    $ModulesDir = $ModulesDir + "\"
    if ($ModulesPath -notcontains $ModulesDir) {
        Throw ("The `$env:PSModulePath does not contain {0}" -f $ModulesDir)
    }
}

$SourceFiles = @()
$Files = @("ARMRunSchedule.psd1", "ARMRunSchedule.psm1")
foreach ($f in $Files) {
    $filePath = (Join-Path $ScriptDir $f)
    if (Test-Path (Join-Path $ScriptDir $f) ) {
        $SourceFiles += (Join-Path $ScriptDir $f)
    }
    else {
        Throw ("{0} does not exist!" -f $filePath)
    }
}

$content = Import-PowerShellDataFile $SourceFiles[0]

$RunScheduleDir = Join-Path $ModulesDir "ARMRunSchedule"
if (-not (Test-Path $RunScheduleDir) ) {
    New-Item -Path "$RunScheduleDir" -ItemType Directory
}

$VersionDir = Join-Path $RunScheduleDir $($content.ModuleVersion)
if (-not (Test-Path $VersionDir) ) {
    New-Item -Path "$VersionDir" -ItemType Directory
}

foreach ($f in $SourceFiles) {
    $file = Copy-Item -Path $f -Destination $VersionDir -Force -PassThru
    Write-Output ("Installed: {0}" -f $file.FullName)
}
