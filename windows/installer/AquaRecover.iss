#define AppName "AquaRecover"
#define AppPublisher "AquaRecover contributors"
#define AppURL "https://github.com/FinnGrndl/AquaRecover"
#define AppVersion GetEnv("AQUA_VERSION")
#define AppBuildDir GetEnv("AQUA_WINDOWS_BUILD_DIR")
#define AppOutputDir GetEnv("AQUA_INSTALLER_OUTPUT_DIR")

[Setup]
AppId={{A80A83E4-227B-49EA-B820-C5AF5906AB1B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\AquaRecover.exe
OutputDir={#AppOutputDir}
OutputBaseFilename=AquaRecover-Windows-{#AppVersion}
LicenseFile=..\..\LICENSE

[Files]
Source: "{#AppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\AquaRecover.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\AquaRecover.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\AquaRecover.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
