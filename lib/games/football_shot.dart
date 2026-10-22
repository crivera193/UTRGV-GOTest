import 'dart:math' as math;
import 'dart:ui';

/// World meters: x lateral, z forward, h above turf. All goals share z=30.
class FootballShot {
  FootballShot(this.vx, this.vz, this.vh);
  final double vx, vz, vh;
  static const depth = 30.0, gravity = 9.8, crossbar = 3.0, top = 12.0;
  static const centers = [-15.0, -5.0, 5.0, 15.0];
  static const halfWidth = 4.2, radius = .18;
  static FootballShot? fromSwipe(Offset delta) {
    if (!delta.dx.isFinite ||
        !delta.dy.isFinite ||
        delta.dy > -45 ||
        delta.dy < -650 ||
        delta.dx.abs() > 400) {
      return null;
    }
    final power = (-delta.dy / 220).clamp(.35, 1.0);
    final vz = 18 + 8 * power;
    final slope = (delta.dx / -delta.dy).clamp(-.65, .65);
    return FootballShot(vz * slope, vz, 8 + 2 * power);
  }

  double x(double t) => vx * t;
  double z(double t) => vz * t;
  double h(double t) => 1 + vh * t - gravity * t * t / 2;
  double get crossingTime => depth / vz;
  int? get goal {
    final t = crossingTime, height = h(crossingTime);
    if (height - radius <= crossbar || height + radius >= top) return null;
    for (var i = 0; i < centers.length; i++) {
      if ((x(t) - centers[i]).abs() + radius < halfWidth) return i;
    }
    return null;
  }

  static Offset project(double x, double z, double h) {
    final scale = 420 / (z + 18);
    return Offset(200 + x * scale, 240 + (12 - h) * scale);
  }

  static double rotation(double t) => t * math.pi * 3;
}
