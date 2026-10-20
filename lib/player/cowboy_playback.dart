import 'package:flutter/foundation.dart';

/// Persistent loop phase; direction/pitch changes never reset this clock.
class CowboyPlayback extends ChangeNotifier {
  double phase = 0;
  double cycleSeconds = 40 / 30;
  bool _walking = false;
  int get frame => _walking ? (phase * 12).floor() % 12 : 12;
  void advance(double seconds, {required bool walking, required double rate}) {
    final before = frame;
    _walking = walking;
    if (walking && seconds > 0) {
      phase = (phase + seconds * rate / cycleSeconds) % 1;
    }
    if (before != frame) notifyListeners();
  }
}

class CowboyFacing {
  int? _direction, _pitch;
  int direction(double heading, double bearing) {
    final relative = (heading - bearing + 360) % 360;
    _direction ??= (relative / 45).round() % 8;
    final delta = ((relative - _direction! * 45 + 540) % 360) - 180;
    if (delta.abs() > 28.5) _direction = (relative / 45).round() % 8;
    return _direction!;
  }

  int pitch(double degrees) {
    _pitch ??= degrees < 15
        ? 0
        : degrees < 40
        ? 1
        : 2;
    if (_pitch == 0 && degrees > 18 ||
        _pitch == 2 && degrees < 37 ||
        _pitch == 1 && (degrees < 12 || degrees > 43)) {
      _pitch = degrees < 15
          ? 0
          : degrees < 40
          ? 1
          : 2;
    }
    return _pitch!;
  }
}
