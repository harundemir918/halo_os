import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../type.dart';

/// One-line notification preview (Lock). A Flare dot means unread, a hollow
/// ash ring means read.
class HaloNotificationPreview extends StatelessWidget {
  const HaloNotificationPreview({
    super.key,
    required this.sender,
    required this.body,
    required this.age,
    required this.unread,
  });

  final String sender;
  final String body;

  /// Mono age (`2M`, `1H`).
  final String age;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${unread ? 'Unread. ' : ''}$sender: $body, $age ago',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: HaloColors.line10)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                _Dot(unread: unread),
                const SizedBox(width: 12),
                Text(
                  HaloType.upper(sender),
                  style: HaloType.status.copyWith(color: HaloColors.bone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HaloType.preview.copyWith(color: HaloColors.boneDim),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  HaloType.upper(age),
                  style: HaloType.status.copyWith(
                    letterSpacing: 0,
                    color: HaloColors.ash,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unread ? HaloColors.flare : null,
        border: unread ? null : Border.all(color: HaloColors.ash, width: 1.5),
      ),
    );
  }
}
