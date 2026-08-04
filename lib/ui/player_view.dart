import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'anchor_mark.dart';
import 'anchor_nudge_row.dart';
import 'marker_seek_bar.dart';

/// 画面が描くのに必要な状態だけをまとめたもの。
class PlayerViewData {
  const PlayerViewData({
    this.fileName,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.anchor = Duration.zero,
    this.playing = false,
    this.speed = 1.0,
    this.recentPaths = const <String>[],
  });

  final String? fileName;
  final Duration duration;
  final Duration position;
  final Duration anchor;
  final bool playing;
  final double speed;

  /// 最近開いたファイル（新しい順）。空状態にだけ出す。
  final List<String> recentPaths;

  bool get hasFile => fileName != null;
}

/// 画面から呼ばれる操作。実装は [PlayerPage] の State 側にある。
///
/// 表示と再生状態を分けてあるので、音声エンジンなしでも画面だけを組み上げられる
/// （`tools/gen_preview.dart` がライト/ダーク両方のプレビュー画像を作るのに使う）。
abstract class PlayerCommands {
  void openFile();
  void openRecent(String path);
  void showShortcuts(BuildContext context);
  void togglePlay();
  void seekTo(Duration position);
  void seekDragStart();
  void seekDragEnd();
  void seekRelative(Duration delta);
  void toStartAndPlay();
  void toEndAndPause();
  void jumpToAnchor();
  void setAnchorToCurrent();
  void setAnchor(Duration anchor);
  void nudgeAnchor(Duration delta);
  void setSpeed(double speed);
}

/// 再生速度の選択肢。
///
/// 遅い側は 0.6 倍までとし、0.1 刻みで細かく選べるようにしている。
/// 0.5 倍は scaletempo2 / rubberband / atempo のいずれでも音が破綻したため
/// 廃止した（引き伸ばしが 2 倍になり、方式を問わず限界を超える）。
const List<double> kSpeeds = [0.6, 0.7, 0.8, 0.9, 1.0, 1.25, 1.5, 2.0];

class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.data,
    required this.commands,
  });

  final PlayerViewData data;
  final PlayerCommands commands;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ファイルを開く導線はここ1箇所だけ。以前はタイトル文字の隠しタップと
        // 右上のフォルダボタンが同じ動作を二重に持っていた。
        title: _FileButton(
            fileName: data.fileName, onPressed: commands.openFile),
        titleSpacing: 8,
        actions: [
          IconButton(
            tooltip: 'Keyboard shortcuts',
            icon: const Icon(Icons.help_outline),
            onPressed: () => commands.showShortcuts(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: data.hasFile ? _buildPlayer(context) : _buildEmptyState(context),
    );
  }

  /// ファイル未選択のとき。無効化されたボタンを並べる代わりに、
  /// 次にやることだけを出す。
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ブランドの象徴として、アプリアイコンそのもの（プレートあり）を出す。
          // 自己完結した配色なのでライト／ダークどちらの画面でも同じに見える。
          SizedBox(
            width: 96,
            height: 96,
            child: CustomPaint(
              painter: const AnchorMarkPainter.icon(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Drop an anchor anywhere in a track,\nand jump back to it with one key.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: commands.openFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open an audio file'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
          ),
          if (data.recentPaths.isNotEmpty) _buildRecent(context),
        ],
      ),
    );
  }

  /// 最近開いたファイル。連番の教材を順に進めるので、並んでいるだけで
  /// 「次にどれをやるか」が分かる。押せばダイアログ無しで再開できる。
  Widget _buildRecent(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recent',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          for (final path in data.recentPaths)
            TextButton(
              onPressed: () => commands.openRecent(path),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(
                _displayName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  /// 表示はファイル名だけにする。フルパスは長すぎて一覧の意味を損なう。
  static String _displayName(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Widget _buildPlayer(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNowPlayingSection(context),
              const SizedBox(height: 12),
              _buildAnchorSection(context),
              const SizedBox(height: 20),
              _buildSpeedSection(context),
            ],
          ),
        ),
      ),
    );
  }

  /// シークバーと再生操作。
  Widget _buildNowPlayingSection(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      // surfaceContainerLow ではダークで地の色とほぼ同じになり、
      // ブロックの輪郭が見えなくなる。
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          MarkerSeekBar(
            duration: data.duration,
            position: data.position,
            marker: data.anchor,
            onSeek: commands.seekTo,
            onSeekStart: commands.seekDragStart,
            onSeekEnd: commands.seekDragEnd,
            onMarkerChange: commands.setAnchor,
            onNudgeMarker: commands.nudgeAnchor,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TimeText(data.position),
                _TimeText(data.duration),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ボタンの重みは3階層だけ: filled(主) / filledTonal(副) / plain(三)。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 26,
                tooltip: 'Back to start & play',
                onPressed: commands.toStartAndPlay,
                icon: const Icon(Icons.first_page),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                iconSize: 26,
                tooltip: 'Back 10 s (←)',
                onPressed: () =>
                    commands.seekRelative(const Duration(seconds: -10)),
                icon: const Icon(Icons.replay_10),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                iconSize: 38,
                tooltip: 'Play / pause (Enter)',
                onPressed: commands.togglePlay,
                icon: Icon(data.playing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                iconSize: 26,
                tooltip: 'Forward 10 s (→)',
                onPressed: () =>
                    commands.seekRelative(const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 26,
                tooltip: 'Go to end & pause',
                onPressed: commands.toEndAndPause,
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// アンカー関連をひとまとめにする。以前は4箇所に散っていた。
  Widget _buildAnchorSection(BuildContext context) {
    final anchorColors = context.anchorColors;
    return _Section(
      color: anchorColors.anchorContainer,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // コア機能。破壊的操作の色(error)ではなくアンカー専用色を使う。
              FilledButton.icon(
                onPressed: commands.jumpToAnchor,
                icon: const Icon(Icons.keyboard_return, size: 22),
                label: const Text('Jump to Anchor'),
                style: FilledButton.styleFrom(
                  backgroundColor: anchorColors.anchor,
                  foregroundColor: anchorColors.onAnchor,
                  minimumSize: const Size(230, 52),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: commands.setAnchorToCurrent,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Set here'),
                style: TextButton.styleFrom(
                  foregroundColor: anchorColors.onAnchorContainer,
                  minimumSize: const Size(0, 44),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnchorNudgeRow(
            anchor: data.anchor,
            enabled: true,
            onNudge: commands.nudgeAnchor,
          ),
        ],
      ),
    );
  }

  /// 再生速度。選択状態を持つトグルなので M3 標準の SegmentedButton を使い、
  /// 押すたびに動くアンカー微調整（塗りなしのステッパー）と見た目で区別する。
  Widget _buildSpeedSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Speed',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [
            for (final s in kSpeeds)
              ButtonSegment(value: s, label: Text('${s}x')),
          ],
          selected: {data.speed},
          showSelectedIcon: false,
          onSelectionChanged: (values) => commands.setSpeed(values.first),
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// カードより軽く、ただの Column より輪郭がある入れ物。
class _Section extends StatelessWidget {
  const _Section({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// 経過 / 全体の時間表示。桁が変わっても左右に揺れないようにする。
class _TimeText extends StatelessWidget {
  const _TimeText(this.value);

  final Duration value;

  static String format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      format(value),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// AppBar のファイル名兼「開く」ボタン。
class _FileButton extends StatelessWidget {
  const _FileButton({required this.fileName, required this.onPressed});

  final String? fileName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: 'Open an audio file',
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.folder_open, size: 20),
          label: Text(
            fileName ?? 'Anchor Player',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
