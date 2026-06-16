import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const AnchorPlayerApp());
}

class AnchorPlayerApp extends StatelessWidget {
  const AnchorPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anchor Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const PlayerPage(),
    );
  }
}

/// リピートモード: off=リピート無し / one=1曲ループ / all=フォルダ全曲ループ。
enum RepeatMode { off, one, all }

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  final FocusNode _keyboardFocus = FocusNode();
  final Random _random = Random();

  static const Set<String> _audioExts = {
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus',
  };
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String? _fileName;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _marker = Duration.zero; // 「戻る」位置。最初は0秒、旗のドラッグで移動。
  bool _playing = false;
  bool _dragging = false;
  double _speed = 1.0;

  RepeatMode _repeat = RepeatMode.one; // 既定: 1曲ループ。
  bool _shuffle = false;

  List<String> _playlist = []; // 開いたファイルと同じフォルダ内の音声一覧。
  int _index = -1;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d ?? Duration.zero);
    }));
    _subs.add(_player.positionStream.listen((p) {
      if (!mounted || _dragging) return;
      setState(() => _position = p);
    }));
    _subs.add(_player.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() => _playing = playing);
    }));
    _subs.add(_player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackComplete();
    }));
    _applyLoopMode(); // 既定の RepeatMode.one を just_audio の LoopMode に反映。
  }

  /// RepeatMode を just_audio のループ設定に反映する。
  /// 1曲ループはネイティブのループ再生に任せる（Windowsで確実）。
  void _applyLoopMode() {
    _player.setLoopMode(_repeat == RepeatMode.one ? LoopMode.one : LoopMode.off);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  // ---- ファイル / プレイリスト ----

  String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  Future<void> _openFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          _audioExts.map((e) => e.substring(1)).toList(), // 先頭の'.'を除く
    );
    final path = result?.files.single.path;
    if (path == null) return;
    _buildPlaylist(path);
    await _loadPath(path);
  }

  /// 開いたファイルと同じフォルダ内の音声ファイルを集めてプレイリストにする。
  void _buildPlaylist(String path) {
    try {
      final entries = File(path).parent.listSync();
      final files = <String>[];
      for (final e in entries) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        final dot = lower.lastIndexOf('.');
        if (dot >= 0 && _audioExts.contains(lower.substring(dot))) {
          files.add(e.path);
        }
      }
      files.sort((a, b) =>
          _baseName(a).toLowerCase().compareTo(_baseName(b).toLowerCase()));
      final idx = files.indexWhere((p) => p == path);
      if (idx < 0) {
        _playlist = [path];
        _index = 0;
      } else {
        _playlist = files;
        _index = idx;
      }
    } catch (_) {
      _playlist = [path];
      _index = 0;
    }
  }

  Future<void> _loadPath(String path, {bool autoplay = false}) async {
    try {
      await _player.setFilePath(path);
      await _player.setSpeed(_speed);
      await _player.setLoopMode(
          _repeat == RepeatMode.one ? LoopMode.one : LoopMode.off);
      if (!mounted) return;
      setState(() {
        _fileName = _baseName(path);
        _marker = Duration.zero;
        _position = Duration.zero;
      });
      if (autoplay) await _player.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot play this file: $e')),
      );
    }
  }

  // ---- 曲送り ----

  int? _computeNextIndex({required bool wrap}) {
    if (_playlist.isEmpty) return null;
    if (_playlist.length == 1) return wrap ? 0 : null;
    if (_shuffle) {
      int n;
      do {
        n = _random.nextInt(_playlist.length);
      } while (n == _index);
      return n;
    }
    final n = _index + 1;
    if (n >= _playlist.length) return wrap ? 0 : null;
    return n;
  }

  void _nextTrack() {
    final n = _computeNextIndex(wrap: true);
    if (n == null) return;
    _index = n;
    _loadPath(_playlist[n], autoplay: true);
  }

  void _prevTrack() {
    if (_playlist.isEmpty) return;
    // 3秒以上再生していたら曲の先頭へ。そうでなければ前の曲へ。
    if (_position > const Duration(seconds: 3)) {
      _player.seek(Duration.zero);
      return;
    }
    var n = _index - 1;
    if (n < 0) n = _playlist.length - 1;
    _index = n;
    _loadPath(_playlist[n], autoplay: true);
  }

  void _onTrackComplete() {
    if (_repeat == RepeatMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    final n = _computeNextIndex(wrap: _repeat == RepeatMode.all);
    if (n == null) {
      _player.pause();
      _player.seek(Duration.zero);
    } else {
      _index = n;
      _loadPath(_playlist[n], autoplay: true);
    }
  }

  // ---- 再生制御 ----

  void _togglePlay() {
    if (_fileName == null) return;
    _playing ? _player.pause() : _player.play();
  }

  void _seekRelative(int seconds) {
    if (_fileName == null) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
    _player.seek(target);
  }

  void _jumpToMarker() {
    if (_fileName == null) return;
    _player.seek(_marker);
    _player.play(); // 移動してそこから再生を続ける。
  }

  void _cycleRepeat() {
    setState(() {
      _repeat = RepeatMode.values[(_repeat.index + 1) % RepeatMode.values.length];
    });
    _applyLoopMode();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _togglePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyB:
        _jumpToMarker();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekRelative(-10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekRelative(10);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _fileName != null;
    final hasPlaylist = _playlist.length > 1;

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Anchor Player'),
          backgroundColor: theme.colorScheme.inversePrimary,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // ファイル名（日本語等もそのまま表示）。
                  Text(
                    _fileName ?? 'No file open',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // ファイルを開く（操作部の近く・中央寄せ）。
                  OutlinedButton.icon(
                    onPressed: _openFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open'),
                  ),
                  const SizedBox(height: 24),

                  // シークバー：旗=マーク / 丸=再生位置。どちらもドラッグで移動。
                  MarkerSeekBar(
                    duration: _duration,
                    position: _position,
                    marker: _marker,
                    onSeek: (d) {
                      _player.seek(d);
                      setState(() => _position = d);
                    },
                    onSeekStart: () => _dragging = true,
                    onSeekEnd: () => _dragging = false,
                    onMarkerChange: (d) => setState(() => _marker = d),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position)),
                      Text(_fmt(_duration)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        'Mark: ${_fmt(_marker)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 操作: 前の曲 / 10秒戻る / 再生 / 10秒進む / 次の曲。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 30,
                        tooltip: 'Previous track',
                        onPressed: hasPlaylist ? _prevTrack : null,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        iconSize: 26,
                        tooltip: 'Back 10s (Left)',
                        onPressed: hasFile ? () => _seekRelative(-10) : null,
                        icon: const Icon(Icons.replay_10),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        iconSize: 40,
                        tooltip: 'Play / Pause (Space)',
                        onPressed: hasFile ? _togglePlay : null,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        iconSize: 26,
                        tooltip: 'Forward 10s (Right)',
                        onPressed: hasFile ? () => _seekRelative(10) : null,
                        icon: const Icon(Icons.forward_10),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 30,
                        tooltip: 'Next track',
                        onPressed: hasPlaylist ? _nextTrack : null,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // マークへ戻る（中核機能）。
                  FilledButton.icon(
                    onPressed: hasFile ? _jumpToMarker : null,
                    icon: const Icon(Icons.replay),
                    label: const Text('Jump to Mark (B)'),
                  ),
                  const SizedBox(height: 16),

                  // リピート / シャッフル。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: _repeatTooltip(),
                        isSelected: _repeat != RepeatMode.off,
                        onPressed: _cycleRepeat,
                        color: _repeat == RepeatMode.off
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary,
                        icon: Icon(_repeat == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        tooltip: _shuffle ? 'Shuffle: On' : 'Shuffle: Off',
                        isSelected: _shuffle,
                        onPressed: () => setState(() => _shuffle = !_shuffle),
                        color: _shuffle
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        icon: const Icon(Icons.shuffle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 再生速度（ラベル無し）。
                  SegmentedButton<double>(
                    segments: _speeds
                        .map((s) => ButtonSegment<double>(
                              value: s,
                              label: Text('${s}x'),
                            ))
                        .toList(),
                    selected: {_speed},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) {
                      final v = sel.first;
                      _player.setSpeed(v);
                      setState(() => _speed = v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _repeatTooltip() {
    switch (_repeat) {
      case RepeatMode.off:
        return 'Repeat: Off';
      case RepeatMode.one:
        return 'Repeat: One track';
      case RepeatMode.all:
        return 'Repeat: All in folder';
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 再生位置のシークバー。2つの独立したハンドルを持つ。
/// - バー上の丸（再生位置）をドラッグ → シーク
/// - バーの上に立つ旗（マーク）をドラッグ → マーク位置を移動
/// 旗は上段・丸は下段（トラック上）に分けて配置するので、つかんだ方だけが動く。
class MarkerSeekBar extends StatefulWidget {
  const MarkerSeekBar({
    super.key,
    required this.duration,
    required this.position,
    required this.marker,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onMarkerChange,
  });

  final Duration duration;
  final Duration position;
  final Duration marker;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<Duration> onMarkerChange;

  static const double _height = 64;
  static const double _trackCenterY = 46; // トラック（丸）の中心Y。旗は上に立つ。

  @override
  State<MarkerSeekBar> createState() => _MarkerSeekBarState();
}

enum _Grab { none, marker, position }

class _MarkerSeekBarState extends State<MarkerSeekBar> {
  _Grab _grab = _Grab.none;
  double _dragFraction = 0;

  double _fraction(Duration d) {
    final ms = widget.duration.inMilliseconds;
    if (ms <= 0) return 0;
    return (d.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  Duration _toDuration(double f) {
    return Duration(milliseconds: (widget.duration.inMilliseconds * f).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.duration.inMilliseconds > 0;
    final positionFraction =
        _grab == _Grab.position ? _dragFraction : _fraction(widget.position);
    final markerFraction = _fraction(widget.marker);
    const cy = MarkerSeekBar._trackCenterY;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double clampFraction(double dx) => (dx / width).clamp(0.0, 1.0);

        void startDrag(Offset local) {
          final markerX = width * markerFraction;
          // 上段で旗の近くをつかんだらマーク、それ以外はトラック上＝再生位置。
          final grabbedFlag =
              local.dy <= cy - 8 && (local.dx - markerX).abs() <= 24;
          if (grabbedFlag) {
            _grab = _Grab.marker;
            widget.onMarkerChange(_toDuration(clampFraction(local.dx)));
          } else {
            _grab = _Grab.position;
            _dragFraction = clampFraction(local.dx);
            widget.onSeekStart();
            widget.onSeek(_toDuration(_dragFraction));
          }
          setState(() {});
        }

        void updateDrag(Offset local) {
          final f = clampFraction(local.dx);
          if (_grab == _Grab.marker) {
            widget.onMarkerChange(_toDuration(f));
          } else if (_grab == _Grab.position) {
            setState(() => _dragFraction = f);
            widget.onSeek(_toDuration(f));
          }
        }

        void endDrag() {
          if (_grab == _Grab.position) {
            widget.onSeek(_toDuration(_dragFraction));
            widget.onSeekEnd();
          }
          setState(() => _grab = _Grab.none);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (d) {
                  // トラック上のタップは再生位置へシーク（旗の上段は無視）。
                  if (d.localPosition.dy > cy - 8) {
                    widget.onSeek(_toDuration(clampFraction(d.localPosition.dx)));
                  }
                }
              : null,
          onPanStart: enabled ? (d) => startDrag(d.localPosition) : null,
          onPanUpdate: enabled ? (d) => updateDrag(d.localPosition) : null,
          onPanEnd: enabled ? (_) => endDrag() : null,
          child: SizedBox(
            height: MarkerSeekBar._height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SeekBarPainter(
                positionFraction: positionFraction,
                markerFraction: markerFraction,
                centerY: cy,
                trackColor: theme.colorScheme.surfaceContainerHighest,
                playedColor: theme.colorScheme.primary,
                thumbColor: theme.colorScheme.primary,
                markerColor: theme.colorScheme.error,
                enabled: enabled,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({
    required this.positionFraction,
    required this.markerFraction,
    required this.centerY,
    required this.trackColor,
    required this.playedColor,
    required this.thumbColor,
    required this.markerColor,
    required this.enabled,
  });

  final double positionFraction;
  final double markerFraction;
  final double centerY;
  final Color trackColor;
  final Color playedColor;
  final Color thumbColor;
  final Color markerColor;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = centerY;
    const trackHeight = 6.0;
    const radius = Radius.circular(3);

    // 背景トラック。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - trackHeight / 2, size.width, trackHeight),
        radius,
      ),
      Paint()..color = trackColor,
    );

    // 再生済み部分。
    if (enabled) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, cy - trackHeight / 2,
              size.width * positionFraction, trackHeight),
          radius,
        ),
        Paint()..color = playedColor,
      );
    }

    // マーク（バーの上に立つ旗：ポール＋三角）。
    final mx = size.width * markerFraction;
    final markerPaint = Paint()
      ..color = markerColor
      ..strokeWidth = 2;
    // ポール（上からトラックまで）。
    canvas.drawLine(Offset(mx, 10), Offset(mx, cy), markerPaint);
    // 旗（三角）。
    final flag = Path()
      ..moveTo(mx, 10)
      ..lineTo(mx + 16, 16)
      ..lineTo(mx, 22)
      ..close();
    canvas.drawPath(flag, Paint()..color = markerColor);
    // ポール先端の小さな丸（つかむ目印）。
    canvas.drawCircle(Offset(mx, 10), 3, Paint()..color = markerColor);

    // 再生位置の丸（トラック上）。
    if (enabled) {
      final tx = size.width * positionFraction;
      canvas.drawCircle(Offset(tx, cy), 10, Paint()..color = thumbColor);
      canvas.drawCircle(
        Offset(tx, cy),
        10,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) {
    return old.positionFraction != positionFraction ||
        old.markerFraction != markerFraction ||
        old.enabled != enabled;
  }
}
