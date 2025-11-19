function Log ($type, $message, $read = $false) {
  $logTypes = @{
    'step'  = @{ Prefix = '[>]'; Color = 'Cyan' }
    'ok'    = @{ Prefix = '[OK]'; Color = 'Green' }
    'warn'  = @{ Prefix = '[~]'; Color = 'Yellow' }
    'error' = @{ Prefix = '[!]'; Color = 'Red' }
  }

  if ($logTypes.ContainsKey($type)) {
    $prefix = $logTypes[$type].Prefix
    $color = $logTypes[$type].Color
    $params = @{ Object = "$prefix $message"; ForegroundColor = $color }
    if ($read) {
      $params.NoNewline = $true
      Write-Host @params
      Read-Host
    }
    else {
      Write-Host @params
    }
  }
  else {
    Write-Host $message
  }
}

try {
  $aadTenant = Get-AzureADTenantDetail
  Log 'ok' "Signed into Entra as: $($aadTenant.DisplayName)"
  Log 'ok' "If this is not correct, please run 'Disconnect-AzureAD' and re-run this script."
}
catch {
  Log 'warn' "Not connected to Azure AD. Connecting..."
  Connect-AzureAD
}

$groupName = "Azure VPN Access"
$group = Get-AzureADGroup -Filter "DisplayName eq '$groupName'"

if (-not $group) {
  Log 'error' "Group '$groupName' not found in Azure AD. Please run the deployment script first."
  exit
}

Log 'ok' "Found group '$groupName' with ObjectId: $($group.ObjectId)"

$legacyGroupName = "Hosted Remote Access Users"
$legacyGroup = Get-AzureADGroup -Filter "DisplayName eq '$legacyGroupName'"

if (-not $legacyGroup) {
  Log 'error' "Legacy group '$legacyGroupName' not found. Unable to migrate group users."
  exit
}

Log 'ok' "Found legacy group '$legacyGroupName' with ObjectId: $($legacyGroup.ObjectId)"

$legacyMembers = Get-AzureADGroupMember -ObjectId $legacyGroup.ObjectId -All $true

$migratedUsers = 0

foreach ($member in $legacyMembers) {
  try {
    Add-AzureADGroupMember -ObjectId $group.ObjectId -RefObjectId $member.ObjectId
    Log 'ok' "Added $($member.DisplayName) to '$groupName'"
    $migratedUsers++
  }
  catch {
    Log 'warn' "Failed to add $($member.DisplayName) to '$groupName': $($_.Exception.Message)"
    $migratedUsers++
  }
}

Log 'ok' "Migration completed. Total users migrated: $migratedUsers"
