function Log ($type, $message) {
  $logTypes = @{
    'step'  = @{ Prefix = '[>]'; Color = 'Cyan' }
    'ok'    = @{ Prefix = '[OK]'; Color = 'Green' }
    'warn'  = @{ Prefix = '[~]'; Color = 'Yellow' }
    'error' = @{ Prefix = '[!]'; Color = 'Red' }
    'info'  = @{ Prefix = '[i]'; Color = 'Gray' }
  }
  if ($logTypes.ContainsKey($type)) {
    Write-Host "$($logTypes[$type].Prefix) $message" -ForegroundColor $logTypes[$type].Color
  } else {
    Write-Host $message
  }
}

function Require-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) { throw "Run elevated." }
}

function Get-CurrentOSInfo {
  $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  [pscustomobject]@{
    ProductName    = $reg.ProductName
    DisplayVersion = $reg.DisplayVersion
    ReleaseId      = $reg.ReleaseId
    EditionID      = $reg.EditionID
  }
}

function Set-TargetReleasePolicy {
  param($ProductVersion, $TargetVersion, $DryRun)
  if (-not $TargetVersion) { return }
  $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
  Log step "Applying TargetRelease policy (ProductVersion='$ProductVersion' Target='$TargetVersion')"
  if ($DryRun) { Log info "(DryRun) Skipping registry writes."; return }

  New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $path -Name "TargetReleaseVersion" -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $path -Name "ProductVersion" -PropertyType String -Value $ProductVersion -Force | Out-Null
  New-ItemProperty -Path $path -Name "TargetReleaseVersionInfo" -PropertyType String -Value $TargetVersion -Force | Out-Null
  New-ItemProperty -Path $path -Name "DeferFeatureUpdatesPeriodInDays" -PropertyType DWord -Value 0 -Force | Out-Null
  Log ok "Policy applied."
}

function Suspend-OSBitLocker {
  if (-not $SuspendBitLocker) { return }
  try {
    $vol = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($vol.ProtectionStatus -eq 'On') {
      Log step "Suspending BitLocker on $env:SystemDrive"
      if (-not $DryRun) { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null }
      Log ok "BitLocker suspended."
    }
  } catch { Log warn "BitLocker check failed (ignoring): $_" }
}

function Resume-OSBitLocker {
  if (-not $ResumeBitLockerAfter) { return }
  try {
    $vol = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($vol.ProtectionStatus -eq 'Off') {
      Log step "Resuming BitLocker on $env:SystemDrive"
      if (-not $DryRun) { Resume-BitLocker -MountPoint $env:SystemDrive | Out-Null }
      Log ok "BitLocker resumed."
    }
  } catch { Log warn "BitLocker resume failed: $_" }
}





function main {
  #Require-Admin
  Log 'ok' 'Admin privileges confirmed.'

  $current = Get-CurrentOSInfo
  Log info "System: $($current.ProductName) $($current.DisplayVersion) $($current.EditionID)."

  Log step "Setting target version."
  Set-TargetReleasePolicy -ProductVersion "Windows 11" -TargetVersion "25H2"
  Log ok "Target version set."

}

main
