/// The little characters: a chick with moods, the mama duck and her ducklings, egg step
/// markers. Small, quiet, never in the way: they decorate, they never start anything.
/// Anything that moves faces the way it is going.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Ambient motion (walking, swaying). Off under `flutter test` so pumpAndSettle settles,
/// and off when the system asks for reduced motion.
bool ambientMotion = !Platform.environment.containsKey('FLUTTER_TEST');

enum ChickMood { innocent, happy, proud, confused, curious, sleepy }

class _Ink {
  _Ink(this.dark);
  final bool dark;
  Color get yolk => dark ? const Color(0xFFD9B56C) : Palette.yolk;
  Color get yolkDeep => dark ? const Color(0xFFC49B4D) : Palette.yolkDeep;
  Color get blush =>
      (dark ? const Color(0xFFD98D73) : Palette.blush).withValues(alpha: 0.75);
  Color get beak => dark ? Palette.terraLight : Palette.terra;
  Color get eye => Palette.bark;
  Color get soft => dark ? Palette.paperTextSoft : Palette.barkSoft;
  Color get mama => dark ? const Color(0xFFE7DDCF) : Palette.mama;
  Color get shell => dark ? const Color(0xFF4A423B) : Palette.shell;
}

Paint _fill(Color c) => Paint()..color = c;
Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _oval(Canvas c, double cx, double cy, double rx, double ry, Paint p) =>
    c.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      p,
    );

/// A small arc like "‿" or "⁀" from (x, y), [w] wide, bulging by [h] (negative = up).
void _arc(Canvas c, double x, double y, double w, double h, Paint p) =>
    c.drawPath(
      Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + w / 2, y + h, x + w, y),
      p,
    );

void _star(Canvas c, double x, double y, double s, Paint p) {
  const pts = [
    [0.0, -5.0],
    [1.5, -1.8],
    [5.0, -1.3],
    [2.5, 1.1],
    [3.1, 4.6],
    [0.0, 2.9],
    [-3.1, 4.6],
    [-2.5, 1.1],
    [-5.0, -1.3],
    [-1.5, -1.8],
  ];
  final path = Path()..moveTo(x + pts[0][0] * s, y + pts[0][1] * s);
  for (final q in pts.skip(1)) {
    path.lineTo(x + q[0] * s, y + q[1] * s);
  }
  c.drawPath(path..close(), p);
}

void _text(Canvas c, String s, double x, double y, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: 'NotoSansHK',
        fontSize: size,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(x, y - tp.height));
}

/// The chick, drawn in an 80 x 70 box centred on its body.
class _ChickPainter extends CustomPainter {
  _ChickPainter(this.mood, this.ink);
  final ChickMood mood;
  final _Ink ink;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 80;
    canvas
      ..save()
      ..scale(k)
      ..translate(40, 34);
    final tilt = switch (mood) {
      ChickMood.confused => -10.0,
      ChickMood.curious => 8.0,
      _ => 0.0,
    };
    canvas
      ..save()
      ..rotate(tilt * math.pi / 180);
    _body(canvas);
    _face(canvas);
    canvas.restore();
    // what floats around it does not tilt
    switch (mood) {
      case ChickMood.proud:
        final p = _fill(ink.yolkDeep);
        _star(canvas, -22, -18, 1, p);
        _star(canvas, 21, -22, 1.2, p);
        _star(canvas, -27, 6, 0.8, p);
        _star(canvas, 26, 4, 0.75, p);
        _star(canvas, 0, -29, 0.7, p);
      case ChickMood.confused:
        _text(canvas, '?', 13, -9, 11, ink.soft);
      case ChickMood.curious:
        final p = _stroke(ink.soft, 1);
        canvas
          ..drawLine(const Offset(15, -14), const Offset(17, -17), p)
          ..drawLine(const Offset(18, -10), const Offset(21, -11), p)
          ..drawLine(const Offset(19, -6), const Offset(22, -5), p);
      case ChickMood.sleepy:
        _text(canvas, 'z', 12, -10, 8, ink.soft);
        _text(canvas, 'z', 16, -16, 10, ink.soft);
      default:
    }
    canvas.restore();
  }

  void _body(Canvas c) {
    _oval(c, 0, 9, 12, 10, _fill(ink.yolk));
    c.drawPath(
      Path()
        ..moveTo(9, 7)
        ..relativeQuadraticBezierTo(4, 1, 3, 5)
        ..relativeQuadraticBezierTo(-3, 0, -4, -3)
        ..close(),
      _fill(ink.yolkDeep),
    );
    c.drawCircle(const Offset(0, -4), 10, _fill(ink.yolk));
    c.drawPath(
      Path()
        ..moveTo(-1.5, -14)
        ..relativeQuadraticBezierTo(1.5, -4, 3, 0)
        ..relativeQuadraticBezierTo(1, -3, 3, -1),
      _stroke(ink.yolkDeep, 1.3),
    );
    _oval(c, -5, -1.6, 1.8, 1.1, _fill(ink.blush));
    _oval(c, 5, -1.6, 1.8, 1.1, _fill(ink.blush));
    final feet = _stroke(ink.beak, 1.6);
    c
      ..drawLine(const Offset(-4, 18.5), const Offset(-4, 21.5), feet)
      ..drawLine(const Offset(4, 18.5), const Offset(4, 21.5), feet);
  }

  void _beak(Canvas c, {double open = 2.4}) => c.drawPath(
    Path()
      ..moveTo(-2, -3.5)
      ..relativeQuadraticBezierTo(2, open, 4, 0)
      ..close(),
    _fill(ink.beak),
  );

  void _face(Canvas c) {
    final eye = _fill(ink.eye);
    final white = _fill(Colors.white);
    final line = _stroke(ink.eye, 1.1);
    switch (mood) {
      case ChickMood.innocent:
        c
          ..drawCircle(const Offset(-3.6, -5.5), 2, eye)
          ..drawCircle(const Offset(3.6, -5.5), 2, eye)
          ..drawCircle(const Offset(-3, -6.2), 0.7, white)
          ..drawCircle(const Offset(4.2, -6.2), 0.7, white);
        _beak(c);
      case ChickMood.happy:
        _arc(c, -5, -5, 2.8, -3.6, line);
        _arc(c, 2.2, -5, 2.8, -3.6, line);
        c.drawPath(
          Path()
            ..moveTo(-2, -3)
            ..relativeQuadraticBezierTo(2, 3.4, 4, 0)
            ..close(),
          _fill(ink.beak),
        );
      case ChickMood.proud:
        final l = _stroke(ink.eye, 1.2);
        c
          ..drawLine(const Offset(-5, -5.5), const Offset(-2.2, -5.5), l)
          ..drawLine(const Offset(2.2, -5.5), const Offset(5, -5.5), l);
        _beak(c);
      case ChickMood.confused:
        c
          ..drawCircle(const Offset(-3.6, -5.5), 2, eye)
          ..drawCircle(const Offset(3.5, -5.4), 2, _stroke(ink.eye, 1));
        c.drawPath(
          Path()
            ..moveTo(-1.8, -2)
            ..relativeQuadraticBezierTo(1, -0.8, 2, 0)
            ..relativeQuadraticBezierTo(1, 0.8, 2, 0),
          _stroke(ink.beak, 1.4),
        );
      case ChickMood.curious:
        c
          ..drawCircle(const Offset(-3.6, -5.5), 2.4, eye)
          ..drawCircle(const Offset(3.6, -5.5), 2.4, eye)
          ..drawCircle(const Offset(-2.9, -6.3), 0.8, white)
          ..drawCircle(const Offset(4.3, -6.3), 0.8, white);
        _oval(c, 0, -1.8, 1.6, 1.3, _fill(ink.beak));
      case ChickMood.sleepy:
        _arc(c, -5, -5.5, 2.8, 2.8, line);
        _arc(c, 2.2, -5.5, 2.8, 2.8, line);
        _beak(c);
    }
  }

  @override
  bool shouldRepaint(_ChickPainter old) =>
      old.mood != mood || old.ink.dark != ink.dark;
}

/// The chick in a mood. [size] is its width; height is 7/8 of it.
class Chick extends StatefulWidget {
  const Chick({
    super.key,
    required this.mood,
    this.size = 80,
    this.sway = false,
  });
  final ChickMood mood;
  final double size;

  /// Rocks gently from side to side (resting on Home).
  final bool sway;

  @override
  State<Chick> createState() => _ChickState();
}

class _ChickState extends State<Chick> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final move =
        widget.sway &&
        ambientMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (move && !_c.isAnimating) _c.repeat(reverse: true);
    if (!move) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = _Ink(Theme.of(context).brightness == Brightness.dark);
    final paint = CustomPaint(
      size: Size(widget.size, widget.size * 7 / 8),
      painter: _ChickPainter(widget.mood, ink),
    );
    return Semantics(
      label: 'Chick, ${widget.mood.name}',
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.rotate(
          angle: (_c.value - 0.5) * 4 * math.pi / 180,
          alignment: const Alignment(0, 0.8),
          child: child,
        ),
        child: paint,
      ),
    );
  }
}

/// A duckling (faces left by default), 28 x 22 units.
class _DucklingPainter extends CustomPainter {
  _DucklingPainter(this.ink, {this.facingRight = false});
  final _Ink ink;
  final bool facingRight;

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / 28;
    c
      ..save()
      ..scale(k)
      ..translate(14, 9);
    if (facingRight) c.scale(-1, 1);
    _oval(c, 2, 6, 9, 6.5, _fill(ink.yolk));
    c.drawPath(
      Path()
        ..moveTo(9, 3)
        ..relativeQuadraticBezierTo(4, -2, 3, 3)
        ..close(),
      _fill(ink.yolk),
    );
    c.drawCircle(const Offset(-4, -2), 6, _fill(ink.yolk));
    _arc(c, -6.3, -3.4, 2, -2.6, _stroke(ink.eye, 0.9));
    _oval(c, -5.5, 0.4, 1.3, 0.8, _fill(ink.blush));
    c.drawPath(
      Path()
        ..moveTo(-10, -1.4)
        ..relativeQuadraticBezierTo(-3.5, 0.6, -3.5, 1.8)
        ..relativeQuadraticBezierTo(2, 1.2, 3.8, 0.2)
        ..close(),
      _fill(ink.beak),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_DucklingPainter old) =>
      old.facingRight != facingRight || old.ink.dark != ink.dark;
}

/// The mama duck (faces left by default), 44 x 34 units.
class _MamaPainter extends CustomPainter {
  _MamaPainter(this.ink);
  final _Ink ink;

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / 44;
    c
      ..save()
      ..scale(k)
      ..translate(22, 14);
    final body = _fill(ink.mama);
    final edge = _stroke(ink.soft, 0.6);
    _oval(c, 3, 9, 14, 9, body);
    _oval(c, 3, 9, 14, 9, edge);
    final tail = Path()
      ..moveTo(15, 5)
      ..relativeQuadraticBezierTo(6, -3, 4, 4)
      ..close();
    c
      ..drawPath(tail, body)
      ..drawPath(tail, edge);
    _arc(c, 0, 8, 11, 5, edge);
    c
      ..drawCircle(const Offset(-7, -4), 7.5, body)
      ..drawCircle(const Offset(-7, -4), 7.5, edge);
    _arc(c, -9.8, -5.6, 2.6, -3.2, _stroke(ink.eye, 1));
    _oval(c, -8.7, -1.2, 1.6, 1, _fill(ink.blush));
    c.drawPath(
      Path()
        ..moveTo(-14, -3.5)
        ..relativeQuadraticBezierTo(-5, 0.8, -5, 2.4)
        ..relativeQuadraticBezierTo(3, 1.5, 5.4, 0.2)
        ..close(),
      _fill(ink.beak),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_MamaPainter old) => old.ink.dark != ink.dark;
}

/// A duckling on its own (the progress bar's rider). It faces right: progress goes right.
class Duckling extends StatelessWidget {
  const Duckling({super.key, this.size = 24, this.facingRight = true});
  final double size;
  final bool facingRight;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 22 / 28),
    painter: _DucklingPainter(
      _Ink(Theme.of(context).brightness == Brightness.dark),
      facingRight: facingRight,
    ),
  );
}

/// A progress bar with a duckling riding its leading edge.
class DuckProgress extends StatelessWidget {
  const DuckProgress({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              left: (box.maxWidth * v - 16).clamp(-4.0, box.maxWidth - 20),
              top: -1,
              child: const Duckling(size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// An egg-shaped step marker: the current step is filled, a finished one is ticked.
class EggMarker extends StatelessWidget {
  const EggMarker({
    super.key,
    required this.number,
    this.current = false,
    this.done = false,
  });
  final int number;
  final bool current;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = _Ink(Theme.of(context).brightness == Brightness.dark);
    return SizedBox(
      width: 18,
      height: 22,
      child: CustomPaint(
        painter: _EggPainter(
          fill: current ? scheme.primary : ink.shell,
          edge: current ? null : scheme.onSurfaceVariant,
          tick: done ? scheme.onPrimaryContainer : null,
        ),
        child: done
            ? null
            : Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: current
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _EggPainter extends CustomPainter {
  _EggPainter({required this.fill, this.edge, this.tick});
  final Color fill;
  final Color? edge;
  final Color? tick;

  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(1, 1, s.width - 2, s.height - 2);
    c.drawOval(r, _fill(fill));
    if (edge != null) c.drawOval(r, _stroke(edge!, 0.7));
    if (tick != null) {
      c.drawPath(
        Path()
          ..moveTo(s.width * 0.3, s.height * 0.56)
          ..lineTo(s.width * 0.45, s.height * 0.68)
          ..lineTo(s.width * 0.72, s.height * 0.42),
        _stroke(tick!, 1.6),
      );
    }
  }

  @override
  bool shouldRepaint(_EggPainter old) =>
      old.fill != fill || old.edge != edge || old.tick != tick;
}

/// Mama duck and her ducklings waddling along a lane (the top of the Start button).
/// They turn to face the way they walk. Tap them and they hop. Purely decoration.
class DuckFamily extends StatefulWidget {
  const DuckFamily({super.key, this.ducklings = 1, this.onTap});
  final int ducklings;
  final VoidCallback? onTap;

  @override
  State<DuckFamily> createState() => _DuckFamilyState();
}

class _DuckFamilyState extends State<DuckFamily>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _t = 0; // seconds
  double? _x;
  double _dir = -1;
  double _max = 0;
  double? _hopAt;

  static const _speed = 14.0; // px a second: an unhurried waddle
  static const _mamaW = 40.0, _babyW = 25.0, _gap = 3.0;

  double get _familyW =>
      _mamaW + widget.ducklings.clamp(0, 6) * (_babyW + _gap);

  bool get _moving => ambientMotion && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_moving && !_ticker.isActive) _ticker.start();
    if (!_moving && _ticker.isActive) _ticker.stop();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.5) return;
    setState(() {
      _t += dt;
      final x = (_x ?? _max * 0.7) + _dir * _speed * dt;
      if (x <= 0) {
        _x = 0;
        _dir = 1;
      } else if (x >= _max) {
        _x = _max;
        _dir = -1;
      } else {
        _x = x;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _bob(int i) =>
      _moving ? math.sin(_t * 2 * math.pi / 1.1 + i * 0.6) : 0;

  double get _hop {
    final at = _hopAt;
    if (at == null) return 0;
    final p = (_t - at) / 0.45;
    if (p >= 1 || p < 0) return 0;
    return -9 * math.sin(math.pi * p);
  }

  @override
  Widget build(BuildContext context) {
    final ink = _Ink(Theme.of(context).brightness == Brightness.dark);
    final right = _dir > 0;
    return LayoutBuilder(
      builder: (context, box) {
        _max = math.max(0, box.maxWidth - _familyW);
        final x = (_x ?? _max * 0.7).clamp(0.0, _max);
        // facing left, mama leads on the left; facing right, the row is mirrored
        final ducks = <Widget>[
          _duck(0, _mamaW, 34 / 44, _MamaPainter(ink)),
          for (var i = 1; i <= widget.ducklings.clamp(0, 6); i++)
            _duck(i, _babyW, 22 / 28, _DucklingPainter(ink)),
        ];
        return SizedBox(
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: x,
                bottom: -3,
                child: GestureDetector(
                  key: const ValueKey('duck-family'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _hopAt = _t);
                    if (!_moving) setState(() {});
                    widget.onTap?.call();
                  },
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(right ? -1 : 1, 1, 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: _gap,
                      children: ducks,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _duck(int i, double w, double aspect, CustomPainter p) =>
      Transform.translate(
        offset: Offset(0, _hop - 1.5 * (_bob(i) + 1) / 2),
        child: Transform.rotate(
          angle: _bob(i) * 3 * math.pi / 180,
          alignment: Alignment.bottomCenter,
          child: CustomPaint(size: Size(w, w * aspect), painter: p),
        ),
      );
}
