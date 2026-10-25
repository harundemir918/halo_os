import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../type.dart';

/// A numbered section of the System list: `01  Connections  HOME-5G`.
/// The open one is marked by a Volt number, a Volt status and a Volt hairline,
/// and shows [child] inline. It is an accordion, not a page push.
class HaloAccordionRow extends StatelessWidget {
  const HaloAccordionRow({
    super.key,
    required this.number,
    required this.title,
    required this.status,
    required this.open,
    required this.onTap,
    this.child,
    this.last = false,
  });

  /// `01`, `02`, ...
  final String number;
  final String title;

  /// Mono status on the right. The open row shows `OPEN`.
  final String status;
  final bool open;
  final VoidCallback? onTap;

  /// Controls shown while open, indented under the title.
  final Widget? child;

  /// Draws the closing hairline under the last row.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final accent = open ? HaloColors.volt : HaloColors.ash;
    return Semantics(
      container: true,
      button: true,
      expanded: open,
      label: '$title, $status',
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: open ? HaloColors.volt : HaloColors.line10),
            bottom: last
                ? const BorderSide(color: HaloColors.line10)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 16, bottom: open ? 20 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          number,
                          style: HaloType.timeLabel.copyWith(color: accent),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: HaloType.sectionTitle.copyWith(
                            color: HaloColors.bone,
                          ),
                        ),
                      ),
                      Text(
                        HaloType.upper(open ? 'Open' : status),
                        style: HaloType.accordionStatus.copyWith(color: accent),
                      ),
                    ],
                  ),
                ),
              ),
              if (open && child != null)
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 16),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
