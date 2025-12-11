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

function main {
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

main
