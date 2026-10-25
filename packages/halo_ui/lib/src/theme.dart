import 'package:flutter/material.dart';

import 'colors.dart';
import 'type.dart';

/// Tokens Material doesn't model, reachable through `HaloTokens.of(context)`.
@immutable
class HaloTokens extends ThemeExtension<HaloTokens> {
  const HaloTokens({
    this.boneDim = HaloColors.boneDim,
    this.ash = HaloColors.ash,
    this.flare = HaloColors.flare,
    this.voltLine = HaloColors.voltLine,
    this.hairline = HaloColors.line10,
    this.outline = HaloColors.line22,
  });

  final Color boneDim;
  final Color ash;
  final Color flare;
  final Color voltLine;

  /// Row dividers and tracks.
  final Color hairline;

  /// Secondary button and inactive switch borders.
  final Color outline;

  static HaloTokens of(BuildContext context) =>
      Theme.of(context).extension<HaloTokens>() ?? const HaloTokens();

  @override
  HaloTokens copyWith({
    Color? boneDim,
    Color? ash,
    Color? flare,
    Color? voltLine,
    Color? hairline,
    Color? outline,
  }) => HaloTokens(
    boneDim: boneDim ?? this.boneDim,
    ash: ash ?? this.ash,
    flare: flare ?? this.flare,
    voltLine: voltLine ?? this.voltLine,
    hairline: hairline ?? this.hairline,
    outline: outline ?? this.outline,
  );

  @override
  HaloTokens lerp(HaloTokens? other, double t) {
    if (other == null) return this;
    return HaloTokens(
      boneDim: Color.lerp(boneDim, other.boneDim, t)!,
      ash: Color.lerp(ash, other.ash, t)!,
      flare: Color.lerp(flare, other.flare, t)!,
      voltLine: Color.lerp(voltLine, other.voltLine, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
    );
  }
}

/// Halo theme. Only the dark appearance is designed (see D-013).
abstract final class HaloTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: HaloColors.volt,
      onPrimary: HaloColors.carbon,
      secondary: HaloColors.volt,
      onSecondary: HaloColors.carbon,
      surface: HaloColors.surface,
      onSurface: HaloColors.bone,
      error: HaloColors.flare,
      onError: HaloColors.carbon,
    );
    final text = TextTheme(
      displayLarge: HaloType.display,
      headlineLarge: HaloType.screenTitle,
      headlineMedium: HaloType.headline,
      titleLarge: HaloType.sectionTitle,
      titleMedium: HaloType.title,
      bodyLarge: HaloType.body,
      bodyMedium: HaloType.body,
      labelLarge: HaloType.button,
      labelMedium: HaloType.label,
      labelSmall: HaloType.labelSmall,
    ).apply(bodyColor: HaloColors.bone, displayColor: HaloColors.bone);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: HaloColors.carbon,
      canvasColor: HaloColors.carbon,
      textTheme: text,
      // Solid surfaces only: no ripples, no tints.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: HaloColors.line10,
      extensions: const [HaloTokens()],
    );
  }
}
