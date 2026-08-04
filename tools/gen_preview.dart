// 画面のプレビュー画像を build/preview/ に書き出す。
//
//   flutter test tools/gen_preview.dart
//
// 実機を触らずにライト/ダーク両方のレイアウトと配色を確かめるためのもの。
// PlayerView は再生状態を外から受け取るだけなので、音声エンジンなしで組み上がる。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anchor_player/theme/app_theme.dart';
import 'package:anchor_player/ui/player_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 何もしないコマンド実装。プレビューは押せなくてよい。
class _NoopCommands implements PlayerCommands {
  @override
  void openFile() {}
  @override
  void openRecent(String path) {}
  @override
  void showShortcuts(BuildContext context) {}
  @override
  void togglePlay() {}
  @override
  void seekTo(Duration position) {}
  @override
  void seekDragStart() {}
  @override
  void seekDragEnd() {}
  @override
  void seekRelative(Duration delta) {}
  @override
  void toStartAndPlay() {}
  @override
  void toEndAndPause() {}
  @override
  void jumpToAnchor() {}
  @override
  void setAnchorToCurrent() {}
  @override
  void setAnchor(Duration anchor) {}
  @override
  void nudgeAnchor(Duration delta) {}
  @override
  void setSpeed(double speed) {}
}

const _playing = PlayerViewData(
  fileName: 'Ba_029.mp3',
  duration: Duration(minutes: 3, seconds: 42),
  position: Duration(seconds: 78),
  anchor: Duration(seconds: 54, milliseconds: 400),
  playing: true,
  speed: 0.75,
);

// 履歴つきの空状態。実際の使い方（連番の教材を順に進める）に近い見え方を確認する。
const _empty = PlayerViewData(recentPaths: [
  r'D:\english\Ba_046.mp3',
  r'D:\english\Ba_043.mp3',
  r'D:\english\Ba_039.mp3',
  r'D:\english\Ba_045.mp3',
  r'D:\english\Ba_042.mp3',
]);

Future<void> _capture(
  WidgetTester tester,
  String name,
  ThemeData theme,
  PlayerViewData data,
) async {
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: PlayerView(data: data, commands: _NoopCommands()),
    ),
  ));
  await tester.pumpAndSettle();

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  // toImage / toByteData はラスタスレッドの完了を待つ実際の非同期処理なので、
  // testWidgets の擬似時間の中では永久に完了しない。runAsync で本物の時間に戻す。
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('build/preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

final _boundary = GlobalKey();

void main() {
  setUp(() {
    // 画面サイズは Windows 版の既定ウィンドウに近い比率。
    // 何も指定しないと 800x600 になり、実際より窮屈に見える。
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(900, 620);
    view.devicePixelRatio = 1.0;
  });

  testWidgets('プレビュー画像を書き出す', (tester) async {
    await _capture(tester, 'light_playing', AppTheme.light(), _playing);
    await _capture(tester, 'dark_playing', AppTheme.dark(), _playing);
    await _capture(tester, 'light_empty', AppTheme.light(), _empty);
    await _capture(tester, 'dark_empty', AppTheme.dark(), _empty);
    // ignore: avoid_print
    print('build/preview/ に 4 枚書き出しました。');
  });
}
