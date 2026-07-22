import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../shortcuts.dart';
import 'player_view.dart';
import 'shortcuts_dialog.dart';

/// 再生状態とキー入力を持つ。画面の見た目は [PlayerView] 側にある。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> implements PlayerCommands {
  final AudioPlayer _player = AudioPlayer();
  final FocusNode _keyboardFocus = FocusNode();

  static const Set<String> _audioExts = {
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus',
  };

  String? _fileName;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _anchor = Duration.zero; // 「戻る」位置。最初は0秒、ピンのドラッグで移動。
  bool _playing = false;
  bool _dragging = false;
  double _speed = 1.0;

  // アンカー微調整キーの長押し（押した瞬間に1回、1秒押し続けると連続移動）。
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;
  Duration? _heldDelta;

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

  // ---- ファイル ----

  String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  @override
  Future<void> openFile() async {
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
        _anchor = Duration.zero;
        _position = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot play this file: $e')),
      );
    }
  }

  @override
  void showShortcuts(BuildContext context) => ShortcutsDialog.show(context);

  // ---- 先頭/末尾ジャンプ ----

  /// 先頭に戻って再生。
  @override
  void toStartAndPlay() {
    if (_fileName == null) return;
    _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
    _player.seek(Duration.zero);
    _player.play();
  }

  /// 末尾（ちょうど終端）に進んで一時停止。
  /// ループが有効なままだと末尾seekで完了→先頭へ戻るため、一時的にループを切る。
  /// 次に再生を始めたとき（各play経路）でループを戻す。
  @override
  void toEndAndPause() {
    if (_fileName == null || _duration <= Duration.zero) return;
    _player.setLoopMode(LoopMode.off);
    _player.pause();
    _player.seek(_duration);
  }

  // ---- 再生制御 ----

  @override
  void togglePlay() {
    if (_fileName == null) return;
    if (_playing) {
      _player.pause();
    } else {
      _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
      _player.play();
    }
  }

  @override
  void seekTo(Duration position) {
    _player.seek(position);
    setState(() => _position = position);
  }

  @override
  void seekDragStart() => _dragging = true;

  @override
  void seekDragEnd() => _dragging = false;

  @override
  void seekRelative(Duration delta) {
    if (_fileName == null) return;
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
    _player.seek(target);
  }

  @override
  void setSpeed(double speed) {
    _player.setSpeed(speed);
    setState(() => _speed = speed);
  }

  // ---- アンカー ----

  @override
  void jumpToAnchor() {
    if (_fileName == null) return;
    _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
    _player.seek(_anchor);
    _player.play(); // 移動してそこから再生を続ける。
  }

  @override
  void setAnchor(Duration anchor) => setState(() => _anchor = anchor);

  /// 現在の再生位置をアンカーにする。
  @override
  void setAnchorToCurrent() {
    if (_fileName == null) return;
    setState(() => _anchor = _position);
  }

  /// アンカー位置を相対移動する。[0, 全体長] にクランプ。
  @override
  void nudgeAnchor(Duration delta) {
    if (_fileName == null) return;
    var a = _anchor + delta;
    if (a < Duration.zero) a = Duration.zero;
    if (a > _duration) a = _duration;
    setState(() => _anchor = a);
  }

  /// 微調整キーを押した瞬間に1回、押し続けて1秒経過後は連続で動かす。
  void _startKeyHold(Duration delta) {
    if (_fileName == null) return;
    _stopKeyHold();
    _heldDelta = delta;
    nudgeAnchor(delta); // 押した瞬間に1回
    _holdDelayTimer = Timer(const Duration(seconds: 1), () {
      _holdRepeatTimer =
          Timer.periodic(const Duration(milliseconds: 110), (_) {
        final d = _heldDelta;
        if (d != null) nudgeAnchor(d);
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

  // ---- キー入力 ----

  /// 割り当ては lib/shortcuts.dart にまとめてある。ここは振り分けるだけ。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final spec = kShortcutByKey[event.logicalKey];
    if (spec == null) return KeyEventResult.ignored;

    // 微調整キーを離したら連続移動を止める。
    if (event is KeyUpEvent) {
      if (spec.repeatable) {
        _stopKeyHold();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // OSのキーリピート(KeyRepeatEvent)は無視し、連続移動は自前タイマーで行う。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (spec.intent) {
      case JumpToAnchorIntent():
        jumpToAnchor();
      case TogglePlayIntent():
        togglePlay();
      case SetAnchorHereIntent():
        setAnchorToCurrent();
      case SeekRelativeIntent(:final delta):
        seekRelative(delta);
      case NudgeAnchorIntent(:final delta):
        _startKeyHold(delta);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      // 子(ボタン等)にフォーカスを渡さない。ボタンをクリックしてもフォーカスが移らず、
      // 常に画面全体でキー操作を受け続ける。
      // (矢印キーがボタン間のフォーカス移動に奪われる問題を防ぐ)
      descendantsAreFocusable: false,
      onKeyEvent: _onKey,
      child: PlayerView(
        data: PlayerViewData(
          fileName: _fileName,
          duration: _duration,
          position: _position,
          anchor: _anchor,
          playing: _playing,
          speed: _speed,
        ),
        commands: this,
      ),
    );
  }
}
