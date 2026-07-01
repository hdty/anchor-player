import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

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
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  final FocusNode _keyboardFocus = FocusNode();

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

  // Anchor 微調整キーの長押し（押した瞬間に1回、1秒押し続けると連続移動）。
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;
  Duration? _heldDelta;

  static final Set<LogicalKeyboardKey> _nudgeKeys = {
    LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.keyZ,
    LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.digit6, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.digit7, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.digit9, LogicalKeyboardKey.numpad9, LogicalKeyboardKey.keyE,
  };

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
    _applyLoopMode(); // 常に1曲エンドレスリピート（LoopMode.one に一本化）。
  }

  /// 常に1曲エンドレスリピート（ネイティブのループ再生に任せる）。
  void _applyLoopMode() {
    _player.setLoopMode(LoopMode.one);
  }

  @override
  void dispose() {
    _stopKeyHold();
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
    await _loadPath(path);
  }

  Future<void> _loadPath(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.setSpeed(_speed);
      _applyLoopMode();
      if (!mounted) return;
      setState(() {
        _fileName = _baseName(path);
        _marker = Duration.zero;
        _position = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot play this file: $e')),
      );
    }
  }

  // ---- 先頭/末尾ジャンプ ----

  /// ⏮ 先頭に戻って再生。
  void _toStartAndPlay() {
    if (_fileName == null) return;
    _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
    _player.seek(Duration.zero);
    _player.play();
  }

  /// ⏭ 末尾（ちょうど終端）に進んで一時停止。
  /// ループが有効なままだと末尾seekで完了→先頭へ戻るため、一時的にループを切る。
  /// 次に再生を始めたとき（各play経路）でループを戻す。
  void _toEndAndPause() {
    if (_fileName == null || _duration <= Duration.zero) return;
    _player.setLoopMode(LoopMode.off);
    _player.pause();
    _player.seek(_duration);
  }

  // ---- 再生制御 ----

  void _togglePlay() {
    if (_fileName == null) return;
    if (_playing) {
      _player.pause();
    } else {
      _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
      _player.play();
    }
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
    _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
    _player.seek(_marker);
    _player.play(); // 移動してそこから再生を続ける。
  }

  /// Anchor(マーク)位置をキーボード等で微調整する。[0, 全体長] にクランプ。
  void _nudgeMarker(Duration delta) {
    if (_fileName == null) return;
    var m = _marker + delta;
    if (m < Duration.zero) m = Duration.zero;
    if (m > _duration) m = _duration;
    setState(() => _marker = m);
  }

  /// 微調整キーを押した瞬間に1回、押し続けて1秒経過後は連続で動かす。
  void _startKeyHold(Duration delta) {
    if (_fileName == null) return;
    _stopKeyHold();
    _heldDelta = delta;
    _nudgeMarker(delta); // 押した瞬間に1回
    _holdDelayTimer = Timer(const Duration(seconds: 1), () {
      _holdRepeatTimer =
          Timer.periodic(const Duration(milliseconds: 110), (_) {
        final d = _heldDelta;
        if (d != null) _nudgeMarker(d);
      });
    });
  }

  /// 連続移動を止める（キーを離したとき／破棄時）。
  void _stopKeyHold() {
    _holdDelayTimer?.cancel();
    _holdRepeatTimer?.cancel();
    _holdDelayTimer = null;
    _holdRepeatTimer = null;
    _heldDelta = null;
  }

  /// 現在の再生位置を Anchor にする。
  void _setAnchorToCurrent() {
    if (_fileName == null) return;
    setState(() => _marker = _position);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 微調整キーを離したら連続移動を止める。
    if (event is KeyUpEvent) {
      if (_nudgeKeys.contains(event.logicalKey)) {
        _stopKeyHold();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // OSのキーリピート(KeyRepeatEvent)は無視し、連続移動は自前タイマーで行う。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      // Jump to Anchor: Space / 0
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        _jumpToMarker();
        return KeyEventResult.handled;
      // Set Anchor here: 5 / S（微調整キー群の中央）
      case LogicalKeyboardKey.digit5:
      case LogicalKeyboardKey.numpad5:
      case LogicalKeyboardKey.keyS:
        _setAnchorToCurrent();
        return KeyEventResult.handled;
      // 再生 / 一時停止: Enter（テンキーEnterも）
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _togglePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekRelative(-10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekRelative(10);
        return KeyEventResult.handled;
      // Anchor 微調整: 押した瞬間に1回、1秒押し続けると連続。
      // 左列(1/4/7, z/a/q)=前へ / 右列(3/6/9, c/d/e)=後ろへ。
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
      case LogicalKeyboardKey.keyZ:
        _startKeyHold(const Duration(milliseconds: -200));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
      case LogicalKeyboardKey.keyC:
        _startKeyHold(const Duration(milliseconds: 200));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit4:
      case LogicalKeyboardKey.numpad4:
      case LogicalKeyboardKey.keyA:
        _startKeyHold(const Duration(seconds: -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit6:
      case LogicalKeyboardKey.numpad6:
      case LogicalKeyboardKey.keyD:
        _startKeyHold(const Duration(seconds: 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit7:
      case LogicalKeyboardKey.numpad7:
      case LogicalKeyboardKey.keyQ:
        _startKeyHold(const Duration(seconds: -5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit9:
      case LogicalKeyboardKey.numpad9:
      case LogicalKeyboardKey.keyE:
        _startKeyHold(const Duration(seconds: 5));
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----

  /// enabled のときだけツールチップを付ける（押せない状態では説明を出さない）。
  Widget _tip(bool enabled, String message, Widget child) =>
      enabled ? Tooltip(message: message, child: child) : child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _fileName != null;

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      // 子(ボタン等)にフォーカスを渡さない。ボタンをクリックしてもフォーカスが移らず、
      // 常に画面全体でキー操作(Space/B/←→)を受け続ける。
      // (矢印キーがボタン間のフォーカス移動に奪われる問題を防ぐ)
      descendantsAreFocusable: false,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          // タイトル行にファイル名を表示（未選択時はアプリ名）＋右にフォルダボタン。
          // ファイル名タップでもファイル変更できる（フォルダボタンと同じ／ツールチップ無し）。
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openFile,
            child: Text(
              _fileName ?? 'Anchor Player',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          backgroundColor: theme.colorScheme.inversePrimary,
          actions: [
            IconButton(
              tooltip: 'Open file',
              icon: const Icon(Icons.folder_open),
              onPressed: _openFile,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  const SizedBox(height: 8),

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
                    onNudgeMarker: _nudgeMarker,
                  ),
                  const SizedBox(height: 8),

                  // 再生時間（現在地 / 全体）。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position)),
                      Text(_fmt(_duration)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Anchorへ戻る（中核機能）。バーの近くに大きく目立たせて配置。
                  _tip(
                    hasFile,
                    'Jump to Anchor',
                    FilledButton.icon(
                      onPressed: hasFile ? _jumpToMarker : null,
                      icon: const Icon(Icons.replay, size: 26),
                      label: const Text('Jump to Anchor'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        minimumSize: const Size(240, 54),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 操作: 前の曲 / 10秒戻る / 再生 / 10秒進む / 次の曲。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 30,
                        tooltip: hasFile ? 'Back to start & play' : null,
                        onPressed: hasFile ? _toStartAndPlay : null,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        iconSize: 26,
                        tooltip: hasFile ? 'Back 10s (Left)' : null,
                        onPressed: hasFile ? () => _seekRelative(-10) : null,
                        icon: const Icon(Icons.replay_10),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        iconSize: 40,
                        tooltip: hasFile ? 'Play / Pause (Enter)' : null,
                        onPressed: hasFile ? _togglePlay : null,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        iconSize: 26,
                        tooltip: hasFile ? 'Forward 10s (Right)' : null,
                        onPressed: hasFile ? () => _seekRelative(10) : null,
                        icon: const Icon(Icons.forward_10),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 30,
                        tooltip: hasFile ? 'Go to end & pause' : null,
                        onPressed: hasFile ? _toEndAndPause : null,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Anchor の現在位置（時刻表示）＋ 現在の再生位置を Anchor にするボタン。
                  // キーボード(1/3,z/c …)や旗の横クリックでも微調整できる。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        'Anchor: ${_fmt(_marker)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(width: 12),
                      _tip(
                        hasFile,
                        'Set Anchor here',
                        OutlinedButton.icon(
                          onPressed: hasFile ? _setAnchorToCurrent : null,
                          icon: const Icon(Icons.flag, size: 18),
                          label: const Text('Set Anchor here'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Anchor 微調整ボタン（タップ=1回 / 長押し=連続）。
                  // タッチ専用環境(Android/iOS)でもキー無しで調整できる。
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _NudgeButton(
                          label: '−5s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(seconds: -5))),
                      _NudgeButton(
                          label: '−1s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(seconds: -1))),
                      _NudgeButton(
                          label: '−0.2s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(milliseconds: -200))),
                      const SizedBox(width: 14),
                      _NudgeButton(
                          label: '+0.2s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(milliseconds: 200))),
                      _NudgeButton(
                          label: '+1s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(seconds: 1))),
                      _NudgeButton(
                          label: '+5s',
                          enabled: hasFile,
                          onNudge: () =>
                              _nudgeMarker(const Duration(seconds: 5))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 再生速度（ラベル無し）。
                  SegmentedButton<double>(
                    segments: _speeds
                        .map((s) => ButtonSegment<double>(
                              value: s,
                              tooltip: 'Change speed',
                              // 各セグメントを同じ幅に揃える。
                              label: SizedBox(
                                width: 44,
                                child: Center(child: Text('${s}x')),
                              ),
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
    required this.onNudgeMarker,
  });

  final Duration duration;
  final Duration position;
  final Duration marker;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<Duration> onMarkerChange; // 絶対位置
  final ValueChanged<Duration> onNudgeMarker; // 相対移動（クランプは親側）

  static const double _height = 64;
  static const double _trackCenterY = 46; // トラック（丸）の中心Y。旗は上に立つ。

  @override
  State<MarkerSeekBar> createState() => _MarkerSeekBarState();
}

enum _Grab { none, marker, position }

class _MarkerSeekBarState extends State<MarkerSeekBar> {
  _Grab _grab = _Grab.none;
  double _dragFraction = 0;
  // 位置ドラッグ中のシーク連射を防ぐスロットル。最終位置は離した時に確定シークする。
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _seekThrottle = Duration(milliseconds: 80);

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
          // 上段(旗)領域は再生位置の丸(半径10=上端cy-10)と重ならないよう cy-12 まで。
          final grabbedFlag =
              local.dy <= cy - 12 && (local.dx - markerX).abs() <= 24;
          if (grabbedFlag) {
            _grab = _Grab.marker;
            widget.onMarkerChange(_toDuration(clampFraction(local.dx)));
          } else {
            _grab = _Grab.position;
            _dragFraction = clampFraction(local.dx);
            widget.onSeekStart();
            widget.onSeek(_toDuration(_dragFraction));
            _lastSeek = DateTime.now();
          }
          setState(() {});
        }

        void updateDrag(Offset local) {
          final f = clampFraction(local.dx);
          if (_grab == _Grab.marker) {
            widget.onMarkerChange(_toDuration(f));
          } else if (_grab == _Grab.position) {
            setState(() => _dragFraction = f); // 表示は毎回更新（滑らか）
            final now = DateTime.now();
            if (now.difference(_lastSeek) >= _seekThrottle) {
              _lastSeek = now;
              widget.onSeek(_toDuration(f)); // 実シークは間引く
            }
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
                  final local = d.localPosition;
                  if (local.dy <= cy - 12) {
                    // 旗レーン：旗の少し横をクリックで Anchor を 0.2 秒微調整。
                    // 旗より左=前へ / 右=後ろへ。旗の近く(±120px)のみ反応。
                    final markerX = width * markerFraction;
                    if ((local.dx - markerX).abs() <= 120) {
                      widget.onNudgeMarker(Duration(
                          milliseconds: local.dx >= markerX ? 200 : -200));
                    }
                  } else {
                    // トラック上のタップは再生位置へシーク。
                    widget.onSeek(_toDuration(clampFraction(local.dx)));
                  }
                }
              : null,
          onPanStart: enabled ? (d) => startDrag(d.localPosition) : null,
          onPanUpdate: enabled ? (d) => updateDrag(d.localPosition) : null,
          onPanEnd: enabled ? (_) => endDrag() : null,
          // ドラッグが途中でキャンセルされても状態を必ず解除する。
          onPanCancel: enabled ? endDrag : null,
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

    // マーク（バーの上に立つ旗：ポール＋三角）。ファイル読み込み後のみ表示。
    if (enabled) {
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
    }

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

/// Anchor 微調整ボタン。タップで1回、長押しで連続的に微調整する。
/// タッチ（Android/iOS）でもキーボード無しで Anchor をずらせる。
class _NudgeButton extends StatefulWidget {
  const _NudgeButton({
    required this.label,
    required this.onNudge,
    required this.enabled,
  });

  final String label;
  final VoidCallback onNudge;
  final bool enabled;

  @override
  State<_NudgeButton> createState() => _NudgeButtonState();
}

class _NudgeButtonState extends State<_NudgeButton> {
  Timer? _timer;

  void _startRepeat() {
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(milliseconds: 110), (_) => widget.onNudge());
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        widget.enabled ? theme.colorScheme.primary : theme.disabledColor;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onNudge : null,
      onLongPressStart: widget.enabled
          ? (_) {
              widget.onNudge(); // 長押し開始で即1回、以降は連続。
              _startRepeat();
            }
          : null,
      onLongPressEnd: widget.enabled ? (_) => _stopRepeat() : null,
      onLongPressCancel: _stopRepeat,
      // 固定幅で全ボタンを同じ大きさに揃える。
      child: Container(
        width: 66,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          widget.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
    // 押せない状態（ファイル未読み込み）ではツールチップを出さない。
    if (!widget.enabled) return button;
    return Tooltip(
      message: 'Adjust Anchor',
      // 長押しは連続微調整に使うため、タッチではツールチップを出さない（ホバーのみ）。
      triggerMode: TooltipTriggerMode.manual,
      child: button,
    );
  }
}
