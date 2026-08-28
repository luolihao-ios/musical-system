param([string]$IsccPath = "${env:ProgramFiles}\Inno Setup 7\ISCC.exe")
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify.ps1')
if (-not (Test-Path -LiteralPath $IsccPath)) { throw "Inno Setup compiler not found: $IsccPath" }
& $IsccPath (Join-Path $PSScriptRoot '..\installer\MuseTransfer.iss')
