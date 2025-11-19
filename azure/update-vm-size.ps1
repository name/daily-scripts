param (
  [Parameter(Mandatory = $true)]
  [string]$VirtualMachineName,
  [Parameter(Mandatory = $true)]
  [string]$VMSize
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

foreach ($Subscription in Get-AzSubscription) {
  $AzureContext = Set-AzContext -Subscription $Subscription.Name -ErrorAction Stop

  foreach ($ResourceGroup in Get-AzResourceGroup) {
    $ResourceGroupName = $ResourceGroup.ResourceGroupName

    foreach ($VM in Get-AzVM -ResourceGroupName $ResourceGroupName) {
      $VMName = $VM.Name

      if ($VMName -eq $VirtualMachineName) {
        Write-Output "Found VM: $VMName in $ResourceGroupName"

        Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force -ErrorAction Continue

        $VM.HardwareProfile.VmSize = $VMSize
        Update-AzVM -ResourceGroupName $ResourceGroupName -VM $VM -ErrorAction Continue

        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Continue
      }
    }
  }
}

Write-Output "Resized $($VirtualMachineName) to $($VMSize) successfully."
