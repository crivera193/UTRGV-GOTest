import 'dart:math' as math;
import 'campus_geography.dart';

enum CampusGpsState {
  waiting,
  onCampus,
  outside,
  boundary,
  inaccurate,
  stale,
  denied,
  disabled,
  unavailable,
}

class CampusFix {
  const CampusFix(this.point, this.accuracy, this.timestamp);
  final CampusPoint point;
  final double accuracy;
  final DateTime timestamp;
}

/// Foreground-only GPS policy, independent of native map rendering and services.
class CampusLocationPolicy {
  CampusLocationPolicy(this.geography);
  final CampusGeography geography;
  CampusGpsState state = CampusGpsState.waiting;
  CampusFix? _last;
  DateTime? _waitingSince;
  CampusPoint? marker;
  bool? _confirmedInside;

  void begin(DateTime now) {
    _last = null;
    _waitingSince = now;
    _confirmedInside = null;
    clear(CampusGpsState.waiting);
  }

  void accept(CampusFix fix, DateTime now) {
    if (_last != null && !fix.timestamp.isAfter(_last!.timestamp)) return;
    if (now.difference(fix.timestamp).inSeconds > 20 ||
        fix.timestamp.isAfter(now.add(const Duration(seconds: 5)))) {
      clear(CampusGpsState.stale);
      return;
    }
    _last = fix;
    if (!fix.accuracy.isFinite ||
        fix.accuracy < 0 ||
        fix.accuracy > 40 ||
        !fix.point.latitude.isFinite ||
        !fix.point.longitude.isFinite ||
        fix.point.latitude.abs() > 90 ||
        fix.point.longitude.abs() > 180) {
      clear(CampusGpsState.inaccurate);
      return;
    }
    final edge = geography.signedEdgeDistance(fix.point);
    final enterMargin = math.max(8.0, fix.accuracy);
    final exitMargin = math.max(12.0, fix.accuracy);
    if (edge > enterMargin) _confirmedInside = true;
    if (edge < -exitMargin) _confirmedInside = false;
    if (edge <= 0) {
      marker = null; // Never place a marker at a substituted campus coordinate.
      state = _confirmedInside == false
          ? CampusGpsState.outside
          : CampusGpsState.boundary;
      return;
    }
    if (_confirmedInside != true) {
      clear(CampusGpsState.boundary);
      return;
    }
    state = CampusGpsState.onCampus;
    final previous = marker;
    if (previous == null ||
        CampusGeography.distance(previous, fix.point) > 50) {
      marker = fix.point;
    } else if (CampusGeography.distance(previous, fix.point) >
        math.max(3, fix.accuracy * 0.25)) {
      final smoothed = CampusPoint(
        previous.longitude + (fix.point.longitude - previous.longitude) * 0.55,
        previous.latitude + (fix.point.latitude - previous.latitude) * 0.55,
      );
      marker = geography.contains(smoothed) ? smoothed : fix.point;
    }
  }

  void expire(DateTime now) {
    if (_last == null &&
        _waitingSince != null &&
        now.difference(_waitingSince!).inSeconds > 20) {
      clear(CampusGpsState.unavailable);
      return;
    }
    if (_last != null && now.difference(_last!.timestamp).inSeconds > 20) {
      clear(CampusGpsState.stale);
    }
  }

  void clear(CampusGpsState next) {
    state = next;
    marker = null;
    if (next == CampusGpsState.stale ||
        next == CampusGpsState.denied ||
        next == CampusGpsState.disabled ||
        next == CampusGpsState.unavailable) {
      _confirmedInside = null;
    }
  }

  String get message => switch (state) {
    CampusGpsState.waiting =>
      _waitingSince == null
          ? 'Explore UTRGV Edinburg · enable location to walk'
          : 'Waiting for a reliable GPS fix',
    CampusGpsState.onCampus => 'On campus',
    CampusGpsState.outside =>
      'You’re outside campus. You can still explore the map.',
    CampusGpsState.boundary =>
      'Near the campus edge · waiting for a clearer GPS fix',
    CampusGpsState.inaccurate => 'GPS accuracy is low · move to an open area',
    CampusGpsState.stale => 'GPS update is stale · waiting for location',
    CampusGpsState.denied =>
      'Location permission is off · campus browsing is available',
    CampusGpsState.disabled => 'Turn on device location to show your position',
    CampusGpsState.unavailable =>
      'Location unavailable · tap Follow me to retry',
  };
}
