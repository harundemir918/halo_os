import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';
import 'switch.dart';

/// `surface` row with a name, a mono sub-label and a [HaloSwitch].
/// When on, a 3 px Volt bar runs down the left edge. The whole row toggles.
class HaloToggleRow extends StatelessWidget {
  const HaloToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title, $subtitle',
      toggled: value,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: SizedBox(
            height: 52,
            child: DecoratedBox(
              decoration: const ShapeDecoration(
                color: HaloColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: HaloRadii.flat,
                  side: BorderSide(color: HaloColors.line08),
                ),
              ),
              child: ClipRRect(
                borderRadius: HaloRadii.flat,
                child: Stack(
                  children: [
                    if (value)
                      const Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 3,
                        child: ColoredBox(color: HaloColors.volt),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 5, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: HaloType.rowTitle.copyWith(
                                    color: value
                                        ? HaloColors.bone
                                        : HaloColors.boneDim,
                                  ),
                                ),
                                Text(
                                  HaloType.upper(subtitle),
                                  style: HaloType.caption.copyWith(
                                    color: HaloColors.ash,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IgnorePointer(
                            child: HaloSwitch(
                              value: value,
                              onChanged: onChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
