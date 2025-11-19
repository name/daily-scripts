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

$context = Get-AzContext
if ($context) {
  Log 'ok' "User is already signed into Azure."
}
else {
  Log 'warn' "User is not signed in. Signing in..."
  Connect-AzAccount -UseDeviceAuthentication
}

Log 'ok' "Signed into Azure as: $($context.Account)"

$subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId, HomeTenantId, ManagedByTenantIds

if ($subscriptions.Count -eq 0) {
  Log 'error' "No subscriptions found."
  exit
}

$selectedSubscription = $subscriptions | Out-GridView -Title "Select a Subscription" -OutputMode Single

if (-not $selectedSubscription) {
  Log 'error' "No subscription selected."
  exit
}

Set-AzContext -SubscriptionId $selectedSubscription.Id | Out-Null
$tenantId = $selectedSubscription.HomeTenantId
Log 'ok' "Subscription set to: $($selectedSubscription.Name)"

try {
  $aadTenant = Get-AzureADTenantDetail
  Log 'ok' "Signed into Entra as: $($aadTenant.DisplayName)"
}
catch {
  Log 'warn' "Not connected to Azure AD. Connecting..."
  Connect-AzureAD -TenantId $tenantId
}

$resourceGroups = Get-AzResourceGroup

if ($resourceGroups.Count -eq 0) {
  Log 'error' "No resource groups found."
  exit
}

$vnGateways = @()

foreach ($rg in $resourceGroups) {
  $vnGatewaysLocal = Get-AzVirtualNetworkGateway -ResourceGroupName $rg.ResourceGroupName

  if ($vnGatewaysLocal.Count -gt 0) {
    foreach ($vng in $vnGatewaysLocal) {
      $vnGateways += [PSCustomObject]@{
        ResourceGroupName     = $rg.ResourceGroupName
        VirtualNetworkGateway = $vng
      }
    }
  }
}

if ($vnGateways.Count -eq 0) {
  Log 'error' "No Virtual Network Gateways found in any resource group."
  exit
}

if ($vnGateways.Count -gt 1) {
  $selectedVNG = $vnGateways | Select-Object ResourceGroupName, @{Name = 'GatewayName'; Expression = { $_.VirtualNetworkGateway.Name } }, @{Name = 'GatewayType'; Expression = { $_.VirtualNetworkGateway.GatewayType } } | Out-GridView -Title "Select a Virtual Network Gateway" -OutputMode Single

  if (-not $selectedVNG) {
    Log 'error' "No Virtual Network Gateway selected."
    exit
  }

  $selectedVNGFull = $vnGateways | Where-Object { $_.ResourceGroupName -eq $selectedVNG.ResourceGroupName -and $_.VirtualNetworkGateway.Name -eq $selectedVNG.GatewayName }
}
else {
  $selectedVNGFull = $vnGateways[0]
}

Log 'ok' "Selected Virtual Network Gateway: $($selectedVNGFull.VirtualNetworkGateway.Name) in $($selectedVNGFull.ResourceGroupName)"

$p2sConfig = $selectedVNGFull.VirtualNetworkGateway.VpnClientConfiguration

if ($null -eq $p2sConfig.VpnClientAddressPool) {
  Log 'warn' "The selected Virtual Network Gateway does not have Point-to-Site configuration, setting it up now..."


  $p2sConfig = New-Object Microsoft.Azure.Commands.Network.Models.PSVpnClientConfiguration
  $p2sConfig.VpnClientAddressPool = New-Object Microsoft.Azure.Commands.Network.Models.PSAddressSpace
  $p2sConfig.VpnClientAddressPool.AddressPrefixes = @("10.100.0.0/24")
  $p2sConfig.VpnClientProtocols = @("OpenVPN")
  $p2sConfig.AadTenant = "https://login.microsoftonline.com/$($tenantId)"
  $p2sConfig.AadAudience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"
  $p2sConfig.AadIssuer = "https://sts.windows.net/$($tenantId)/"

  Set-AzVirtualNetworkGateway -VirtualNetworkGateway $selectedVNGFull.VirtualNetworkGateway -VpnClientAddressPool $p2sConfig.VpnClientAddressPool.AddressPrefixes -VpnClientProtocol $p2sConfig.VpnClientProtocols -VpnAuthenticationType "AAD" -AadTenantUri $p2sConfig.AadTenant -AadAudienceId $p2sConfig.AadAudience -AadIssuerUri $p2sConfig.AadIssuer | Out-Null

  Log 'ok' "Point-to-Site configuration updated with Azure AD authentication."

  $consentUrl = "https://login.microsoftonline.com/$tenantId/oauth2/authorize?response_type=code&client_id=41b23e61-6c1e-4545-b367-cd054e0ed4b4&redirect_uri=https://portal.azure.com&nonce=efeb9897-584f-474d-a30c-3269ac1cafac"

  Log 'step' "Opening admin consent URL in browser. Please have a Global Admin approve the consent."
  Start-Process $consentUrl
  Log 'warn' "Press Enter after admin consent is granted." -read $true
}

$p2sConfig = $selectedVNGFull.VirtualNetworkGateway.VpnClientConfiguration

if ($null -eq $p2sConfig.VpnClientAddressPool) {
  Log 'error' "Failed to set up Point-to-Site configuration."
  exit
}

Log 'ok' "Point-to-Site configuration is set up."

$sp = Get-AzureADServicePrincipal -Filter "AppId eq '41b23e61-6c1e-4545-b367-cd054e0ed4b4'"

if ($sp) {
  Set-AzureADServicePrincipal -ObjectId $sp.ObjectId -AppRoleAssignmentRequired $true
  Log 'ok' "Assignment required set to Yes for the Azure VPN enterprise app."
}
else {
  Log 'error' "Azure VPN service principal not found."
}

$groupName = "Azure VPN Access"
$group = Get-AzureADGroup -Filter "DisplayName eq '$groupName'"

if (-not $group) {
  $group = New-AzureADGroup -DisplayName $groupName -MailEnabled $false -SecurityEnabled $true -MailNickName "AzureVPNAccess"
  Log 'ok' "Security group '$groupName' created."
}
else {
  Log 'ok' "Security group '$groupName' already exists."
}

$sp = Get-AzureADServicePrincipal -Filter "AppId eq '41b23e61-6c1e-4545-b367-cd054e0ed4b4'"

if ($sp) {
  $existingAssignment = Get-AzureADGroupAppRoleAssignment -ObjectId $group.ObjectId -All $true | Where-Object { $_.ResourceId -eq $sp.ObjectId -and $_.Id -eq ([Guid]::Empty) }
  if (-not $existingAssignment) {
    New-AzureADGroupAppRoleAssignment -ObjectId $group.ObjectId -PrincipalId $group.ObjectId -ResourceId $sp.ObjectId -Id ([Guid]::Empty) | Out-Null
    Log 'ok' "Group '$groupName' assigned to the Azure VPN app role."
  }
  else {
    Log 'ok' "Group '$groupName' is already assigned to the Azure VPN app role."
  }
}
else {
  Log 'error' "Azure VPN service principal not found."
}
