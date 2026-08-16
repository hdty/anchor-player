// アンカー微調整ステッパーの挙動。
//
// このボタンは「押すたびに動く」モーメンタリ動作で、長押しすると連続で動く。
// 押しっぱなしのまま止まらない・離しても止まらない、といった壊れ方をすると
// アンカーが飛んでいくので、開始と停止の両方を確かめる。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_player/theme/app_theme.dart';
import 'package:anchor_player/ui/anchor_nudge_row.dart';

Future<void> _pumpRow(
  WidgetTester tester, {
  required void Function(Duration) onNudge,
  Duration anchor = Duration.zero,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AnchorNudgeRow(
          anchor: anchor,
          enabled: enabled,
          onNudge: onNudge,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('刻みボタンを押すとその量が通知される', (tester) async {
    final nudges = <Duration>[];
    await _pumpRow(tester, onNudge: nudges.add);

    await tester.tap(find.text('+1'));
    await tester.pump();
    await tester.tap(find.text('−5'));
    await tester.pump();

    expect(nudges, [const Duration(seconds: 1), const Duration(seconds: -5)]);
  });

  testWidgets('左列は前へ、右列は後ろへ動かす', (tester) async {
    final nudges = <Duration>[];
    await _pumpRow(tester, onNudge: nudges.add);

    for (final label in ['−5', '−1', '−0.2', '+0.2', '+1', '+5']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }

    expect(nudges.sublist(0, 3).every((d) => d.isNegative), isTrue);
    expect(nudges.sublist(3).every((d) => !d.isNegative), isTrue);
  });

  testWidgets('長押しすると連続で動き、離すと止まる', (tester) async {
    final nudges = <Duration>[];
    await _pumpRow(tester, onNudge: nudges.add);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('+0.2')),
    );
    // 長押し判定＋数回ぶんの繰り返しが起きる時間だけ持つ。
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    final duringHold = nudges.length;

    await gesture.up();
    await tester.pumpAndSettle();
    final afterRelease = nudges.length;

    expect(duringHold, greaterThan(1), reason: '押している間は連続で動く');

    // 離した後さらに時間を進めても増えない＝タイマーが止まっている。
    await tester.pump(const Duration(seconds: 1));
    expect(nudges.length, afterRelease, reason: '離したら止まる');
  });

  testWidgets('無効のときは押しても何も起きない', (tester) async {
    final nudges = <Duration>[];
    await _pumpRow(tester, onNudge: nudges.add, enabled: false);

    await tester.tap(find.text('+1'), warnIfMissed: false);
    await tester.pump();

    expect(nudges, isEmpty);
  });

  testWidgets('アンカー時刻を 0.1 秒まで表示する', (tester) async {
    await _pumpRow(
      tester,
      onNudge: (_) {},
      anchor: const Duration(milliseconds: 12400),
    );

    // 微調整の最小刻みが 0.2 秒なので、秒までの表示では変化が見えない。
    expect(find.textContaining('00:12.4'), findsOneWidget);
  });
}
