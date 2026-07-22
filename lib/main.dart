import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'theme/app_theme.dart';
import 'ui/player_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // デスクトップ(Windows等)の音声バックエンドを libmpv(media_kit) にする。
  // just_audio_windows より高音質・安定。just_audio の API はそのまま使える。
  // pitch は無効のまま（速度変更時にピッチ補正で声の高さを保つ＝シャドーイング向き）。
  JustAudioMediaKit.title = 'Anchor Player';
  JustAudioMediaKit.ensureInitialized(windows: true);
  runApp(const AnchorPlayerApp());
}

class AnchorPlayerApp extends StatelessWidget {
  const AnchorPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anchor Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const PlayerPage(),
    );
  }
}
