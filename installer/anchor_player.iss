; Anchor Player の Windows インストーラ定義（Inno Setup 6）
;
; 単体で叩かず tools/make-installer.ps1 …ではなく、下記のように
; バージョンを渡してコンパイルする（唯一の定義は pubspec.yaml）:
;   ISCC.exe /DAppVersion=0.7.1 installer\anchor_player.iss
;
; 出力: build\dist\AnchorPlayer-Setup-<version>.exe
;
; 配布物は build\windows\x64\runner\Release\ の中身をそのまま入れる。
; DLL（flutter_windows / libmpv など）を利用者が意識しなくて済むようにするのが目的。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "Anchor Player"
; インストール先のフォルダ名。表示名と違って空白を入れない。
; パスに空白があると、引用符を忘れたスクリプトやコマンドラインで壊れる。
#define AppDirName "AnchorPlayer"
#define AppPublisher "HidéToys"
#define AppURL "https://github.com/hdty/anchor-player"
#define AppExeName "anchor_player.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId を変えると別アプリ扱いになり上書き更新できなくなるので固定する。
AppId={{8E4F1C2A-6B7D-4E39-9A15-3C7D2B8F1A64}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
; {autopf} と {autodesktop} は下の権限選択に追従する。
;   全ユーザー   → C:\Program Files\AnchorPlayer
;   自分だけ     → %LOCALAPPDATA%\Programs\AnchorPlayer
DefaultDirName={autopf}\{#AppDirName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 既定は「自分だけ」（UAC を出さない）。起動時のダイアログで
; 「全ユーザー」を選べば昇格し、インストール先も Program Files に切り替わる。
; lowest を明示しないと管理者で起動してしまい、権限と場所がちぐはぐになる。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\dist
OutputBaseFilename=AnchorPlayer-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 64bit 専用（Flutter の Windows ビルドは x64）。
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Release フォルダを丸ごと入れる（exe / DLL / data すべて）。
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
