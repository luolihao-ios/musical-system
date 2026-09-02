$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$publish = Join-Path $root 'artifacts\publish'
dotnet publish (Join-Path $root 'src\AiyueTransfer.App\AiyueTransfer.App.csproj') --configuration Release --runtime win-x64 --self-contained true --output $publish
if (-not (Test-Path (Join-Path $publish 'AiyueTransfer.App.exe'))) { throw 'Windows publish output is missing.' }
