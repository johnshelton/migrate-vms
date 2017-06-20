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
  [string] $VMName= $(throw "-VM Name is required."),
  [string] $SourceVCenterServers = $(throw "-Source VCenter Server is required"),
  [string] $TargetVCenterServers = $(throw "-Target VCenter Server is required"),
  [string] $TargetResourcePool = $(throw "-Target VM Resource Pool is required")
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
# $SourceVCenterServers = "TST-VMVC-01.wfm.wegmans.com"
# $TargetVCenterServers = "TST-VCSA-01.test.wfm.local"
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
Connect-VIServer $SourceVCenterServers
Connect-VIServer $TargetVCenterServers
Clear-Host
$OutputFile = $path + $FileName + '_' + $VMName + '_' + $ExecutionStamp + $FileExt
$VM = Get-VM -Name $VMName -Server $SourceVCenterServers
If (!$VM) {Write-Host "VM $VMName not found.  Exiting Script"; Exit}
$VMXPath = $VM.ExtensionData.Config.Files.VmPathName
$VMNetworkInfo = Get-NetworkAdapter -VM $VMName -Server $SourceVCenterServers
Write-Host "Captured the Network Info for $VMName `n $VMNetworkInfo"
$VMPowerState = (Get-VM -Name $VMName -Server $SourceVCenterServers | Select PowerState).PowerState
If ($VMPowerState -ne "PoweredOff"){
  $Response = Read-Host "$VMName is currently running.  Are you sure you want to proceed with a shutdown and migration (Y/N)?"
  If ($Response -ne "Y" -or $Response -ne "y") {Exit}
  Get-VM -Name $VMName -Server $SourceVCenterServers | Stop-VMGuest -Confirm:$false
  $i = 0
  While ($VMPowerState -ne "PoweredOff"){
    $VMPowerState = (Get-VM -Name $VMName -Server $SourceVCenterServers| Select PowerState).PowerState
    $i++
    Write-Host "Waiting for $VMName to shutdown down"
    If ($i > 10) {Write-Host "$VMName did not complete the shutdown in time.  Exiting the script."; Exit}
    Start-Sleep 30
  } 
}
Else {Write-Host "$VMName was already powered off.  Continuing Script"}
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
  Start-VM -VM $VMName -Server $TargetVCenterServers
  IF (!(Get-VMQuestion -VM $VMName -Server $TargetVCenterServers)) {Get-VM -Name $VMName -Server $TargetVCenterServers | Get-VMQuestion | Set-VMQuestion -Option "I moved it" -Confirm:$False}
  $VMNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$SourceVCenterServers"
  $VMNewNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$TargetVCenterServers"
}
Else {
  Write-Host "Old Networks and New Networks do not match.  Manual intervention is needed."
  $VMNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$SourceVCenterServers"
  $VMNewNetworkInfo | Export-Excel -Path $OutputFile -WorkSheetname "$TargetVCenterServers"
}