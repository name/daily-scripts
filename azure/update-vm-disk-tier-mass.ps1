param (
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionName
)

try {
  Disable-AzContextAutosave -Scope Process
  $AzureContext = (Connect-AzAccount -Identity -AccountId "REPLACE").context
  Write-Output "Authenticated as $($AzureContext.Account.Id)"
}
catch {
  Write-Error "Failed to authenticate: $_"
  exit
}

function Get-AppropriateSize {
  param (
    [int]$currentSize,
    [hashtable]$sizeMap
  )

  $next_size = $null
  foreach ($size in $sizeMap.GetEnumerator() | Sort-Object Value) {
    if ($currentSize -le $size.Value) {
      $next_size = $size.Value
      break
    }
  }
  return $next_size
}

$size_mapping = @{
  "Standard_LRS" = @{
    "S4"  = 32
    "S6"  = 64
    "S10" = 128
    "S15" = 256
    "S20" = 512
    "S30" = 1024
    "S40" = 2048
    "S50" = 4095
  }
}

$change_records = @()

foreach ($Subscription in Get-AzSubscription) {
  $AzureContext = Set-AzContext -Subscription $Subscription.Name -ErrorAction Stop

  if ($Subscription.Name -eq $SubscriptionName) {
    Write-Output "Processing subscription: $($Subscription.Name)"
    foreach ($ResourceGroup in Get-AzResourceGroup) {
      $ResourceGroupName = $ResourceGroup.ResourceGroupName

      foreach ($VM in Get-AzVM -ResourceGroupName $ResourceGroupName) {
        $VMName = $VM.Name

        Write-Output "Found VM: $VMName in $ResourceGroupName"

        $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status
        $powerState = $vmStatus.Statuses[1].Code

        if ($powerState -ne "PowerState/deallocated") {
          Write-Output "Stopping VM: $VMName in $ResourceGroupName"
          Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force
        }
        else {
          Write-Output "VM: $VMName is already deallocated. Skipping stop."
        }

        $osDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $VM.StorageProfile.OsDisk.Name
        $current_tier = $osDisk.Sku.Name
        $current_size = $osDisk.DiskSizeGB

        Write-Output "Current OS Disk - Name: $($osDisk.Name), Size: $current_size GiB, Tier: $current_tier"

        $new_tier = "Standard_LRS"
        $appropriate_size = Get-AppropriateSize -currentSize $current_size -sizeMap $size_mapping[$new_tier]

        $needs_update = $false
        if ($current_tier -ne $new_tier) {
          Write-Output "Changing OS disk $($osDisk.Name) to $new_tier..."
          $osDisk.Sku.Name = $new_tier
          $needs_update = $true
        }

        if ($appropriate_size -and $current_size -ne $appropriate_size) {
          Write-Output "Resizing OS Disk to: $appropriate_size GiB"
          $osDisk.DiskSizeGB = $appropriate_size
          $needs_update = $true
        }
        else {
          Write-Output "No resizing needed for OS Disk $($osDisk.Name). Current size: $current_size GiB"
        }

        if ($needs_update) {
          $change_records += [PSCustomObject]@{
            SubscriptionName = $Subscription.Name
            VM               = $VMName
            Disk             = $osDisk.Name
            PrevSize         = $current_size
            NewSize          = $appropriate_size
            PrevTier         = $current_tier
            NewTier          = $new_tier
          }
          Update-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $osDisk.Name -Disk $osDisk
        }

        foreach ($dataDisk in $VM.StorageProfile.DataDisks) {
          $disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name
          $current_tier = $disk.Sku.Name
          $current_size = $disk.DiskSizeGB

          Write-Output "Current Data Disk - Name: $($disk.Name), Size: $current_size GiB, Tier: $current_tier"

          $new_tier = "Standard_LRS"
          $appropriate_size = Get-AppropriateSize -currentSize $current_size -sizeMap $size_mapping[$new_tier]

          $needs_update = $false
          if ($current_tier -ne $new_tier) {
            $disk.Sku.Name = $new_tier
            $needs_update = $true
          }

          if ($appropriate_size -and $current_size -ne $appropriate_size) {
            Write-Output "Resizing Data Disk to: $appropriate_size GiB"
            $disk.DiskSizeGB = $appropriate_size
            $needs_update = $true
          }

          if ($needs_update) {
            $change_records += [PSCustomObject]@{
              SubscriptionName = $Subscription.Name
              VM               = $VMName
              Disk             = $disk.Name
              PrevSize         = $current_size
              NewSize          = $appropriate_size
              PrevTier         = $current_tier
              NewTier          = $new_tier
            }
            Update-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $disk.Name -Disk $disk
          }
        }

        if ($powerState -ne "PowerState/deallocated") {
          Write-Output "Starting VM: $VMName in $ResourceGroupName"
          Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        }
        else {
          Write-Output "VM: $VMName remains deallocated."
        }
      }
    }
  }
}

Write-Output "Changes made:"
$change_records | Format-Table -AutoSize

Write-Output "VM resizing completed"
