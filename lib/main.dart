import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'theme/app_theme.dart';
import 'ui/player_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // デスクトップ(Windows等)の音声バックエンドを libmpv(media_kit) にする。
  // just_audio_windows より高音質・安定。just_audio の API はそのまま使える。
  //
  // pitch = false にすると、速度変更が mpv の `speed`＋`audio-pitch-correction` 経由になり、
  // 減速時のタイムストレッチが旧 `scaletempo` から新しい `scaletempo2` に変わる。
  // 旧 scaletempo は減速時に声がふらつく/こもるため、シャドーイング用途では
  // scaletempo2 の方が明瞭。声の高さ(ピッチ)は保たれ、本アプリは setPitch を使わない。
  //
  // rubberband(R3/R2) も検証したが、R3 は水中のような反響、R2 は男声にビブラートが出て
  // scaletempo2 に及ばなかった。lavfi の atempo も同様。0.5 倍は方式を問わず限界なので、
  // 速度の下限自体を 0.6 倍に引き上げた（kSpeeds を参照）。
  JustAudioMediaKit.pitch = false;
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
