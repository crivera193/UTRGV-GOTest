import '../map/campus_geography.dart';
import 'chapel_capture.dart';

abstract final class ProximitySettings {
  static const entryMeters = 25.0;
  static const exitMeters = 40.0;
  static const maxAccuracyMeters = 15.0;
  static const maxFixAge = Duration(seconds: 10);
  static const dwell = Duration(seconds: 3);
}

class GameSpot {
  const GameSpot({
    required this.id,
    required this.name,
    required this.point,
    this.gameId = 'preview',
    this.enabled = true,
    this.attackMeters,
    this.entryMeters = ProximitySettings.entryMeters,
    this.exitMeters = ProximitySettings.exitMeters,
  }) : assert(entryMeters > 0 && exitMeters > entryMeters);

  final String id, name, gameId;
  final CampusPoint point;
  final bool enabled;
  final double entryMeters, exitMeters;
  final double? attackMeters;
}

// Official Concept3D map 1165, location 295835. Play outdoors within radius;
// the separately mapped chapel lawn is ~20 m north of this landmark.
const chapelSpot = GameSpot(
  id: ChapelConfig.id,
  name: ChapelConfig.name,
  point: ChapelConfig.point,
  gameId: 'chapel-football',
  entryMeters: ChapelConfig.attackMeters,
  exitMeters: 45,
  attackMeters: ChapelConfig.attackMeters,
);
const productionGameSpots = <GameSpot>[chapelSpot];
List<GameSpot> get configuredGameSpots => productionGameSpots;
