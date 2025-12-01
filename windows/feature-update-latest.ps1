<#
Feature Update Automation (Hybrid: COM-Force + Silent Assistant Fallback)
File: feature-update-hybrid.ps1

Purpose:
- Standard Path: Force synchronous COM-based WUA update (TargetReleaseVersion).
- Fallback Path: If COM fails (ResultCode 4 on 23H2), trigger the Fallback Handler.
- Fallback Handler:
  1. If 'LocalIsoPath' is provided, mount ISO and run 'setup.exe /auto upgrade /quiet'.
  2. If no ISO, download Installation Assistant and run it HIDDEN (background mode).

Run elevated (Administrator).
#>

param(
  [string]$VersionSourceUrl = "https://pastebin.com/raw/TG2JsMci",
  [string]$OverrideTargetVersion = "24H2",
  [ValidateSet("Windows 10","Windows 11")]
  [string]$ProductVersion = "Windows 11",
  [string]$LocalIsoPath = "",                                               # Optional: Path to a pre-downloaded 24H2 ISO
  [switch]$SetPolicyOnly = $false,
  [switch]$DryRun = $false,
  [switch]$Force = $false,
  [bool]$Install = $true,
  [switch]$NoReboot = $true,
  [int]$MinFreeGB = 20,
  [switch]$SuspendBitLocker = $true,
  [switch]$ResumeBitLockerAfter = $true,
  [int]$ScanRetryCount = 3,                                                 # Retained for compatibility, unused in sync mode
  [int]$ScanRetryDelaySeconds = 30                                          # Retained for compatibility
)

#####################################################################
# Logging
#####################################################################
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

#####################################################################
# Helpers
#####################################################################
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

function Fetch-TargetVersion {
  param([string]$Url, [string]$Override)
  if ($Override) { Log step "Using override target version: $Override"; return $Override.Trim() }
  try {
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15).Content.Trim()
    Log ok "Fetched remote version: $content"
    return $content
  } catch {
    Log error "Failed to fetch remote version: $_"; return $null
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

#####################################################################
# BitLocker
#####################################################################
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

#####################################################################
# COM Update Logic
#####################################################################
function Search-FeatureUpgrades-Sync {
  param([switch]$DryRun)
  Log step "Initializing Windows Update Session (COM)..."
  $session = New-Object -ComObject "Microsoft.Update.Session"
  $searcher = $session.CreateUpdateSearcher()
  $searcher.ServerSelection = 2 # ssWindowsUpdate (Force Online)
  $searcher.ServiceID = "7971f918-a847-4430-9279-4a52d1efe18d"

  Log step "Starting SYNCHRONOUS online search... (This may take 2-5 minutes)"
  if ($DryRun) { Log info "(DryRun) Skipping search."; return @() }

  try {
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
  } catch {
    Log error "Search failed with COM error: $_"
    return @()
  }
  Log ok "Search completed. Found $($result.Updates.Count) total updates."

  $upgrades = @()
  foreach ($upd in $result.Updates) {
    foreach ($cat in $upd.Categories) {
      if ($cat.Name -eq "Upgrades") {
        $upgrades += $upd
        Log info "FOUND CANDIDATE: $($upd.Title)"
        break
      }
    }
  }
  return $upgrades
}

function Install-Updates-Com {
  param($Upgrades)
  if ($Upgrades.Count -eq 0) { return }

  $session = New-Object -ComObject "Microsoft.Update.Session"
  $dlColl = New-Object -ComObject "Microsoft.Update.UpdateColl"

  foreach ($u in $Upgrades) {
    if ($u.EulaAccepted -eq $false) {
      Log step "Accepting EULA for '$($u.Title)'..."
      try { $u.AcceptEula() } catch { Log warn "Could not accept EULA: $_" }
    }
    $dlColl.Add($u) | Out-Null
  }

  Log step "Initializing Downloader (Priority=High)..."
  $downloader = $session.CreateUpdateDownloader()
  $downloader.Updates = $dlColl
  $downloader.Priority = 3 # High

  try {
    $dlResult = $downloader.Download()
  } catch { throw "Download exception: $_" }

  if ($dlResult.ResultCode -ne 2) {
    Log error "Download failed with ResultCode=$($dlResult.ResultCode)."
    throw "WUA_DOWNLOAD_FAILED_CODE_4"
  }
  Log ok "Download success."

  $instColl = New-Object -ComObject "Microsoft.Update.UpdateColl"
  $Upgrades | ForEach-Object { $instColl.Add($_) | Out-Null }

  Log step "Installing..."
  $installer = $session.CreateUpdateInstaller()
  $installer.Updates = $instColl
  $installer.ForceQuiet = $true

  $instResult = $installer.Install()
  Log ok "Install Result: Code=$($instResult.ResultCode)"
}

#####################################################################
# FALLBACK HANDLER
#####################################################################
function Invoke-FallbackUpgrade {
  param([string]$IsoPath)

  Log warn "Initiating Fallback Upgrade Protocol..."

  # PATH A: ISO Mount (If path provided)
  if ($IsoPath -and (Test-Path $IsoPath)) {
    Log step "Mounting ISO: $IsoPath"
    try {
      $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
      $driveLetter = ($mount | Get-Volume).DriveLetter
      if (-not $driveLetter) { throw "Could not determine drive letter for mounted ISO." }
      $drive = "$($driveLetter):"
      $setupPath = Join-Path $drive "setup.exe"

      Log step "Running Setup from $drive..."
      # Setup.exe silent args: /auto upgrade /quiet /noreboot /dynamicupdate disable
      $proc = Start-Process -FilePath $setupPath -ArgumentList "/auto upgrade /quiet /noreboot /dynamicupdate disable /showoobe none" -PassThru -Wait

      Log ok "Setup exited with code: $($proc.ExitCode)"
      Dismount-DiskImage -ImagePath $IsoPath | Out-Null
      return
    } catch {
      Log error "ISO fallback failed: $_"
      throw
    }
  }

  # PATH B: Installation Assistant (Hidden Mode)
  # Since we cannot download the ISO programmatically without tokens, we use the Assistant
  # but hide its window to simulate the "silent ISO" experience.

  Log step "No ISO provided. Downloading Windows 11 Installation Assistant..."
  $url = "https://go.microsoft.com/fwlink/?linkid=2171764"
  $exePath = "$env:TEMP\Win11Assistant.exe"

  try {
    Invoke-WebRequest -Uri $url -OutFile $exePath -UseBasicParsing
  } catch { throw "Failed to download Assistant." }

  Log step "Launching Assistant (HIDDEN MODE)..."
  Log info "Process will run in background. Check Task Manager for 'Windows11InstallationAssistant'."

  try {
    # -WindowStyle Hidden makes the UI invisible.
    # /quietinstall suppresses interactive prompts.
    $p = Start-Process -FilePath $exePath -ArgumentList "/quietinstall /skipeula /auto upgrade /copylogs $env:TEMP" -WindowStyle Hidden -PassThru

    # Wait loop with timeout (e.g., 60 mins) or just return
    Log ok "Assistant launched in background (PID: $($p.Id))."

  } catch {
    throw "Failed to launch Assistant: $_"
  }
}

#####################################################################
# Main
#####################################################################
try {
  Require-Admin
  $current = Get-CurrentOSInfo
  Log info "System: $($current.ProductName) ($($current.DisplayVersion))"

  # Clean SD
  Log step "Cleaning SoftwareDistribution..."
  Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
  Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
  Start-Service wuauserv

  # Policy
  $target = Fetch-TargetVersion -Url $VersionSourceUrl -Override $OverrideTargetVersion
  Set-TargetReleasePolicy -ProductVersion $ProductVersion -TargetVersion $target -DryRun:$DryRun
  if ($SetPolicyOnly) { exit }

  Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators\GE24H2Setup" -Recurse -ErrorAction SilentlyContinue
  Suspend-OSBitLocker

  # Attempt COM Update
  $candidates = Search-FeatureUpgrades-Sync -DryRun:$DryRun

  if ($candidates.Count -gt 0 -and $Install) {
    try {
      Install-Updates-Com -Upgrades $candidates
    } catch {
      $err = $_.Exception.Message
      # Trigger Fallback if WUA fails specifically on 23H2 with ResultCode 4
      if ($err -match "WUA_DOWNLOAD_FAILED_CODE_4" -and $current.DisplayVersion -eq "23H2") {
        Log warn "WUA Download Blocked (SSU Mismatch). Triggering Fallback."
        Invoke-FallbackUpgrade -IsoPath $LocalIsoPath
      } else {
        throw $err
      }
    }
  } else {
    if ($candidates.Count -eq 0) {
      Log warn "No updates found via WUA. (Consider using Fallback manually if you have an ISO)"
      # Optional: Uncomment to force fallback even if no updates found
      # Invoke-FallbackUpgrade -IsoPath $LocalIsoPath
    }
  }

  Resume-OSBitLocker
  Log ok "Workflow complete."

} catch {
  Log error "FATAL: $_"
  Resume-OSBitLocker
}
