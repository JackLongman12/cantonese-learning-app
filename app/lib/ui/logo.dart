/// DuckLearn mark: the duckling's face fills the whole tile, as an app icon should.
/// Drawn in code so the app, the icons and every size stay identical.
library;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class DuckLogo extends StatelessWidget {
  const DuckLogo({super.key, this.size = 48, this.tile = true});

  final double size;

  /// Rounded-square tile (app icon, header). When false the face is drawn full-bleed
  /// with square edges, for platforms that apply their own mask (Android adaptive).
  final bool tile;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _FacePainter(rounded: tile)),
  );
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.rounded});
  final bool rounded;

  static const _yolkTop = Color(0xFFFFD866);
  static const _yolkBottom = Color(0xFFF2B630);
  static const _beak = Color(0xFFF07F22);
  static const _beakDark = Color(0xFFD7621A);
  static const _blush = Color(0xFFF2836B);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset o(double x, double y) => Offset(s * x, s * y);
    final p = Paint()..isAntiAlias = true;
    final full = Offset.zero & Size.square(s);
    final clip = RRect.fromRectAndRadius(
      full,
      Radius.circular(rounded ? s * 0.23 : 0),
    );

    canvas.save();
    canvas.clipRRect(clip);

    // the head is the whole tile
    p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_yolkTop, _yolkBottom],
    ).createShader(full);
    canvas.drawRect(full, p);
    p.shader = null;

    // tuft: a cinnabar curl at the crown, the one oriental accent
    final tuft = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.06
      ..color = Palette.cinnabar;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.5, s * 0.17)
        ..cubicTo(s * 0.47, s * 0.06, s * 0.6, s * 0.03, s * 0.62, s * 0.11),
      tuft,
    );

    // eyes: big, glossy, slightly looking up
    for (final x in [0.33, 0.67]) {
      final c = o(x, 0.42);
      p.color = Colors.white;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: s * 0.25, height: s * 0.28),
        p,
      );
      p.color = Palette.ink;
      final pupil = c + Offset(s * (x < 0.5 ? 0.025 : -0.025), -s * 0.005);
      canvas.drawOval(
        Rect.fromCenter(center: pupil, width: s * 0.15, height: s * 0.17),
        p,
      );
      p.color = Colors.white;
      canvas.drawCircle(pupil + Offset(-s * 0.03, -s * 0.04), s * 0.033, p);
      canvas.drawCircle(pupil + Offset(s * 0.03, s * 0.035), s * 0.013, p);
    }

    // brows: little brush strokes
    final brow = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.03
      ..color = Palette.ink;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.23, s * 0.25)
        ..quadraticBezierTo(s * 0.32, s * 0.2, s * 0.41, s * 0.24),
      brow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.59, s * 0.24)
        ..quadraticBezierTo(s * 0.68, s * 0.2, s * 0.77, s * 0.25),
      brow,
    );

    // blush
    p.color = _blush.withValues(alpha: 0.6);
    for (final x in [0.17, 0.83]) {
      canvas.drawOval(
        Rect.fromCenter(center: o(x, 0.62), width: s * 0.15, height: s * 0.08),
        p,
      );
    }

    // bill: wide and smiling
    final upper = Path()
      ..moveTo(s * 0.3, s * 0.63)
      ..quadraticBezierTo(s * 0.5, s * 0.55, s * 0.7, s * 0.63)
      ..quadraticBezierTo(s * 0.74, s * 0.7, s * 0.66, s * 0.72)
      ..quadraticBezierTo(s * 0.5, s * 0.75, s * 0.34, s * 0.72)
      ..quadraticBezierTo(s * 0.26, s * 0.7, s * 0.3, s * 0.63)
      ..close();
    final lower = Path()
      ..moveTo(s * 0.36, s * 0.72)
      ..quadraticBezierTo(s * 0.5, s * 0.86, s * 0.64, s * 0.72)
      ..close();
    p.color = _beakDark;
    canvas.drawPath(lower, p);
    p.color = _beak;
    canvas.drawPath(upper, p);
    // nostrils
    p.color = _beakDark;
    for (final x in [0.45, 0.55]) {
      canvas.drawOval(
        Rect.fromCenter(center: o(x, 0.63), width: s * 0.03, height: s * 0.018),
        p,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.rounded != rounded;
}
