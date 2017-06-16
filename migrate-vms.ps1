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
  [string] $VMName= $(throw "-VMName is required.")
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
#
Connect-VIServer $SourceVCenterServers
Connect-VIServer $TargetVCenterServers
$VM = Get-VM -Server $SourceVCenterServers -Name $VMName
$VMXPath = $VM.ExtensionData.Config.Files.VmPathName
$VMNetworkInfo = Get-NetworkAdapter -VM $VMName -Server $SourceVCenterServers
Shutdown-VMGuest -Server $SourceVCenterServers -VM $VMName
Remove-VM -VM $VMName -Server $SourceVCenterServers
New-VM -VMFilePath $VMXPath -Server $TargetVCenterServers