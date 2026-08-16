// シークバーの操作の振り分けを確かめる。
//
// このバーは1つの領域に2つのハンドル（上段=アンカーのピン / 下段=再生位置の丸）を
// 持つため、「どちらを掴んだか」の判定を間違えると、動かしたつもりのない方が動く。
// 実際に開発中、ピンの当たり判定と丸の上端が重なって掴み分けが曖昧になったことがある。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_player/theme/app_theme.dart';
import 'package:anchor_player/ui/marker_seek_bar.dart';

/// 幅を固定して置く。位置の計算が幅に依存するので、テスト側で決めておく。
const double _barWidth = 400;
const Duration _duration = Duration(seconds: 100);

Future<Rect> _pumpBar(
  WidgetTester tester, {
  Duration position = Duration.zero,
  Duration marker = Duration.zero,
  void Function(Duration)? onSeek,
  void Function(Duration)? onMarkerChange,
  void Function(Duration)? onNudgeMarker,
  VoidCallback? onSeekStart,
  VoidCallback? onSeekEnd,
  Duration duration = _duration,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _barWidth,
            child: MarkerSeekBar(
              duration: duration,
              position: position,
              marker: marker,
              onSeek: onSeek ?? (_) {},
              onSeekStart: onSeekStart ?? () {},
              onSeekEnd: onSeekEnd ?? () {},
              onMarkerChange: onMarkerChange ?? (_) {},
              onNudgeMarker: onNudgeMarker ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byType(MarkerSeekBar));
}

void main() {
  testWidgets('トラックをタップすると、その位置へシークする', (tester) async {
    Duration? sought;
    final rect = await _pumpBar(tester, onSeek: (d) => sought = d);

    // 下段（トラック）の中央を叩く。
    await tester.tapAt(Offset(rect.left + _barWidth / 2, rect.bottom - 16));
    await tester.pump();

    expect(sought, isNotNull);
    // 全長100秒の中央なので概ね50秒。描画の丸め幅ぶんは許容する。
    expect(sought!.inSeconds, closeTo(50, 2));
  });

  testWidgets('トラックのドラッグは再生位置を動かし、アンカーは動かさない', (tester) async {
    Duration? sought;
    var markerChanged = false;
    var started = false;
    var ended = false;
    final rect = await _pumpBar(
      tester,
      onSeek: (d) => sought = d,
      onMarkerChange: (_) => markerChanged = true,
      onSeekStart: () => started = true,
      onSeekEnd: () => ended = true,
    );

    final y = rect.bottom - 16; // 下段
    await tester.dragFrom(Offset(rect.left + 40, y), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(started, isTrue, reason: 'ドラッグ開始が通知される');
    expect(ended, isTrue, reason: 'ドラッグ終了が通知される');
    expect(sought, isNotNull);
    expect(markerChanged, isFalse, reason: '再生位置を掴んだのでアンカーは動かない');
  });

  testWidgets('ピンをドラッグするとアンカーだけが動く', (tester) async {
    Duration? markerTo;
    var sought = false;
    // ピンを中央に置き、その位置から掴む。
    final rect = await _pumpBar(
      tester,
      marker: const Duration(seconds: 50),
      onMarkerChange: (d) => markerTo = d,
      onSeek: (_) => sought = true,
    );

    final pinX = rect.left + _barWidth / 2;
    await tester.dragFrom(
      Offset(pinX, rect.top + 8), // 上段＝ピンのレーン
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();

    expect(markerTo, isNotNull, reason: 'アンカーが動く');
    expect(markerTo!.inSeconds, lessThan(50), reason: '左へ動かしたので前に戻る');
    expect(sought, isFalse, reason: 'アンカーを掴んだso再生位置は動かない');
  });

  testWidgets('ピンの少し横をタップすると 0.2 秒ぶん微調整される', (tester) async {
    final nudges = <Duration>[];
    final rect = await _pumpBar(
      tester,
      marker: const Duration(seconds: 50),
      onNudgeMarker: nudges.add,
    );

    final pinX = rect.left + _barWidth / 2;
    final y = rect.top + 8; // 上段

    await tester.tapAt(Offset(pinX + 30, y)); // ピンの右
    await tester.pump();
    await tester.tapAt(Offset(pinX - 30, y)); // ピンの左
    await tester.pump();

    expect(nudges, hasLength(2));
    expect(nudges[0], const Duration(milliseconds: 200), reason: '右は後ろへ');
    expect(nudges[1], const Duration(milliseconds: -200), reason: '左は前へ');
  });

  testWidgets('長さが未確定（0秒）のときは操作を受け付けない', (tester) async {
    var touched = false;
    final rect = await _pumpBar(
      tester,
      duration: Duration.zero,
      onSeek: (_) => touched = true,
      onMarkerChange: (_) => touched = true,
      onNudgeMarker: (_) => touched = true,
    );

    await tester.tapAt(Offset(rect.left + 100, rect.bottom - 16));
    await tester.pump();

    expect(touched, isFalse, reason: '読み込み前に触っても何も起きない');
  });

  testWidgets('再生位置とアンカーを読み上げで区別できる', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBar(
      tester,
      position: const Duration(seconds: 30),
      marker: const Duration(seconds: 10),
    );

    // 2つのハンドルは見た目で区別しているので、読み上げでも別物として伝える。
    expect(find.bySemanticsLabel(RegExp('Playback position')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Anchor')), findsOneWidget);
    handle.dispose();
  });
}
