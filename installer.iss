; Inno Setup script: per-user install, no admin. Built by release.ps1 (it passes /DAppVersion).
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{7D38264A-DF9B-47A7-8851-C432181DD6CA}
AppName=KitsuneRoblox
AppVersion={#AppVersion}
AppPublisher=mihoshiho
AppPublisherURL=https://github.com/mihoshiho/KitsuneRoblox
DefaultDirName={localappdata}\Programs\KitsuneRoblox
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=build
OutputBaseFilename=KitsuneRoblox-Setup
SetupIconFile=ui\fox.ico
UninstallDisplayIcon={app}\KitsuneRoblox.exe
UninstallDisplayName=KitsuneRoblox
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: startup; Description: "Start with Windows"; Flags: unchecked

[Files]
Source: "build\KitsuneRoblox.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "lib\WebView2\64bit\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "ui\index.html"; DestDir: "{app}\ui"; Flags: ignoreversion
Source: "ui\fox.ico"; DestDir: "{app}\ui"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\KitsuneRoblox"; Filename: "{app}\KitsuneRoblox.exe"
Name: "{userstartup}\KitsuneRoblox"; Filename: "{app}\KitsuneRoblox.exe"; Tasks: startup

[Run]
; also after a quiet update: the app starts again by itself. Through Explorer: started by Setup directly,
; the app gets Setup's "redirection guard" and can't open Roblox through the per-account folder links.
Filename: "{win}\explorer.exe"; Parameters: """{app}\KitsuneRoblox.exe"""; Description: "Open KitsuneRoblox"; Flags: nowait postinstall
