; Inno Setup script to package the Windows bundle of Meeting Minutes App
; Requires: Inno Setup (iscc.exe) on Windows

[Setup]
AppId={{C6C6ED80-7B47-4B8B-8EFB-0E9E9C5B9A9E}
AppName=Meeting Minutes
AppVersion=1.0.0
AppPublisher=Your Organization
DefaultDirName={autopf}\\Meeting Minutes
DisableDirPage=no
DefaultGroupName=Meeting Minutes
DisableProgramGroupPage=no
OutputDir=..\\..\\dist\\windows
OutputBaseFilename=MeetingMinutesSetup
ArchitecturesInstallIn64BitMode=x64
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Package the entire Flutter Windows release bundle
; Make sure you've run: flutter build windows
Source: "..\\..\\flutter_app\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\\Meeting Minutes"; Filename: "{app}\\meeting_minutes_app.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\\Meeting Minutes"; Filename: "{app}\\meeting_minutes_app.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\\meeting_minutes_app.exe"; Description: "Launch Meeting Minutes"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

