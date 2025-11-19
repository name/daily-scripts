function Log ($type, $message, $read = $false) {
  $logTypes = @{
    'step'  = @{ Prefix = '[>]'; Color = 'Cyan' }
    'ok'    = @{ Prefix = '[OK]'; Color = 'Green' }
    'warn'  = @{ Prefix = '[~]'; Color = 'Yellow' }
    'error' = @{ Prefix = '[!]'; Color = 'Red' }
  }

  if ($logTypes.ContainsKey($type)) {
    $prefix = $logTypes[$type].Prefix
    $color  = $logTypes[$type].Color
    $params = @{ Object = "$prefix $message"; ForegroundColor = $color }
    if ($read) {
      $params.NoNewline = $true
      Write-Host @params
      Read-Host
    } else {
      Write-Host @params
    }
  } else {
    Write-Host $message
  }
}

# Require elevation (HKLM write)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Log 'error' 'Administrator privileges required. Run PowerShell as Administrator.'
  exit 1
}

# Policy mapping:
# "Network security: Allow PKU2U authentication requests to this computer to use online identities"
# Registry: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\pku2u
# Value:    AllowOnlineID (REG_DWORD)
# Enabled  = 1 (online IDs allowed)
# Disabled = 0 (online IDs blocked)  <-- Desired for hardening / local policy set to Disabled

$targetPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\pku2u'
$valueName   = 'AllowOnlineID'
$desired     = 0

Log 'step' "Ensuring PKU2U online identity authentication is disabled (setting $valueName=$desired)"

try {
  if (-not (Test-Path -Path $targetPath)) {
    New-Item -Path $targetPath -Force | Out-Null
    Log 'ok' "Created key: $targetPath"
  }

  New-ItemProperty -Path $targetPath -Name $valueName -PropertyType DWord -Value $desired -Force | Out-Null

  $current = (Get-ItemProperty -Path $targetPath -Name $valueName -ErrorAction Stop).$valueName
  if ([int]$current -eq $desired) {
    Log 'ok' "$valueName confirmed as $desired at $targetPath (PKU2U disabled)"
  } else {
    Log 'error' "$valueName verification failed (got '$current', expected '$desired')"
    exit 2
  }
}
catch {
  Log 'error' "Failed to apply PKU2U setting: $($_.Exception.Message)"
  exit 3
}

# Optional quick status output for automation:
Write-Output ("PKU2U-AllowOnlineID={0}" -f $desired)

Log 'ok' 'PKU2U online identity authentication has been disabled successfully.'
exit 0
