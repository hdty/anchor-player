import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// アンカーの現在位置と微調整ボタンを1行にまとめたもの。
///
///     −5  −1  −0.2   ⚓ 0:12.4   +0.2  +1  +5
///
/// 以前はアンカーの情報が「時刻テキスト」「微調整バー」「Set ボタン」「シークバーの旗」の
/// 4箇所に散っていた。動かす対象（時刻）と動かす手段（ボタン）を隣り合わせにして、
/// 押した結果がその場で読めるようにしている。
///
/// 見た目は塗りのないステッパー。速度選択が M3 の [SegmentedButton]（＝選択状態を持つ
/// トグル）なのに対し、こちらは押すたびに動くモーメンタリ動作なので、意図的に別の形にする。
class AnchorNudgeRow extends StatelessWidget {
  const AnchorNudgeRow({
    super.key,
    required this.anchor,
    required this.enabled,
    required this.onNudge,
  });

  /// 現在のアンカー位置。
  final Duration anchor;
  final bool enabled;
  final ValueChanged<Duration> onNudge;

  /// 左右対称に並べる刻み。左列＝前へ / 右列＝後ろへ。
  static const List<Duration> _steps = [
    Duration(seconds: 5),
    Duration(seconds: 1),
    Duration(milliseconds: 200),
  ];

  static String formatWithTenths(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (d.inMilliseconds.remainder(1000) ~/ 100);
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s.$tenths' : '$m:$s.$tenths';
  }

  static String _label(Duration d, {required bool negative}) {
    final sign = negative ? '−' : '+'; // U+2212 マイナス記号（ハイフンより見やすい）
    final text = d.inMilliseconds % 1000 == 0
        ? '${d.inSeconds}'
        : (d.inMilliseconds / 1000).toStringAsFixed(1);
    return '$sign$text';
  }

  @override
  Widget build(BuildContext context) {
    final anchorColors = context.anchorColors;
    final onContainer = anchorColors.onAnchorContainer;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final step in _steps)
          _NudgeButton(
            label: _label(step, negative: true),
            tooltip:
                'Anchor ${_label(step, negative: true)} s (hold to repeat)',
            color: onContainer,
            enabled: enabled,
            onTap: () => onNudge(-step),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _AnchorReadout(anchor: anchor, enabled: enabled),
        ),
        for (final step in _steps.reversed)
          _NudgeButton(
            label: _label(step, negative: false),
            tooltip:
                'Anchor ${_label(step, negative: false)} s (hold to repeat)',
            color: onContainer,
            enabled: enabled,
            onTap: () => onNudge(step),
          ),
      ],
    );
  }
}

/// アンカー時刻の表示。0.1 秒まで出す。
///
/// 微調整の最小刻みが 0.2 秒なのに以前は `mm:ss` までしか出しておらず、
/// ボタンを押しても表示が変わらないことがあった。
class _AnchorReadout extends StatelessWidget {
  const _AnchorReadout({required this.anchor, required this.enabled});

  final Duration anchor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final anchorColors = context.anchorColors;
    final color = enabled
        ? anchorColors.anchor
        : Theme.of(context).disabledColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.anchor, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          AnchorNudgeRow.formatWithTenths(anchor),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            // 桁が変わっても左右に揺れないようにする。
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// タップで1回、押しっぱなしで連続して動かすボタン。
class _NudgeButton extends StatefulWidget {
  const _NudgeButton({
    required this.label,
    required this.tooltip,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_NudgeButton> createState() => _NudgeButtonState();
}

class _NudgeButtonState extends State<_NudgeButton> {
  Timer? _timer;

  void _startRepeat() {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(milliseconds: 110), (_) => widget.onTap());
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
    final button = GestureDetector(
      onLongPressStart: widget.enabled
          ? (_) {
              widget.onTap(); // 長押し開始で即1回、以降は連続。
              _startRepeat();
            }
          : null,
      onLongPressEnd: widget.enabled ? (_) => _stopRepeat() : null,
      onLongPressCancel: _stopRepeat,
      child: TextButton(
        onPressed: widget.enabled ? widget.onTap : null,
        style: TextButton.styleFrom(
          foregroundColor: widget.color,
          minimumSize: const Size(46, 38),
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        child: Text(widget.label),
      ),
    );
    return widget.enabled
        ? Tooltip(message: widget.tooltip, child: button)
        : button;
  }
}
