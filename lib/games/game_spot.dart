import 'package:flutter/foundation.dart';
import '../map/campus_geography.dart';

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
    this.entryMeters = ProximitySettings.entryMeters,
    this.exitMeters = ProximitySettings.exitMeters,
  }) : assert(entryMeters > 0 && exitMeters > entryMeters);

  final String id, name, gameId;
  final CampusPoint point;
  final bool enabled;
  final double entryMeters, exitMeters;
}

// No pedestrian launch point has been verified for production yet.
const productionGameSpots = <GameSpot>[];
const debugGameSpotsEnabled =
    kDebugMode && bool.fromEnvironment('GAME_SPOTS_DEMO');
// Reuses the legacy fountain record, NOT a verified safe outdoor destination.
// Only for developer demonstration; never included in release/profile builds.
const debugDemoSpot = GameSpot(
  id: 'debug-fountain-preview',
  name: 'DEBUG ONLY · fountain demonstration (unverified)',
  point: CampusPoint(-98.176061, 26.304802),
);

List<GameSpot> get configuredGameSpots => [
  ...productionGameSpots,
  if (debugGameSpotsEnabled) debugDemoSpot,
];
