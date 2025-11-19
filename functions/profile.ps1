function ll { Get-ChildItem -Force -ErrorAction SilentlyContinue -ErrorVariable +err | Format-Table -AutoSize }

function ls { Get-ChildItem -Force -ErrorAction SilentlyContinue -ErrorVariable +err | Format-Wide -Column 5 }

function traceroute {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )

    tracert $IpAddress
}

function cert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $false)]
        [int]$Port = 443
    )

    $uri = [System.Uri]::new($Url)
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $tcpClient.Connect($uri.Host, $Port)
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream())
        try {
            $sslStream.AuthenticateAsClient($uri.Host)
            $cert = $sslStream.RemoteCertificate

            $certInfo = @{
                Url           = $Url
                Port          = $Port
                Subject       = $cert.Subject
                Issuer        = $cert.Issuer
                NotBefore     = $cert.GetEffectiveDateString()
                NotAfter      = $cert.GetExpirationDateString()
                DaysRemaining = ($cert.NotAfter - (Get-Date)).Days
            }

            return New-Object -TypeName PSObject -Property $certInfo
        }
        catch {
            Write-Error "Error checking SSL certificate for ${$Url}:${$Port} : ${$_}"
        }
        finally {
            $sslStream.Dispose()
        }
    }
    catch {
        Write-Error "Error connecting to ${$Url}:${$Port} : ${$_}"
    }
    finally {
        $tcpClient.Dispose()
    }
}

function tail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [int]$Lines = 10
    )

    Get-Content $Path -Tail $Lines -Wait
}

function lookup {
    param(
        [Parameter(Mandatory = $false)]
        [string]$IpAddress
    )

    if ($IpAddress -eq '') {
        $url = "https://ipinfo.io/json?token=REPLACE"
    }
    else {
        $url = "https://ipinfo.io/$IpAddress/json?token=REPLACE"
    }

    $response = Invoke-RestMethod $url

    $result = [ordered]@{
        IP           = $response.ip
        Hostname     = $response.hostname
        City         = $response.city
        Region       = $response.region
        Country      = $response.country
        PostalCode   = $response.postal
        Latitude     = $response.loc.Split(',')[0]
        Longitude    = $response.loc.Split(',')[1]
        Timezone     = $response.timezone
        Organization = $response.org
    }

    Write-Output $result
}

function hst {
    param (
        [int]$Count = 10
    )

    $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"

    if (Test-Path $historyPath) {
        $history = Get-Content $historyPath
        $totalCommands = $history.Count

        if ($Count -gt 0) {
            $startIndex = [Math]::Max(0, $totalCommands - $Count)
            $history = $history[$startIndex..($totalCommands - 1)]
        }

        for ($i = 0; $i -lt $history.Count; $i++) {
            $commandNumber = $totalCommands - $history.Count + $i + 1
            Write-Output ("{0,6}  {1}" -f $commandNumber, $history[$i])
        }
    }
    else {
        Write-Warning "History file not found at $historyPath"
    }
}

function tree {
    param (
        [string]$path = ".",
        [string[]]$ignore = @(".git", "__pycache__", "node_modules", ".idea", ".vscode"),
        [int]$max_depth = $null,
        [string]$output = $null
    )

    function get_directory_tree {
        param (
            [string]$root_path = ".",
            [string[]]$ignore_patterns = @(),
            [int]$max_depth = $null,
            [int]$current_depth = 0,
            [string]$indent = ""
        )

        if ($null -ne $max_depth -and $current_depth -gt $max_depth) { return }

        try {
            $items = Get-ChildItem -Path $root_path -ErrorAction Stop | Sort-Object Name
        }
        catch {
            Write-Output "$indent├── [Access Denied]"
            return
        }

        $total_items = ($items | Where-Object {
                $item_name = $_.Name
                -not ($ignore_patterns | Where-Object { $item_name -like "*$_*" })
            }).Count

        $current_item = 0

        foreach ($item in $items) {
            $should_ignore = $ignore_patterns | Where-Object { $item.Name -like "*$_*" }
            if ($should_ignore) { continue }

            $current_item++
            $is_last = ($current_item -eq $total_items)
            $prefix = if ($is_last) { "└── " } else { "├── " }
            $new_indent = if ($is_last) { $indent + "    " } else { $indent + "│   " }

            Write-Output "$indent$prefix$($item.Name)"
            if ($item.PSIsContainer) {
                get_directory_tree -root_path $item.FullName -ignore_patterns $ignore_patterns -max_depth $max_depth -current_depth ($current_depth + 1) -indent $new_indent
            }
        }
    }

    $absolute_path = (Resolve-Path $path).Path
    $tree_output = @("$absolute_path")
    $tree_output += get_directory_tree -root_path $absolute_path -ignore_patterns $ignore -max_depth $max_depth

    if ($output) {
        $tree_output | Out-File -FilePath $output -Encoding utf8
        Write-Host "Tree structure written to $output"
    }
    else {
        $tree_output
    }
}

$Detailed = $true

function Write-Diag {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    if ($script:Detailed) {
        $ts = (Get-Date).ToString('o')
        $origColor = $Host.UI.RawUI.ForegroundColor
        try { $Host.UI.RawUI.ForegroundColor = $Color } catch {}
        Write-Host "[DIAG $ts] $Message"
        try { $Host.UI.RawUI.ForegroundColor = $origColor } catch {}
    }
}

function Get-MxHost([string]$d) {
    Write-Diag "Resolving MX records for domain '$d'"
    $mxRecords = Resolve-DnsName -Type MX -Name $d -ErrorAction Stop | Sort-Object -Property Preference
    if (-not $mxRecords) { throw "No MX found for $d" }
    foreach ($r in $mxRecords) {
        Write-Diag (" MX preference={0} host={1}" -f $r.Preference, $r.NameExchange.TrimEnd('.'))
    }
    $best = $mxRecords | Select-Object -First 1 -ExpandProperty NameExchange
    $best = $best.TrimEnd('.')
    Write-Diag "Selected MX host: $best"
    # Resolve A / AAAA
    try {
        $addresses = Resolve-DnsName -Name $best -Type A -ErrorAction Stop | Where-Object { $_.Type -in 'A' }
        foreach ($a in $addresses) { Write-Diag ("  IP {0} ({1})" -f $a.IPAddress, $a.Type) }
    }
    catch { Write-Diag "Address resolution failed for $($best): $($_.Exception.Message)" 'Yellow' }
    return $best
}

function New-Mail([string]$from, [string]$to, [string]$subj, [string]$body) {
    $m = [System.Net.Mail.MailMessage]::new()
    $m.From = $from
    $m.To.Add($to)
    $m.Subject = $subj
    $m.Body = $body
    $m.IsBodyHtml = $false
    Write-Diag "Mail object created: From=$($from) To=$($to) Subject='$($subj)' Size(bytes)=$(([System.Text.Encoding]::UTF8.GetByteCount($body)))"
    return $m
}

function Test-SmtpConnectivity([string]$hostname, [int]$port = 25) {
    Write-Diag "Testing TCP connectivity to $($hostname):$($port)"
    $result = [pscustomobject]@{ Host = $hostname; Port = $port; LatencyMs = $null; Banner = $null; Error = $null }
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp.Connect($hostname, $port)
        $sw.Stop()
        $result.LatencyMs = $sw.ElapsedMilliseconds
        $stream = $tcp.GetStream()
        Start-Sleep -Milliseconds 200
        if ($stream.DataAvailable) {
            $buffer = New-Object byte[] 1024
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
            $result.Banner = $banner
        }
        $stream.Dispose()
        $tcp.Close()
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    if ($result.Error) { Write-Diag " TCP connect failed: $($result.Error)" 'Red' } else { Write-Diag " TCP latency ${($result.LatencyMs)}ms Banner: $($result.Banner)" }
    return $result
}

function Send-Try([string]$hostname, [bool]$ssl, [System.Net.Mail.MailMessage]$msg) {
    Write-Diag "Attempting send via host=$hostname TLS=$ssl"
    $c = [System.Net.Mail.SmtpClient]::new($hostname, 25)
    $c.EnableSsl = $ssl
    $c.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
    $c.UseDefaultCredentials = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $c.Send($msg)
        $sw.Stop()
        Write-Diag " Send succeeded in ${($sw.ElapsedMilliseconds)}ms"
        "OK: Sent via $hostname on 25 (TLS=$ssl)"
    }
    catch {
        $sw.Stop()
        $ex = $_.Exception
        $msgs = @()
        while ($ex) { $msgs += $ex.Message; $ex = $ex.InnerException }
        Write-Diag (" Send failed in {0}ms: {1}" -f $sw.ElapsedMilliseconds, ($msgs -join ' | ')) 'Yellow'
        "ERR (TLS=$ssl): $($msgs -join ' | ')"
    }
    finally {
        $c.Dispose()
    }
}

function smtp-test {
    param(
        [Parameter(Mandatory)] [string] $Domain,          # accepted domain in EXO, e.g. 'example.com'
        [Parameter(Mandatory)] [string] $From,            # e.g. 'noreply@example.com'
        [Parameter(Mandatory)] [string] $To,              # test recipient (internal or external)
        [string] $Subject = 'SMTP test via connector relay',
        [string] $Body = 'SMTP test message sent via connector relay.'
    )

    $mx = Get-MxHost $Domain
    $connInfo = Test-SmtpConnectivity -host $mx -port 25
    $msg = New-Mail $From $To $Subject $Body

    Write-Diag "Beginning send attempts (first with TLS, then without if needed)"
    $result1 = Send-Try $mx $true  $msg
    if ($result1 -like 'OK:*') {
        Write-Diag "First attempt succeeded. Skipping plaintext attempt." 'Green'
        $result1
        return
    }

    $result2 = Send-Try $mx $false $msg
    if ($Detailed) { Write-Diag "Final results:"; Write-Diag "  TLS attempt: $result1"; Write-Diag "  Plain attempt: $result2" }
    $result1
    $result2
}
