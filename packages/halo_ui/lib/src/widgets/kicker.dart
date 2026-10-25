import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../type.dart';

/// Section kicker: an 8 × 8 square followed by an uppercase mono label.
/// Volt by default (`NOW`). Pass [color] and `square: false` for the plain
/// ash list label (`TODAY`).
class HaloKicker extends StatelessWidget {
  const HaloKicker(
    this.label, {
    super.key,
    this.color = HaloColors.volt,
    this.square = true,
  });

  final String label;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (square) ...[
          SizedBox(width: 8, height: 8, child: ColoredBox(color: color)),
          const SizedBox(width: 8),
        ],
        Text(
          HaloType.upper(label),
          style: HaloType.kicker.copyWith(color: color),
        ),
      ],
    );
  }
}
