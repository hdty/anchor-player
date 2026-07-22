import 'package:flutter/material.dart';

/// Anchor Player のシンボルマーク。
///
/// このファイルがアイコン形状の**唯一の定義**。アプリ内の表示（空状態など）と
/// `tools/gen_icon.dart` によるアイコン画像の書き出しが、どちらもここを使う。
/// 以前は design/anchor_source.png というラスタ原画から背景を推測除去していたが、
/// スケールしないため幾何をコードに移した。
///
/// 座標は 96×96 のグリッドで定義する（Material Symbols の 24px グリッド ×4）。
/// ストローク幅 8・丸終端は Material Symbols Rounded の weight 400 相当。
class AnchorMark {
  const AnchorMark._();

  /// 設計グリッドの一辺。
  static const double grid = 96;

  /// 角丸プレートの半径。
  static const double plateRadius = 22;

  /// 均一ストローク幅（Material Symbols Rounded weight 400 相当）。
  static const double strokeWidth = 8;

  // ブランドカラー（HidéToys）。
  static const Color water = Color(0xFFA3D8E1); // 淡い水色（プレート地）
  static const Color sakura = Color(0xFFC9457E); // 桜色を機能色まで濃くしたもの（リング）
  static const Color ink = Color(0xFF13253F); // インクネイビー（錨本体）

  static const Offset _ringCenter = Offset(48, 27);
  static const double _ringRadius = 15;

  /// リング内に抜く再生三角。
  static Path playTriangle() => Path()
    ..moveTo(43.5, 20)
    ..lineTo(56, 27)
    ..lineTo(43.5, 34)
    ..close();

  /// 錨の下部（フルーク）の U 字。左端から下を回って右端まで一筆で描く
  /// （2本に分けると底の中央で丸終端が重なり継ぎ目が出るため）。
  static Path fluke() => Path()
    ..moveTo(22, 65)
    ..quadraticBezierTo(22, 83, 48, 83)
    ..quadraticBezierTo(74, 83, 74, 65);

  /// マークを [canvas] に描く。呼び出し側で 96×96 の座標系に変換しておくこと。
  ///
  /// 再生三角は [BlendMode.clear] で抜くため、必ず saveLayer の中で描く。
  /// プレートはレイヤの外に描くので、抜いた三角からプレートが透ける。
  static void paintOn(
    Canvas canvas, {
    required Color inkColor,
    required Color ringColor,
    Color? plateColor,
  }) {
    if (plateColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, grid, grid),
          const Radius.circular(plateRadius),
        ),
        Paint()..color = plateColor,
      );
    }

    canvas.saveLayer(const Rect.fromLTWH(0, 0, grid, grid), Paint());

    final stroke = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // リング（再生ボタンを兼ねる）。
    canvas.drawCircle(_ringCenter, _ringRadius, Paint()..color = ringColor);
    // シャンク（縦棒）。
    canvas.drawLine(const Offset(48, 42), const Offset(48, 83), stroke);
    // ストック（横棒）。
    canvas.drawLine(const Offset(30, 53), const Offset(66, 53), stroke);
    // フルーク（下部の U 字）。
    canvas.drawPath(fluke(), stroke);
    // リングから再生三角を抜く。
    canvas.drawPath(
      playTriangle(),
      Paint()..blendMode = BlendMode.clear,
    );

    canvas.restore();
  }
}

/// [AnchorMark] を任意のサイズに収めて描く Painter。
///
/// 96×96 のグリッドを短辺に合わせて等倍スケールし、中央に配置する。
class AnchorMarkPainter extends CustomPainter {
  const AnchorMarkPainter({
    required this.inkColor,
    required this.ringColor,
    this.plateColor,
    this.scaleFactor = 1.0,
  });

  final Color inkColor;
  final Color ringColor;

  /// null なら角丸プレートを描かない（アプリ内でマークだけ使う場合）。
  final Color? plateColor;

  /// グリッドをさらに縮める倍率。Android アダプティブアイコンの
  /// セーフゾーン（108dp 中の 66dp）に収めるときに使う。
  final double scaleFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / AnchorMark.grid * scaleFactor;
    final side = AnchorMark.grid * s;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(s);
    AnchorMark.paintOn(
      canvas,
      inkColor: inkColor,
      ringColor: ringColor,
      plateColor: plateColor,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AnchorMarkPainter old) =>
      old.inkColor != inkColor ||
      old.ringColor != ringColor ||
      old.plateColor != plateColor ||
      old.scaleFactor != scaleFactor;
}
