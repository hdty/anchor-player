import 'package:flutter/material.dart';

/// Anchor Player のアプリアイコン。
///
/// このファイルがアイコン形状の**唯一の定義**。アプリ内の表示（空状態）と
/// `tools/gen_icon.dart` によるアイコン画像の書き出しが、どちらもここを使う。
///
/// 図案の考え方（ヒエラルキー）:
/// このアプリの主機能は「音声ファイルの再生」で、アンカーはその再生を助ける
/// 重要な補助機能。だから主役は**大きな再生三角**、アンカーはその右下に
/// 半分サイズで少しだけ重なる**バッジ**として従属させる。
///
/// 座標は 96×96 のグリッドで定義する（Material Symbols の 24px グリッド ×4）。
/// アンカーの周囲には地の色の「逃げ」を入れて三角から浮かせる。実装は
/// [BlendMode.clear] で三角をアンカー形に太く抜き、その中に細いアンカーを描く。
/// こうすると地（プレートを描くときはプレート色、描かないときは透明）が
/// 隙間として覗く。詳細は design/icon_blueprint.md を参照。
class AnchorMark {
  const AnchorMark._();

  /// 設計グリッドの一辺。
  static const double grid = 96;

  /// 角丸プレートの半径。
  static const double plateRadius = 22;

  // ブランドカラー（HidéToys）。
  static const Color water = Color(0xFFA3D8E1); // 淡い水色
  static const Color ink = Color(0xFF13253F); // インクネイビー
  static const Color paleSakura = Color(0xFFE8AFCF); // 薄桜色（アイコンのアンカー）
  static const Color sakura = Color(0xFFC9457E); // 濃い桜（UI機能色。アイコンでは使わない）

  // 主役の再生三角。
  static final List<Offset> _triangle = const [
    Offset(32, 22),
    Offset(32, 74),
    Offset(74, 48),
  ];

  // 右下のアンカー（バッジ、半分サイズ）。
  static const Offset _ringCenter = Offset(63, 53);
  static const double _ringRadius = 4;
  static const Offset _shankTop = Offset(63, 57);
  static const Offset _shankBottom = Offset(63, 72);
  static const Offset _stockLeft = Offset(54, 62);
  static const Offset _stockRight = Offset(72, 62);

  // アンカー本体のストローク幅と、地色の逃げ（太く抜く）幅。
  static const double _ringStroke = 3.5;
  static const double _lineStroke = 5;
  static const double _ringGap = 7.5;
  static const double _lineGap = 9;

  static Path _trianglePath() {
    final p = Path()..moveTo(_triangle[0].dx, _triangle[0].dy);
    for (final v in _triangle.skip(1)) {
      p.lineTo(v.dx, v.dy);
    }
    return p..close();
  }

  static Path _flukesPath() => Path()
    ..moveTo(52, 68)
    ..quadraticBezierTo(52, 76, 63, 76)
    ..quadraticBezierTo(74, 76, 74, 68);

  static void _drawAnchor(
    Canvas canvas, {
    required double ringWidth,
    required double lineWidth,
    Color? color,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..blendMode = blendMode;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..blendMode = blendMode;
    if (color != null) {
      ring.color = color;
      line.color = color;
    } else {
      // clear では色は不透明でありさえすればよい。
      ring.color = const Color(0xFF000000);
      line.color = const Color(0xFF000000);
    }
    canvas.drawCircle(_ringCenter, _ringRadius, ring);
    canvas.drawLine(_shankTop, _shankBottom, line);
    canvas.drawLine(_stockLeft, _stockRight, line);
    canvas.drawPath(_flukesPath(), line);
  }

  /// マークを [canvas] に描く。呼び出し側で 96×96 の座標系に変換しておくこと。
  ///
  /// - [triangleColor] : 主役の再生三角の色。
  /// - [anchorColor]   : アンカーの色。null なら塗らず、逃げ（抜き）だけ残す。
  /// - [plateColor]    : 角丸プレートの色。null ならプレートを描かない
  ///                      （Android アダプティブの前景用。抜いた部分は透明になる）。
  /// - [withAnchor]    : false なら再生三角だけ描く（Android のモノクロ用。
  ///                      単色に落とすと逃げが「欠け」に見えるため）。
  static void paintOn(
    Canvas canvas, {
    required Color triangleColor,
    Color? anchorColor,
    Color? plateColor,
    bool withAnchor = true,
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

    final tri = _trianglePath();
    final triFill = Paint()
      ..color = triangleColor
      ..isAntiAlias = true;
    final triRound = Paint()
      ..color = triangleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (!withAnchor) {
      canvas.drawPath(tri, triFill);
      canvas.drawPath(tri, triRound); // 角を丸める。
      return;
    }

    // 三角を描き、その上からアンカー形に太く「抜く」。抜いた部分は
    // レイヤ合成後に地（プレート色 or 透明）が覗き、これが逃げになる。
    canvas.saveLayer(const Rect.fromLTWH(0, 0, grid, grid), Paint());
    canvas.drawPath(tri, triFill);
    canvas.drawPath(tri, triRound); // 角を丸める（Material Symbols Rounded の語彙）。
    _drawAnchor(
      canvas,
      ringWidth: _ringGap,
      lineWidth: _lineGap,
      blendMode: BlendMode.clear,
    );
    canvas.restore();

    // 逃げの中に、細いアンカーを載せる。
    if (anchorColor != null) {
      _drawAnchor(
        canvas,
        ringWidth: _ringStroke,
        lineWidth: _lineStroke,
        color: anchorColor,
      );
    }
  }
}

/// [AnchorMark] を任意のサイズに収めて描く Painter。
///
/// 96×96 のグリッドを短辺に合わせて等倍スケールし、中央に配置する。
class AnchorMarkPainter extends CustomPainter {
  const AnchorMarkPainter({
    required this.triangleColor,
    this.anchorColor,
    this.plateColor,
    this.withAnchor = true,
    this.scaleFactor = 1.0,
  });

  /// アプリアイコン（プレートあり・確定配色）。
  const AnchorMarkPainter.icon()
      : triangleColor = AnchorMark.water,
        anchorColor = AnchorMark.paleSakura,
        plateColor = AnchorMark.ink,
        withAnchor = true,
        scaleFactor = 1.0;

  final Color triangleColor;
  final Color? anchorColor;
  final Color? plateColor;
  final bool withAnchor;

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
      triangleColor: triangleColor,
      anchorColor: anchorColor,
      plateColor: plateColor,
      withAnchor: withAnchor,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AnchorMarkPainter old) =>
      old.triangleColor != triangleColor ||
      old.anchorColor != anchorColor ||
      old.plateColor != plateColor ||
      old.withAnchor != withAnchor ||
      old.scaleFactor != scaleFactor;
}
