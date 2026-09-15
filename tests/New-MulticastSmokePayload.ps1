[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$resolvedParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $Path))
if (-not (Test-Path -LiteralPath $resolvedParent -PathType Container)) {
    throw "目标目录不存在：$resolvedParent"
}

$payload = [byte[]]::new(1MB)
for ($index = 0; $index -lt $payload.Length; $index++) {
    $payload[$index] = [byte]($index % 256)
}

[System.IO.File]::WriteAllBytes($Path, $payload)
(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
