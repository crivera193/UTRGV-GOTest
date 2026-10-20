import 'dart:math' as math;

/// Only real GPS fixes (or explicitly labelled test fixtures) enter this policy.
/// Camera changes never enter it. Coordinates remain owned by the campus policy.
class CowboyMotion {
  double heading = 0;
  double playbackRate = 1;
  bool walking = false;
  _MotionFix? _anchor;
  DateTime? _lastFix;
  DateTime? _lastMovement;
  int _credibleSegments = 0;

  void accept({
    required double longitude,
    required double latitude,
    required double accuracy,
    required DateTime timestamp,
    required DateTime now,
    required bool onCampus,
  }) {
    if (_lastFix != null && !timestamp.isAfter(_lastFix!)) return;
    if (!onCampus ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 20 ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        now.difference(timestamp).inSeconds > 5 ||
        timestamp.isAfter(now.add(const Duration(seconds: 2)))) {
      stop();
      return;
    }
    _lastFix = timestamp;
    final fix = _MotionFix(longitude, latitude, accuracy, timestamp);
    final anchor = _anchor;
    _anchor ??= fix;
    if (anchor == null) return;
    final seconds = timestamp.difference(anchor.time).inMilliseconds / 1000;
    final east =
        (longitude - anchor.lon) * 111320 * math.cos(latitude * math.pi / 180);
    final north = (latitude - anchor.lat) * 111320;
    final distance = math.sqrt(east * east + north * north);
    final threshold = math.max(1.8, math.max(accuracy, anchor.accuracy) * 0.5);
    if (seconds <= 0) return;
    if (seconds > 12) {
      _anchor = fix;
      walking = false;
      _credibleSegments = 0;
      return;
    }
    if (distance < threshold) {
      expire(now);
      return;
    }
    _anchor = fix;
    final speed = distance / seconds;
    if (speed < 0.45 || speed > 3.5 || seconds < 0.5) {
      walking = false;
      _credibleSegments = 0;
      return;
    }
    // Two coherent segments reject an isolated jump. A reversal resets evidence.
    final nextHeading = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
    final delta = ((nextHeading - heading + 540) % 360) - 180;
    if (_credibleSegments > 0 && delta.abs() > 100) _credibleSegments = 0;
    heading = nextHeading;
    _credibleSegments++;
    walking = _credibleSegments >= 2;
    _lastMovement = timestamp;
    // Measured matched-travel speed recorded by the approved Blender rig.
    playbackRate = (speed / 1.0645109415).clamp(0.65, 1.6);
  }

  void expire(DateTime now) {
    if (_lastMovement == null ||
        now.difference(_lastMovement!).inMilliseconds > 4500) {
      walking = false;
      _credibleSegments = 0;
    }
  }

  void stop() {
    walking = false;
    _anchor = null;
    _lastFix = null;
    _lastMovement = null;
    _credibleSegments = 0;
  }
}

class _MotionFix {
  _MotionFix(this.lon, this.lat, this.accuracy, this.time);
  final double lon, lat, accuracy;
  final DateTime time;
}
