import 'campus_geography.dart';
import 'dart:math' as math;

/// The default is a close exploration view; View campus remains a separate fit.
abstract final class CampusPresentation {
  static const pitch = 55.0;
  static const overviewPitch = 55.0;
  static const explorationZoom = 16.8;
  static const followZoom = 17.5;
  static const academicCore = CampusPoint(-98.1740, 26.3067);

  /// About 220 m across the padded screen at the focus point. Wider viewports
  /// use a closer zoom to retain the same useful neighborhood scale.
  static double zoomForViewport(double width) {
    final metersPerWorld =
        40075016.686 * math.cos(academicCore.latitude * math.pi / 180);
    return (math.log(metersPerWorld * math.max(200, width - 48) / (512 * 220)) /
            math.ln2)
        .clamp(16.0, 17.5);
  }

  /// Place the GPS player lower in the scene, leaving room to see ahead.
  static double explorationTopPadding(double height) =>
      height < 400 ? 80 : height * 0.35;
}

class CampusCameraSession {
  double explorationZoom = CampusPresentation.explorationZoom;
  bool isOverview = false;

  void initialize(double viewportWidth) {
    explorationZoom = CampusPresentation.zoomForViewport(viewportWidth);
    isOverview = false;
  }

  void viewCampus() => isOverview = true;
  void explore() => isOverview = false;

  void rememberZoom(double zoom) {
    if (!isOverview && zoom.isFinite) explorationZoom = zoom.clamp(12, 19.5);
  }
}
