[CmdletBinding()]
param(
    [ValidateSet('WindowsAmd64', 'LinuxAmd64')]
    [string]$Target = 'WindowsAmd64',
    [switch]$RequireBinary
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $repositoryRoot 'upstream.lock.json'
$sourcePath = Join-Path $repositoryRoot 'src'
$binarySubdirectory = if ($Target -eq 'WindowsAmd64') { 'windows-amd64' } else { 'linux-amd64' }
$binaryDirectory = Join-Path $repositoryRoot (Join-Path 'output' $binarySubdirectory)
$senderName = if ($Target -eq 'WindowsAmd64') { 'udp-sender.exe' } else { 'udp-sender' }
$receiverName = if ($Target -eq 'WindowsAmd64') { 'udp-receiver.exe' } else { 'udp-receiver' }
$sender = Join-Path $binaryDirectory $senderName
$receiver = Join-Path $binaryDirectory $receiverName

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Validation failed: $Message" }
}

function Invoke-UsageOutput {
    param([string]$FileName)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FileName
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $info.Arguments = '--help'
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    Assert-True $process.Start() "Unable to start $FileName."
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = "$stdout`n$stderr" }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
Assert-True ($manifest.version -eq '20250223') 'Unexpected source manifest version.'
Assert-True ($manifest.source.sha256 -eq 'cefd7554c877e1bc76987d2b96b23f7699a2e5340c254454f61b6e0dae370aa7') 'Unexpected source manifest SHA-256.'
Assert-True (Test-Path -LiteralPath (Join-Path $sourcePath 'COPYING')) 'Missing upstream COPYING.'
Assert-True (Test-Path -LiteralPath (Join-Path $sourcePath 'sender-diskio.c')) 'Missing upstream sender source.'
Assert-True (Test-Path -LiteralPath (Join-Path $sourcePath 'receiver-diskio.c')) 'Missing upstream receiver source.'

if (-not (Test-Path -LiteralPath $sender) -or -not (Test-Path -LiteralPath $receiver)) {
    if ($RequireBinary) {
        throw "Validation failed: missing $Target artifacts; run its build script first."
    }
    Write-Output "Static validation passed; $Target artifacts are absent, so --help and stream checks are skipped."
    exit 0
}

if ($Target -eq 'WindowsAmd64') {
    $senderUsage = Invoke-UsageOutput -FileName $sender
    $receiverUsage = Invoke-UsageOutput -FileName $receiver
    Assert-True ($senderUsage.ExitCode -eq 1) "udp-sender --help usage exit code = $($senderUsage.ExitCode), want 1."
    Assert-True ($receiverUsage.ExitCode -eq 1) "udp-receiver --help usage exit code = $($receiverUsage.ExitCode), want 1."
    Assert-True ($senderUsage.Output -match 'udp-sender\.exe \[--file file\]') 'udp-sender --help did not produce its usage line.'
    Assert-True ($receiverUsage.Output -match 'udp-receiver\.exe \[--file file\]') 'udp-receiver --help did not produce its usage line.'
    foreach ($option in '--interface', '--portbase', '--mcast-data-address', '--mcast-rdv-address', '--min-receivers', '--max-wait', '--min-wait', '--nokbd') {
        Assert-True ($senderUsage.Output.Contains($option)) "udp-sender --help is missing $option."
    }
    Assert-True ($receiverUsage.Output.Contains('--portbase')) 'udp-receiver --help is missing --portbase.'
    Assert-True ($receiverUsage.Output.Contains('--nokbd')) 'udp-receiver --help is missing --nokbd.'
    Write-Output 'Windows binaries produced expected usage text and exit code for --help.'
} else {
    Write-Output 'Linux amd64 artifact exists; this Windows host did not run ELF --help.'
}
