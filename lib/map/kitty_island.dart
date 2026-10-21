import 'campus_geography.dart';
import 'campus_location.dart';

/// Owner-confirmed courtyard, not the earlier Physical Science sighting.
abstract final class KittyIsland {
  static const center = CampusPoint(-98.171621, 26.307804);
  static const entryMeters = 30.0;
  static const exitMeters = 45.0;
  static const maxAccuracyMeters = 20.0;
  static const maxAge = Duration(seconds: 10);
  static const dwell = Duration(seconds: 2);
  // Decorative positions around the supplied pin, not surveyed cat locations.
  static const cats = [
    CampusPoint(-98.171680, 26.307780),
    CampusPoint(-98.171621, 26.307876),
    CampusPoint(-98.171570, 26.307830),
  ];
}

/// Foreground decoration driven by raw fixes, never the cosmetic cowboy position.
class KittyIslandProximity {
  bool visible = false;
  DateTime? _lastTimestamp, _enteredAt;

  void accept(CampusFix fix, {required bool onCampus, required DateTime now}) {
    if (_lastTimestamp != null && !fix.timestamp.isAfter(_lastTimestamp!)) {
      refresh(now);
      return;
    }
    if (_lastTimestamp != null &&
        fix.timestamp.difference(_lastTimestamp!) > KittyIsland.maxAge) {
      unavailable();
    }
    final p = fix.point;
    if (!onCampus ||
        !fix.accuracy.isFinite ||
        fix.accuracy < 0 ||
        fix.accuracy > KittyIsland.maxAccuracyMeters ||
        !p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180 ||
        fix.timestamp.isAfter(now) ||
        now.difference(fix.timestamp) > KittyIsland.maxAge) {
      unavailable();
      return;
    }
    _lastTimestamp = fix.timestamp;
    final distance = CampusGeography.distance(p, KittyIsland.center);
    if (distance > KittyIsland.exitMeters) {
      visible = false;
      _enteredAt = null;
    } else if (!visible) {
      if (distance <= KittyIsland.entryMeters) {
        _enteredAt ??= fix.timestamp;
        visible = fix.timestamp.difference(_enteredAt!) >= KittyIsland.dwell;
      } else {
        _enteredAt = null;
      }
    }
  }

  void refresh(DateTime now) {
    if (_lastTimestamp == null ||
        now.difference(_lastTimestamp!) > KittyIsland.maxAge) {
      unavailable();
    }
  }

  void unavailable() {
    visible = false;
    _enteredAt = null;
    // Retain timestamp so duplicate fixes cannot restart arrival dwell.
  }
}
