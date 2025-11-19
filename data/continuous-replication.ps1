param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [string]$ReplicationName,

    [Parameter(Mandatory = $false)]
    [switch]$NoConfirmation
)

if (-not (Test-Path $SourcePath)) {
    Write-Host "Source path does not exist."
    exit 1
}

if (-not (Test-Path $DestinationPath)) {
    Write-Host "Destination path does not exist."
    exit 1
}

$LogFile = "C:\Temp\robocopy_${ReplicationName}.log"

$Cores = (Get-WmiObject -Class Win32_Processor).NumberOfCores
$Threads = $Cores * 2

$RoboCopyArgs = @(
    $SourcePath,
    $DestinationPath,
    "/MIR", # Mirror mode (includes /E and /PURGE)
    "/COPY:DATSO", # Copy Data, Attributes, Timestamps, Security, Owner info
    "/DCOPY:T", # Copy Directory Timestamps
    "/MT:$Threads", # Multi-threaded copying
    "/R:3", # Number of retries
    "/W:5", # Wait time between retries
    "/LOG+:$LogFile",
    "/TEE", # Output to console and log file
    "/XJ", # Exclude junction points
    "/FFT", # Assume FAT file times (2-second precision)
    "/ZB", # Use restartable mode; if access denied use Backup mode
    "/MON:1", # Monitor source; run again when more than 1 change seen
    "/J", # Copy using unbuffered I/O (recommended for large files)
    "/NOOFFLOAD" # Do not use the Windows copy offload mechanism
)

Write-Host "Source path: $SourcePath"
Write-Host "Destination path: $DestinationPath"
Write-Host "Log file: $LogFile"
Write-Host "Replication name: $ReplicationName"
Write-Host "Threads: $Threads"
Write-Host "RoboCopy arguments: $($RoboCopyArgs -join ' ')"

if (-not $NoConfirmation) {
    $confirmation = Read-Host "Do you want to start continuous replication? (Y/N)"

    if ($confirmation -ne "Y") {
        Write-Host "Replication cancelled."
        exit 0
    }
}

Write-Host "Starting continuous replication. Press Ctrl+C to stop."

try {
    while ($true) {
        & robocopy $RoboCopyArgs

        $exitCode = $LASTEXITCODE
        switch ($exitCode) {
            0 { Write-Host "No files were copied. No failure was encountered. No files were mismatched. The files already exist in the destination directory." }
            1 { Write-Host "All files were copied successfully." }
            2 { Write-Host "There are some additional files in the destination directory that are not present in the source directory. No files were copied." }
            3 { Write-Host "Some files were copied. Additional files were present. No failure was encountered." }
            5 { Write-Host "Some files were copied. Some files were mismatched. No failure was encountered." }
            6 { Write-Host "Additional files and mismatched files exist. No files were copied and no failures were encountered. This means that the files already exist in the destination directory." }
            7 { Write-Host "Files were copied, a file mismatch was present, and additional files were present." }
            8 { Write-Host "Several files did not copy." }
            default { Write-Host "Unexpected exit code: $exitCode" }
        }

        Write-Host "Waiting for changes in the source directory..."
    }
}
catch {
    Write-Host "Script terminated by user."
}
finally {
    Write-Host "Replication stopped. Check the log file for details: $LogFile"
}
