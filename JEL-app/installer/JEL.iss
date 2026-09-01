#ifndef AppVersion
#define AppVersion "0.1.0"
#endif
#define AppName "JEL"
#define AppPublisher "JerEx"
#define AppExeName "JEL.exe"

[Setup]
AppId={{9D6D9B35-4A1F-4C39-9B0E-1E4D9A6D0E10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\JerEx\JEL
DefaultGroupName=JerEx\JEL
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=JEL-Setup-{#AppVersion}-win-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\src\JEL.App\Assets\JEL.ico

[Files]
Source: "..\publish\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\JEL"; Filename: "{app}\{#AppExeName}"
Name: "{commondesktop}\JEL"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch JEL"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
