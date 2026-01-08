param(
    [switch]$Daemon,
    [switch]$Work,
    [switch]$NonWork,
    [string]$Leave,
    [switch]$Ack,
    # Global toggles
    [int]$SetIdleTimeoutMinutes,
    [int]$SetBatteryWorkWarning,
    [int]$SetBatteryCriticalWarning,
    [int]$SetCheckIntervalSeconds
)

$StatePath = "$env:TEMP\ps-watchdog-state.json"

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class IdleHelper {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static TimeSpan GetIdleTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return TimeSpan.Zero;
        uint idleMs = (uint)Environment.TickCount - lii.dwTime;
        return TimeSpan.FromMilliseconds(idleMs);
    }
}
"@

function Get-State {
    if (Test-Path $StatePath) {
        Get-Content $StatePath | ConvertFrom-Json
    } else {
        [pscustomobject]@{
            Mode                  = "work"
            LeaveUntil            = 0
            AlarmState            = "ack"
            IdleTimeoutMinutes    = 5
            BatteryWorkWarning    = 40
            BatteryCriticalWarning = 20
            CheckIntervalSeconds  = 60
        }
    }
}

function Set-State($state) {
    $state | ConvertTo-Json | Set-Content $StatePath
}

# ---- control mode (non-daemon) ----
if (-not $Daemon) {
    $s = Get-State
    $changed = $false

    if ($Work)    { $s.Mode = "work";    $s.AlarmState = "ack"; $changed = $true }
    if ($NonWork) { $s.Mode = "nonwork"; $s.AlarmState = "ack"; $changed = $true }

    if ($Leave) {
        $ts = Get-Date $Leave -ErrorAction SilentlyContinue
        if (-not $ts) { Write-Error "Invalid leave expression: $Leave"; exit 1 }
        $s.LeaveUntil = [int][double]::Parse((Get-Date -Date $ts -UFormat %s))
        $s.AlarmState = "ack"
        $changed = $true
    }

    if ($Ack) { $s.AlarmState = "ack"; $changed = $true }

    # Update global toggles if provided
    if ($PSBoundParameters.ContainsKey('SetIdleTimeoutMinutes')) {
        $s.IdleTimeoutMinutes = $SetIdleTimeoutMinutes
        $changed = $true
    }
    if ($PSBoundParameters.ContainsKey('SetBatteryWorkWarning')) {
        $s.BatteryWorkWarning = $SetBatteryWorkWarning
        $changed = $true
    }
    if ($PSBoundParameters.ContainsKey('SetBatteryCriticalWarning')) {
        $s.BatteryCriticalWarning = $SetBatteryCriticalWarning
        $changed = $true
    }
    if ($PSBoundParameters.ContainsKey('SetCheckIntervalSeconds')) {
        $s.CheckIntervalSeconds = $SetCheckIntervalSeconds
        $changed = $true
    }

    if ($changed) { Set-State $s }
    exit 0
}

function Get-IdleMilliseconds {
    [IdleHelper]::GetIdleTime().TotalMilliseconds
}

function Get-BatteryPercent {
    $b = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
    if (-not $b) { return $null }
    $b.EstimatedChargeRemaining
}

function Set-AlarmState($state, $reason) {
    $s = Get-State
    $s.AlarmState = $state
    $s | Add-Member -NotePropertyName LastReason -NotePropertyValue $reason -Force
    Set-State $s
    Write-Host "ALARM $($state): $reason"
}

Write-Host "Watchdog started"

while ($true) {
    $s = Get-State
    $s
    $now = [int][double]::Parse((Get-Date -UFormat %s))

    $idleMs = Get-IdleMilliseconds
    $bat    = Get-BatteryPercent

    $leaveActive = $s.LeaveUntil -gt $now
    $idleThresholdMs = $s.IdleTimeoutMinutes * 60 * 1000

    if ($s.Mode -eq "work" -and -not $leaveActive) {
        if ($idleMs -gt $idleThresholdMs -and $s.AlarmState -eq "ack") {
            Set-AlarmState "soft 7" "Idle > $($s.IdleTimeoutMinutes) min"
        }
        if ($bat -ne $null -and $bat -lt $s.BatteryWorkWarning -and $s.AlarmState -eq "ack") {
            Set-AlarmState "soft" "Battery < $($s.BatteryWorkWarning)%"
        }
    }

    if ($bat -ne $null -and $bat -lt $s.BatteryCriticalWarning -and $s.AlarmState -eq "ack") {
        Set-AlarmState "soft" "Battery < $($s.BatteryCriticalWarning)%"
    }

    # crude soft->hard escalation
    $s = Get-State
    if ($s.AlarmState -like "soft*") {
        Write-Host "BEEP: $($s.AlarmState) - $($s.LastReason)"
        if ($s.AlarmState -match '^soft\s+(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -le 1) { $s.AlarmState = "hard" }
            else { $s.AlarmState = "soft " + ($n-1) }
            Set-State $s
        }
    } elseif ($s.AlarmState -eq "hard") {
        Write-Host "HARD ALARM: $($s.LastReason)"
    }

    Start-Sleep -Seconds $s.CheckIntervalSeconds
}
