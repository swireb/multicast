[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('windows-amd64', 'linux-amd64', 'all')]
    [string]$Target = 'all',
    [string]$ZigPath,
    [string]$PinnedZigArchive,
    [switch]$DownloadToolchain,
    [switch]$Check,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$sourceRoot = Join-Path $repoRoot 'src'
$patchRoot = Join-Path $repoRoot 'patches'
$buildRoot = Join-Path $repoRoot 'build'
$workRoot = Join-Path $buildRoot 'work'
$cacheRoot = Join-Path $buildRoot 'cache'
$toolsRoot = Join-Path $buildRoot 'tools'
$outputRoot = Join-Path $repoRoot 'output'
$zigVersion = '0.14.1'
$zigArchive = Join-Path $toolsRoot 'zig-x86_64-windows-0.14.1.zip'
$zigInstall = Join-Path $toolsRoot 'zig-x86_64-windows-0.14.1\zig.exe'
$zigArchiveSha256 = '554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c'
$zigUrl = 'https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip'

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "构建前置条件失败：$Message" } }
function Assert-WithinRepo([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    Assert-True ($full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) "路径超出 multicast 仓库：$full"
    return $full
}
function Assert-DeletionTarget([string]$Path) {
    $full = Assert-WithinRepo $Path
    Assert-True ($full -eq $workRoot -or $full.StartsWith($workRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $full -eq $cacheRoot -or $full.StartsWith($cacheRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $full -eq $outputRoot -or $full.StartsWith($outputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) "拒绝删除 build/tools、源码或仓库其他内容：$full"
    for ($probe = $full; $probe.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase); $probe = Split-Path -Parent $probe) {
        if (Test-Path -LiteralPath $probe) { Assert-True (-not [bool]((Get-Item -Force -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint)) "拒绝经过重解析点操作：$probe" }
        if ($probe -eq $repoRoot) { break }
    }
    return $full
}
function Find-Executable([string[]]$Names, [string[]]$Fallbacks) {
    foreach ($name in $Names) { $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($command) { return $command.Source } }
    foreach ($candidate in $Fallbacks) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate } }
    return $null
}
function Get-Zig {
    if ($ZigPath) { $zig = [IO.Path]::GetFullPath($ZigPath) }
    else {
        if ($PinnedZigArchive) { Assert-True (Test-Path -LiteralPath $PinnedZigArchive -PathType Leaf) "PinnedZigArchive 不存在：$PinnedZigArchive"; New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null; Copy-Item -LiteralPath $PinnedZigArchive -Destination $zigArchive -Force }
        if (-not (Test-Path -LiteralPath $zigArchive)) {
            Assert-True $DownloadToolchain '缺少固定 Zig；传入 -ZigPath、-PinnedZigArchive，或显式传入 -DownloadToolchain。'
            New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
            Invoke-WebRequest -UseBasicParsing -Uri $zigUrl -OutFile $zigArchive
        }
        Assert-True (Test-Path -LiteralPath $zigArchive) "缺少 Zig 归档：$zigArchive"
        Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $zigArchive).Hash.ToLowerInvariant() -eq $zigArchiveSha256) '固定 Zig 归档 SHA-256 不匹配。'
        if (-not (Test-Path -LiteralPath $zigInstall)) { Expand-Archive -LiteralPath $zigArchive -DestinationPath $toolsRoot -Force }
        $zig = $zigInstall
    }
    Assert-True (Test-Path -LiteralPath $zig -PathType Leaf) "Zig 不存在：$zig"
    Assert-True ((& $zig version).Trim() -eq $zigVersion) "需要 Zig $zigVersion。"
    return $zig
}
function Assert-Layout {
    foreach ($path in @($sourceRoot, (Join-Path $sourceRoot 'COPYING'), (Join-Path $sourceRoot 'udp-sender.c'), (Join-Path $sourceRoot 'udp-receiver.c'), (Join-Path $patchRoot '0001-windows-amd64-types.patch'))) { Assert-True (Test-Path -LiteralPath $path) "缺少锁定源码或补丁：$path" }
}
function New-WorkCopy([string]$Name) {
    $work = Assert-DeletionTarget (Join-Path $workRoot $Name)
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $work -Recurse -Force
    $patch = Find-Executable @('patch.exe', 'patch') @((Join-Path $env:ProgramFiles 'Git\usr\bin\patch.exe'))
    Assert-True ($null -ne $patch) '缺少 patch（Windows 可安装 Git for Windows）。'
    Get-ChildItem -LiteralPath $patchRoot -Filter '*.patch' -File | Sort-Object Name | ForEach-Object { & $patch "--directory=$work" --strip=1 "--input=$($_.FullName)" | Out-Host; if ($LASTEXITCODE -ne 0) { throw "补丁应用失败：$($_.Name)" } }
    return $work
}
function Invoke-Configure([string]$Work, [string]$ConfigureHost, [string]$ZigTarget, [string]$Zig) {
    $bash = Find-Executable @('bash.exe', 'bash') @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'))
    Assert-True ($null -ne $bash) '缺少 POSIX bash（Windows 可安装 Git for Windows）。'
    New-Item -ItemType Directory -Force -Path (Join-Path $cacheRoot 'zig-global'), (Join-Path $cacheRoot 'zig-local') | Out-Null
    $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $cacheRoot 'zig-global'
    $env:ZIG_LOCAL_CACHE_DIR = Join-Path $cacheRoot 'zig-local'
    $env:CC = "$(($Zig -replace '\\', '/')) cc -target $ZigTarget"; $env:CFLAGS = '-O2 -Wall -D_FILE_OFFSET_BITS=64'
    $workForBash = $Work -replace '\\', '/'
    & $bash --noprofile --norc -lc "export PATH=/usr/bin:/bin:`$PATH; cd '$workForBash' && sh ./configure --host=$ConfigureHost"
    if ($LASTEXITCODE -ne 0) { throw "configure 失败：$ConfigureHost" }
}
function Invoke-Compile([string]$Name, [string]$ZigTarget, [string]$ConfigureHost, [string]$Zig) {
    $work = New-WorkCopy $Name; Invoke-Configure $work $ConfigureHost $ZigTarget $Zig
    $out = Join-Path $outputRoot $Name; New-Item -ItemType Directory -Force -Path $out | Out-Null
    $extension = if ($Name -eq 'windows-amd64') { '.exe' } else { '' }
    $sender = @('udp-sender.c','socklib.c','udpcast.c','strparse.c','rateGovernor.c','rate-limit.c','auto-rate.c','sender-diskio.c','senddata.c','udps-negotiate.c','fifo.c','produconsum.c','participants.c','log.c','statistics.c','fec.c','udpc_version.c','console.c','process.c') | ForEach-Object { Join-Path $work $_ }
    $receiver = @('udp-receiver.c','socklib.c','udpcast.c','strparse.c','receiver-diskio.c','receivedata.c','udpr-negotiate.c','produconsum.c','fifo.c','log.c','statistics.c','fec.c','udpc_version.c','console.c','process.c') | ForEach-Object { Join-Path $work $_ }
    if ($Name -eq 'windows-amd64') {
        & $Zig cc -target $ZigTarget -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 "-I$work" @sender -lws2_32 -liphlpapi '-o' (Join-Path $out "udp-sender$extension")
        if ($LASTEXITCODE -ne 0) { throw "udp-sender 构建失败：$Name" }
        & $Zig cc -target $ZigTarget -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 "-I$work" @receiver -lws2_32 -liphlpapi '-o' (Join-Path $out "udp-receiver$extension")
    } else {
        & $Zig cc -target $ZigTarget -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 "-I$work" @sender -pthread '-o' (Join-Path $out "udp-sender$extension")
        if ($LASTEXITCODE -ne 0) { throw "udp-sender 构建失败：$Name" }
        & $Zig cc -target $ZigTarget -O2 -g0 -s -Wall -DNO_BB -D_FILE_OFFSET_BITS=64 "-I$work" @receiver -pthread '-o' (Join-Path $out "udp-receiver$extension")
    }
    if ($LASTEXITCODE -ne 0) { throw "udp-receiver 构建失败：$Name" }
    Write-Host "已生成 $out"
}

Assert-Layout
if ($Clean) {
    foreach ($path in @($workRoot, $cacheRoot, $outputRoot)) {
        if (Test-Path -LiteralPath $path) {
            $targetPath = Assert-DeletionTarget $path
            if ($PSCmdlet.ShouldProcess($targetPath, '删除本地构建产物')) { Remove-Item -LiteralPath $targetPath -Recurse -Force }
        }
    }
    exit 0
}
if ($Check) { $null = Get-Zig; Write-Host '检查通过：锁定源码、补丁与 Zig 0.14.1 已就绪。'; exit 0 }
$zig = Get-Zig
if ($Target -in @('windows-amd64','all')) { Invoke-Compile 'windows-amd64' 'x86_64-windows-gnu' 'x86_64-w64-mingw32' $zig }
if ($Target -in @('linux-amd64','all')) { Invoke-Compile 'linux-amd64' 'x86_64-linux-musl' 'x86_64-linux-musl' $zig }
