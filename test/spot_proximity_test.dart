import 'package:campus_app/games/game_spot.dart';
import 'package:campus_app/games/spot_proximity.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Synthetic equatorial coordinates; no stored player location.
  const a = GameSpot(id: 'a', name: 'A', point: CampusPoint(0, 0));
  const b = GameSpot(id: 'b', name: 'B', point: CampusPoint(0.00005, 0));
  final epoch = DateTime.utc(2026, 10, 19);
  DateTime at(int s) => epoch.add(Duration(seconds: s));
  void fix(
    SpotProximity p,
    int s, {
    double lon = 0,
    double accuracy = 3,
    bool campus = true,
    int? age,
  }) {
    p.accept(
      CampusFix(CampusPoint(lon, 0), accuracy, at(s - (age ?? 0))),
      onCampus: campus,
      now: at(s),
    );
  }

  SpotProximity arrived([List<GameSpot> spots = const [a]]) {
    final p = SpotProximity(spots);
    fix(p, 0);
    fix(p, 3);
    expect(p.state, SpotState.eligible);
    return p;
  }

  test('fresh consistent entry; geographic meters and exit hysteresis', () {
    final p = SpotProximity([a]);
    fix(p, 0);
    expect(p.state, SpotState.outsideRange);
    p.refresh(at(3)); // Time alone is not a second GPS fix.
    expect(p.state, SpotState.outsideRange);
    fix(p, 3);
    expect(p.state, SpotState.eligible);
    fix(p, 4, lon: 0.00027); // 30m, beyond entry but inside exit.
    expect(p.state, SpotState.eligible);
    fix(p, 5, lon: 0.0005);
    expect(p.launch(at(5)), isNull);
    fix(p, 8, lon: 0.0005);
    expect(p.state, SpotState.outsideRange);
    fix(p, 9);
    fix(p, 12);
    expect(p.state, SpotState.eligible);
  });
  test('poor/stale/future/missing/outside fixes cannot unlock', () {
    for (final accuracy in [16.0, double.nan, -1.0]) {
      final p = arrived();
      fix(p, 4, accuracy: accuracy);
      expect(p.launch(at(4)), isNull);
      expect(p.state, SpotState.unavailable);
    }
    final p = arrived();
    expect(p.launch(at(14)), isNull);
    p.accept(
      CampusFix(const CampusPoint(0, 0), 3, at(30)),
      onCampus: true,
      now: at(15),
    );
    expect(p.state, SpotState.unavailable);
    fix(p, 31, campus: false);
    expect(p.state, SpotState.outsideCampus);
    expect(p.launch(at(31)), isNull);
    p.unavailable();
    expect(p.launch(at(32)), isNull);
  });
  test('accuracy uncertainty cannot count as entry', () {
    final p = SpotProximity([a]);
    fix(p, 0, lon: 0.00018, accuracy: 10);
    fix(p, 3, lon: 0.00018, accuracy: 10);
    expect(p.state, SpotState.outsideRange);
  });
  test(
    'overlap picks nearest once and remains stable across distance noise',
    () {
      final p = arrived([b, a]);
      expect(p.selected, a);
      fix(p, 4, lon: 0.00005);
      expect(p.selected, a);
      p.dismiss();
      fix(p, 5);
      expect(p.selected, isNull);
      expect(p.state, SpotState.dismissed);
    },
  );
  test(
    'dismiss requires genuine leave/re-entry, not GPS loss or one outlier',
    () {
      final p = arrived();
      p.dismiss();
      p.unavailable(); // permission denial or app background
      fix(p, 4);
      fix(p, 7);
      expect(p.state, SpotState.dismissed);
      fix(p, 8, lon: 0.001);
      fix(p, 9);
      fix(p, 12);
      expect(p.state, SpotState.dismissed);
      fix(p, 13, lon: 0.001);
      fix(p, 16, lon: 0.001);
      fix(p, 17);
      fix(p, 20);
      expect(p.state, SpotState.eligible);
    },
  );
  test(
    'only one launch; GPS noise during game never closes it; close suppresses',
    () {
      final p = arrived();
      expect(p.launch(at(3)), a);
      expect(p.launch(at(3)), isNull);
      p.unavailable();
      expect(p.state, SpotState.active);
      fix(p, 4);
      fix(p, 7);
      expect(p.launch(at(7)), isNull);
      p.close(at(7));
      expect(p.state, SpotState.dismissed);
      expect(p.launch(at(7)), isNull);
    },
  );
  test('Play rechecks stale fix and dwell resets after long stream gap', () {
    final p = arrived();
    expect(p.launch(at(20)), isNull);
    fix(p, 21);
    expect(p.state, SpotState.outsideRange);
    fix(p, 24);
    expect(p.launch(at(24)), a);
  });
  test(
    'closing after in-game departure and GPS loss still suppresses arrival',
    () {
      final p = arrived();
      p.launch(at(3));
      fix(p, 4, lon: 0.001);
      fix(p, 7, lon: 0.001); // departure clears original suppression
      p.unavailable();
      p.close(at(8));
      fix(p, 9);
      fix(p, 12);
      expect(p.state, SpotState.dismissed);
      expect(p.launch(at(12)), isNull);
    },
  );
  test('disabled spots and replayed fixes do not qualify', () {
    final p = SpotProximity([
      a,
      const GameSpot(
        id: 'off',
        name: 'Off',
        point: CampusPoint(0, 0),
        enabled: false,
      ),
    ]);
    fix(p, 0);
    p.accept(
      CampusFix(const CampusPoint(0, 0), 3, at(0)),
      onCampus: true,
      now: at(3),
    );
    expect(p.state, SpotState.outsideRange);
    fix(p, 3);
    expect(p.selected, a);
    expect(productionGameSpots, [chapelSpot]);
    expect(chapelSpot.attackMeters, 39.624);
  });
}
