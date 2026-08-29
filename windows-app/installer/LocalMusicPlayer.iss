#define AppName "暮色音乐"
#define AppVersion "0.1.0"
#define AppPublisher "luolihao"
#define AppExeName "LocalMusicPlayer.exe"

[Setup]
AppId={{A0CCBA67-529A-44BE-99FA-7DE2E90EF97E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\LocalMusicPlayer
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=LocalMusicPlayer-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#AppExeName}
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式："; Flags: unchecked

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\musemusic"; ValueType: string; ValueName: ""; ValueData: "URL:暮色音乐导入协议"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\musemusic"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\musemusic\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent
