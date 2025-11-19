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
  $requiredScopes = @("Policy.ReadWrite.ConditionalAccess", "Policy.Read.All", "Application.Read.All", "Directory.Read.All")
  Connect-MgGraph -TenantId $tenantId -Scopes $requiredScopes
  Log 'ok' "Connected to Microsoft Graph."
}
catch {
  Log 'error' "Failed to connect to Microsoft Graph: $_"
  exit
}

$vpnSp = Get-MgServicePrincipal -Filter "appId eq '41b23e61-6c1e-4545-b367-cd054e0ed4b4'"
if (-not $vpnSp) {
  Log 'error' "Azure VPN service principal not found in Microsoft Graph."
  exit
}

$vpnGroup = Get-MgGroup -Filter "displayName eq 'Azure VPN Access'"
if (-not $vpnGroup) {
  Log 'error' "Azure VPN Access group not found."
  exit
}

$globalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10"

$existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq 'Multifactor authentication for Azure VPN'"
if ($existingPolicy) {
  Log 'ok' "Conditional Access Policy 'Multifactor authentication for Azure VPN' already exists."
}
else {
  $policyParams = @{
    DisplayName   = "Multifactor authentication for Azure VPN"
    State         = "enabled"
    Conditions    = @{
      Users        = @{
        IncludeGroups = @($vpnGroup.Id)
        ExcludeRoles  = @($globalAdminRoleId)
      }
      Applications = @{
        IncludeApplications = @($vpnSp.AppId)
      }
    }
    GrantControls = @{
      Operator        = "OR"
      BuiltInControls = @("mfa")
    }
  }

  try {
    New-MgIdentityConditionalAccessPolicy -BodyParameter $policyParams
    Log 'ok' "Conditional Access Policy 'Multifactor authentication for Azure VPN' created and enabled."
  }
  catch {
    Log 'error' "Failed to create Conditional Access Policy: $_"
  }
}
