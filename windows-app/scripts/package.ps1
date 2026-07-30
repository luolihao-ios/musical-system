[CmdletBinding()]
param(
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
$windowsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$project = Join-Path $windowsRoot 'src\LocalMusicPlayer\LocalMusicPlayer.csproj'
$publishPath = [System.IO.Path]::GetFullPath(
    (Join-Path $windowsRoot 'artifacts\publish'))
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $windowsRoot 'artifacts'))
$installerScript = Join-Path $windowsRoot 'installer\LocalMusicPlayer.iss'
$userNuGetCache = [Environment]::GetEnvironmentVariable(
    'NUGET_PACKAGES',
    'User')
if (-not [string]::IsNullOrWhiteSpace($userNuGetCache)) {
    $env:NUGET_PACKAGES = $userNuGetCache
}

if (-not $publishPath.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean a publish path outside $artifactsRoot."
}

if (Test-Path -LiteralPath $publishPath) {
    Remove-Item -LiteralPath $publishPath -Recurse -Force
}
New-Item -ItemType Directory -Path $publishPath -Force | Out-Null

& dotnet publish $project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    --nologo `
    -p:PublishSingleFile=false `
    -o $publishPath
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $candidates = @(
        $env:ISCC_PATH,
        'E:\DevTools\Inno Setup 7\ISCC.exe',
        'E:\DevTools\InnoSetup7\ISCC.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $IsccPath = $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

$missingCompiler = [string]::IsNullOrWhiteSpace($IsccPath)
$compilerDoesNotExist = -not (
    -not $missingCompiler -and (Test-Path -LiteralPath $IsccPath))
if ($missingCompiler -or $compilerDoesNotExist) {
    throw 'ISCC.exe was not found. Pass -IsccPath or set ISCC_PATH.'
}

& $IsccPath $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
}

$portableExe = Join-Path $publishPath 'LocalMusicPlayer.exe'
$installerExe = Join-Path $artifactsRoot 'installer\LocalMusicPlayer-Setup.exe'
$portableMissing = -not (Test-Path -LiteralPath $portableExe)
$installerMissing = -not (Test-Path -LiteralPath $installerExe)
if ($portableMissing -or $installerMissing) {
    throw 'Expected Windows package artifacts were not produced.'
}

Write-Host "Portable app: $portableExe"
Write-Host "Installer:    $installerExe"
