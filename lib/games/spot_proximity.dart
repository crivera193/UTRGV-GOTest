import 'package:geolocator/geolocator.dart';
import '../map/campus_location.dart';
import 'game_spot.dart';

enum SpotState {
  unavailable,
  outsideCampus,
  outsideRange,
  eligible,
  dismissed,
  active,
}

/// Accepts injected fixes from the existing foreground stream (or tests).
/// Never reads a map camera, smoothed marker, or starts a location subscription.
class SpotProximity {
  SpotProximity(this.spots);
  final List<GameSpot> spots;
  SpotState state = SpotState.unavailable;
  GameSpot? selected;
  final _enteredAt = <String, DateTime>{};
  final _inside = <String>{};
  final _suppressed = <String>{};
  final _exitAt = <String, DateTime>{};
  CampusFix? _fix;
  DateTime? _lastTimestamp;
  bool _onCampus = false;
  String? _activeSpotId;
  bool get active => state == SpotState.active;

  bool _usable(DateTime now) {
    final f = _fix;
    return f != null &&
        f.accuracy.isFinite &&
        f.accuracy >= 0 &&
        f.accuracy <= ProximitySettings.maxAccuracyMeters &&
        f.point.latitude.isFinite &&
        f.point.latitude.abs() <= 90 &&
        f.point.longitude.isFinite &&
        f.point.longitude.abs() <= 180 &&
        !f.timestamp.isAfter(now) &&
        now.difference(f.timestamp) <= ProximitySettings.maxFixAge;
  }

  double _distance(GameSpot s) => Geolocator.distanceBetween(
    _fix!.point.latitude,
    _fix!.point.longitude,
    s.point.latitude,
    s.point.longitude,
  );

  double? distanceTo(GameSpot spot) => _fix == null ? null : _distance(spot);

  String? attackReason(GameSpot spot, DateTime now) {
    if (!_usable(now)) {
      return 'A fresh GPS fix with accuracy of 15 m or better is required.';
    }
    if (!_onCampus) return 'A confirmed on-campus GPS fix is required.';
    if (_distance(spot) + _fix!.accuracy >
        (spot.attackMeters ?? spot.entryMeters)) {
      return 'Move within 130 ft (39.624 m), including GPS uncertainty. Stay on a safe outdoor path.';
    }
    return null;
  }

  void accept(CampusFix fix, {required bool onCampus, required DateTime now}) {
    // Replayed/out-of-order fixes cannot provide dwell evidence.
    if (_lastTimestamp != null && !fix.timestamp.isAfter(_lastTimestamp!)) {
      return;
    }
    if (_fix != null &&
        fix.timestamp.difference(_fix!.timestamp) >
            ProximitySettings.maxFixAge) {
      _enteredAt.clear();
      _inside.clear();
      _exitAt.clear();
    }
    _fix = fix;
    _lastTimestamp = fix.timestamp;
    _onCampus = onCampus;
    if (!_usable(now)) {
      unavailable();
      return;
    }
    // Leave/re-entry suppression is cleared only by consistent reliable fixes
    // beyond exit + accuracy. Invalid/missing GPS is never evidence of leaving.
    for (final s in spots.where((s) => s.enabled)) {
      final d = _distance(s);
      if (d - fix.accuracy > s.exitMeters) {
        _exitAt.putIfAbsent(s.id, () => fix.timestamp);
        if (fix.timestamp.difference(_exitAt[s.id]!) >=
            ProximitySettings.dwell) {
          _inside.remove(s.id);
          _suppressed.remove(s.id);
          _enteredAt.remove(s.id);
        }
      } else {
        _exitAt.remove(s.id);
      }
      if (!onCampus) {
        _enteredAt.remove(s.id);
        _inside.remove(s.id);
        continue;
      }
      if (d + fix.accuracy <= s.entryMeters) {
        _enteredAt.putIfAbsent(s.id, () => fix.timestamp);
        if (fix.timestamp.difference(_enteredAt[s.id]!) >=
            ProximitySettings.dwell) {
          _inside.add(s.id);
        }
      } else if (!_inside.contains(s.id)) {
        _enteredAt.remove(s.id);
      }
    }
    _evaluate(now);
  }

  void unavailable() {
    _fix = null;
    _onCampus = false;
    _enteredAt.clear();
    _inside.clear();
    _exitAt.clear();
    if (!active) {
      state = SpotState.unavailable;
      selected = null;
    }
  }

  void refresh(DateTime now) => _evaluate(now);

  void _evaluate(DateTime now) {
    if (active) return; // GPS noise cannot close or reopen the game.
    if (!_usable(now)) {
      unavailable();
      return;
    }
    if (!_onCampus) {
      selected = null;
      state = SpotState.outsideCampus;
      return;
    }
    final candidates =
        spots
            .where(
              (s) =>
                  s.enabled &&
                  _inside.contains(s.id) &&
                  !_suppressed.contains(s.id) &&
                  _distance(s) + _fix!.accuracy <= s.exitMeters,
            )
            .toList()
          ..sort((a, b) {
            final order = _distance(a).compareTo(_distance(b));
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    // Retain the invited choice while eligible, despite small distance changes.
    if (!candidates.contains(selected)) selected = candidates.firstOrNull;
    state = selected != null
        ? SpotState.eligible
        : _suppressed.isNotEmpty
        ? SpotState.dismissed
        : SpotState.outsideRange;
  }

  void dismiss() {
    if (state != SpotState.eligible) return;
    // Suppress overlapping invitations as a single arrival, not a card carousel.
    _suppressArrival();
    selected = null;
    state = SpotState.dismissed;
  }

  GameSpot? launch(DateTime now) {
    if (active) return null;
    _evaluate(now); // Play must recheck age, accuracy, campus and distance.
    if (state != SpotState.eligible) return null;
    if (selected!.attackMeters != null &&
        attackReason(selected!, now) != null) {
      return null;
    }
    _suppressArrival();
    _activeSpotId = selected!.id;
    state = SpotState.active;
    return selected;
  }

  bool launchAttack(GameSpot spot, DateTime now) {
    if (active || attackReason(spot, now) != null) return false;
    _suppressArrival();
    selected = spot;
    _activeSpotId = spot.id;
    state = SpotState.active;
    return true;
  }

  void close(DateTime now) {
    if (!active) return;
    _suppressArrival();
    if (_activeSpotId != null) _suppressed.add(_activeSpotId!);
    _activeSpotId = null;
    selected = null;
    state = SpotState.dismissed;
    _evaluate(now);
  }

  void _suppressArrival() {
    _suppressed.addAll(_inside);
    // Include overlapping spots still dwelling when Dismiss/Play was pressed.
    if (_fix != null) {
      _suppressed.addAll(
        spots
            .where(
              (s) => s.enabled && _distance(s) <= s.exitMeters + _fix!.accuracy,
            )
            .map((s) => s.id),
      );
    }
  }
}
