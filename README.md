# Anchor Player

英会話のシャドーイング練習用の音楽プレイヤー。
**任意の位置にマーカー（錨）を置き、ボタン一つでそこへ戻って再生を続けられる**のが目的。

Flutter 製。Windows で動作し、将来 iPhone / Android へ移植可能。

- 表示名: **Anchor Player** / Dart パッケージ名: `anchor_player`（アンダースコア＝Dartの仕様上必須）
- GitHub リポジトリ名は `anchor-player`（ハイフン）。パッケージ名と一致させる必要はない。

## 使い方

1. ファイル名の下の **Open** から音声ファイルを開く（mp3 / m4a / wav など）
2. シークバーの **赤い旗をドラッグ** → マーク位置を移動（最初は0秒）
3. 再生中に **「Jump to Mark」** ボタン（または `B` キー）→ その位置へ戻って再生継続

### 操作

| 操作 | 方法 |
|------|------|
| 再生 / 一時停止 | 中央のボタン / `Space` |
| マーク位置を動かす | バー上の旗をドラッグ |
| 再生位置を動かす | バー上の丸をドラッグ / トラックをタップ |
| マークへ戻る | Jump to Mark / `B` |
| 10秒戻る / 進む | ⏪10 ⏩10 / `←` `→` |
| 前 / 次の曲 | ⏮ ⏭（開いたファイルと同じフォルダ内） |
| リピート | Off → 1曲 → フォルダ全曲（既定は1曲ループ） |
| シャッフル | フォルダ内ランダム |
| 再生速度 | 0.5〜2.0x |

## 開発

```powershell
$env:Path = "C:\Users\hdty\flutter\bin;$env:Path"   # Flutter のパス
cd C:\Users\hdty\projects\anchor_player

flutter run -d windows      # 開発実行（ホットリロード可）
flutter build windows       # リリースビルド
flutter analyze             # 静的解析
```

ビルド成果物: `build\windows\x64\runner\Release\anchor_player.exe`
（配布時は同じ `Release` フォルダ内の DLL 群も一緒に配る）

## 構成

- `lib/main.dart` … アプリ全体（UI とプレイヤーロジック）
  - `MarkerSeekBar` … 旗ドラッグでマーク・丸ドラッグでシークするカスタムバー
- 音声: [just_audio](https://pub.dev/packages/just_audio) + just_audio_windows
- ファイル選択: [file_picker](https://pub.dev/packages/file_picker)

### メモ
- 日本語環境(CP932)で `just_audio_windows` が警告C4819→ビルドエラーになるため、
  `windows/CMakeLists.txt` に `/utf-8` を追加して回避済み。

## License

[MIT](LICENSE) © 2026 HidéToys
