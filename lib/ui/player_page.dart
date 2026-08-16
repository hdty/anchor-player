import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_engine.dart';
import '../recent_files.dart';
import '../shortcuts.dart';
import 'player_view.dart';
import 'shortcuts_dialog.dart';

/// 再生状態とキー入力を持つ。画面の見た目は [PlayerView] 側にある。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.engineFactory});

  /// テストから偽の [AudioEngine] を渡すための口。
  /// 本番では null のままで、[JustAudioEngine] が使われる。
  final AudioEngine Function()? engineFactory;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> implements PlayerCommands {
  late final AudioEngine _player =
      (widget.engineFactory ?? JustAudioEngine.new)();
  final FocusNode _keyboardFocus = FocusNode();

  static const Set<String> _audioExts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
  };

  String? _fileName;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _anchor = Duration.zero; // 「戻る」位置。最初は0秒、ピンのドラッグで移動。
  bool _playing = false;
  bool _dragging = false;
  double _speed = 1.0;
  RecentFiles _recent = RecentFiles.empty;

  // アンカー微調整キーの長押し（押した瞬間に1回、1秒押し続けると連続移動）。
  Timer? _holdDelayTimer;
  Timer? _holdRepeatTimer;
  Duration? _heldDelta;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.durationStream.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d ?? Duration.zero);
      }),
    );
    _subs.add(
      _player.positionStream.listen((p) {
        if (!mounted || _dragging) return;
        setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.playingStream.listen((playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
      }),
    );
    _run('init', _applyLoopMode); // 常に1曲エンドレスリピート（EngineLoopMode.one に一本化）。
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final recent = await RecentFiles.load();
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  /// 常に1曲エンドレスリピート（ネイティブのループ再生に任せる）。
  Future<void> _applyLoopMode() => _player.setLoopMode(EngineLoopMode.one);

  // ---- 再生エンジンへの操作の直列化 ----

  /// 発行した順に実行されることを保証するためのキュー。
  ///
  /// エンジンへの操作はどれも非同期なので、投げっぱなしにするとコマンドをまたいで
  /// 追い越しが起きる。例えば ⏭（末尾へ seek）の直後に Jump to Anchor を押すと、
  /// 後から着地した ⏭ の seek によってアンカーではなく終端へ飛んでしまう。
  /// 1本のキューに通せば、コマンドをまたいでも順序が入れ替わらない。
  Future<void> _queue = Future<void>.value();

  /// [action] をキューの末尾につないで実行する。
  ///
  /// 例外はここで拾ってログに出す。投げっぱなしのままだとリリースビルドで痕跡が
  /// 残らず、「ときどき効かない」の調査ができなくなるため。
  /// 吸収しないとキューが壊れて以後の操作が全て止まる、という理由もある。
  Future<void> _run(String label, Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((Object e) {
      _reportFailure(label, e);
    });
    _queue = next;
    return next;
  }

  /// 再生操作の失敗を知らせる。
  ///
  /// 以前はログに出すだけで、利用者からは「押しても効かない」としか見えなかった。
  /// ただし例外の全文は出さない。読んでも対処できないうえ、パスなどが混じる。
  /// 詳細は debugPrint に残す。
  DateTime _lastFailureShown = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _failureNotifyInterval = Duration(seconds: 5);

  void _reportFailure(String label, Object error) {
    debugPrint('Anchor Player: $label failed: $error');
    if (!mounted) return;

    // 1操作が複数の失敗を生む（seek と play が続けて落ちる等）ので、
    // 出しっぱなしにすると画面が通知で埋まる。一定時間に1回だけ出す。
    final now = DateTime.now();
    if (now.difference(_lastFailureShown) < _failureNotifyInterval) return;
    _lastFailureShown = now;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playback failed. Try reopening the file.')),
    );
  }

  /// 再生を始める。**`play()` を await してはいけない。**
  ///
  /// just_audio の `play()` が返す Future は「再生が完了 / 一時停止 / 停止した」
  /// ときに完了する。キューの中で待つと再生中ずっとキューが詰まり、以後の操作が
  /// 全て止まってしまう。順序が要るのは play より前の seek / setLoopMode なので、
  /// それらを await したうえで play は投げるだけにする。
  void _startPlayback(String label) {
    unawaited(
      _player.play().catchError((Object e) {
        _reportFailure('$label play', e);
      }),
    );
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
      allowedExtensions: _audioExts
          .map((e) => e.substring(1))
          .toList(), // 先頭の'.'を除く
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _loadPath(path);
  }

  @override
  Future<void> openRecent(String path) => _loadPath(path);

  /// 読み込みもキューに通す。前のコマンドが出したシークが、新しく開いたファイルに
  /// 着地するのを防ぐため。例外は中で処理するので [_run] 側には伝わらない。
  Future<void> _loadPath(String path) => _run('load', () => _load(path));

  /// アンカーと再生位置は、読み込みのたびに必ず 0 に戻す（[docs/SPEC.md] の仕様）。
  /// 前回どこにアンカーを置いて終えたかは持ち越さない。
  Future<void> _load(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.setSpeed(_speed);
      await _applyLoopMode();
      // 再生できたものだけ履歴に残す。開けなかったファイルを覚えても意味がない。
      final recent = await RecentFiles.add(path);
      if (!mounted) return;
      setState(() {
        _fileName = _baseName(path);
        _anchor = Duration.zero;
        _position = Duration.zero;
        _recent = recent;
      });
    } catch (e) {
      debugPrint('Anchor Player: load failed: $e');
      // 読み込みに失敗した音源は中途半端にエンジンへ載っている可能性がある。
      // 画面だけ前のファイルのまま残すと「再生を押しても鳴らない」状態になるので、
      // 空状態まで戻して表示とエンジンを一致させる。
      try {
        await _player.stop();
      } catch (_) {
        // 停止にも失敗したら打つ手がない。空状態にする方を優先する。
      }
      if (!mounted) return;
      setState(() {
        _fileName = null;
        _duration = Duration.zero;
        _position = Duration.zero;
        _anchor = Duration.zero;
      });
      // 例外の全文は出さない。読んでも対処できず、パスなどが混じる。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${_baseName(path)}')),
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
    _run('toStartAndPlay', () async {
      await _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
      await _player.seek(Duration.zero);
      _startPlayback('toStartAndPlay');
    });
  }

  /// 末尾（ちょうど終端）に進んで一時停止。
  /// ループが有効なままだと末尾seekで完了→先頭へ戻るため、一時的にループを切る。
  /// 次に再生を始めたとき（各play経路）でループを戻す。
  @override
  void toEndAndPause() {
    if (_fileName == null || _duration <= Duration.zero) return;
    _run('toEndAndPause', () async {
      await _player.setLoopMode(EngineLoopMode.off);
      await _player.pause();
      await _player.seek(_duration);
    });
  }

  // ---- 再生制御 ----

  @override
  void togglePlay() {
    if (_fileName == null) return;
    if (_playing) {
      _run('pause', () => _player.pause());
    } else {
      _run('play', () async {
        // ループを戻してから再生する。順序が逆だと、⏭ で終端に置いたまま再生した
        // ときにループ無効のまま即完了して無音になる。
        await _applyLoopMode();
        _startPlayback('play');
      });
    }
  }

  @override
  void seekTo(Duration position) {
    _run('seekTo', () => _player.seek(position));
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
    _run('seekRelative', () => _player.seek(target));
  }

  @override
  void setSpeed(double speed) {
    _run('setSpeed', () => _player.setSpeed(speed));
    setState(() => _speed = speed);
  }

  // ---- アンカー ----

  @override
  void jumpToAnchor() {
    if (_fileName == null) return;
    _run('jumpToAnchor', () async {
      await _applyLoopMode(); // 末尾一時停止でループを切っている場合に備え再有効化。
      await _player.seek(_anchor);
      _startPlayback('jumpToAnchor'); // 移動してそこから再生を続ける。
    });
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
      _holdRepeatTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
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
          recentPaths: _recent.paths,
        ),
        commands: this,
      ),
    );
  }
}
