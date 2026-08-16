// 中核動作のテスト。
//
// ここで守っているのは、実際に不具合を出した経路ばかり:
//  - アンカーが範囲外へ出る
//  - seek より先に play が着地して、意図しない位置から鳴る
//  - 操作が重なって発行順が入れ替わる
//  - 読み込み後にアンカーが持ち越される（仕様は「必ず0秒に戻す」）
//  - 読み込み失敗時に画面とエンジンの状態が食い違う
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anchor_player/theme/app_theme.dart';
import 'package:anchor_player/ui/player_page.dart';

import 'fake_audio_engine.dart';

/// 読み込み済みの状態にしてから本体を返す。
Future<FakeAudioEngine> _pumpLoaded(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 100),
  String path = '/music/Ba_052.mp3',
}) async {
  final fake = FakeAudioEngine();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: PlayerPage(engineFactory: () => fake),
    ),
  );
  await tester.pumpAndSettle();

  // ファイル選択ダイアログは通さず、履歴からの読み込み経路で載せる。
  final state = tester.state<State<PlayerPage>>(find.byType(PlayerPage));
  await (state as dynamic).openRecent(path);
  fake.emitDuration(duration);
  await tester.pumpAndSettle();
  return fake;
}

/// 画面から読み取ったアンカー時刻（`00:12.4` 形式）。
String _anchorText(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => RegExp(r'^\d+:\d\d\.\d$').hasMatch(s));
  return texts.isEmpty ? '' : texts.first;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('アンカーの範囲', () {
    testWidgets('0秒より前へは動かせない', (tester) async {
      await _pumpLoaded(tester);

      // 先頭にある状態で前方向へ何度も送る。
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('−5'));
        await tester.pump();
      }

      expect(_anchorText(tester), '00:00.0');
    });

    testWidgets('音源の終端より後ろへは動かせない', (tester) async {
      await _pumpLoaded(tester, duration: const Duration(seconds: 10));

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('+5'));
        await tester.pump();
      }

      // 全長10秒なので、いくら送っても 00:10.0 で止まる。
      expect(_anchorText(tester), '00:10.0');
    });
  });

  group('Jump to Anchor', () {
    testWidgets('seek がplayより先に発行される', (tester) async {
      final fake = await _pumpLoaded(tester);

      // アンカーを 5 秒へ動かしてから飛ぶ。
      await tester.tap(find.text('+5'));
      await tester.pump();
      fake.calls.clear();

      await tester.tap(find.text('Jump to Anchor'));
      await tester.pumpAndSettle();

      final seekAt = fake.indexOf('seek(');
      final playAt = fake.indexOf('play');
      expect(seekAt, isNonNegative, reason: 'seek が呼ばれる');
      expect(playAt, isNonNegative, reason: 'play が呼ばれる');
      expect(seekAt, lessThan(playAt), reason: '順序が逆だと、前の位置から鳴ってしまう');
      expect(fake.seeks.last, const Duration(seconds: 5));
    });

    testWidgets('play を待たずに次の操作を受け付ける', (tester) async {
      // FakeAudioEngine の play() は完了しない（本物と同じ性質）。
      // キューの中で await していたら、以降の操作が全て止まってここで固まる。
      final fake = await _pumpLoaded(tester);

      await tester.tap(find.text('Jump to Anchor'));
      await tester.pumpAndSettle();
      fake.calls.clear();

      await tester.tap(find.text('+1'));
      await tester.pump();
      await tester.tap(find.text('Jump to Anchor'));
      await tester.pumpAndSettle();

      expect(fake.where('seek('), isNotEmpty, reason: '再生中でも後続の操作が届く');
    });
  });

  testWidgets('操作を連続で出しても発行順が入れ替わらない', (tester) async {
    final fake = await _pumpLoaded(tester);
    fake.calls.clear();

    // 末尾へ飛ぶ → すぐアンカーへ飛ぶ、という以前壊れていた並び。
    await tester.tap(find.byTooltip('Go to end & pause'));
    await tester.tap(find.text('Jump to Anchor'));
    await tester.pumpAndSettle();

    // 末尾(100秒)への seek が、アンカー(0秒)への seek より先に出ていること。
    final endAt = fake.calls.indexOf('seek(${const Duration(seconds: 100)})');
    final anchorAt = fake.calls.lastIndexOf(
      'seek(${const Duration(seconds: 0)})',
    );
    expect(endAt, isNonNegative);
    expect(anchorAt, isNonNegative);
    expect(
      endAt,
      lessThan(anchorAt),
      reason: '後から出した Jump が、先に出した末尾seekに追い越されてはいけない',
    );
    expect(fake.seeks.last, Duration.zero, reason: '最後はアンカー位置に居る');
  });

  group('読み込み', () {
    testWidgets('音源を開くとアンカーと再生位置が0秒になる', (tester) async {
      final fake = await _pumpLoaded(tester);

      // アンカーを動かし、再生位置も進めておく。
      await tester.tap(find.text('+5'));
      await tester.pump();
      fake.emitPosition(const Duration(seconds: 30));
      await tester.pump();
      expect(_anchorText(tester), isNot('00:00.0'));

      // 別の音源を開く。
      final state = tester.state<State<PlayerPage>>(find.byType(PlayerPage));
      await (state as dynamic).openRecent('/music/Ba_053.mp3');
      await tester.pumpAndSettle();

      expect(_anchorText(tester), '00:00.0', reason: 'アンカーは持ち越さない');
    });

    testWidgets('同じ音源を開き直してもアンカーは0秒になる', (tester) async {
      const path = '/music/Ba_052.mp3';
      await _pumpLoaded(tester, path: path);

      await tester.tap(find.text('+5'));
      await tester.pump();
      expect(_anchorText(tester), isNot('00:00.0'));

      final state = tester.state<State<PlayerPage>>(find.byType(PlayerPage));
      await (state as dynamic).openRecent(path); // 履歴から同じものを再度
      await tester.pumpAndSettle();

      expect(_anchorText(tester), '00:00.0');
    });

    testWidgets('読み込みに失敗したら空状態へ戻す', (tester) async {
      final fake = await _pumpLoaded(tester);
      expect(find.text('Jump to Anchor'), findsOneWidget);

      fake.failNextLoad = Exception('broken file');
      final state = tester.state<State<PlayerPage>>(find.byType(PlayerPage));
      await (state as dynamic).openRecent('/music/broken.mp3');
      await tester.pumpAndSettle();

      // 前のファイルの画面を残したままにすると「押しても鳴らない」状態になる。
      expect(
        find.text('Jump to Anchor'),
        findsNothing,
        reason: '表示とエンジンの状態を一致させる',
      );
      expect(find.text('Open an audio file'), findsOneWidget);
      expect(fake.calls, contains('stop'), reason: 'エンジン側も片付ける');
      // 例外の中身をそのまま利用者に見せない。
      expect(find.textContaining('broken file'), findsNothing);
    });
  });

  group('キーボード', () {
    testWidgets('Space はアンカーへ、Enter は再生/一時停止に振り分ける', (tester) async {
      final fake = await _pumpLoaded(tester);
      fake.calls.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(fake.where('seek('), isNotEmpty, reason: 'Space はアンカーへ飛ぶ');

      fake.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fake.calls, contains('play'), reason: 'Enter は再生');
    });

    testWidgets('微調整キーを離すと連続移動が止まる', (tester) async {
      await _pumpLoaded(tester);

      // 押しっぱなしにして連続移動を始めさせる。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit6); // +1s
      await tester.pump(const Duration(milliseconds: 1500));
      final afterHold = _anchorText(tester);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit6);
      await tester.pump(const Duration(seconds: 2));

      expect(
        _anchorText(tester),
        afterHold,
        reason: 'キーを離した後もタイマーが生きていると、アンカーが際限なく進む',
      );
    });
  });
}
