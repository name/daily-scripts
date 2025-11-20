param (
    [string]$RG,
    [string]$VAULT
)

Write-Host "Fetching protected VMs from vault '$VAULT'..."
$vms = az backup item list `
    --resource-group $RG `
    --vault-name $VAULT `
    --backup-management-type AzureIaasVM `
    -o json | ConvertFrom-Json

Write-Host "Fetching all recent backup jobs for the vault..."
$allJobs = az backup job list `
    --resource-group $RG `
    --vault-name $VAULT `
    --backup-management-type AzureIaasVM `
    --operation Backup `
    --status Completed `
    -o json | ConvertFrom-Json

$results = foreach ($vm in $vms) {
    $vmName = $vm.properties.friendlyName

    $latestJob = $allJobs |
        Where-Object { $_.properties.entityFriendlyName -eq $vmName } |
        Sort-Object -Property @{Expression={$_.properties.endTime}} -Descending |
        Select-Object -First 1

    [PSCustomObject]@{
        VMName     = $vmName
        Status     = $latestJob.properties.status
        EndTime    = $latestJob.properties.endTime
    }
}

$results | Format-Table -AutoSize
