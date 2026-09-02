#define AppName "爱乐互传"
#define AppVersion "1.0.0"
#define AppExeName "AiyueTransfer.App.exe"

[Setup]
AppId={{1B8E3B22-82C1-49C9-881A-C4F15A057C16}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=luolihao
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=AiYueTransfer-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""AiYueTransfer TCP 53317"" dir=in action=allow protocol=TCP localport=53317 profile=private,public program=""{app}\{#AppExeName}"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""AiYueTransfer UDP 53317"" dir=in action=allow protocol=UDP localport=53317 profile=private,public program=""{app}\{#AppExeName}"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#AppExeName}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""AiYueTransfer TCP 53317"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""AiYueTransfer UDP 53317"""; Flags: runhidden waituntilterminated
