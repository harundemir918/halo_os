import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';

/// 44 × 44 notch with the account initials. Circles are for apps only, so the
/// avatar is a notch, not a circle.
class HaloAvatar extends StatelessWidget {
  const HaloAvatar({
    super.key,
    required this.initials,
    required this.label,
    required this.onPressed,
  });

  final String initials;

  /// Spoken label (`Account: Avery Stone`).
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              color: HaloColors.surface,
              shape: NotchBorder(
                radius: HaloRadii.notchAvatar,
                side: BorderSide(color: HaloColors.line22),
              ),
            ),
            child: Text(
              HaloType.upper(initials),
              style: HaloType.avatar.copyWith(color: HaloColors.bone),
            ),
          ),
        ),
      ),
    );
  }
}
