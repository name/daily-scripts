$replicationTasks = @(
    @{
        SourcePath      = "\\serv\source"
        DestinationPath = "D:\destination"
        ReplicationName = "Job1"
    },
    @{
        SourcePath      = "\\serv\source2"
        DestinationPath = "D:\destination2"
        ReplicationName = "Job2"
    },
    @{
        SourcePath      = "\\serv\source3"
        DestinationPath = "D:\destination3"
        ReplicationName = "Job3"
    }
)

$jobs = @()

$scriptPath = Join-Path $PSScriptRoot "continuous-replication.ps1"

foreach ($task in $replicationTasks) {
    $jobScript = {
        param($scriptPath, $sourcePath, $destinationPath, $replicationName)
        try {
            & $scriptPath -SourcePath $sourcePath -DestinationPath $destinationPath -ReplicationName $replicationName -NoConfirmation
        }
        catch {
            Write-Error "Error in replication task: $_"
            throw
        }
    }

    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $scriptPath, $task.SourcePath, $task.DestinationPath, $task.ReplicationName
    $jobs += $job
}

Write-Host "All replication tasks started. Press Ctrl+C to stop all tasks."

try {
    $jobs | Wait-Job -Timeout 5

    $failedJobs = $jobs | Where-Object { $_.State -eq 'Failed' }
    if ($failedJobs) {
        Write-Host "The following jobs have failed:"
        foreach ($job in $failedJobs) {
            Write-Host "Job $($job.Id): $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
        }
    }

    while ($true) {
        Start-Sleep -Seconds 10
        $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
        if (-not $runningJobs) {
            Write-Host "All jobs have completed or failed. Exiting."
            break
        }
    }
}
catch {
    Write-Host "Termination signal received. Stopping all replication tasks..."
}
finally {
    $jobs | Stop-Job
    $jobs | Remove-Job

    Write-Host "All replication tasks have been stopped."
}
