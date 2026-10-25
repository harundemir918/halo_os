import 'package:flutter/widgets.dart';

import '../colors.dart';

/// Outline icons on a 24 × 24 grid, 1.8 px stroke, round caps and joins.
/// Paths are from design/source. More arrive with the screens that need them.
enum HaloIcons { flashlight, camera }

class HaloIcon extends StatelessWidget {
  const HaloIcon(
    this.icon, {
    super.key,
    this.size = 22,
    this.color = HaloColors.bone,
  });

  final HaloIcons icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(icon, color),
    ),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final HaloIcons icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in _paths(icon)) {
      canvas.drawPath(path, paint);
    }
  }

  static List<Path> _paths(HaloIcons icon) => switch (icon) {
    // M8 3h8l-1 5H9z  M9 8l-1 4v9h8v-9l-1-4
    HaloIcons.flashlight => [
      Path()
        ..moveTo(8, 3)
        ..lineTo(16, 3)
        ..lineTo(15, 8)
        ..lineTo(9, 8)
        ..close(),
      Path()
        ..moveTo(9, 8)
        ..lineTo(8, 12)
        ..lineTo(8, 21)
        ..lineTo(16, 21)
        ..lineTo(16, 12)
        ..lineTo(15, 8),
    ],
    // M4 8h3l2-3h6l2 3h3v11H4z  circle (12,13) r3.5
    HaloIcons.camera => [
      Path()
        ..moveTo(4, 8)
        ..lineTo(7, 8)
        ..lineTo(9, 5)
        ..lineTo(15, 5)
        ..lineTo(17, 8)
        ..lineTo(20, 8)
        ..lineTo(20, 19)
        ..lineTo(4, 19)
        ..close(),
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 3.5)),
    ],
  };

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
