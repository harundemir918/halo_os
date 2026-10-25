import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';
import 'button.dart';

/// Inline action card: Flare dot, mono sender and age, a question and two
/// small buttons. 92 high. Never stacked or grouped (docs/DESIGN_SYSTEM.md §1).
class HaloActionCard extends StatelessWidget {
  const HaloActionCard({
    super.key,
    required this.sender,
    required this.age,
    required this.message,
    required this.onYes,
    required this.onLater,
    this.yesLabel = 'Yes',
    this.laterLabel = 'Later',
  });

  final String sender;
  final String age;
  final String message;
  final VoidCallback? onYes;
  final VoidCallback? onLater;
  final String yesLabel;
  final String laterLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const ShapeDecoration(
        color: HaloColors.surface,
        shape: NotchBorder(
          radius: HaloRadii.notchXL,
          side: BorderSide(color: HaloColors.line08),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: HaloColors.flare,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                HaloType.upper('$sender · $age'),
                style: HaloType.status.copyWith(color: HaloColors.ash),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HaloType.itemTitle.copyWith(color: HaloColors.bone),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HaloButton(
                    label: yesLabel,
                    variant: HaloButtonVariant.bone,
                    size: HaloButtonSize.small,
                    onPressed: onYes,
                  ),
                  const SizedBox(width: 6),
                  HaloButton(
                    label: laterLabel,
                    variant: HaloButtonVariant.secondary,
                    size: HaloButtonSize.small,
                    onPressed: onLater,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
