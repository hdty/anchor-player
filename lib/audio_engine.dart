import 'dart:async';

import 'package:just_audio/just_audio.dart' as ja;

/// このアプリが音声エンジンに求めることの全て。
///
/// テストから差し替えられるようにするためだけの薄い層で、
/// **just_audio の API を真似ることは目的にしていない。**
/// 実際に使っている 9 メソッドと 3 ストリームしか載せない。
/// 増やしたくなったら、まず本当に必要かを疑うこと。
abstract class AudioEngine {
  /// 総再生時間。読み込み前や不明な間は null が流れる。
  Stream<Duration?> get durationStream;
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;

  Future<void> setFilePath(String path);
  Future<void> setSpeed(double speed);
  Future<void> setLoopMode(EngineLoopMode mode);
  Future<void> seek(Duration position);

  /// **返る Future は「再生が終わった / 止まった」ときに完了する。**
  /// 再生開始を待つものではないので、操作を直列化するキューの中で await しては
  /// いけない（再生している間ずっとキューが詰まる）。
  Future<void> play();

  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

/// 使うのは「1曲を繰り返す」か「繰り返さない」かの2値だけ。
/// プレイリストを持たないので just_audio の LoopMode をそのまま公開しない。
enum EngineLoopMode { one, off }

/// just_audio を [AudioEngine] として使う。
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() : _player = ja.AudioPlayer();

  final ja.AudioPlayer _player;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setLoopMode(EngineLoopMode mode) => _player.setLoopMode(
    mode == EngineLoopMode.one ? ja.LoopMode.one : ja.LoopMode.off,
  );

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
