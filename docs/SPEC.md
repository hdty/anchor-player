# Anchor Player 仕様書（SPEC）

## 背景・目的
英会話の学習でシャドーイングを行う際、いくつかのセンテンスからなる文章を
一文ごとに念入りに繰り返し練習したい。
Windows標準のメディアプレイヤーは「10秒戻し」しかできず、
任意の位置へ正確に戻れないため練習に向かない。

そこで、トラック内の**任意の位置に戻れる**メディアプレイヤーを自作する。
戻り先となる位置を「アンカー」と呼ぶ。

## ターゲット環境
- 第一優先: Windows デスクトップアプリ
- 将来: iOS / Android へ移植
- 実装: Flutter / Dart
- 音声再生: media_kit（libmpv）

## 用語
- **アンカー (Anchor)**: トラック内のユーザーが指定した戻り位置（1点）。

## コア要件（必須・これを崩さない）
1. **アンカーの指定**
   - 1トラック全体を表すシークバーの中の任意の1点を、アンカーとして指定できる。
2. **アンカーへの復帰再生**
   - ボタン（既定では Space キー）を押すと、再生位置がアンカーへ移動し、
     そこから再生を継続する。

この2点が本アプリの存在理由であり、最優先で確実に動作させる。

## 現在の実装状況（v0.5.0 時点）

### アンカー機能
- シークバー上段の**ピンをドラッグ**してアンカーを設定（初期位置は0秒）。
- **ピンの少し横（±120px）をクリック**で ±0.2 秒の微調整（左=前 / 右=後）。
- **キーボードで微調整**（左列=前へ / 右列=後ろへ。テンキー対応）:
  - ±0.2秒: `1`・`z` / `3`・`c`
  - ±1秒: `4`・`a` / `6`・`d`
  - ±5秒: `7`・`q` / `9`・`e`
- **「Set here」**ボタン（`5` / `s`）: 現在の再生位置をアンカーにする。
- **「Jump to Anchor」**ボタン（`Space` / `0`）: アンカーへ移動して再生継続（中核機能）。
- アンカー時刻の表示（0.1 秒まで。微調整の最小刻みが 0.2 秒のため）。

### 標準プレイヤー機能
- 音声ファイルを開く（file_picker、対応: mp3/m4a/aac/wav/flac/ogg/opus）。
- 再生 / 一時停止（`Enter`）。
- シークバーのドラッグ／トラックのタップで任意位置へシーク。
- 10秒戻し / 送り（`←` / `→`）。
- 先頭へ戻って再生 / 末尾へ進んで一時停止。
- 再生位置・総再生時間の表示。
- 再生速度 0.6〜2.0x（声の高さは保持＝ピッチ補正あり）。遅い側は 0.1 刻み。
- 開いた1ファイルを常にエンドレスリピート（`LoopMode.one` に一本化）。
- 高品質な libmpv 音声エンジン（旧 just_audio_windows の音割れを解消）。
- Windows / Android / iOS のアプリアイコン。
- ライト / ダークテーマ（`ThemeMode.system`）。
- ファイル未選択時の空状態と、アプリ内のショートカット一覧ダイアログ。
- **最近開いたファイルの履歴**（最大5件）。空状態に新しい順で並び、押すとダイアログ
  無しで開ける。連番の教材を日々進める使い方なので、並んでいるだけで次にやるものが
  分かる。保存は `shared_preferences`（`lib/recent_files.dart`）。
  再生できたものだけ記録し、消えたファイルは起動時に除外する
  （Android は選択のたびにキャッシュへ複製するため、古いパスは残らない）。

### 再生速度とタイムストレッチ（検証済み・結論）
選択肢は `lib/ui/player_view.dart` の `kSpeeds` ただ1箇所。遅い側の下限は **0.6 倍**。

減速時の音質はタイムストレッチ実装で決まる。`JustAudioMediaKit.pitch = false` にすると
media_kit は旧 `scaletempo` ではなく mpv 既定の **`scaletempo2`** を使う（`main()` で設定）。
旧 `scaletempo` は声がふらつきこもるため使わない。

**0.5 倍は廃止した。** 引き伸ばしが 2 倍になり、下記のとおり方式を問わず破綻したため。

| 方式 | 0.5 倍での結果 |
|---|---|
| `scaletempo2`（採用） | ごく一部でプツッと途切れる。窓を広げても（`window-size=30/50`）改善せず |
| `rubberband` R3 (`engine=finer`) | 水中のような反響（位相ボコーダ特有のにじみ） |
| `rubberband` R2 (`engine=faster`) | 男声にビブラート。`window=short` は低い基本周波数を解像できず悪化 |
| `lavfi=[atempo=0.5]` | 同様に不合格 |

rubberband を使うには (1) rubberband 入り libmpv（純正 14.8MB に対し **112MB**）と
(2) `af` を設定する口（`just_audio_media_kit` は公開APIを持たないため複製＋パッチ）の
両方が要る。**音質が scaletempo2 に及ばないため採用しない。** 再挑戦する価値は低い。

### 再生エンジンへの操作は直列化する
`_PlayerPageState._run()` が1本のキューに通す。エンジンへの操作（seek / play / pause /
setLoopMode / setSpeed / 読み込み）はどれも非同期なので、投げっぱなしにすると
**コマンドをまたいで追い越しが起きる**。例: ⏭（末尾へ seek）の直後に Jump to Anchor を
押すと、後から着地した ⏭ の seek でアンカーではなく終端へ飛ぶ。

**`play()` だけは await してはいけない。** just_audio の `play()` が返す Future は
「再生が完了 / 一時停止 / 停止した」ときに完了する。キューの中で待つと再生中ずっと
キューが詰まり、以後の操作が全て止まる。順序が要るのは play より前の seek /
setLoopMode なので、それらを await してから `_startPlayback()` で投げるだけにする。

例外は `_run` が拾ってログに出す。握り潰すとリリースビルドで痕跡が残らず
「ときどき効かない」の調査ができない。キューが壊れて以後の操作が止まるのも防ぐ。

### バージョン表示
「?」のショートカット一覧の **Close と同じ行（`actions`）** に `アプリ名 vX.Y.Z` を出す。
数字は Dart 側に持たず、`package_info_plus` が実行ファイルの埋め込み値を読む
（Windows は Runner.rc の `FLUTTER_VERSION` が pubspec 由来）。
**唯一の定義は `pubspec.yaml`**。定数で持つと書き換え忘れて表示が嘘をつく。

内容領域には置かないこと。v0.7.1 で内容の下に足した結果、一覧が押し出されて
末尾の項目（`9`/`E`）が見えなくなった。`actions` は `Row` ではなく `OverflowBar`
なので `Expanded` は使えず、左右への配置は `actionsAlignment` で行う。

### キーボード操作一覧
割り当ての実体は **`lib/shortcuts.dart` の `kShortcuts`** ただ1箇所にある。
キー判定もアプリ内のショートカット一覧ダイアログも同じ表を読むので、
挙動と説明がずれることはない。この文書に表を再掲すると三重管理になるため置かない。
変更するときは `kShortcuts` を直す。

## デザイン

### アイコン
形状の定義は **`lib/ui/anchor_mark.dart` の `AnchorMark` ただ1箇所**にある。
寸法・配色・描画順の詳細は **[design/icon_blueprint.md](../design/icon_blueprint.md)** に設計図としてまとめてある。

図案の要点: 主機能である**再生（大きな再生三角）を主役**にし、補助機能である
**アンカーは右下に半分サイズのバッジ**として従属させる。アンカーの周囲は地の色で
「逃げ」を作り三角から浮かせる。確定配色は 地=紺 / 再生三角=水色 / アンカー=薄桜。
96×96 グリッド・丸終端（Material Symbols Rounded weight 400 相当）。

生成手順:

1. `flutter test tools/gen_icon.dart` → `design/icon_*.png`（16〜1024px）と
   Android アダプティブ用の前景 / monochrome PNG を書き出す。
2. `powershell -File tools/make-icon.ps1` → 上記 PNG を
   `windows/runner/resources/app_icon.ico` にパックする（描画はしない）。
3. `dart run flutter_launcher_icons` → Android / iOS のアイコンを生成する。

`design/anchor_mark.svg` は人間が形を確かめるための参照用マスタ。
生成には使わないので、`AnchorMark` を直したら手で合わせること。

以前は 1.3MB のラスタ原画から外周 flood fill で背景を推測除去していたが、
スケールしないため廃止した。

### 配色
シード色は淡い水色。M3 が色相を保ったままトーンを割り当てる。

| 用途 | 色 |
|------|-----|
| シード（`ColorScheme.fromSeed`） | `#A3D8E1`（HidéToys の淡い水色） |
| アイコン（地=紺 / 再生=水 / 錨=薄桜） | `#13253F` / `#A3D8E1` / `#E8AFCF` |

アンカーは「戻る場所」であって破壊的操作ではないので、`colorScheme.error`（赤）ではなく
専用の意味色を `AnchorColors`（`ThemeExtension`、`lib/theme/app_theme.dart`）に持たせる。
淡い桜色 `#E8AFCF` は白地でコントラストが約 1.4:1 しかないため、
**広い面（container）には淡い方、線・文字・アイコンには濃い方**を使う。

| ロール | Light | Dark |
|---|---|---|
| anchor | `#C9457E` | `#E8AFCF` |
| onAnchor | `#FFFFFF` | `#4A0E2C` |
| anchorContainer | `#FBE4EE` | `#6B2144` |
| onAnchorContainer | `#4A0E2C` | `#FBE4EE` |

### ボタンの語彙
重みは3階層だけに限る。以前は1画面に6種類のボタンスタイルが混在していた。

| 階層 | 使うもの | 例 |
|---|---|---|
| 主 | `FilledButton` / `IconButton.filled` | Jump to Anchor、再生 / 一時停止 |
| 副 | `IconButton.filledTonal` | ±10秒 |
| 三 | `IconButton` / `TextButton` | 先頭へ・末尾へ、Set here、アンカー微調整 |

**同じ見た目は同じ意味**にする。選択状態を持つトグル（再生速度）は M3 標準の
`SegmentedButton`、押すたびに動くモーメンタリ動作（アンカー微調整）は塗りのないステッパー、
と形で区別する。v0.4.3 で両者を同じ連結セグメントに「統一」した結果、
意味の違いが見えなくなったのを元に戻したもの。

### 画面の構成
- **Now playing**（`surfaceContainerLow`）: シークバー・時間・トランスポート。
- **Anchor**（`anchorContainer`）: Jump to Anchor と Set here、その下にアンカー時刻と微調整を1行で。
- アンカーに関わるものは必ずこのブロックに置く。
  以前は時刻・微調整・Set ボタン・シークバーの旗の4箇所に散っていた。

### プレビュー
`flutter test tools/gen_preview.dart` で `build/preview/` にライト / ダーク × 再生中 / 空状態の
画像を書き出す。`PlayerView` が再生状態を外から受け取るだけの `StatelessWidget` なので、
音声エンジンなしで画面だけを組み上げられる。実機を起動せずに配色とレイアウトを確認できる。

## 未実装 / 将来検討
- **音量調整 UI**: 現状はエンジン任せ（未実装）。
- **複数アンカー / A-B リピート**: 現時点では未対応（必要になれば検討）。
- **iOS / Android 版**: Windows 版が固まってから移植に着手する。
  （UIロジックは流用可能。音声は media_kit がモバイルにも対応）。

## 技術構成
- UI / アプリ基盤: Flutter（Windows / Android / iOS）
- 音声再生エンジン: media_kit（内部で libmpv を使用）。
  - just_audio の API はそのままに、`just_audio_media_kit` + `media_kit_libs_windows_audio`
    でデスクトップのバックエンドを libmpv にしている。`main()` で
    `JustAudioMediaKit.ensureInitialized()` を呼ぶ。
- ファイル選択: file_picker
- アイコン生成: `tools/make-icon.ps1`（Windows PowerShell 5.1 + UTF-8 BOM で実行）。
- 日本語環境(CP932)対策: `windows/CMakeLists.txt` に `/utf-8` を指定（警告C4819→/WX 回避）。
- 配布: **`git tag vX.Y.Z && git push origin vX.Y.Z` だけ**。あとは GitHub Actions
  （`.github/workflows/release.yml`）が Windows / Android をビルドして Release を作る。
  - **手元でビルドした成果物をアップロードしない。** SignPath Foundation の無償署名は
    「バイナリがソースからの自動ビルドであること」を要件にしており、手動配布では通らない。
  - リリースノートは **`docs/release-notes/vX.Y.Z.md`**（Git 管理下）に置く。
    無ければコミット履歴から自動生成される。
  - タグと `pubspec.yaml` のバージョンが違うと `check-version` ジョブで止まる。
  - 動作確認は Actions 画面の **Run workflow**（`workflow_dispatch`）で。
    タグを作らずに全ジョブを回せる。Release の作成はタグ時のみ。
  - ローカルで作りたい場合は下記（インストーラは手元でも同じ手順で作れる）。
  - **インストーラ**（主）: `bash tools/make-installer.sh` → `AnchorPlayer-Setup-<version>.exe`。
    定義は `installer/anchor_player.iss`（Inno Setup 6）。利用者は DLL を意識しない。
    バージョンは pubspec.yaml から読むので `.iss` に数字を書かない。
    `AppId` の GUID は**変えてはいけない**（変えると別アプリ扱いになり上書き更新できない）。
    `PrivilegesRequired=lowest` + `PrivilegesRequiredOverridesAllowed=dialog` で
    権限とインストール先を連動させる（全ユーザー→`Program Files\AnchorPlayer` /
    自分だけ→`%LOCALAPPDATA%\Programs\AnchorPlayer`）。フォルダ名に空白を入れない。
  - **zip**（副）: インストールせずに使いたい場合向けに残す。
- Flutter 製なので配布物は exe 単体にならない（16ファイル・43MB）。内訳は
  `flutter_windows.dll` 20MB と **`libmpv-2.dll` 15MB（音声エンジン。Flutter とは無関係）**。
  ネイティブに作り直しても libmpv は必要なので単一 exe にはならず、
  Windows 標準 API に替えれば減速再生の音質が破綻する。**インストーラで解決する。**

## スコープ運用方針
- 機能を増やす前に、コア要件2点の確実な動作を優先する。
- 仕様の追加・変更が出たら、まずこの SPEC.md に追記し、
  恒久的なルールになったもののみ CLAUDE.md 側へ昇格させる。
