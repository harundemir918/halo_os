import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../type.dart';

/// Mono status row: something on the left, connectivity and battery on the
/// right. The caller places it (24 px gutters, 16 px from the top).
class HaloStatusRow extends StatelessWidget {
  const HaloStatusRow({super.key, required this.left, required this.right});

  /// Left text. Use [strong] for a highlighted time (`09:41`).
  final InlineSpan left;
  final String right;

  /// A bone, medium-weight span inside the ash row.
  static TextSpan strong(String text) => TextSpan(
    text: text,
    style: const TextStyle(color: HaloColors.bone, fontWeight: FontWeight.w500),
  );

  @override
  Widget build(BuildContext context) {
    final style = HaloType.status.copyWith(color: HaloColors.ash);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text.rich(left, style: style),
        Text(right, style: style),
      ],
    );
  }
}
