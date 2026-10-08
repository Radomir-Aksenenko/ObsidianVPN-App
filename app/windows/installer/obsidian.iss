; Inno Setup 6 script for the Obsidian Windows app.
; Built by .github/workflows/app.yml (windows job) with:
;   ISCC.exe /DAppVersion=<VERSION> /DOutputName=obsidian-windows-x64-setup /DOutputDirPath=<dir> obsidian.iss
; Source files come from the Flutter Release folder (app/build/windows/x64/runner/Release).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef OutputName
  #define OutputName "obsidian-windows-x64-setup"
#endif
#ifndef OutputDirPath
  #define OutputDirPath "..\..\..\dist"
#endif

; Flutter runner binary name (BINARY_NAME in app/windows/CMakeLists.txt).
#define AppExeName "Obsidian.exe"
; Go VPN client bundled with the app (app/assets/bin, copied next to the exe).
#define ClientExeName "obsidian-client-windows-amd64.exe"

[Setup]
AppId={{3029B839-2801-45C1-A184-19ED1C121761}
AppName=Obsidian
AppVersion={#AppVersion}
AppPublisher=Obsidian
DefaultDirName={autopf}\Obsidian
DefaultGroupName=Obsidian
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDirPath}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName=Obsidian
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Obsidian"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Obsidian"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,Obsidian}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#ClientExeName}"; Flags: runhidden; RunOnceId: "KillClient"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExeName}"; Flags: runhidden; RunOnceId: "KillApp"

[Code]
const
  OldAppPrefix = 'ObsidianVPN';
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall';
  WowUninstallKey = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall';

procedure KillProcess(const ImageName: string);
var
  ResultCode: Integer;
begin
  { Failures (process not running) are ignored. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM "' + ImageName + '"', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ Runs the uninstaller of every "ObsidianVPN*" entry (the old Tauri client) under RootKey/BaseKey. }
procedure RunOldUninstallers(RootKey: Integer; BaseKey: string);
var
  Names: TArrayOfString;
  I: Integer;
  DisplayName, Cmd, EntryKey: string;
  ResultCode: Integer;
begin
  if not RegGetSubkeyNames(RootKey, BaseKey, Names) then
    Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    EntryKey := BaseKey + '\' + Names[I];
    DisplayName := '';
    if RegQueryStringValue(RootKey, EntryKey, 'DisplayName', DisplayName) and
       (Pos(OldAppPrefix, DisplayName) = 1) then
    begin
      Cmd := '';
      if not RegQueryStringValue(RootKey, EntryKey, 'QuietUninstallString', Cmd) then
      begin
        if RegQueryStringValue(RootKey, EntryKey, 'UninstallString', Cmd) then
          Cmd := Cmd + ' /S';
      end;
      if Cmd <> '' then
        { Failures are ignored: the new install proceeds regardless. }
        Exec(ExpandConstant('{cmd}'), '/C "' + Cmd + '"', '', SW_HIDE,
          ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    KillProcess('ObsidianVPN.exe');
    KillProcess('obsidian_vpn.exe');
    KillProcess('obsidian-client.exe');
    KillProcess('{#ClientExeName}');
    KillProcess('{#AppExeName}');
    RunOldUninstallers(HKLM, UninstallKey);
    RunOldUninstallers(HKLM, WowUninstallKey);
    RunOldUninstallers(HKCU, UninstallKey);
  end;
end;
