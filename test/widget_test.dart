// Anchor Player の基本的なスモークテスト。
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_player/main.dart';

void main() {
  testWidgets('起動して初期表示が出る', (WidgetTester tester) async {
    await tester.pumpWidget(const AnchorPlayerApp());

    // 初期状態ではファイル未選択の案内が出る。
    expect(find.text('No file open'), findsOneWidget);
    expect(find.text('Jump to Mark (B)'), findsOneWidget);
  });
}
