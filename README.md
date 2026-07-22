# Anchor Player

英会話のシャドーイング練習用の音楽プレイヤー。
**任意の位置にマーカー（錨）を置き、ボタン一つでそこへ戻って再生を続けられる**のが目的。

Flutter 製。Windows で動作し、将来 iPhone / Android へ移植可能。

- 表示名: **Anchor Player** / Dart パッケージ名: `anchor_player`（アンダースコア＝Dartの仕様上必須）
- GitHub リポジトリ名は `anchor-player`（ハイフン）。パッケージ名と一致させる必要はない。

## 使い方

1. 左上の **フォルダボタン**から音声ファイルを開く（mp3 / m4a / wav など）
2. シークバーの **ピンをドラッグ** → アンカー位置を移動（最初は0秒）
3. 再生中に **「Jump to Anchor」** ボタン（または `Space` キー）→ その位置へ戻って再生継続

### 操作

| 操作 | 方法 |
|------|------|
| アンカーへ戻って再生継続 | Jump to Anchor / `Space` |
| 再生 / 一時停止 | 中央のボタン / `Enter` |
| アンカー位置を動かす | バー上のピンをドラッグ / `−5 −1 −0.2 +0.2 +1 +5` ボタン |
| 現在位置をアンカーにする | Set here / `5`・`S` |
| 再生位置を動かす | バー上の丸をドラッグ / トラックをタップ |
| 10秒戻る / 進む | ⏪10 ⏩10 / `←` `→` |
| 先頭へ戻って再生 / 末尾へ進んで停止 | 両端のボタン |
| 再生速度 | 0.5〜2.0x |

キー割り当ての一覧はアプリ右上の **?** ボタンで開ける。
開いた1ファイルは常にエンドレスリピートする。

## 開発

```powershell
$env:Path = "C:\Users\hdty\flutter\bin;$env:Path"   # Flutter のパス
cd C:\Users\hdty\projects\anchor_player

flutter run -d windows      # 開発実行（ホットリロード可）
flutter build windows       # リリースビルド
flutter analyze             # 静的解析

flutter test tools/gen_preview.dart   # 画面プレビューを build\preview\ に4枚出す
flutter test tools/gen_icon.dart      # アイコン PNG を design\ に出す
powershell -File tools\make-icon.ps1  # 上の PNG を app_icon.ico にまとめる
dart run flutter_launcher_icons       # Android / iOS のアイコンを生成
```

ビルド成果物: `build\windows\x64\runner\Release\anchor_player.exe`
（配布時は同じ `Release` フォルダ内の DLL 群も一緒に配る）

## 構成

- `lib/main.dart` … 起動とテーマの配線
- `lib/shortcuts.dart` … キーバインドの唯一の定義。キー判定もアプリ内の一覧もここを読む
- `lib/theme/app_theme.dart` … ライト / ダークの配色と `AnchorColors`（アンカー専用の意味色）
- `lib/ui/`
  - `anchor_mark.dart` … アプリアイコンの形状の唯一の定義。空状態の表示にも使う
  - `player_page.dart` … 再生状態とキー入力
  - `player_view.dart` … 画面の見た目（状態を外から受け取るので音声エンジンなしで描ける）
  - `marker_seek_bar.dart` … ピンでアンカー・丸でシークするカスタムバー
  - `anchor_nudge_row.dart` … アンカー時刻と微調整を1行にまとめたステッパー
- 音声: [just_audio](https://pub.dev/packages/just_audio) + just_audio_media_kit（libmpv）
- ファイル選択: [file_picker](https://pub.dev/packages/file_picker)

### メモ
- 日本語環境(CP932)で警告C4819→ビルドエラーになるため、
  `windows/CMakeLists.txt` に `/utf-8` を追加して回避済み。

## License

[MIT](LICENSE) © 2026 HidéToys
