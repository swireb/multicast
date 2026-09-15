[CmdletBinding()]
param(
    [string]$InterfaceIp = '127.0.0.1',
    [int]$PortBase = 9000,
    [switch]$RunLocalStream
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sender = Join-Path $repositoryRoot 'output/windows-amd64/udp-sender.exe'
$receiver = Join-Path $repositoryRoot 'output/windows-amd64/udp-receiver.exe'
$source = Join-Path $repositoryRoot 'src/sender-diskio.c'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Validation failed: $Message" }
}

function Start-UdpcastProcess {
    param([string]$FileName, [string[]]$Arguments)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FileName
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    Assert-True $process.Start() 'Unable to start udp-sender.'
    return $process
}

Assert-True (Test-Path -LiteralPath $sender) 'Missing Windows udp-sender.exe; run build.ps1 first.'
Assert-True (($PortBase % 2) -eq 0) 'PortBase must be even.'
Assert-True ((Get-Content -Raw -LiteralPath $source).Contains('setmode(0, O_BINARY)')) 'Upstream Windows stdin binary-mode guard is missing.'

# 只有一个接收端但 min-receivers=2。--start-timeout 到期后必须失败，不得发送数据。
$minReceiver = $null
$senderProcess = $null
try {
    $minReceiver = Start-UdpcastProcess -FileName $receiver -Arguments @('--interface', $InterfaceIp, '--portbase', "$PortBase", '--start-timeout', '10', '--receive-timeout', '10', '--nokbd', '--no-progress')
    Start-Sleep -Milliseconds 500
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $senderProcess = Start-UdpcastProcess -FileName $sender -Arguments @('--interface', $InterfaceIp, '--portbase', "$PortBase", '--min-receivers', '2', '--start-timeout', '3', '--nokbd', '--no-progress')
    $senderProcess.StandardInput.BaseStream.Close()
    $exited = $senderProcess.WaitForExit(15000)
    $stopwatch.Stop()
    Assert-True $exited 'udp-sender did not exit within 15 seconds below min-receivers.'
    $stdout = $senderProcess.StandardOutput.ReadToEnd()
    $stderr = $senderProcess.StandardError.ReadToEnd()
    Assert-True ($senderProcess.ExitCode -ne 0) "udp-sender exited 0 below min-receivers; stderr=$stderr"
    Assert-True ($stderr.Contains('UDP sender for')) "udp-sender did not enter interface/session wait: $stderr"
    Assert-True ($stopwatch.Elapsed.TotalSeconds -ge 2.5) "udp-sender did not honor --start-timeout: $($stopwatch.Elapsed.TotalSeconds) seconds."
    Assert-True ($stdout.Length -eq 0) 'udp-sender wrote data or logging to stdout.'
    Write-Output "One-receiver min-receivers=2 start-timeout passed (exit=$($senderProcess.ExitCode), elapsed=$([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s)."
} finally {
    foreach ($process in @($senderProcess, $minReceiver)) {
        if ($null -ne $process -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    }
}

if (-not $RunLocalStream) {
    Write-Output 'No local-stream test requested; it cannot replace cross-host or Windows-to-Linux validation.'
    exit 0
}

Assert-True (Test-Path -LiteralPath $receiver) 'Missing Windows udp-receiver.exe; run build.ps1 first.'
$streamPortBase = $PortBase + 2
$dataMcast = '239.192.0.2'
$rdvMcast = '239.192.0.3'
$payload = [byte[]]::new((4096 * 3) + 257)
for ($index = 0; $index -lt $payload.Length; $index++) { $payload[$index] = [byte]($index % 256) }
$receiverProcess = $null
$streamSender = $null
try {
    $receiverProcess = Start-UdpcastProcess -FileName $receiver -Arguments @('--interface', $InterfaceIp, '--portbase', "$streamPortBase", '--mcast-rdv-address', $rdvMcast, '--start-timeout', '10', '--receive-timeout', '10', '--nokbd', '--no-progress')
    $received = [System.IO.MemoryStream]::new()
    $copyTask = $receiverProcess.StandardOutput.BaseStream.CopyToAsync($received)
    Start-Sleep -Milliseconds 500
    $streamSender = Start-UdpcastProcess -FileName $sender -Arguments @('--interface', $InterfaceIp, '--portbase', "$streamPortBase", '--mcast-data-address', $dataMcast, '--mcast-rdv-address', $rdvMcast, '--min-receivers', '1', '--start-timeout', '10', '--nokbd', '--no-progress')
    $streamSender.StandardInput.BaseStream.Write($payload, 0, $payload.Length)
    $streamSender.StandardInput.BaseStream.Close()
    Assert-True $streamSender.WaitForExit(30000) 'Local-stream sender did not exit within 30 seconds.'
    Assert-True $receiverProcess.WaitForExit(30000) 'Local-stream receiver did not exit within 30 seconds.'
    $null = $copyTask.GetAwaiter().GetResult()
    $senderError = $streamSender.StandardError.ReadToEnd()
    $receiverError = $receiverProcess.StandardError.ReadToEnd()
    Assert-True ($streamSender.ExitCode -eq 0) "Local-stream sender failed: $senderError"
    Assert-True ($receiverProcess.ExitCode -eq 0) "Local-stream receiver failed: $receiverError"
    $expectedHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($payload))
    $actualHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($received.ToArray()))
    Assert-True ($actualHash -eq $expectedHash) "Local binary stream SHA-256 mismatch: $actualHash"
    Write-Output "Local Windows multi-buffer stdin/stdout stream passed (SHA-256=$actualHash); this does not represent cross-host or cross-platform multicast."
} finally {
    foreach ($process in @($streamSender, $receiverProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    }
}
