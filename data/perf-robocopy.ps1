param (
  [string]$source,
  [string]$destination
)

if ($null -eq $source -or $null -eq $destination) {
  Write-Host "Usage: perf_robocopy.ps1 -source <source> -destination <destination>"
  exit 1
}

$source = "`"$source`""
$destination = "`"$destination`""

if (-not (Test-Path "C:\temp")) {
  New-Item -ItemType Directory -Path "C:\temp"
}

$log_file = ".\robocopy.log"

$cores = (Get-WmiObject -Class Win32_Processor).NumberOfCores
$threads = $cores * 2

$retries = 5
$retry_wait = 5

$mirror = $true
$copy_all = $false

$robocopy_args = @(
  $source,
  $destination,
  "/MT:$threads",
  "/R:$retries",
  "/W:$retry_wait",
  "/TEE",
  "/XJ",
  "/MOT:1",
  "/LOG+:$log_file"
)

if ($mirror) {
  $robocopy_args += "/MIR"
} else {
  $robocopy_args += "/E"
  $robocopy_args += "/PURGE"
}

if ($copy_all) {
  $robocopy_args += "/COPY:DATSOU"
  $robocopy_args += "/DCOPY:DAT"
} else {
  $robocopy_args += "/COPY:DAT"
  $robocopy_args += "/DCOPY:DAT"
}

Write-Host "Starting RoboCopy operation..."
$robocopy_command = "robocopy $($robocopy_args -join ' ')"
Write-Host "Command: $robocopy_command"

$confirmation = Read-Host "Do you want to continue? (Y/N)"
if ($confirmation.ToLower() -ne "y") {
  Write-Host "Operation cancelled."
  exit 1
}

Invoke-Expression $robocopy_command
