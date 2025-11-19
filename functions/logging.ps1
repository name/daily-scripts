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
