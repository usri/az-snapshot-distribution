<#
.NOTES
    Daniel Hibbert - March 2020
    Version 0.1

    Microsoft Azure - create-snapshotMD.ps1

    THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY
    KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
    PARTICULAR PURPOSE.

.DESCRIPTION

    This script will automate the process of creating a snapshot of a managed data disk
    attached to a Source VM, and created and attach a new managed disk on the target vm(s) 

    If a data disk exists on the target VM with the same LUN assisgment as the source the
    existing data disk will be detached and replaced with the new data disk. 

.PARAMETER sourceVM

    [string] Source VM for creating managed disk snapshot

.PARAMETER targetVMs

    [array] List of VMs to attach the new disk(s)

.EXAMPLE
       
       create-snashotMD.ps1 -sourceVM VM01 -snapshotResourceGroupName rg-snapshotstorage
#>
param (

    [parameter(position=0, mandatory=$true)][string]$sourceVm,
    [parameter(position=1, mandatory=$true)][string]$snapshotResourceGroupName
)

Clear-Host


try {
    $result = Get-AzContext -ErrorAction Stop
    if (-not $result.Environment) {
        throw"Please login (Login-AzureRmAccount) and set the proper subscription context before proceeding."
    }

}
catch {
    throw "Please login and set the proper subscription context before proceeding."
}



# Global Variables
try {
    # Validate: VM Exists
    $vmConfig = Get-AzVM -Name $sourceVm -ErrorAction Stop
    if (!$vmConfig.id){
        throw "Unable to find specified VM"
    }

    # Validate: Resource Group Exists
    $rgSnapshotStore = Get-AzResourceGroup -Name $snapshotResourceGroupName
    if (!$rgSnapshotStore.Id){
        throw "Unable to find Resource Group"
    }
}
catch {
    throw "Invalid parameters"
    $_
}

$createdSnapshots = @()
$configVar = New-Object psobject -Property @{
    sourceVM = $vmConfig.Name
    disks = $vmConfig.StorageProfile.DataDisks
    targetDataDisk = @()
    location = $vmConfig.location
}

# Check for multipule data disks on source VM
if ($configVar.disks.count -gt 1){

    # Generate menu to select data disk for snapshot
    write-host -ForegroundColor yellow "`nFound multiple data disks. [Comma seperate for multipule selection]`n"
    [int]$listitr =1
    $configVar.disks | ForEach-Object {
        write-host "[$listitr] - "$_.name
        $listitr++
    }
    [string]$mdResponse = $(Read-Host -Prompt "Select data disk")
    $mdResponse.split(',') | foreach-object {
        $configVar.targetDataDisk += $configVar.disks[$($_ -1)]
    }
}

clear-host

##Create_data_disk_snapshot
$configVar.targetDataDisk | ForEach-Object {
    
    # Create Snapshot Configuration
    $mdSnapshotName = $_.name + "-snap-" + $(get-date -Format MMddyyyy-mmhhss)
    $mdCondfig = Get-AzDisk -Name $_.Name

    $mdSnapshot = New-AzSnapshotConfig `
        -SourceUri $mdCondfig.Id `
        -location $configVar.location `
        -createOption copy `
        -Tag @{
            "LUN" = $($_.LUN).tostring()
            "SourceVM" = $configVar.sourceVM
            "diskSizeGB" = $($_.DiskSizeGB).tostring()
            "diskSKU" = $mdCondfig.Sku.Name
        }

    # Create Data Disk Snapshot
    try {

        write-host -ForegroundColor green -NoNewline "[Step 1] - Creating Data Disk Snapshot"

        $createdSnapshots += (
        New-AzSnapshot -Snapshot $mdSnapshot `
            -SnapshotName $mdSnapshotName `
            -ResourceGroupName $snapshotResourceGroupName
        )
        write-host -ForegroundColor Yellow "...Completed!"
        write-host -ForegroundColor green "`tSnapshot Name: $mdSnapshotName`n"
    }
    catch {
        Write-Host -ForegroundColor red "...Failed!!!`n"    
        write-host -ForegroundColor red $_
    }
}