import 'package:flutter/widgets.dart';

/// Notch radius tokens: one big top-left corner, three small.
/// See docs/DESIGN_SYSTEM.md §4. Circles are for apps only.
abstract final class HaloRadii {
  static const BorderRadius notchXS = BorderRadius.only(
    topLeft: Radius.circular(10),
    topRight: Radius.circular(3),
    bottomRight: Radius.circular(3),
    bottomLeft: Radius.circular(3),
  );
  static const BorderRadius notchS = BorderRadius.only(
    topLeft: Radius.circular(12),
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
    bottomLeft: Radius.circular(4),
  );
  static const BorderRadius notchM = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
    bottomLeft: Radius.circular(4),
  );
  static const BorderRadius notchML = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(6),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(6),
  );
  static const BorderRadius notchL = BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(5),
    bottomRight: Radius.circular(5),
    bottomLeft: Radius.circular(5),
  );
  static const BorderRadius notchXL = BorderRadius.only(
    topLeft: Radius.circular(28),
    topRight: Radius.circular(6),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(6),
  );
  static const BorderRadius notchXXL = BorderRadius.only(
    topLeft: Radius.circular(32),
    topRight: Radius.circular(6),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(6),
  );
  static const BorderRadius flat = BorderRadius.all(Radius.circular(5));
  static const BorderRadius knob = BorderRadius.all(Radius.circular(2));
}

/// A [ShapeBorder] for the notch shape, with an optional outline.
class NotchBorder extends RoundedRectangleBorder {
  const NotchBorder({BorderRadius radius = HaloRadii.notchM, super.side})
    : super(borderRadius: radius);
}
