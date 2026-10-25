import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';

/// Volt time tile next to a `surface` card with a mono kicker and a title.
/// 68 high. See docs/DESIGN_SYSTEM.md §6.
class HaloEventCard extends StatelessWidget {
  const HaloEventCard({
    super.key,
    required this.time,
    required this.kicker,
    required this.title,
  });

  /// Mono time in the tile (`10:00`).
  final String time;

  /// Mono kicker (`NEXT · IN 19 MIN`).
  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$kicker. $title at $time',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              Container(
                width: 68,
                alignment: Alignment.center,
                decoration: const ShapeDecoration(
                  color: HaloColors.volt,
                  shape: NotchBorder(radius: HaloRadii.notchXL),
                ),
                child: Text(
                  time,
                  style: HaloType.tileTime.copyWith(color: HaloColors.carbon),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: const ShapeDecoration(
                    color: HaloColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: HaloRadii.flat,
                      side: BorderSide(color: HaloColors.line08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        HaloType.upper(kicker),
                        style: HaloType.status.copyWith(color: HaloColors.ash),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HaloType.cardTitle.copyWith(
                          color: HaloColors.bone,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
