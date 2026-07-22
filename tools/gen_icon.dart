// アプリアイコンの PNG を書き出す生成スクリプト。
//
//   flutter test tools/gen_icon.dart
//
// テストとして実行するのは、dart:ui のラスタライズ（Picture.toImage）に
// Flutter のランタイムが要るため。golden 画像を生成するのと同じ仕組みで、
// flutter_test 上なら dart:io のファイル書き込みも併用できる。
//
// 形状の定義は lib/ui/anchor_mark.dart にあり、このスクリプトは持たない。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anchor_player/ui/anchor_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Windows の .ico と各プラットフォームのランチャー用に要るサイズ。
const List<int> _sizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024];

/// Android アダプティブアイコンのセーフゾーン（108dp 中の内側 66dp）。
/// 前景はこの比率まで縮めておかないと、丸マスクや角丸マスクで端が切れる。
const double _adaptiveSafeRatio = 66 / 108;

Future<void> _writePng(
  String path,
  int side, {
  required Color inkColor,
  required Color ringColor,
  Color? plateColor,
  double scaleFactor = 1.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AnchorMarkPainter(
    inkColor: inkColor,
    ringColor: ringColor,
    plateColor: plateColor,
    scaleFactor: scaleFactor,
  ).paint(canvas, Size(side.toDouble(), side.toDouble()));
  final image = await recorder.endRecording().toImage(side, side);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  test('アイコン画像を design/ に書き出す', () async {
    for (final side in _sizes) {
      await _writePng(
        'design/icon_$side.png',
        side,
        inkColor: AnchorMark.ink,
        ringColor: AnchorMark.sakura,
        plateColor: AnchorMark.water,
      );
    }

    // Android アダプティブアイコンの前景（透過・マークのみ・セーフゾーン内）。
    await _writePng(
      'design/icon_foreground_1024.png',
      1024,
      inkColor: AnchorMark.ink,
      ringColor: AnchorMark.sakura,
      scaleFactor: _adaptiveSafeRatio,
    );

    // Android 13+ のテーマ付きアイコン用。単色に落とされる前提なので
    // リングも本体と同じ色で描き、抜いた再生三角だけが形として残るようにする。
    await _writePng(
      'design/icon_monochrome_1024.png',
      1024,
      inkColor: AnchorMark.ink,
      ringColor: AnchorMark.ink,
      scaleFactor: _adaptiveSafeRatio,
    );

    for (final side in _sizes) {
      expect(File('design/icon_$side.png').existsSync(), isTrue);
    }
    // ignore: avoid_print
    print('design/ に ${_sizes.length + 2} 個の PNG を書き出しました。');
  });
}
