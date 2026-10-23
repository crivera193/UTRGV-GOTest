import 'dart:async';
import 'package:campus_app/games/point_catalog.dart';
import 'package:campus_app/games/game_spot.dart';
import 'package:campus_app/games/spot_proximity.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chapel_capture_test.dart' show pointFixture;

class CatalogTransport implements PointCatalogRepository {
  List<LiveGamePoint> rows = [];
  final changes = StreamController<List<LiveGamePoint>>();
  @override
  Future<List<LiveGamePoint>> load() async => rows;
  @override
  Stream<List<LiveGamePoint>> watch() => changes.stream;
}

void main() {
  test(
    'catalog adds, moves, renames and removes stable IDs without restart',
    () async {
      final transport = CatalogTransport();
      final catalog = PointCatalog(transport);
      await catalog.load();
      expect(catalog.loaded, isTrue);
      expect(catalog.points, isEmpty);
      final original = LiveGamePoint.fromJson(pointFixture());
      transport.changes.add([original]);
      await Future<void>.delayed(Duration.zero);
      expect(catalog.find(original.id)!.name, original.name);
      final changed = LiveGamePoint.fromJson({
        ...pointFixture(),
        'name': 'Moved point',
        'longitude': .001,
        'revision': 2,
        'rules': {
          ...original.rules.toJson(),
          'questions_total': 7,
          'question_seconds': 9,
          'max_damage_percent': 30,
          'cooldown_seconds': 42,
          'version': 2,
        },
      });
      transport.changes.add([changed]);
      await Future<void>.delayed(Duration.zero);
      expect(catalog.find(original.id)!.point.longitude, .001);
      expect(catalog.find(original.id)!.rules.questionsTotal, 7);
      expect(catalog.find(original.id)!.rules.summary, contains('9 seconds'));
      transport.changes.addError(StateError('Disconnected'));
      await Future<void>.delayed(Duration.zero);
      expect(catalog.error, isNotNull);
      expect(catalog.find(original.id)!.name, 'Moved point');
      transport.changes.add([]);
      await Future<void>.delayed(Duration.zero);
      expect(catalog.error, isNull);
      expect(catalog.find(original.id), isNull);
      catalog.dispose();
      await transport.changes.close();
    },
  );

  test('moving a point invalidates accumulated proximity dwell', () {
    const original = GameSpot(
      id: 'stable-id',
      name: 'First name',
      point: CampusPoint(0, 0),
    );
    final proximity = SpotProximity([original]);
    final epoch = DateTime.utc(2026, 10, 22);
    for (final second in [0, 3]) {
      final now = epoch.add(Duration(seconds: second));
      proximity.accept(
        CampusFix(const CampusPoint(0, 0), 1, now),
        onCampus: true,
        now: now,
      );
    }
    expect(proximity.state, SpotState.eligible);
    proximity.replaceSpots(const [
      GameSpot(id: 'stable-id', name: 'Moved', point: CampusPoint(.01, 0)),
    ], epoch.add(const Duration(seconds: 4)));
    expect(proximity.launch(epoch.add(const Duration(seconds: 4))), isNull);
    proximity.replaceSpots([], epoch.add(const Duration(seconds: 5)));
    expect(proximity.selected, isNull);
  });

  test('live point data is required and invalid rules fail closed', () {
    final row = pointFixture();
    expect(
      () => LiveGamePoint.fromJson({...row, 'rules': null}),
      throwsA(anything),
    );
    for (final invalid in [0, 21]) {
      expect(
        () => LiveGamePoint.fromJson({
          ...row,
          'rules': {...row['rules'] as Map, 'questions_total': invalid},
        }),
        throwsFormatException,
      );
    }
  });
}
