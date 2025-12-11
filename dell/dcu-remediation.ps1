function Log ($type, $message) {
    $logTypes = @{
        'step'  = @{ Prefix = '[>]'; Color = 'Cyan' }
        'ok'    = @{ Prefix = '[OK]'; Color = 'Green' }
        'warn'  = @{ Prefix = '[~]'; Color = 'Yellow' }
        'error' = @{ Prefix = '[!]'; Color = 'Red' }
    }
    if ($logTypes.ContainsKey($type)) {
        Write-Host "$($logTypes[$type].Prefix) $message" -ForegroundColor $logTypes[$type].Color
    } else {
        Write-Host $message
    }
}

function Require-Admin {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run elevated."
    }
}

function Install-DCU {
    Log 'step' 'Starting installation...'
    Require-Admin

    if (Get-Package -Name "Dell Command | Update*" -ErrorAction SilentlyContinue) {
        Log 'ok' 'Dell Command | Update is already installed.'
        return
    }

    Log 'step' 'Preparing download...'
    $downloadUrl = 'https://dl.dell.com/FOLDER13922692M/1/Dell-Command-Update-Windows-Universal-Application_2WT0J_WIN64_5.6.0_A00.EXE'
    $tempDir = 'C:\Temp'
    $downloadPath = Join-Path $tempDir 'DCU_Setup.exe'

    if (!(Test-Path $tempDir)) {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    }

    Log 'step' 'Downloading...'
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    } catch {
        Log 'error' "Download crashed: $_"
        throw "Download failed."
    }

    if (!(Test-Path $downloadPath)) { throw "File vanished?" }

    Log 'step' 'Installing...'
    $Process = Start-Process -FilePath $downloadPath -ArgumentList '/s /v"/qn"' -Wait -PassThru

    if ($Process.ExitCode -in 0, 3010, 2) {
        Log 'ok' "DCU Installed (Exit: $($Process.ExitCode))."
    } else {
        Log 'error' "Failed. Exit code: $($Process.ExitCode). Check C:\ProgramData\Dell\UpdatePackage\Log for details."
        throw "Install failed."
    }
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

Install-DCU

Log 'step' 'Initializing Dell Command | Update sequence...'
Require-Admin

$dcuCLI = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
if (-not (Test-Path $dcuCLI)) { $dcuCLI = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe" }
if (-not (Test-Path $dcuCLI)) { throw "dcu-cli.exe not found. Install DCU first." }

Configure-DCU -dcuPath $dcuCLI
Scan-DCU -dcuPath $dcuCLI
Apply-DCU -dcuPath $dcuCLI

Log 'ok' 'Sequence complete.'
