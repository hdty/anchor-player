# Anchor Player

## 概要
英会話シャドーイング練習用のメディアプレイヤー。
音声トラックのシークバー上に「アンカー（戻り位置）」を1点指定でき、
再生中にボタンを押すとそのアンカーへジャンプして再生を継続する。
一文ずつ念入りに反復練習するのが目的。
方針は「標準のメディアプレイヤー相当の機能 ＋ アンカー機能」。

- 種別: Flutter / Dart 製クロスプラットフォームアプリ
- 対象: Windows デスクトップ（第一優先）→ 将来 iOS / Android へ移植
- 音声再生: media_kit（libmpv）

## コア要件（崩さない2点）
1. シークバー上の任意の1点をアンカーとして指定できる。
2. 再生中にボタンを押すと、アンカー位置へ移動してそこから再生を続ける。

※ 上記以外は標準プレイヤー相当でよい。試作後に不要機能を削る方針なので、
   機能を増やす前にこの2点の確実な動作を優先する。

## ディレクトリ
- lib/      : Dart 実装（本体）
- test/     : テスト
- testdata/ : テスト用の音声など
- windows/ android/ ios/ : 各プラットフォーム固有
- design/   : アプリアイコンの元画像・プレビュー（anchor_source.png, icon_*.png）
- tools/    : 補助スクリプト
- docs/     : 詳細仕様。@docs/SPEC.md を参照（自動インポートされる）
- build/dist/ : 配布物（生成物。Git管理外・参照不要）

## コマンド
- 依存取得 : flutter pub get
- 実行     : flutter run -d windows
- テスト   : flutter test
- リリース : flutter build windows --release

## ルール
- まず Windows で確実に動かす。移植性を壊す Windows 専用 API は避け、
  必要なら再生処理などを抽象化して iOS/Android 移植に備える。
- 大きなリファクタやUIの作り替えは、着手前に案を提示して選ばせる。
- ビルド成果物（build/, .dart_tool/, .idea/）は編集・参照しない。
