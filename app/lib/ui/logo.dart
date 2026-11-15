/// DuckLearn mark: a white duck's face, winking, with a yellow beak and anime blush, the
/// round head centred on a terracotta tile (no tuft: just the face). Drawn in code so the app, the launcher
/// icons and every size stay identical.
library;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class DuckLogo extends StatelessWidget {
  const DuckLogo({super.key, this.size = 48, this.tile = true});

  final double size;

  /// Rounded terracotta tile (app icon, in-app). When false only the face is drawn,
  /// smaller and on transparent, inside the safe zone of Android's adaptive icons
  /// (the launcher adds the terracotta background and its own mask).
  final bool tile;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _FacePainter(tile: tile)),
  );
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.tile});
  final bool tile;

  static const _white = Color(0xFFFFFFFF);
  static const _edge = Color(0xFFE9DFD2);
  static const _ink = Color(0xFF3F3731);
  static const _beak = Color(0xFFF6C344);
  static const _tongue = Color(0xFFE07A5F);
  static const _blush = Color(0xFFF4A3A8);
  static const _blushLine = Color(0xFFE07A86);

  Paint _fill(Color c) => Paint()
    ..isAntiAlias = true
    ..color = c;

  Paint _line(Color c, double w) => Paint()
    ..isAntiAlias = true
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas
      ..save()
      ..scale(s / 120);
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 120, 120),
          const Radius.circular(28),
        ),
        _fill(Palette.terra),
      );
    } else {
      // adaptive foreground: keep the face inside the launcher's safe zone
      canvas
        ..translate(60, 60)
        ..scale(0.75)
        ..translate(-60, -60);
    }

    // head
    canvas
      ..drawCircle(const Offset(60, 60), 38, _fill(_white))
      ..drawCircle(const Offset(60, 60), 38, _line(_edge, 1.5));

    // anime blush: pink cheeks with three little strokes
    for (final x in const [35.0, 85.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 70), width: 18, height: 11),
        _fill(_blush.withValues(alpha: 0.75)),
      );
      final l = _line(_blushLine, 1.4);
      for (final dx in const [-6.0, -1.5, 3.0]) {
        canvas.drawLine(Offset(x + dx, 73), Offset(x + dx + 3, 67), l);
      }
    }

    // open eye with highlights, and a wink
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(44, 53), width: 11, height: 14),
        _fill(_ink),
      )
      ..drawCircle(const Offset(46, 50), 2.1, _fill(_white))
      ..drawCircle(const Offset(42.6, 56), 0.9, _fill(_white))
      ..drawPath(
        Path()
          ..moveTo(69, 55)
          ..relativeQuadraticBezierTo(7, -9, 14, 0),
        _line(_ink, 3.2),
      );

    // smiling beak with a little tongue
    canvas
      ..drawPath(
        Path()
          ..moveTo(47, 67)
          ..relativeQuadraticBezierTo(13, -9, 26, 0)
          ..relativeQuadraticBezierTo(-13, 13, -26, 0)
          ..close(),
        _fill(_beak),
      )
      ..drawPath(
        Path()
          ..moveTo(53, 70)
          ..relativeQuadraticBezierTo(7, 5, 14, 0)
          ..relativeQuadraticBezierTo(-7, 6, -14, 0)
          ..close(),
        _fill(_tongue),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.tile != tile;
}
