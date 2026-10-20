import 'dart:math' as math;
import 'package:flutter/material.dart';

const journalInk = Color(0xFF123D2B);
const journalPaper = Color(0xFFF5F1E3);
const journalOrange = Color(0xFFE85C08);

TextStyle journalType(double size, {Color color = journalInk}) => TextStyle(
  fontFamily: 'DMSerifDisplay',
  fontSize: size,
  height: 1.05,
  color: color,
);

/// Decorative only: the grid never changes the layout or intercepts form input.
class JournalPaper extends StatelessWidget {
  const JournalPaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _PaperPainter(), child: child);
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = journalPaper);
    final grid = Paint()
      ..color = journalInk.withValues(alpha: .045)
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Deterministic paper flecks keep the page from feeling like a flat fill.
    final fleck = Paint()..color = journalInk.withValues(alpha: .035);
    final random = math.Random(17);
    for (int i = 0; i < size.width * size.height / 150; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .45,
        fleck,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => false;
}

class JournalCompass extends StatelessWidget {
  const JournalCompass({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: const Size(52, 58), painter: _CompassPainter()),
  );
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..color = journalInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    canvas.drawCircle(center, 17, line);
    for (int i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi / 4);
      final radius = i.isEven ? 24.0 : 14.0;
      final path = Path()
        ..moveTo(0, -radius)
        ..lineTo(4, 0)
        ..lineTo(0, -3)
        ..close();
      canvas.drawPath(path, Paint()..color = journalInk);
      canvas.drawPath(
        Path()
          ..moveTo(0, -radius)
          ..lineTo(-4, 0)
          ..lineTo(0, -3)
          ..close(),
        line,
      );
      canvas.restore();
    }
    for (final entry in <String, Offset>{
      'N': Offset(center.dx - 3, 0),
      'S': Offset(center.dx - 3, size.height - 8),
      'W': Offset(0, center.dy - 4),
      'E': Offset(size.width - 6, center.dy - 4),
    }.entries) {
      final text = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: const TextStyle(
            color: journalInk,
            fontSize: 7,
            fontFamily: 'Inter',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, entry.value);
    }
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) => false;
}

class JournalMasthead extends StatelessWidget {
  const JournalMasthead({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const JournalCompass(),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('UTRGV-GO', style: journalType(29)),
            ),
          ),
          const SizedBox(width: 12),
          const ExcludeSemantics(
            child: Text(
              'EXPLORE\nWALK\nDISCOVER',
              style: TextStyle(
                fontSize: 7,
                letterSpacing: 2,
                height: 1.8,
                color: journalInk,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Divider(height: 1, color: journalInk.withValues(alpha: .45)),
    ],
  );
}

class JournalMapStrip extends StatelessWidget {
  const JournalMapStrip({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          widthFactor: .38,
          child: Image.asset(
            'assets/auth/field-notes-map.png',
            width: 340,
            height: 340,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    ),
  );
}
