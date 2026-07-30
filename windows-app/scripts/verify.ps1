[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$windowsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$solution = Join-Path $windowsRoot 'LocalMusicPlayer.slnx'
$userNuGetCache = [Environment]::GetEnvironmentVariable(
    'NUGET_PACKAGES',
    'User')
if (-not [string]::IsNullOrWhiteSpace($userNuGetCache)) {
    $env:NUGET_PACKAGES = $userNuGetCache
}

function Invoke-DotNet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

Write-Host 'Restoring NuGet packages...'
Invoke-DotNet restore $solution --nologo

Write-Host 'Checking C# formatting...'
Invoke-DotNet format $solution --verify-no-changes --no-restore --verbosity minimal

Write-Host 'Building the Windows app in Release mode...'
Invoke-DotNet build $solution -c Release --no-restore --nologo

Write-Host 'Running all Windows tests...'
Invoke-DotNet test $solution -c Release --no-build --no-restore --nologo --verbosity minimal

Write-Host 'Checking NuGet dependencies for known vulnerabilities...'
Invoke-DotNet list $solution package --vulnerable --include-transitive

Write-Host 'Windows verification completed successfully.'
