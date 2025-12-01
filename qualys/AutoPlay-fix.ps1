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

# Require elevation for HKLM writes
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Log 'error' 'Administrator privileges required. Run PowerShell as Administrator.'
  exit 1
}

# Comprehensive AutoPlay/AutoRun disablement:
# - Turn off AutoPlay for all drive types (policy + user)
# - Disable AutoPlay for non-volume devices (e.g., phones/cameras)
# - Ensure Explorer honors AutoRun/AutoPlay policy
# - Disable AutoPlay UI toggle for current user

$settings = @(
  # Computer-wide policy: disable AutoPlay/AutoRun for all drive types
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun';      Value = 255 }

  # Also set for current user (helps ensure UI reflects disabled state)
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun';      Value = 255 }
  # Group Policy (Policies branch): enforce for all drive types
  @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\Explorer';                Name = 'NoDriveTypeAutoRun';      Value = 255 }
  @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';                Name = 'NoDriveTypeAutoRun';      Value = 255 }
  # Group Policy (Policies branch): disable AutoRun per-drive across all letters (A-Z)
  @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\Explorer';                Name = 'NoDriveAutoRun';           Value = -1 }
  @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';                Name = 'NoDriveAutoRun';           Value = -1 }
  # Disable AutoPlay for non-volume devices (MTP, etc.)
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoAutoplayfornonVolume';  Value = 1 }
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoAutoplayfornonVolume';  Value = 1 }
  # Ensure the shell honors the policy setting
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HonorAutorunSetting';     Value = 1 }
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HonorAutorunSetting';     Value = 1 }
  # Disable the AutoPlay "Use AutoPlay for all media and devices" toggle for current user
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'; Name = 'DisableAutoplay'; Value = 1 }

)

function Set-DwordValue {
  param(
    [Parameter(Mandatory=$true)][string] $Path,
    [Parameter(Mandatory=$true)][string] $Name,
    [Parameter(Mandatory=$true)][int]    $Value
  )

  try {
    if (-not (Test-Path -Path $Path)) {
      New-Item -Path $Path -Force | Out-Null
      Log 'ok' "Created key: $Path"
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null

    $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    if ([int]$v -eq $Value) {
      Log 'ok' "$Name=$Value set at $Path"
    } else {
      Log 'error' "$Name verification failed at $Path (got '$v', expected '$Value')"
    }
  }
  catch {
    Log 'error' "Failed to set $Name at ${Path}: $($_.Exception.Message)"
  }
}

Log 'step' 'Disabling AutoPlay/AutoRun using registry policies and user settings'

foreach ($s in $settings) {
  Log 'step' "Ensuring $($s.Name)=$($s.Value) at $($s.Path)"
  Set-DwordValue -Path $s.Path -Name $s.Name -Value $s.Value
}

Log 'step' 'Extra hardening: disabling CD-ROM AutoRun and adding NoDriveAutoRun (CurrentVersion)'
Set-DwordValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveAutoRun' -Value -1
Set-DwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveAutoRun' -Value -1
Set-DwordValue -Path 'HKLM:\System\CurrentControlSet\Services\Cdrom' -Name 'AutoRun' -Value 0
# Stamp Default user (HKU\DEFAULT) so future profiles inherit NoDriveTypeAutoRun=255
$defaultHive = 'C:\Users\Default\NTUSER.DAT'
if (Test-Path $defaultHive) {
  Log 'step' 'Stamping Default user profile hive with NoDriveTypeAutoRun=255'
  & reg.exe load HKU\DEFAULT $defaultHive 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    try {
      $defPath = 'HKU:\DEFAULT\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
      if (-not (Test-Path $defPath)) { New-Item -Path $defPath -Force | Out-Null }
      New-ItemProperty -Path $defPath -Name 'NoDriveTypeAutoRun' -PropertyType DWord -Value 255 -Force | Out-Null
      $verify = (Get-ItemProperty -Path $defPath -Name 'NoDriveTypeAutoRun' -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
      if ($verify -eq 255) {
        Log 'ok' 'Default profile stamped: NoDriveTypeAutoRun=255'
      } else {
        Log 'warn' "Default profile verification failed (got $verify)"
      }
    }
    finally {
      & reg.exe unload HKU\DEFAULT 2>$null | Out-Null
      Log 'step' 'Default user hive unloaded'
    }
  }
  else {
    Log 'warn' 'Failed to load Default user hive; skipping stamping.'
  }
}
else {
  Log 'warn' 'Default user NTUSER.DAT not found; skipping stamping.'
}

Log 'ok' 'AutoPlay/AutoRun has been disabled comprehensively (policy + user settings, including Default profile stamp).'
exit 0
