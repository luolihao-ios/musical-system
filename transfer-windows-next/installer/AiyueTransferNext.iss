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
SetupIconFile=..\..\transfer-windows\src\MuseTransfer.App\app.ico

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\AiyueTransfer.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\AiyueTransfer.ico"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""AiYueTransfer TCP 54218"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""AiYueTransfer discovery UDP 54217"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""AiYueTransfer mDNS UDP 5353"""; Flags: runhidden waituntilterminated

[Code]
procedure AddFirewallRule(const RuleName, Protocol, LocalPort: String);
var
  ResultCode: Integer;
  Parameters: String;
begin
  Parameters := 'advfirewall firewall add rule name="' + RuleName + '" dir=in action=allow protocol=' + Protocol +
    ' localport=' + LocalPort + ' profile=private,public program="' + ExpandConstant('{app}\{#AppExeName}') + '"';
  if (not Exec(ExpandConstant('{sys}\netsh.exe'), Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
    MsgBox('爱乐互传未能自动添加 ' + Protocol + ' ' + LocalPort + ' 防火墙规则。请在 Windows Defender 防火墙中允许此程序在专用和公用网络上接收入站连接。', mbError, MB_OK);
end;

procedure RemoveFirewallRule(const RuleName: String);
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="' + RuleName + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Parameters: String;
begin
  if CurStep = ssPostInstall then begin
    { Remove the two rules from earlier versions that overlapped LocalSend. }
    RemoveFirewallRule('AiYueTransfer TCP 53317');
    RemoveFirewallRule('AiYueTransfer UDP 53317');
    AddFirewallRule('AiYueTransfer TCP 54218', 'TCP', '54218-54318');
    AddFirewallRule('AiYueTransfer discovery UDP 54217', 'UDP', '54217');
    { Bonjour/mDNS replies arrive on UDP 5353, not on the transfer port. }
    Parameters := 'advfirewall firewall add rule name="AiYueTransfer mDNS UDP 5353" dir=in action=allow protocol=UDP' +
      ' localport=5353 profile=private,public program="' + ExpandConstant('{app}\{#AppExeName}') + '"';
    Exec(ExpandConstant('{sys}\netsh.exe'), Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
