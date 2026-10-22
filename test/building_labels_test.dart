import 'dart:convert';
import 'dart:io';
import 'package:campus_app/map/building_labels.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/widgets/building_name_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final labels = BuildingLabel.parse(
    File('assets/campus/building-labels.json').readAsStringSync(),
  );
  final features =
      (jsonDecode(
            File('assets/campus/features.geojson').readAsStringSync(),
          )['features']
          as List);

  test('every label is inside its own current building footprint', () {
    expect(labels, hasLength(78));
    expect(labels.map((b) => b.id).toSet().length, labels.length);
    for (final label in labels) {
      final identity = label.id.split('#');
      final feature = features
          .where(
            (f) =>
                f['properties']['osm_id'] == identity[0] &&
                f['properties']['kind'] == 'building',
          )
          .elementAt(int.parse(identity[1]));
      final footprint = CampusGeography.fromGeoJson(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [feature],
        }),
      );
      expect(
        footprint.contains(CampusPoint(label.longitude, label.latitude)),
        isTrue,
        reason: label.id,
      );
      expect(label.shortName.trim(), isNotEmpty);
      expect(label.name.trim(), isNotEmpty);
    }
    expect(labels.where((b) => b.verifiedName), hasLength(69));
    expect(labels.singleWhere((b) => b.shortName == 'CS').code, 'EIEAB');
    expect(
      labels.singleWhere((b) => b.shortName == 'LIB').name,
      'University Library',
    );
    expect(labels.singleWhere((b) => b.shortName == 'MED').code, 'EMEBL');
    expect(labels.any((b) => b.name.contains('pineapplepie')), isFalse);
  });

  testWidgets('tap detail fits long names and closes at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;
    final building = labels.singleWhere((b) => b.shortName == 'CS');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BuildingNameCard(
              building: building,
              onClose: () => closed = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text(building.name), findsOneWidget);
    expect(find.text('EIEAB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close building name'));
    expect(closed, isTrue);
  });
}
