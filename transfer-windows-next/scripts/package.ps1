param(
    [string]$IsccPath = "${env:ProgramFiles}\Inno Setup 7\ISCC.exe"
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$publish = Join-Path $root 'artifacts\publish'
$applicationProject = Join-Path $root 'src\AiyueTransfer.App\AiyueTransfer.App.csproj'
$installerScript = Join-Path $root 'installer\AiyueTransferNext.iss'
$sharedIcon = Join-Path $root '..\transfer-windows\src\MuseTransfer.App\app.ico'

& (Join-Path $PSScriptRoot 'verify.ps1')
dotnet publish $applicationProject --configuration Release --runtime win-x64 --self-contained true --output $publish

if (-not (Test-Path -LiteralPath (Join-Path $publish 'AiyueTransfer.App.exe'))) {
    throw 'Windows publish output is missing.'
}
if (-not (Test-Path -LiteralPath $sharedIcon)) {
    throw "The installer icon asset is missing: $sharedIcon"
}

Copy-Item -LiteralPath $sharedIcon -Destination (Join-Path $publish 'AiyueTransfer.ico') -Force

if (-not (Test-Path -LiteralPath $IsccPath)) {
    $userCompiler = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'
    if (Test-Path -LiteralPath $userCompiler) {
        $IsccPath = $userCompiler
    }
}
if (-not (Test-Path -LiteralPath $IsccPath)) {
    throw "Inno Setup compiler not found: $IsccPath"
}

& $IsccPath $installerScript
if (-not (Test-Path -LiteralPath (Join-Path $root 'artifacts\installer\AiYueTransfer-Setup.exe'))) {
    throw 'Windows installer output is missing.'
}
