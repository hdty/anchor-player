import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 再生位置のシークバー。2つの独立したハンドルを持つ。
/// - トラック上の丸（再生位置）をドラッグ → シーク
/// - トラックの上に立つピン（アンカー）をドラッグ → アンカー位置を移動
///
/// ピンは上段・丸は下段（トラック上）に分けて配置するので、つかんだ方だけが動く。
/// ピンの形（丸い頭＋丸終端の軸）はアプリアイコンの錨と同じ語彙にしてある。
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
  static const double _trackCenterY = 46; // トラック（丸）の中心Y。ピンは上に立つ。

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

  /// 読み上げ用の時刻。「2分5秒」のように単位を伴わせる
  /// （`02:05` は読み上げると意味が取りにくい）。
  static String _describe(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return m > 0 ? '$m min $s sec' : '$s sec';
  }

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
    final scheme = Theme.of(context).colorScheme;
    final anchorColors = context.anchorColors;
    final enabled = widget.duration.inMilliseconds > 0;
    final positionFraction = _grab == _Grab.position
        ? _dragFraction
        : _fraction(widget.position);
    final markerFraction = _fraction(widget.marker);
    const cy = MarkerSeekBar._trackCenterY;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double clampFraction(double dx) => (dx / width).clamp(0.0, 1.0);

        void startDrag(Offset local) {
          final markerX = width * markerFraction;
          // 上段でピンの近くをつかんだらアンカー、それ以外はトラック上＝再生位置。
          // 上段(ピン)領域は再生位置の丸(半径10=上端cy-10)と重ならないよう cy-12 まで。
          final grabbedPin =
              local.dy <= cy - 12 && (local.dx - markerX).abs() <= 24;
          if (grabbedPin) {
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
                    // ピンのレーン：ピンの少し横をクリックでアンカーを 0.2 秒微調整。
                    // ピンより左=前へ / 右=後ろへ。ピンの近く(±120px)のみ反応。
                    final markerX = width * markerFraction;
                    if ((local.dx - markerX).abs() <= 120) {
                      widget.onNudgeMarker(
                        Duration(
                          milliseconds: local.dx >= markerX ? 200 : -200,
                        ),
                      );
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
          // 見た目は1枚の CustomPaint だが、意味としては2つの独立した値を持つ。
          // 読み上げでも別物として伝わるように、それぞれに Semantics を重ねる
          // （描画には関与しないので、大きさ・当たり判定は変わらない）。
          child: Stack(
            children: [
              Semantics(
                label: 'Playback position',
                value: _describe(widget.position),
                increasedValue: 'Right arrow: forward 10 seconds',
                decreasedValue: 'Left arrow: back 10 seconds',
                slider: true,
                readOnly: !enabled,
                child: const SizedBox.shrink(),
              ),
              Semantics(
                label: 'Anchor',
                value: _describe(widget.marker),
                hint: 'Space returns here. Drag the pin to move it.',
                slider: true,
                readOnly: !enabled,
                child: const SizedBox.shrink(),
              ),
              SizedBox(
                height: MarkerSeekBar._height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SeekBarPainter(
                    positionFraction: positionFraction,
                    markerFraction: markerFraction,
                    centerY: cy,
                    trackColor: scheme.surfaceContainerHighest,
                    playedColor: scheme.primary,
                    thumbColor: scheme.primary,
                    thumbBorderColor: scheme.surface,
                    markerColor: anchorColors.anchor,
                    markerInnerColor: anchorColors.onAnchor,
                    enabled: enabled,
                    grabbingMarker: _grab == _Grab.marker,
                  ),
                ),
              ),
            ],
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
    required this.thumbBorderColor,
    required this.markerColor,
    required this.markerInnerColor,
    required this.enabled,
    required this.grabbingMarker,
  });

  final double positionFraction;
  final double markerFraction;
  final double centerY;
  final Color trackColor;
  final Color playedColor;
  final Color thumbColor;
  final Color thumbBorderColor;
  final Color markerColor;
  final Color markerInnerColor;
  final bool enabled;
  final bool grabbingMarker;

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

    if (!enabled) return;

    // 再生済み部分。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          cy - trackHeight / 2,
          size.width * positionFraction,
          trackHeight,
        ),
        radius,
      ),
      Paint()..color = playedColor,
    );

    // アンカーのピン：丸い頭＋丸終端の軸。アイコンの錨と同じ形の語彙。
    final mx = size.width * markerFraction;
    final headRadius = grabbingMarker ? 9.0 : 7.0;
    canvas.drawLine(
      Offset(mx, 12),
      Offset(mx, cy),
      Paint()
        ..color = markerColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(mx, 12), headRadius, Paint()..color = markerColor);
    canvas.drawCircle(
      Offset(mx, 12),
      headRadius / 2.8,
      Paint()..color = markerInnerColor,
    );

    // 再生位置の丸（トラック上）。
    final tx = size.width * positionFraction;
    canvas.drawCircle(Offset(tx, cy), 10, Paint()..color = thumbColor);
    canvas.drawCircle(
      Offset(tx, cy),
      10,
      Paint()
        ..color = thumbBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) {
    return old.positionFraction != positionFraction ||
        old.markerFraction != markerFraction ||
        old.enabled != enabled ||
        old.grabbingMarker != grabbingMarker ||
        old.trackColor != trackColor ||
        old.markerColor != markerColor;
  }
}
