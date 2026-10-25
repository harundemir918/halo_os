import 'package:flutter/painting.dart';

/// Halo type tokens. See docs/DESIGN_SYSTEM.md §3.
///
/// Where the design gives a range, the value is the one used most often in
/// `design/source/*.dc.html`; use [TextStyle.copyWith] for the odd screen.
/// Styles carry no color: the caller picks bone, boneDim or ash.
///
/// Bricolage Grotesque is a variable font, so the weight axis is set
/// explicitly. Mono labels are UPPERCASE: use [HaloType.upper] on the string.
abstract final class HaloType {
  static const String voiceFamily = 'Bricolage Grotesque';
  static const String monoFamily = 'DM Mono';
  static const String package = 'halo_ui';

  static TextStyle _voice(
    double size,
    int weight,
    double tracking, {
    double? height,
  }) => TextStyle(
    fontFamily: voiceFamily,
    package: package,
    fontSize: size,
    fontWeight: FontWeight.values[weight ~/ 100 - 1],
    fontVariations: [FontVariation.weight(weight.toDouble())],
    letterSpacing: size * tracking,
    height: height,
  );

  static TextStyle _mono(
    double size,
    int weight,
    double tracking, {
    double? height,
  }) => TextStyle(
    fontFamily: monoFamily,
    package: package,
    fontSize: size,
    fontWeight: FontWeight.values[weight ~/ 100 - 1],
    letterSpacing: size * tracking,
    height: height,
  );

  // Voice: Bricolage Grotesque. Negative tracking.
  static final TextStyle clockHero = _voice(196, 800, -0.05, height: 0.8);
  static final TextStyle display = _voice(92, 800, -0.045, height: 1);
  static final TextStyle screenTitle = _voice(36, 800, -0.04, height: 1);
  static final TextStyle headline = _voice(38, 800, -0.04, height: 1);
  static final TextStyle dialValue = _voice(38, 800, -0.04, height: 1);
  static final TextStyle sectionTitle = _voice(24, 700, -0.03);
  static final TextStyle title = _voice(19, 700, -0.02);
  static final TextStyle body = _voice(16, 500, -0.01, height: 1.3);
  static final TextStyle button = _voice(16, 700, 0);

  // Mono: DM Mono. Positive tracking, UPPERCASE for labels.
  static final TextStyle label = _mono(11, 500, 0.12);
  static final TextStyle labelSmall = _mono(10.5, 400, 0.09);
  static final TextStyle monoValue = _mono(13, 500, 0.06);

  /// Mono labels are uppercase by design.
  static String upper(String s) => s.toUpperCase();
}
