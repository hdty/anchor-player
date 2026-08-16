import 'dart:async';

import 'package:anchor_player/audio_engine.dart';

/// テスト用の音声エンジン。呼ばれた順番を記録するのが主な仕事。
///
/// このアプリの不具合は「何を呼んだか」より **「どの順で呼んだか」** で起きてきた
/// （seek より先に play が着地してアンカーではなく終端から鳴る、など）。
/// なので [calls] に発行順を残す。
class FakeAudioEngine implements AudioEngine {
  final _duration = StreamController<Duration?>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  /// 呼ばれたメソッド名を発行順に並べたもの。`seek(0:00:05.000)` のように引数も残す。
  final List<String> calls = [];

  /// seek された位置の履歴。
  final List<Duration> seeks = [];

  /// 次の [setFilePath] を失敗させる。読み込み失敗の経路を試すため。
  Object? failNextLoad;

  /// [play] が返す Future を完了させない。
  ///
  /// 本物の just_audio では `play()` の Future は「再生が終わったとき」に完了する。
  /// 誤って操作キューの中で await すると、その間キューが詰まって以後の操作が
  /// 全部止まる。既定でこの性質を再現しておき、退行したらテストが固まるようにする。
  final _playCompleter = Completer<void>();

  bool disposed = false;

  void emitDuration(Duration? d) => _duration.add(d);
  void emitPosition(Duration p) => _position.add(p);
  void emitPlaying(bool p) => _playing.add(p);

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> setFilePath(String path) async {
    calls.add('setFilePath($path)');
    final failure = failNextLoad;
    if (failure != null) {
      failNextLoad = null;
      throw failure;
    }
  }

  @override
  Future<void> setSpeed(double speed) async => calls.add('setSpeed($speed)');

  @override
  Future<void> setLoopMode(EngineLoopMode mode) async =>
      calls.add('setLoopMode(${mode.name})');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek($position)');
    seeks.add(position);
  }

  @override
  Future<void> play() {
    calls.add('play');
    return _playCompleter.future; // わざと完了させない（上のコメント参照）
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async {
    disposed = true;
    await _duration.close();
    await _position.close();
    await _playing.close();
  }

  /// [calls] のうち、名前で始まるものだけを取り出す。
  List<String> where(String prefix) =>
      calls.where((c) => c.startsWith(prefix)).toList();

  int indexOf(String prefix) => calls.indexWhere((c) => c.startsWith(prefix));
}
