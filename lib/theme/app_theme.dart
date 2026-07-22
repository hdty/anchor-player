import 'package:flutter/material.dart';

import '../ui/anchor_mark.dart';

/// アンカー専用の意味色。
///
/// アンカーは「戻る場所」であって破壊的操作ではないので、以前使っていた
/// `colorScheme.error`（M3 では削除・破棄の色）から専用の色へ分離した。
/// 色は HidéToys の桜色系。ただし淡い桜色 `#E8AFCF` は白地でコントラストが
/// 約 1.4:1 しかなく文字やアイコンには使えないため、
/// 面積を取る地には淡い方（container）、線・文字・アイコンには濃い方を割り当てる。
@immutable
class AnchorColors extends ThemeExtension<AnchorColors> {
  const AnchorColors({
    required this.anchor,
    required this.onAnchor,
    required this.anchorContainer,
    required this.onAnchorContainer,
  });

  /// 旗・Jump ボタンの地・アンカー時刻など、アンカーを指す機能要素の色。
  final Color anchor;

  /// [anchor] の上に載る前景色。
  final Color onAnchor;

  /// アンカー関連をまとめたカードの地など、広い面に敷く淡い色。
  final Color anchorContainer;

  /// [anchorContainer] の上に載る前景色。
  final Color onAnchorContainer;

  static const AnchorColors light = AnchorColors(
    anchor: AnchorMark.sakura,
    onAnchor: Color(0xFFFFFFFF),
    anchorContainer: Color(0xFFFBE4EE),
    onAnchorContainer: Color(0xFF4A0E2C),
  );

  static const AnchorColors dark = AnchorColors(
    anchor: Color(0xFFE8AFCF),
    onAnchor: Color(0xFF4A0E2C),
    // 暗い画面ではブロックの面積がそのまま主張になるので、
    // ライトの container より相対的に沈めてある（濃い桜色だと画面を支配してしまう）。
    anchorContainer: Color(0xFF43172B),
    onAnchorContainer: Color(0xFFFBE4EE),
  );

  @override
  AnchorColors copyWith({
    Color? anchor,
    Color? onAnchor,
    Color? anchorContainer,
    Color? onAnchorContainer,
  }) {
    return AnchorColors(
      anchor: anchor ?? this.anchor,
      onAnchor: onAnchor ?? this.onAnchor,
      anchorContainer: anchorContainer ?? this.anchorContainer,
      onAnchorContainer: onAnchorContainer ?? this.onAnchorContainer,
    );
  }

  @override
  AnchorColors lerp(AnchorColors? other, double t) {
    if (other == null) return this;
    return AnchorColors(
      anchor: Color.lerp(anchor, other.anchor, t)!,
      onAnchor: Color.lerp(onAnchor, other.onAnchor, t)!,
      anchorContainer: Color.lerp(anchorContainer, other.anchorContainer, t)!,
      onAnchorContainer:
          Color.lerp(onAnchorContainer, other.onAnchorContainer, t)!,
    );
  }
}

/// `Theme.of(context).extension<AnchorColors>()!` の省略形。
extension AnchorColorsOf on BuildContext {
  AnchorColors get anchorColors => Theme.of(this).extension<AnchorColors>()!;
}

/// アプリのテーマ。
///
/// シード色はアイコンのプレートと同じ淡い水色。M3 が色相を保ったまま
/// 適切なトーンへ割り当てるので、アイコンと画面の色が地続きになる。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light, AnchorColors.light);
  static ThemeData dark() => _build(Brightness.dark, AnchorColors.dark);

  static ThemeData _build(Brightness brightness, AnchorColors anchorColors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AnchorMark.water,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [anchorColors],
      // AppBar は M3 既定の surface に戻す（以前の inversePrimary 塗りは
      // どのロールにも当てはまらない色で、画面全体から浮いていた）。
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      // 数字が横に揺れないよう、時間表示は等幅数字の指定を前提にする。
      // （表示側で FontFeature.tabularFigures を使う）
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}
