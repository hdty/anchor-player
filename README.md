# Anchor Player

英会話のシャドーイング練習用の音楽プレイヤー。
**任意の位置にアンカー（錨）を置き、ワンキーでそこへ戻って再生を続けられる**のが目的。

一般的なプレイヤーの「10秒戻し」では文の切れ目に合わないため、
一文ずつ繰り返す練習に向かない。それを解くために作った。

## ダウンロード

**[→ 最新版をダウンロード（Releases）](https://github.com/hdty/anchor-player/releases/latest)**

| プラットフォーム | ファイル | 備考 |
|---|---|---|
| **Windows** | `AnchorPlayer-Setup-x.y.z.exe` | **インストーラを推奨**。ダブルクリックで導入できる |
| Windows（インストール不要） | `anchor-player-vx.y.z-windows-x64.zip` | 展開して `AnchorPlayer\anchor_player.exe` を実行 |
| Android | `anchor-player-vx.y.z.apk` | **実験的対応**。下記の注意を参照 |

### インストール時の注意

**Windows**: 現在コード署名がないため、初回起動時に SmartScreen の警告が出る。
「詳細情報」→「実行」で進める。インストーラは管理者権限を必須とせず、
「すべてのユーザー」（`C:\Program Files\AnchorPlayer`）か
「自分だけ」（`%LOCALAPPDATA%\Programs\AnchorPlayer`）を選べる。

**Android**: **実験的対応・個人利用向け**。デバッグ署名のため正式な署名ではなく、
Google Play では配布していない。APK を端末へ転送し、ファイルアプリから開いて
インストールする（「不明なアプリのインストール」の許可が必要）。
また Android ではファイル選択のたびに端末側がキャッシュへ複製する仕様のため、
**最近開いたファイルの履歴が残らないことがある**。

iOS はビルド構成のみ用意しており、動作は未検証。

## 使い方

1. 上部の **ファイル名の部分**（未選択時は「Open an audio file」）から音声ファイルを開く
   （mp3 / m4a / aac / wav / flac / ogg / opus）
2. シークバーの **ピンをドラッグ**してアンカーを置く
3. **`Space`**（または「Jump to Anchor」ボタン）でアンカーへ戻り、そこから再生が続く

繰り返したい一文の先頭にアンカーを置き、`Space` を押しながら練習する、という使い方を想定している。

### 覚えておくとよい動作

- **音源を開くと、アンカーと再生位置は必ず0秒に戻る。** 前回どこにアンカーを置いて
  終わったかは持ち越さない。同じ音源でも次は先頭から練習することが多いため、
  この動作を仕様としている。
- **開いた1ファイルを常にエンドレスリピートする。** 曲送りの概念はない。
- **最近開いたファイルが最初の画面に5件並ぶ。** 押すとファイル選択を経ずに開ける。
  連番の教材を日々進める場合、並んでいるだけで次にやるものが分かる。
  （再生できたファイルだけが記録され、消えたファイルは自動で一覧から外れる）

### 操作一覧

| 操作 | 方法 |
|------|------|
| **アンカーへ戻って再生継続** | **`Space`** / `0` / Jump to Anchor ボタン |
| 再生 / 一時停止 | `Enter` / 中央のボタン |
| 現在位置をアンカーにする | `5` / `S` / Set here |
| アンカーを動かす | バー上のピンをドラッグ / `−5 −1 −0.2 +0.2 +1 +5` ボタン |
| アンカーを ±0.2 / 1 / 5 秒 | `1`·`Z` / `3`·`C`、`4`·`A` / `6`·`D`、`7`·`Q` / `9`·`E` |
| 再生位置を動かす | バー上の丸をドラッグ / トラックをタップ |
| 10秒戻る / 進む | `←` / `→` |
| 先頭へ戻って再生 / 末尾へ進んで停止 | 両端のボタン |
| 再生速度 | 0.6〜2.0x（遅い側は 0.1 刻み） |

アンカー微調整のキーは**押した瞬間に1回、1秒押し続けると連続**で動く。
数字キーはテンキーにも対応し、左列が前へ・右列が後ろへ、と3×3の配置に対応している。

キー割り当ての全一覧はアプリ右上の **?** ボタンで開ける。

> 0.5倍速は提供していない。音声を2倍に引き伸ばす処理となり、
> 試したどのタイムストレッチ方式でも音が破綻したため、下限を 0.6倍とした。
> 詳細は [docs/SPEC.md](docs/SPEC.md) を参照。

## 開発

Flutter / Dart 製。Windows を第一優先とし、Android にも対応している。

```bash
git clone https://github.com/hdty/anchor-player.git
cd anchor-player

flutter pub get
flutter run -d windows      # 開発実行（ホットリロード可）
flutter analyze             # 静的解析
flutter test                # テスト
flutter build windows       # リリースビルド
```

Flutter SDK が PATH に無い場合は通しておくこと。使用バージョンは
`.github/workflows/` に固定してあるので、CI と揃えると再現性が高い。

### 補助スクリプト

```bash
flutter test tools/gen_preview.dart    # 画面プレビューを build/preview/ に4枚出す
flutter test tools/gen_icon.dart       # アイコン PNG を design/ に出す
powershell -File tools/make-icon.ps1   # 上の PNG を app_icon.ico にまとめる
dart run flutter_launcher_icons        # Android / iOS のアイコンを生成
bash tools/make-installer.sh           # Windows インストーラを作る（要 Inno Setup 6）
```

### リリース

タグを push すると GitHub Actions がビルドして Release を作る。
手元でビルドした成果物は配布しない。

```bash
git tag -a vX.Y.Z -m "Anchor Player vX.Y.Z" && git push origin vX.Y.Z
```

リリースノートは `docs/release-notes/vX.Y.Z.md` に置く。

## 構成

- `lib/main.dart` … 起動とテーマの配線
- `lib/shortcuts.dart` … キーバインドの唯一の定義。キー判定もアプリ内の一覧もここを読む
- `lib/recent_files.dart` … 最近開いたファイルの保存
- `lib/theme/app_theme.dart` … ライト / ダークの配色と `AnchorColors`（アンカー専用の意味色）
- `lib/ui/`
  - `anchor_mark.dart` … アプリアイコンの形状の唯一の定義。空状態の表示にも使う
  - `player_page.dart` … 再生状態とキー入力
  - `player_view.dart` … 画面の見た目（状態を外から受け取るので音声エンジンなしで描ける）
  - `marker_seek_bar.dart` … ピンでアンカー・丸でシークするカスタムバー
  - `anchor_nudge_row.dart` … アンカー時刻と微調整を1行にまとめたステッパー
- 音声: [just_audio](https://pub.dev/packages/just_audio) + just_audio_media_kit（libmpv）
- ファイル選択: [file_picker](https://pub.dev/packages/file_picker)
- 設計の詳細と、これまでの技術的判断の記録は [docs/SPEC.md](docs/SPEC.md) にある

### メモ

- 日本語環境(CP932)で警告C4819→ビルドエラーになるため、
  `windows/CMakeLists.txt` に `/utf-8` を追加して回避済み。

## License

[MIT](LICENSE) © 2026 HidéToys
