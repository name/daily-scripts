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

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Log 'error' 'Administrator privileges required. Run PowerShell as Administrator.'
  exit 1
}

$paths = @(
  'HKLM:\Software\Microsoft\Cryptography\Wintrust\Config',
  'HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
)
$name = 'EnableCertPaddingCheck'
$val  = 1

foreach ($p in $paths) {
  try {
    Log 'step' "Ensuring $name=$val at $p"
    if (-not (Test-Path -Path $p)) { New-Item -Path $p -Force | Out-Null }

    New-ItemProperty -Path $p -Name $name -PropertyType DWord -Value $val -Force | Out-Null

    $v = (Get-ItemProperty -Path $p -Name $name -ErrorAction Stop).$name
    if ([int]$v -eq $val) {
      Log 'ok' "$name confirmed as $val at $p"
    } else {
      Log 'error' "$name verification failed (got '$v') at $p"
    }
  }
  catch {
    Log 'error' "Failed at $($p): $($_.Exception.Message)"
  }
}

Log 'ok' 'WinVerifyTrust registry settings applied and verified.'
exit 0
