// Anchor Player の基本的なスモークテスト。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_player/main.dart';
import 'package:anchor_player/shortcuts.dart';
import 'package:anchor_player/theme/app_theme.dart';
import 'package:anchor_player/ui/anchor_nudge_row.dart';

void main() {
  testWidgets('起動するとファイル未選択の案内が出る', (WidgetTester tester) async {
    await tester.pumpWidget(const AnchorPlayerApp());

    expect(find.text('Open an audio file'), findsOneWidget);
    // ファイル未選択のうちは再生系のUIを出さない。
    expect(find.text('Jump to Anchor'), findsNothing);
  });

  testWidgets('ダークテーマでも組み上がる', (WidgetTester tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.dark),
      child: AnchorPlayerApp(),
    ));

    expect(find.text('Open an audio file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ショートカット一覧を開ける', (WidgetTester tester) async {
    await tester.pumpWidget(const AnchorPlayerApp());

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    // 一覧は kShortcuts から組み立てるので、全キーが並ぶ。
    for (final s in kShortcuts) {
      expect(find.text(s.keyLabel), findsOneWidget);
    }
  });

  test('ライト・ダークとも AnchorColors が入っている', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.extension<AnchorColors>(), isNotNull);
    }
  });

  test('アンカー時刻は 0.1 秒まで出す', () {
    // 微調整の最小刻みが 0.2 秒なので、秒までの表示では変化が見えない。
    expect(
      AnchorNudgeRow.formatWithTenths(const Duration(milliseconds: 12400)),
      '00:12.4',
    );
    expect(
      AnchorNudgeRow.formatWithTenths(const Duration(seconds: 3725)),
      '1:02:05.0',
    );
  });
}
