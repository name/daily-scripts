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

function Configure-DCU {
    param ($dcuPath)
    Log 'step' "Configuring Dell Command | Update..."

    & $dcuPath /configure -autoSuspendBitLocker=enable
    & $dcuPath /configure -lockSettings=enable
    & $dcuPath /configure "-updateType=bios,firmware"
}

function Scan-DCU {
    param ($dcuPath)
    Log 'step' "Scanning for updates..."
    & $dcuPath /scan "-updateType=bios,firmware"
}

function Apply-DCU {
    param ($dcuPath)
    Log 'step' "Applying updates..."
    $logFile = "C:\Temp\DCU-update.log"

    if (Test-Path $logFile) { Remove-Item $logFile -Force }

    $proc = Start-Process -FilePath $dcuPath -ArgumentList "/applyUpdates -silent -reboot=disable -outputLog=`"$logFile`"" -Wait -PassThru

    $logContent = if (Test-Path $logFile) { Get-Content $logFile | Out-String } else { "" }

    # 0 = Success, No Reboot
    # 1 = Success, Reboot Required (Common in v5.x for BIOS)
    # 2 = Success, Reboot Required (Standard DUP code)
    if ($proc.ExitCode -eq 0) {
        Log 'ok' "Updates applied successfully. No reboot required."
    } elseif ($proc.ExitCode -in 1, 2) {
        Log 'warn' "Updates applied successfully. REBOOT REQUIRED to finalize (Exit: $($proc.ExitCode))."
        Log 'info' "Please reboot this machine manually."
    } else {
        Log 'error' "Update failed with exit code $($proc.ExitCode)"
        if ($logContent) {
            Write-Host "`n=== DCU LOG TAIL ===" -ForegroundColor Gray
            $logContent.Split("`n") | Select-Object -Last 10
            Write-Host "==================`n" -ForegroundColor Gray
        }
    }
}

function main {
  Log 'step' 'Initializing Dell Command | Update sequence...'
  Require-Admin

  $dcuCLI = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
  if (-not (Test-Path $dcuCLI)) { $dcuCLI = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe" }
  if (-not (Test-Path $dcuCLI)) { throw "dcu-cli.exe not found. Install DCU first." }

  Configure-DCU -dcuPath $dcuCLI
  Scan-DCU -dcuPath $dcuCLI
  Apply-DCU -dcuPath $dcuCLI

  Log 'ok' 'Sequence complete.'
}

main
