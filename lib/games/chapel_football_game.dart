import 'dart:async';
import 'dart:ui';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        TextPainter,
        TextSpan,
        TextStyle,
        FontWeight,
        TextAlign,
        LinearGradient;
import 'chapel_capture.dart';
import 'football_shot.dart';
import 'game_host.dart';

class ChapelFootballGame extends SessionGame with DragCallbacks {
  ChapelFootballGame(super.session, super.onExit);
  CaptureSession get attack => session.capture!;
  int? _pointer, _shotId;
  Offset? _start, _end;
  FootballShot? _shot;
  Offset? _kickDelta;
  double _time = 0;
  Offset logical(Offset p) =>
      Offset(p.dx * 400 / canvasSize.x, p.dy * 650 / canvasSize.y);
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final p = logical(event.canvasPosition.toOffset());
    if (!sessionVisible ||
        _pointer != null ||
        attack.phase != AttackPhase.questionReady ||
        (p - const Offset(200, 520)).distance > 110) {
      return;
    }
    _pointer = event.pointerId;
    _start = _end = p;
    attack.aiming();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_pointer == event.pointerId) {
      _end = logical(event.canvasEndPosition.toOffset());
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    if (_pointer == event.pointerId) cancelInput();
    super.onDragCancel(event);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_pointer != event.pointerId) return;
    final delta = _end! - _start!;
    _pointer = null;
    _start = _end = null;
    shootSwipe(delta);
  }

  /// Logical-coordinate entry shared by pointer handling and deterministic tests.
  void shootSwipe(Offset delta) {
    if (!sessionVisible ||
        attack.closed ||
        attack.phase != AttackPhase.aiming) {
      return;
    }
    final shot = FootballShot.fromSwipe(delta);
    if (shot == null) {
      attack.cancelAim();
      return;
    }
    _shotId = attack.fire();
    if (_shotId != null) {
      _shot = shot;
      _kickDelta = delta;
      _time = 0;
    }
  }

  void cancelInput() {
    _pointer = null;
    _start = _end = null;
    attack.cancelAim();
  }

  @override
  void setVisible(bool visible) {
    if (!visible) cancelInput();
    super.setVisible(visible);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final shot = _shot;
    if (shot == null || attack.closed) return;
    _time += dt;
    // Analytic plane crossing: a long frame cannot skip a goal.
    if (_time >= shot.crossingTime) {
      _shot = null;
      unawaited(attack.resolveKick(_shotId!, _kickDelta!));
    }
  }

  void text(
    Canvas c,
    String value,
    Rect rect, {
    double font = 15,
    Color color = Colors.white,
    bool bold = false,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: font,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: rect.width);
    p.paint(c, Offset(rect.left, rect.center.dy - p.height / 2));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final c = canvas;
    c.save();
    c.scale(canvasSize.x / 400, canvasSize.y / 650);
    c.drawRect(
      const Rect.fromLTWH(0, 0, 400, 650),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff8cd8e5), Color(0xffe7f7ef)],
        ).createShader(const Rect.fromLTWH(0, 0, 400, 320)),
    );
    // Original terraced stadium and field; all geometry is local vector art.
    for (var row = 0; row < 5; row++) {
      c.drawRect(
        Rect.fromLTWH(0, 180 + row * 12.0, 400, 10),
        Paint()
          ..color = row.isEven
              ? const Color(0xff315968)
              : const Color(0xff577b7b),
      );
      for (var x = 6; x < 400; x += 14) {
        c.drawCircle(
          Offset(x.toDouble(), 184 + row * 12.0),
          1.4,
          Paint()..color = const Color(0xffedc98e),
        );
      }
    }
    c.drawRect(
      const Rect.fromLTWH(0, 240, 400, 410),
      Paint()..color = const Color(0xff327f4e),
    );
    for (var z = 0.0; z < 80; z += 5) {
      final a = FootballShot.project(-28, z, 0),
          b = FootballShot.project(28, z, 0);
      c.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0x88dcf0cd)
          ..strokeWidth = z % 10 == 0 ? 2 : 1,
      );
    }
    for (final x in [-23.0, 23.0]) {
      c.drawLine(
        FootballShot.project(x, 0, 0),
        FootballShot.project(x, 80, 0),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3,
      );
    }
    for (var i = 0; i < 4; i++) {
      final x = FootballShot.centers[i];
      final left = FootballShot.project(
            x - FootballShot.halfWidth,
            30,
            FootballShot.top,
          ),
          right = FootballShot.project(
            x + FootballShot.halfWidth,
            30,
            FootballShot.top,
          );
      final bar = FootballShot.project(x, 30, 3),
          base = FootballShot.project(x, 30, 0);
      final paint = Paint()
        ..color = const Color(0xffffd959)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      c.drawLine(base, bar, paint);
      c.drawLine(Offset(left.dx, bar.dy), Offset(right.dx, bar.dy), paint);
      c.drawLine(left, Offset(left.dx, bar.dy), paint);
      c.drawLine(right, Offset(right.dx, bar.dy), paint);
      final box = Rect.fromLTRB(
        left.dx + 3,
        left.dy + 4,
        right.dx - 3,
        bar.dy - 4,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(5)),
        Paint()..color = const Color(0xee163b35),
      );
      text(
        c,
        '${String.fromCharCode(65 + i)}\n${attack.question.answers[i]}',
        box.deflate(3),
        font: 13,
        bold: true,
      );
    }
    if (_start != null && _end != null) {
      final delta = _end! - _start!;
      final shot = FootballShot.fromSwipe(delta);
      c.drawLine(
        const Offset(200, 520),
        Offset(200 + delta.dx.clamp(-150, 150), 520 + delta.dy.clamp(-220, 50)),
        Paint()
          ..color = const Color(0xaaffffff)
          ..strokeWidth = 3,
      );
      text(
        c,
        shot == null
            ? 'Swipe forward ↑'
            : 'Power ${((-delta.dy / 220).clamp(.35, 1) * 100).round()}%',
        const Rect.fromLTWH(60, 570, 280, 35),
      );
    }
    final shot = _shot;
    final center = shot == null
        ? const Offset(200, 520)
        : FootballShot.project(shot.x(_time), shot.z(_time), shot.h(_time));
    final scale = shot == null ? 1.0 : (18 / (shot.z(_time) + 18));
    final shadow = shot == null
        ? const Offset(200, 550)
        : FootballShot.project(shot.x(_time), shot.z(_time), 0);
    c.drawOval(
      Rect.fromCenter(center: shadow, width: 62 * scale, height: 12 * scale),
      Paint()..color = const Color(0x55001f15),
    );
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(shot == null ? -.15 : FootballShot.rotation(_time));
    c.scale(scale);
    final ball = Path()
      ..moveTo(0, -42)
      ..cubicTo(35, -24, 35, 24, 0, 42)
      ..cubicTo(-35, 24, -35, -24, 0, -42);
    c.drawPath(
      ball,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff76320f), Color(0xffd88641), Color(0xff793613)],
        ).createShader(const Rect.fromLTWH(-30, -42, 60, 84)),
    );
    c.drawLine(
      const Offset(0, -20),
      const Offset(0, 20),
      Paint()
        ..color = const Color(0xfffff2cc)
        ..strokeWidth = 3,
    );
    for (var y = -15.0; y <= 15; y += 7.5) {
      c.drawLine(
        Offset(-7, y),
        Offset(7, y),
        Paint()
          ..color = const Color(0xfffff2cc)
          ..strokeWidth = 2,
      );
    }
    c.restore();
    if (attack.phase == AttackPhase.sessionEnded) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(28, 370, 344, 180),
          const Radius.circular(20),
        ),
        Paint()..color = const Color(0xf2183f37),
      );
      text(
        c,
        attack.captured ? 'POINT CAPTURED' : 'ATTACK COMPLETE',
        const Rect.fromLTWH(40, 395, 320, 50),
        font: 26,
        bold: true,
      );
      text(
        c,
        attack.captured
            ? '◆ ${attack.point.playerTeam.displayName}\nChapel Point · ${attack.point.state.hp} HP\nSaved online'
            : 'Earned damage is saved.\nReturn to the map to try again.',
        const Rect.fromLTWH(55, 455, 290, 65),
        font: 17,
      );
    }
    c.restore();
  }
}
