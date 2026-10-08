#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

[Setup]
AppId={{7D1E0205-ECD0-407D-96F7-E61BD74F65C2}
AppName=Meddata
AppVersion={#AppVersion}
AppVerName=Meddata {#AppVersion}
AppPublisher=Meddata
DefaultDirName={localappdata}\Programs\Meddata
DefaultGroupName=Meddata
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=Meddata-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Meddata.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Meddata"; Filename: "{app}\Meddata.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Meddata"; Filename: "{app}\Meddata.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Meddata.exe"; Description: "Launch Meddata"; Flags: postinstall nowait skipifsilent
