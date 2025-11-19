$account = az account show 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Not logged in. Logging in..."
  az login
}

$subscriptions = az account list --query "[].{Name:name, Id:id, State:state}" --output json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
  Write-Host "No subscriptions found."
  exit
}

Write-Host "Available subscriptions:"
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
  Write-Host "$($i + 1). $($subscriptions[$i].Name) (ID: $($subscriptions[$i].Id), State: $($subscriptions[$i].State))"
}

$selection = Read-Host "Enter the number of the subscription to select (1-$($subscriptions.Count))"
$index = [int]$selection - 1

if ($index -lt 0 -or $index -ge $subscriptions.Count) {
  Write-Host "Invalid selection."
  exit
}

$selectedSub = $subscriptions[$index]
az account set --subscription $selectedSub.Id
Write-Host "Subscription set to: $($selectedSub.Name)"
