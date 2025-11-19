try {
  Disable-AzContextAutosave -Scope Process
  $AzureContext = (Connect-AzAccount -Identity -AccountId "REPLACE" -Subscription "REPLACE").context
  Write-Output "----------------------------------------"
  Write-Output "Authenticated as $($AzureContext.Account.Id)"
  Write-Output "----------------------------------------"
}
catch {
  Write-Output "----------------------------------------"
  Write-Error "Failed to authenticate: $_"
  Write-Output "----------------------------------------"
  exit
}

$subscriptions = Get-AzSubscription

foreach ($subscription in $subscriptions) {
  $subscriptionName = $subscription.Name
  $subscriptionGuid = $subscription.Id
  $subscriptionState = $subscription.State

  Write-Output "Subscription: $subscriptionName"
  Write-Output "Subscription ID: $subscriptionGuid"
  Write-Output "Subscription State: $subscriptionState"
  Write-Output "----------------------------------------"
}
