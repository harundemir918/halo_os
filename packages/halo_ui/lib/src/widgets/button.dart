import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';

enum HaloButtonVariant {
  /// Volt fill, carbon text. The one primary action.
  primary,

  /// Transparent with a `line22` outline, bone text.
  secondary,

  /// Bone fill, carbon text (the inline "Yes").
  bone,
}

enum HaloButtonSize {
  /// 44 high.
  regular,

  /// 32 high, for inline actions.
  small,
}

/// Notch button. See docs/DESIGN_SYSTEM.md §6.
class HaloButton extends StatelessWidget {
  const HaloButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = HaloButtonVariant.primary,
    this.size = HaloButtonSize.regular,
  });

  final String label;
  final VoidCallback? onPressed;
  final HaloButtonVariant variant;
  final HaloButtonSize size;

  @override
  Widget build(BuildContext context) {
    final small = size == HaloButtonSize.small;
    final outlined = variant == HaloButtonVariant.secondary;
    final style = switch ((small, outlined)) {
      (false, false) => HaloType.button,
      (false, true) => HaloType.buttonLight,
      (true, false) => HaloType.buttonSmall,
      (true, true) => HaloType.buttonSmallLight,
    };
    final fill = switch (variant) {
      HaloButtonVariant.primary => HaloColors.volt,
      HaloButtonVariant.secondary => null,
      HaloButtonVariant.bone => HaloColors.bone,
    };
    final textColor = outlined ? HaloColors.bone : HaloColors.carbon;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            height: small ? 32 : 44,
            padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
            decoration: ShapeDecoration(
              color: fill,
              shape: NotchBorder(
                radius: small ? HaloRadii.notchS : HaloRadii.notchM,
                side: outlined
                    ? const BorderSide(color: HaloColors.line22)
                    : BorderSide.none,
              ),
            ),
            // widthFactor keeps the button as wide as its label.
            child: Center(
              widthFactor: 1,
              child: Text(label, style: style.copyWith(color: textColor)),
            ),
          ),
        ),
      ),
    );
  }
}
