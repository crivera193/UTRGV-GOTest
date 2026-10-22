import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game_team.dart';

/// Pure presentation. Flutter hit targets share the exact three column bounds.
/// No character, location subscription, game-world input or membership writes.
class TeamSelectionGame extends FlameGame {
  TeamSelectionGame({this.onAssetError}) {
    images = Images(prefix: 'assets/teams/');
    pauseWhenBackgrounded =
        false; // The Flutter host combines app/dialog visibility.
  }
  final VoidCallback? onAssetError;
  ui.Image? _hat, _pedestal;
  double _time = 0;
  bool reducedMotion = false;

  @override
  Future<void> onLoad() async {
    try {
      _hat = await images.load('cowboy-hat.png');
      _pedestal = await images.load('pedestal.png');
    } catch (_) {
      onAssetError?.call();
      rethrow;
    }
  }

  @override
  Color backgroundColor() => const Color(0xff10171f);

  @override
  void update(double dt) {
    super.update(dt);
    if (!reducedMotion) _time += dt.clamp(0, .05);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = size.x, h = size.y;
    if (w <= 0 || h <= 0) return;
    final floor = Rect.fromCenter(
      center: Offset(w / 2, h * .72),
      width: w * 1.2,
      height: h * .57,
    );
    canvas.drawOval(
      floor,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xff39403e), Color(0xff10171f)],
        ).createShader(floor),
    );
    for (final scale in [.48, .71, .94]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: floor.center,
          width: w * scale,
          height: h * scale * .37,
        ),
        Paint()
          ..color = const Color(0xff77705a).withValues(alpha: .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    for (var i = 0; i < 3; i++) {
      final x = w * (i + .5) / 3;
      final base = h * (i == 1 ? .71 : .83);
      final color = GameTeam.values[i].color;
      final glow = Rect.fromCenter(
        center: Offset(x, base - h * .39),
        width: w * .48,
        height: h * .87,
      );
      canvas.drawOval(
        glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: .55),
              color.withValues(alpha: .18),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(glow),
      );
      final beam = Path()
        ..moveTo(x - w * .06, base - h * .05)
        ..lineTo(x - w * .13, h * .02)
        ..lineTo(x + w * .13, h * .02)
        ..lineTo(x + w * .06, base - h * .05)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: .18), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, w, base)),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, base - 2),
          width: w * .27,
          height: h * .06,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      if (_pedestal case final pedestal?) {
        final target = Rect.fromLTWH(
          x - w * .15,
          base - h * .55,
          w * .3,
          h * .55,
        );
        canvas.drawImageRect(
          pedestal,
          Rect.fromLTWH(
            0,
            0,
            pedestal.width.toDouble(),
            pedestal.height.toDouble(),
          ),
          target,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      final bob = reducedMotion ? 0.0 : math.sin(_time * 1.2 + i) * h * .006;
      if (_hat case final hat?) {
        final target = Rect.fromLTWH(
          x - w * .18,
          base - h * .73 + bob,
          w * .36,
          w * .27,
        );
        canvas.drawImageRect(
          hat,
          Rect.fromLTWH(0, 0, hat.width.toDouble(), hat.height.toDouble()),
          target,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      // A few deterministic motes; bounded, no per-frame allocations of assets.
      if (!reducedMotion) {
        for (var p = 0; p < 5; p++) {
          final t = (_time * .07 + p * .21) % 1;
          canvas.drawCircle(
            Offset(x + math.sin(p * 9.7) * w * .09, base - h * (.13 + t * .65)),
            p.isEven ? 1.3 : .8,
            Paint()
              ..color = color.withValues(alpha: math.sin(t * math.pi) * .35),
          );
        }
      }
    }
  }

  @override
  void onDispose() {
    dispose();
    super.onDispose();
  }
}
