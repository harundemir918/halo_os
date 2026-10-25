import 'package:flutter/widgets.dart';

import '../colors.dart';
import '../notch_border.dart';
import '../type.dart';

/// One option of a [HaloSegmented].
class HaloSegment<T> {
  const HaloSegment(this.value, this.label);

  final T value;
  final String label;
}

/// Equal-width options, 40 high. The selected one is Volt with the notch.
class HaloSegmented<T> extends StatelessWidget {
  const HaloSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<HaloSegment<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _option(options[i])),
        ],
      ],
    );
  }

  Widget _option(HaloSegment<T> o) {
    final selected = o.value == value;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onChanged != null,
      label: o.label,
      onTap: onChanged == null ? null : () => onChanged!(o.value),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(o.value),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: selected ? HaloColors.volt : null,
              shape: NotchBorder(
                radius: selected ? HaloRadii.notchSM : HaloRadii.flatS,
                side: selected
                    ? BorderSide.none
                    : const BorderSide(color: HaloColors.line22),
              ),
            ),
            child: Text(
              HaloType.upper(o.label),
              style: (selected ? HaloType.segmentSelected : HaloType.segment)
                  .copyWith(
                    color: selected ? HaloColors.carbon : HaloColors.bone,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
