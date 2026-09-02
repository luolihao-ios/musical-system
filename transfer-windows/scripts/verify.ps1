$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
dotnet restore (Join-Path $root 'MuseTransfer.slnx')
dotnet build (Join-Path $root 'MuseTransfer.slnx') --configuration Release --no-restore
dotnet test (Join-Path $root 'MuseTransfer.slnx') --configuration Release --no-build
$publish = Join-Path $root 'artifacts\publish'
dotnet publish (Join-Path $root 'src\MuseTransfer.App\MuseTransfer.App.csproj') --configuration Release --runtime win-x64 --self-contained true --output $publish
if (-not (Test-Path (Join-Path $publish 'MuseTransfer.App.exe'))) { throw 'MuseTransfer.App.exe was not published.' }
if (-not (Select-String -Path (Join-Path $root 'src\MuseTransfer.App\MainWindow.xaml') -Pattern 'LocalPublicKey, Mode=OneWay')) { throw 'LocalPublicKey must use a one-way binding.' }
if (-not (Select-String -Path (Join-Path $root 'src\MuseTransfer.App\MainWindow.xaml') -Pattern 'Progress, Mode=OneWay')) { throw 'Progress must use a one-way binding.' }
if (-not (Select-String -Path (Join-Path $root 'installer\MuseTransfer.iss') -Pattern '\{autodesktop\}')) { throw 'Desktop shortcut is not configured.' }
if (-not (Test-Path (Join-Path $root 'src\MuseTransfer.App\app.ico'))) { throw 'Application icon is missing.' }
