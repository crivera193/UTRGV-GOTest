import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class BuildingLabel {
  const BuildingLabel({
    required this.id,
    required this.shortName,
    required this.code,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.verifiedName,
  });
  final String id, shortName, code, name;
  final double longitude, latitude;
  final bool verifiedName;

  static List<BuildingLabel> parse(String text) => [
    for (final row in (jsonDecode(text)['labels'] as List))
      BuildingLabel(
        id: row['id'],
        shortName: row['short'],
        code: row['code'],
        name: row['name'],
        longitude: (row['center'][0] as num).toDouble(),
        latitude: (row['center'][1] as num).toDouble(),
        verifiedName: row['verified_name'],
      ),
  ];
}

/// Native roof-elevated symbols: the SDK owns center/perspective at every zoom.
/// There are no screen-coordinate offsets or asynchronous per-frame projections.
class BuildingLabelAnnotations {
  PointAnnotationManager? _manager;
  Cancelable? _taps;
  Future<void>? _loading;
  bool _disposed = false;
  final _byId = <String, BuildingLabel>{};

  Future<void> install(
    MapboxMap map,
    List<BuildingLabel> buildings,
    void Function(BuildingLabel) select, {
    required double pixelRatio,
  }) {
    if (_disposed || _manager != null) return Future.value();
    return _loading ??= _install(
      map,
      buildings,
      select,
      pixelRatio,
    ).whenComplete(() => _loading = null);
  }

  Future<void> _install(
    MapboxMap map,
    List<BuildingLabel> buildings,
    void Function(BuildingLabel) select,
    double pixelRatio,
  ) async {
    final manager = await map.annotations.createPointAnnotationManager(
      id: 'campus-building-short-labels',
    );
    if (_disposed) return;
    await manager.setIconAnchor(IconAnchor.CENTER);
    await manager.setIconPitchAlignment(IconPitchAlignment.VIEWPORT);
    await manager.setIconRotationAlignment(IconRotationAlignment.VIEWPORT);
    await manager.setSymbolZElevate(true);
    await manager.setIconAllowOverlap(false);
    await manager.setIconIgnorePlacement(false);
    await manager.setIconPadding(4);
    final options = <PointAnnotationOptions>[];
    for (final building in buildings) {
      options.add(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(building.longitude, building.latitude),
          ),
          image: await badge(building.shortName),
          iconAnchor: IconAnchor.CENTER,
          // Android's bitmap annotation path consumes physical image pixels.
          // iOS UIImage annotations use points. Keep badges in logical pixels.
          iconSize: defaultTargetPlatform == TargetPlatform.android
              ? pixelRatio / 2
              : .5,
          customData: {'building_id': building.id},
        ),
      );
    }
    if (_disposed) return;
    final annotations = await manager.createMulti(options);
    for (var i = 0; i < annotations.length; i++) {
      final annotation = annotations[i];
      if (annotation != null) _byId[annotation.id] = buildings[i];
    }
    if (_disposed) return;
    _taps = manager.tapEvents(
      onTap: (annotation) {
        final building = _byId[annotation.id];
        if (!_disposed && building != null) select(building);
      },
    );
    _manager = manager;
  }

  static Future<Uint8List> badge(String shortName) async {
    final text = TextPainter(
      text: TextSpan(
        text: shortName,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xfffffff1),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = (text.width + 18).ceil().clamp(36, 100);
    const height = 28;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.5, .5, width - 1, height - 1),
      const Radius.circular(7),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xff805033));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xffeaf5e4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    text.paint(
      canvas,
      Offset((width - text.width) / 2, (height - text.height) / 2),
    );
    text.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width * 2, height * 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> reset(MapboxMap map) async {
    _taps?.cancel();
    _taps = null;
    final manager = _manager;
    _manager = null;
    _byId.clear();
    if (manager != null) await map.annotations.removeAnnotationManager(manager);
  }

  void dispose() {
    _disposed = true;
    _taps?.cancel();
    _byId.clear();
  }
}
