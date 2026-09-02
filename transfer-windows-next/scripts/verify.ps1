$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testProject = Join-Path $root 'tests\AiyueTransfer.Protocol.Tests\AiyueTransfer.Protocol.Tests.csproj'

dotnet test $testProject --configuration Release --no-restore
