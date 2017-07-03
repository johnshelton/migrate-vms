<#
=======================================================================================
File Name: migrate-vms.ps1
Created on: 2017-06-16
Created with VSCode
Version 1.0
Last Updated: 
Last Updated by: John Shelton | c: 260-410-1200 | e: john.shelton@wegmans.com

Purpose: Migrate a VM from One VCenter Environment to another by removing from Inventory
and then importing it back in.

Notes: 

Change Log:


=======================================================================================
#>
#
# Define Parameter(s)
#
param (
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
  [string] $VMName= $(throw "-VM Name is required.")
  #[string] $SourceVCenterServers = $(throw "-Source VCenter Server is required"),
  #[string] $TargetVCenterServers = $(throw "-Target VCenter Server is required"),
  #[string] $TargetResourcePool = $(throw "-Target VM Resource Pool is required")
)
#
# Check if VMWare Module is installed and if not install it
#
$VMWareModuleInstalledLoop = 0
While ($VMWareModuleInstalledLoop -lt "4" -and $VMWareModuleInstalled -ne $True) {
  $VMWareModuleInstalled = Get-InstalledModule -Name VMWare*
  If ($VMWareModuleInstalled) {Write-Host "VMWare Module Installed.  Continuing Script."; $VMWareModuleInstalled = $True} Else {Install-Module "VMWare.powercli" -Scope AllUsers -Force -AllowClobber; $VMWareModuleInstalled = $False }
  $VMWareModuleInstalledLoop ++
  If ($VMWareModuleInstalledLoop -ge "4") {Write-host "VMWare Module is not installed and the auto installation failed. Manual intervention is needed"; Exit}
}
#
# Define Variables
#
$SourceVCenterServers = "TST-VMVC-01.wfm.wegmans.com"
$TargetVCenterServers = "TST-VCSA-01.test.wfm.local"
# $TargetResourcePool = "Resources"
$TargetResourcePool = ""
$ExecutionStamp = Get-Date -Format yyyyMMdd_HH-mm-ss
#
# Define Output Paths
#
$path = "c:\temp\migrate-vms\"
$FullFileName = $MyInvocation.MyCommand.Name
$FileName = $FullFilename.Substring(0, $FullFilename.LastIndexOf('.'))
$FileExt = '.xlsx'
$PathExists = Test-Path $path
IF($PathExists -eq $False)
  {
  New-Item -Path $path -ItemType  Directory
  }
#
$Loop = 0
Connect-VIServer $SourceVCenterServers
Connect-VIServer $TargetVCenterServers
Clear-Host
# Future addition to prompt for resource pool
$AvailableTargetResourcePools = Get-ResourcePool -Server $TargetVCenterServers
$AvailableTargetNetworks = Get-VirtualPortGroup -Server $TargetVCenterServers
While ($AvailableTargetResourcePools.name -notcontains $TargetResourcePool -and $Loop -lt 6){
  $Loop ++
  #Write-Host "" target resource pool specified " $TargetResourcePool "was not found."
  Write-Host "Please choose the Target Resource Pool from the following list:"
  $ChoiceLoop = 0
  ForEach ($AvailableTargetResourcePool in $AvailableTargetResourcePools) {
    Write-Host "     "$ChoiceLoop ":" $AvailableTargetResourcePool
    $ChoiceLoop ++
  }
  Write-Host ""
  $TargetResourcePoolID = Read-Host "Please enter the number of the Target Resource Pool from above"
  $TargetResourcePool = $AvailableTargetResourcePools[$TargetResourcePoolID]
  If ($Loop -eq 5) {Write-Host "The Resource Pool choosen is still not valid and the max retires has been reached"; Exit}
}

$OutputFile = $path + $FileName + '_' + $VMName + '_' + $ExecutionStamp + $FileExt
$VM = Get-VM -Name $VMName -Server $SourceVCenterServers
If (!$VM) {Write-Host "VM $VMName not found.  Exiting Script"; Exit}
$VMXPath = $VM.ExtensionData.Config.Files.VmPathName
Write-Host "The VM config file is located at" $VMXPath
$VMNetworkInfo = Get-NetworkAdapter -VM $VMName -Server $SourceVCenterServers
Write-Host "Captured the Network Info for $VMName The virtual machine has" $VMNetworkInfo.count "network(s)."
$VMPowerState = (Get-VM -Name $VMName -Server $SourceVCenterServers | Select PowerState).PowerState
#
# Check if all the source network names are available on the target environment
#
$Failed = "No"
ForEach ($TempVMNetworkInfo in $VMNetworkInfo){
  If($AvailableTargetNetworks.Name -notcontains $TempVMNetworkInfo.NetworkName) {
    Write-Host "$VMName is connected to "$TempVMNetworkInfo.NetworkName "but that network is not found on" $TargetVCenterServers
    Write-Host "Please add the network" $TempVMNetworkInfo.NetworkName "to" $TargetVCenterServers -ForegroundColor Yellow
    $Failed = "Yes"
  }
  Else{
    Write-Host $VMName "is connected to "$TempVMNetworkInfo.NetworkName "which is available on" $TargetVCenterServers
  }
}
IF ($Failed -eq "Yes") {
  Write-Host "Not all of the networks for" $VMName "are available on" $TargetVCenterServers " Please add the networks and try again." -ForegroundColor Red
  Write-Host "Exiting the script."
  Exit
}
#
If ($VMPowerState -ne "PoweredOff"){
  $Response = Read-Host "$VMName is currently running.  Are you sure you want to proceed with a shutdown and migration (Y/N)?"
  If ($Response -ne "Y" -or $Response -ne "y") {Exit}
  Get-VM -Name $VMName -Server $SourceVCenterServers | Stop-VMGuest -Confirm:$false
  $i = 0
  While ($VMPowerState -ne "PoweredOff"){
    $VMPowerState = (Get-VM -Name $VMName -Server $SourceVCenterServers| Select PowerState).PowerState
    $i++
    Write-Host "Waiting for $VMName to shutdown"
    If ($i > 10) {Write-Host "$VMName did not complete the shutdown in time.  Exiting the script."; Exit}
    Start-Sleep 30
  } 
}
Else {Write-Host "$VMName is powered off.  Continuing Script"}
Remove-VM -VM $VMName -Server $SourceVCenterServers -Confirm:$false
Write-Host "Removed $VMName from inventory on $SourceVCenterServers"
# Disconnect-VIServer $SourceVCenterServers
New-VM -VMFilePath $VMXPath -Server $TargetVCenterServers -ResourcePool $TargetResourcePool
IF (!(Get-VM $VMName -Server $TargetVCenterServers)) {Write-Host "Added $VMName to $TargetVCenterServers"}
Else {Write-Host "Error adding $VMName to $TargetVCenters"}
ForEach ($VMNic in $VMNetworkInfo) {
  Get-VM -Name $VMName -Server $TargetVCenterServers | Get-NetworkAdapter | Where {$_.Name -like $VMNic.Name} | Set-NetworkAdapter -NetworkName ($VMNic.NetworkName) -Confirm:$false
  $VMNewNetworkInfo = Get-NetworkAdapter -VM $VMName -Server $TargetVCenterServers
  Write-Host "$VMName - " $VMNic.Name " is now connected to "$VMNewNetworkInfo.Name
}
IF($VMNetworkInfo.NetworkName -eq $VMNewNetworkInfo.NetworkName -and $VMNetworkInfo.Type -eq $VMNewNetworkInfo.Type -and $VMNetworkInfo.MacAddress -eq $VMNewNetworkInfo.MacAddress ) {
  Write-Host "Old Network and New Network match."
  Start-VM -VM $VMName -Server $TargetVCenterServers -Confirm:$False
  Start-Sleep -Seconds 5
  IF ((Get-VMQuestion -VM $VMName -Server $TargetVCenterServers)) {Get-VM -Name $VMName -Server $TargetVCenterServers | Get-VMQuestion -Server $TargetVCenterServers | Set-VMQuestion -Option "I Moved It" -Confirm:$False}
  Start-Sleep -Seconds 15
  $Loop = 0
  While(((Get-VM -Name $VMName -Server $TargetVCenterServers).PowerState) -ne "PoweredOn" -and $Loop -lt 10) {
    Write-Host $VMName "is not powering on.  Attempting to resolve by answering question with I Moved It." -ForegroundColor Yellow
    IF ((Get-VMQuestion -VM $VMName -Server $TargetVCenterServers)) {Get-VM -Name $VMName -Server $TargetVCenterServers | Get-VMQuestion | Set-VMQuestion -Option "I Moved It" -Confirm:$False}
    $Loop ++
    Start-Sleep -Seconds 10
  }
  $VMNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$SourceVCenterServers"
  $VMNewNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$TargetVCenterServers"
  $VMXPath | Export-Excel -Path $OutputFile -WorkSheetname "VMFile"
  IF(((Get-VM -Name $VMName -Server $TargetVCenterServers).PowerState) -ne "PoweredOn") {
    Write-Host "VM Migration completed however there seems to have been an error powering the VM on.  Please verify that VM is up and healthy." -ForegroundColor Yellow
    Write-Host "The log file can be found at" $OutputFile -ForegroundColor Yellow
    Write-host "Please examine the tabs to see the begining and ending information as well as the path to the VM file"  -ForegroundColor Yellow
  }
  Else {
    Write-Host "VM Migration completed.  Please verify that VM is up and healthy."
    Write-Host "The log file can be found at" $OutputFile
    Write-host "Please examine the tabs to see the begining and ending information as well as the path to the VM file"
  }
}
Else {
  Write-Host "Migration of VM failed" -ForegroundColor Red
  Write-Host "Old Networks and New Networks do not match.  Manual intervention is needed." -ForegroundColor Red
  $VMNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$SourceVCenterServers"
  $VMNewNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$TargetVCenterServers"
  $VMXPath | Export-Excel -Path $OutputFile -WorkSheetname "VMFile"
  Write-Host "The log file can be found at" $OutputFile -ForegroundColor Red
  Write-host "Please examine the tabs to see the begining and ending information as well as the path to the VM file" -ForegroundColor Red
}