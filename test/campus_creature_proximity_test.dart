import 'package:campus_app/map/campus_creatures.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 10, 23);
  for (final landmark in CampusCreatureLandmark.all) {
    test('${landmark.id} reveals independently and expires like cats', () {
      final gates = CampusCreatureProximity(CampusCreatureLandmark.all);
      void fix(
        int t, {
        double meters = 0,
        double accuracy = 5,
        bool onCampus = true,
      }) {
        gates.accept(
          CampusFix(
            CampusPoint(
              landmark.point.longitude,
              landmark.point.latitude + meters / 111195,
            ),
            accuracy,
            start.add(Duration(seconds: t)),
          ),
          onCampus: onCampus,
          now: start.add(Duration(seconds: t)),
        );
      }

      expect(gates.anyVisible, isFalse);
      fix(0, meters: 100);
      fix(1, meters: 29);
      expect(gates.visible(landmark.id), isFalse);
      fix(3, meters: 29);
      expect(gates.visible(landmark.id), isTrue);
      for (final other in CampusCreatureLandmark.all.where(
        (v) => v.id != landmark.id,
      )) {
        expect(gates.visible(other.id), isFalse);
      }
      fix(4, meters: 40);
      expect(gates.visible(landmark.id), isTrue);
      fix(5, meters: 46);
      expect(gates.anyVisible, isFalse);
      fix(6);
      fix(8);
      expect(gates.visible(landmark.id), isTrue);
      gates.refresh(start.add(const Duration(seconds: 19)));
      expect(gates.anyVisible, isFalse);
      fix(20);
      fix(22, accuracy: 21);
      expect(gates.anyVisible, isFalse);
      fix(23);
      fix(25, onCampus: false);
      expect(gates.anyVisible, isFalse);
      fix(26);
      fix(28);
      expect(gates.visible(landmark.id), isTrue);
      gates.unavailable();
      expect(gates.anyVisible, isFalse);
    });
  }
}
