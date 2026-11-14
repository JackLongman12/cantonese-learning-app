/// 小鴨, the DuckLearn duckling. Flat shapes in the app palette, drawn in code so it scales
/// cleanly and needs no image assets. It grows as the learner's reading grows.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

enum DuckMood { happy, cheer, sleepy }

/// Growth follows how many characters the learner can read reliably.
enum DuckStage {
  egg('蛋', 'Egg', 0),
  duckling('小鴨', 'Duckling', 30),
  duck('鴨', 'Duck', 300),
  swan('天鵝', 'Swan', 1500);

  const DuckStage(this.zh, this.en, this.from);
  final String zh;
  final String en;

  /// Characters known well needed to reach this stage.
  final int from;

  static DuckStage forKnown(int known) =>
      values.lastWhere((s) => known >= s.from, orElse: () => egg);

  DuckStage? get next => index + 1 < values.length ? values[index + 1] : null;
}

class DuckMascot extends StatelessWidget {
  const DuckMascot({
    super.key,
    this.size = 96,
    this.mood = DuckMood.happy,
    this.stage = DuckStage.duckling,
  });

  final double size;
  final DuckMood mood;
  final DuckStage stage;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _DuckPainter(mood, stage)),
  );
}

class _DuckPainter extends CustomPainter {
  _DuckPainter(this.mood, this.stage);
  final DuckMood mood;
  final DuckStage stage;

  static const _body = Color(0xFFF2C14E); // warm yolk
  static const _bodyShade = Color(0xFFE0A93A);
  static const _swan = Color(0xFFFBF7EF);
  static const _swanShade = Color(0xFFE4D9C4);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    final p = Paint()..isAntiAlias = true;

    // soft ground shadow
    p.color = Palette.ink.withValues(alpha: 0.08);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.9),
        width: s * 0.62,
        height: s * 0.09,
      ),
      p,
    );

    if (stage == DuckStage.egg) {
      _egg(canvas, s, p);
    } else {
      _bird(canvas, s, p);
    }
    canvas.restore();
  }

  void _egg(Canvas canvas, double s, Paint p) {
    final outline = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.ink;
    // baby duck: shoulders and head rising out of the shell
    p.color = _body;
    final shoulders = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.62),
      width: s * 0.42,
      height: s * 0.3,
    );
    canvas.drawOval(shoulders, p);
    canvas.drawOval(shoulders, outline);
    final headC = Offset(s * 0.5, s * 0.4);
    final headR = s * 0.15;
    canvas.drawCircle(headC, headR, p);
    canvas.drawCircle(headC, headR, outline);
    canvas.drawPath(
      Path()
        ..moveTo(headC.dx - headR * 0.1, headC.dy - headR)
        ..quadraticBezierTo(
          headC.dx - headR * 0.2,
          headC.dy - headR * 1.45,
          headC.dx + headR * 0.25,
          headC.dy - headR * 1.25,
        ),
      outline,
    );
    // little front-facing beak
    p.color = Palette.cinnabar;
    canvas.drawOval(
      Rect.fromCenter(
        center: headC + Offset(0, headR * 0.32),
        width: headR * 0.62,
        height: headR * 0.3,
      ),
      p,
    );
    p.color = Palette.cinnabar.withValues(alpha: 0.28);
    for (final dx in [-0.62, 0.62]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: headC + Offset(headR * dx, headR * 0.3),
          width: headR * 0.38,
          height: headR * 0.22,
        ),
        p,
      );
    }
    _eyes(
      canvas,
      s,
      p,
      left: headC + Offset(-headR * 0.38, -headR * 0.12),
      right: headC + Offset(headR * 0.38, -headR * 0.12),
      r: headR * 0.13,
    );

    // bottom half of the shell, jagged rim, no top
    final rim = <Offset>[
      for (var k = 0; k <= 8; k++)
        Offset(s * (0.22 + 0.07 * k), s * (k.isEven ? 0.6 : 0.53)),
    ];
    final shell = Path()..moveTo(rim.first.dx, rim.first.dy);
    for (final pt in rim.skip(1)) {
      shell.lineTo(pt.dx, pt.dy);
    }
    shell
      ..cubicTo(s * 0.8, s * 0.76, s * 0.68, s * 0.89, s * 0.5, s * 0.89)
      ..cubicTo(
        s * 0.32,
        s * 0.89,
        s * 0.2,
        s * 0.76,
        rim.first.dx,
        rim.first.dy,
      )
      ..close();
    p.color = Palette.paper;
    canvas.drawPath(shell, p);
    canvas.drawPath(shell, outline);
    // a few speckles so it reads as an eggshell
    p.color = Palette.gold.withValues(alpha: 0.5);
    for (final (x, y) in [
      (0.36, 0.72),
      (0.6, 0.78),
      (0.66, 0.67),
      (0.45, 0.82),
    ]) {
      canvas.drawCircle(Offset(s * x, s * y), s * 0.014, p);
    }
  }

  void _bird(Canvas canvas, double s, Paint p) {
    final swan = stage == DuckStage.swan;
    final bodyColor = swan ? _swan : _body;
    final shade = swan ? _swanShade : _bodyShade;
    final outline = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.ink;

    // head: always the short-necked look
    final headC = Offset(s * 0.62, s * 0.36);
    final headR = s * 0.18;
    // body with a perky tail
    final body = Path()
      ..moveTo(s * 0.2, s * 0.62)
      ..quadraticBezierTo(s * 0.16, s * 0.48, s * 0.12, s * 0.42) // tail tip
      ..quadraticBezierTo(s * 0.3, s * 0.5, s * 0.42, s * 0.52)
      ..quadraticBezierTo(s * 0.86, s * 0.48, s * 0.82, s * 0.7)
      ..quadraticBezierTo(s * 0.76, s * 0.88, s * 0.48, s * 0.88)
      ..quadraticBezierTo(s * 0.22, s * 0.86, s * 0.2, s * 0.62)
      ..close();
    p.color = bodyColor;
    canvas.drawPath(body, p);
    canvas.drawPath(body, outline);

    p.color = bodyColor;
    canvas.drawCircle(headC, headR, p);
    canvas.drawCircle(headC, headR, outline);
    if (stage == DuckStage.swan) {
      // small gold crown
      p.color = Palette.gold;
      final top = headC.dy - headR * 0.92;
      canvas.drawPath(
        Path()
          ..moveTo(headC.dx - headR * 0.42, top)
          ..lineTo(headC.dx - headR * 0.42, top - headR * 0.42)
          ..lineTo(headC.dx - headR * 0.21, top - headR * 0.22)
          ..lineTo(headC.dx, top - headR * 0.5)
          ..lineTo(headC.dx + headR * 0.21, top - headR * 0.22)
          ..lineTo(headC.dx + headR * 0.42, top - headR * 0.42)
          ..lineTo(headC.dx + headR * 0.42, top)
          ..close(),
        p,
      );
    } else {
      // tuft
      canvas.drawPath(
        Path()
          ..moveTo(headC.dx - headR * 0.1, headC.dy - headR)
          ..quadraticBezierTo(
            headC.dx - headR * 0.2,
            headC.dy - headR * 1.45,
            headC.dx + headR * 0.25,
            headC.dy - headR * 1.25,
          ),
        outline,
      );
    }
    if (stage == DuckStage.duck) {
      // cinnabar scarf where head meets body, tails flying back
      p.color = Palette.cinnabar;
      final knot = headC + Offset(-headR * 0.05, headR * 0.92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: knot,
            width: headR * 1.5,
            height: headR * 0.34,
          ),
          Radius.circular(headR * 0.17),
        ),
        p,
      );
      canvas.drawPath(
        Path()
          ..moveTo(knot.dx - headR * 0.5, knot.dy)
          ..lineTo(knot.dx - headR * 1.2, knot.dy + headR * 0.25)
          ..lineTo(knot.dx - headR * 1.0, knot.dy + headR * 0.55)
          ..lineTo(knot.dx - headR * 0.35, knot.dy + headR * 0.15)
          ..close(),
        p,
      );
    }

    // wing: folded, or raised in cheer
    final wing = Path();
    if (mood == DuckMood.cheer) {
      wing
        ..moveTo(s * 0.4, s * 0.64)
        ..cubicTo(s * 0.22, s * 0.62, s * 0.14, s * 0.44, s * 0.24, s * 0.34)
        ..cubicTo(s * 0.3, s * 0.46, s * 0.44, s * 0.54, s * 0.54, s * 0.62)
        ..close();
    } else {
      wing
        ..moveTo(s * 0.34, s * 0.64)
        ..quadraticBezierTo(s * 0.46, s * 0.58, s * 0.62, s * 0.66)
        ..quadraticBezierTo(s * 0.5, s * 0.78, s * 0.34, s * 0.64)
        ..close();
    }
    p.color = shade;
    canvas.drawPath(wing, p);
    canvas.drawPath(wing, outline);

    // beak
    final beak = Path()
      ..moveTo(headC.dx + headR * 0.75, headC.dy - headR * 0.05)
      ..quadraticBezierTo(
        headC.dx + headR * 1.55,
        headC.dy + headR * 0.0,
        headC.dx + headR * 1.35,
        headC.dy + headR * 0.3,
      )
      ..quadraticBezierTo(
        headC.dx + headR * 1.0,
        headC.dy + headR * 0.45,
        headC.dx + headR * 0.7,
        headC.dy + headR * 0.3,
      )
      ..close();
    p.color = swan ? Palette.ink : Palette.cinnabar;
    canvas.drawPath(beak, p);

    // blush
    p.color = Palette.cinnabar.withValues(alpha: 0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: headC + Offset(headR * 0.25, headR * 0.45),
        width: headR * 0.5,
        height: headR * 0.28,
      ),
      p,
    );

    _eyes(
      canvas,
      s,
      p,
      left: headC + Offset(-headR * 0.05, -headR * 0.15),
      right: headC + Offset(headR * 0.5, -headR * 0.2),
      r: headR * 0.13,
    );

    // feet
    p.color = swan ? Palette.ink : Palette.cinnabar;
    for (final x in [0.42, 0.58]) {
      canvas.drawPath(
        Path()
          ..moveTo(s * x, s * 0.87)
          ..lineTo(s * (x - 0.05), s * 0.92)
          ..lineTo(s * (x + 0.06), s * 0.92)
          ..close(),
        p,
      );
    }

    if (mood == DuckMood.sleepy) {
      _zzz(canvas, s, headC + Offset(headR * 1.2, -headR * 1.4));
    }
    if (mood == DuckMood.cheer) _sparkles(canvas, s);
  }

  void _eyes(
    Canvas canvas,
    double s,
    Paint p, {
    required Offset left,
    required Offset right,
    required double r,
  }) {
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.8
      ..color = Palette.ink;
    for (final e in [left, right]) {
      switch (mood) {
        case DuckMood.sleepy:
          canvas.drawLine(e - Offset(r, 0), e + Offset(r, 0), stroke);
        case DuckMood.cheer:
          // happy arcs ^ ^
          canvas.drawArc(
            Rect.fromCircle(center: e + Offset(0, r * 0.6), radius: r * 1.1),
            math.pi * 1.1,
            math.pi * 0.8,
            false,
            stroke,
          );
        case DuckMood.happy:
          p.color = Palette.ink;
          canvas.drawCircle(e, r, p);
          p.color = Colors.white;
          canvas.drawCircle(e + Offset(-r * 0.3, -r * 0.35), r * 0.35, p);
      }
    }
  }

  void _zzz(Canvas canvas, double s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'z z',
        style: TextStyle(
          fontFamily: brushFont,
          fontSize: s * 0.12,
          color: Palette.inkSoft,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _sparkles(Canvas canvas, double s) {
    final p = Paint()
      ..isAntiAlias = true
      ..color = Palette.gold;
    for (final (x, y, r) in [
      (0.86, 0.18, 0.035),
      (0.12, 0.2, 0.028),
      (0.9, 0.4, 0.022),
    ]) {
      final c = Offset(s * x, s * y);
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final rr = i.isEven ? s * r : s * r * 0.35;
        final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), p);
    }
  }

  @override
  bool shouldRepaint(_DuckPainter old) =>
      old.mood != mood || old.stage != stage;
}
