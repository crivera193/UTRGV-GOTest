import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'campus_geography.dart';
import 'campus_location.dart';
import 'kitty_island.dart';

/// Owner-selected buildings. Heights match the bundled map extrusions.
class CampusCreatureLandmark {
  const CampusCreatureLandmark({
    required this.id,
    required this.point,
    required this.asset,
    required this.roofMeters,
    required this.width,
    required this.aspectRatio,
    this.anchor = const Offset(.5, .97),
    this.poster,
  });
  final String id, asset;
  final String? poster;
  final CampusPoint point;
  final double roofMeters, width, aspectRatio;
  final Offset anchor;

  static const all = [
    CampusCreatureLandmark(
      id: 'computer-science-dragon',
      point: CampusPoint(-98.1747739, 26.3062088),
      asset: 'assets/animations/campus-creatures/dragon.webp',
      poster: 'assets/animations/campus-creatures/dragon-still.png',
      roofMeters: 10.9,
      width: 180,
      aspectRatio: 716 / 504,
      anchor: Offset(470 / 716, 493 / 504),
    ),
    CampusCreatureLandmark(
      id: 'school-of-medicine-floral',
      point: CampusPoint(-98.17508, 26.30995),
      asset: 'assets/animations/campus-creatures/floral.json',
      roofMeters: 9.4,
      width: 145,
      aspectRatio: 1,
    ),
  ];

  double widthAtZoom(double zoom) =>
      (width * math.pow(2, zoom - 17.8)).clamp(55, 260).toDouble();

  /// Ground projection plus the vertical rise of the local roof. These are
  /// camera-facing decorations, with approximate roof alignment, not 3D meshes.
  double roofRise(double zoom, double pitch) {
    final metersPerPixel =
        40075016.686 *
        math.cos(point.latitude * math.pi / 180) /
        (512 * math.pow(2, zoom));
    return roofMeters / metersPerPixel * math.sin(pitch * math.pi / 180);
  }
}

class CampusCreaturePlacement {
  const CampusCreaturePlacement(this.landmark, this.position, this.width);
  final CampusCreatureLandmark landmark;
  final Offset position;
  final double width;
}

/// One arrival gate per catalog landmark, sharing the cats' raw-GPS policy.
class CampusCreatureProximity {
  CampusCreatureProximity(Iterable<CampusCreatureLandmark> landmarks)
    : _gates = {
        for (final landmark in landmarks)
          landmark.id: KittyIslandProximity(center: landmark.point),
      };
  final Map<String, KittyIslandProximity> _gates;
  bool visible(String id) => _gates[id]?.visible ?? false;
  bool get anyVisible => _gates.values.any((gate) => gate.visible);
  void accept(CampusFix fix, {required bool onCampus, required DateTime now}) {
    for (final gate in _gates.values) {
      gate.accept(fix, onCampus: onCampus, now: now);
    }
  }

  void refresh(DateTime now) {
    for (final gate in _gates.values) {
      gate.refresh(now);
    }
  }

  void unavailable() {
    for (final gate in _gates.values) {
      gate.unavailable();
    }
  }
}
