import 'package:flutter/material.dart';

/// App-owned, non-executable illustration designs. Catalogs supply labels/colors,
/// never arbitrary image URLs, user files, HTML or drawing instructions.
class TrainerAvatar extends StatelessWidget {
  const TrainerAvatar({super.key, required this.definition, this.size = 104});
  final Map<String, dynamic>? definition;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: definition?['label'] as String? ?? 'Avatar unavailable',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AvatarPainter(definition)),
    ),
  );
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.definition);
  final Map<String, dynamic>? definition;
  Color color(String key, Color fallback) {
    final value = definition?[key];
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return fallback;
    }
    return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final accent = color('accent', const Color(0xff8c9a91));
    final ink = const Color(0xff253c36), cream = const Color(0xfffff3d6);
    final brush = Paint();
    void oval(double x, double y, double w, double h, Color c) {
      canvas.drawOval(Rect.fromLTWH(x, y, w, h), brush..color = c);
    }

    void round(double x, double y, double w, double h, double r, Color c) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        brush..color = c,
      );
    }

    void triangle(Offset a, Offset b, Offset c, Color fill) {
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        brush..color = fill,
      );
    }

    void eyes() {
      oval(34, 46, 6, 8, ink);
      oval(60, 46, 6, 8, ink);
      oval(35, 47, 2, 2, Colors.white);
      oval(61, 47, 2, 2, Colors.white);
    }

    canvas.drawCircle(
      const Offset(50, 50),
      50,
      brush..color = color('background', const Color(0xffe0e8e0)),
    );
    switch (definition?['design']) {
      case 'cat':
      case 'fox':
        final fox = definition?['design'] == 'fox';
        triangle(
          const Offset(20, 46),
          const Offset(22, 17),
          const Offset(43, 34),
          accent,
        );
        triangle(
          const Offset(58, 34),
          const Offset(78, 17),
          const Offset(80, 46),
          accent,
        );
        oval(18, 29, 64, 54, accent);
        if (fox) {
          triangle(
            const Offset(20, 53),
            const Offset(50, 81),
            const Offset(50, 58),
            cream,
          );
          triangle(
            const Offset(80, 53),
            const Offset(50, 81),
            const Offset(50, 58),
            cream,
          );
        } else {
          oval(31, 59, 38, 19, cream);
        }
        eyes();
        triangle(
          const Offset(45, 61),
          const Offset(55, 61),
          const Offset(50, 67),
          ink,
        );
        if (!fox) {
          for (final y in [60.0, 66.0]) {
            canvas.drawLine(
              Offset(13, y - 2),
              Offset(33, y),
              brush
                ..color = ink
                ..strokeWidth = 1.5,
            );
            canvas.drawLine(
              Offset(67, y),
              Offset(87, y - 2),
              brush
                ..color = ink
                ..strokeWidth = 1.5,
            );
          }
        }
      case 'owl':
        oval(19, 20, 62, 66, accent);
        triangle(
          const Offset(22, 34),
          const Offset(21, 16),
          const Offset(40, 25),
          accent,
        );
        triangle(
          const Offset(61, 25),
          const Offset(79, 16),
          const Offset(78, 34),
          accent,
        );
        oval(24, 32, 29, 32, cream);
        oval(47, 32, 29, 32, cream);
        eyes();
        triangle(
          const Offset(44, 61),
          const Offset(56, 61),
          const Offset(50, 71),
          const Color(0xffe7a443),
        );
      case 'robot':
        round(18, 29, 64, 51, 12, accent);
        round(27, 39, 46, 26, 8, cream);
        round(10, 43, 8, 20, 3, accent);
        round(82, 43, 8, 20, 3, accent);
        canvas.drawLine(
          const Offset(50, 30),
          const Offset(50, 18),
          brush
            ..color = ink
            ..strokeWidth = 3,
        );
        oval(46, 11, 8, 8, accent);
        eyes();
        round(40, 69, 20, 3, 2, ink);
      case 'cactus':
        round(38, 16, 24, 60, 12, accent);
        round(19, 34, 12, 29, 6, accent);
        round(25, 53, 19, 11, 5, accent);
        round(69, 29, 12, 29, 6, accent);
        round(56, 49, 19, 11, 5, accent);
        round(32, 72, 36, 17, 4, const Color(0xffbd7651));
        oval(44, 39, 3, 5, ink);
        oval(54, 39, 3, 5, ink);
        oval(59, 19, 10, 8, const Color(0xffeaa4ab));
      case 'cowboy':
        round(29, 39, 42, 43, 20, cream);
        oval(33, 48, 5, 7, ink);
        oval(61, 48, 5, 7, ink);
        round(27, 19, 46, 29, 9, accent);
        oval(14, 37, 72, 14, accent);
        round(28, 34, 44, 7, 2, const Color(0xffedb35b));
        triangle(
          const Offset(33, 76),
          const Offset(68, 76),
          const Offset(50, 91),
          const Color(0xffdc7355),
        );
      default:
        oval(36, 24, 28, 28, accent);
        oval(23, 57, 54, 32, accent);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) =>
      oldDelegate.definition != definition;
}
