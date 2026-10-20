import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gps;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';
import '../map/campus_geography.dart';
import '../map/campus_location.dart';
import '../map/campus_style.dart';
import '../widgets/mapbox_configuration_notice.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  MapboxMap? _map;
  CampusGeography? _geography;
  CampusLocationPolicy? _location;
  CameraViewportState? _initialViewport;
  StreamSubscription<gps.Position>? _positions;
  StreamSubscription<gps.ServiceStatus>? _services;
  Timer? _expiry;
  String? _styleJson, _styleUri, _error;
  bool _ready = false, _styleLoaded = false, _following = false;
  bool _requesting = false, _locationEnabled = false, _hasFitted = false;
  bool _configured = false, _fitting = false;
  double _minZoom = 12;
  Size? _size;
  int _locationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (hasMapboxConfiguration) unawaited(_loadCampus());
  }

  Future<void> _loadCampus() async {
    try {
      final boundary = await rootBundle.loadString(
        'assets/campus/boundary.geojson',
      );
      final data = await rootBundle.loadString(
        'assets/campus/features.geojson',
      );
      final geography = CampusGeography.fromGeoJson(boundary);
      final style = jsonEncode(CampusStyle.build(boundary, data));
      // Pass a local style at native construction; never request Standard.
      // Only public geographic data is cached, never location or credentials.
      final dir = await Directory.systemTemp.createTemp('utrgv-campus-');
      final file = await File(
        '${dir.path}/style.json',
      ).writeAsString(style, flush: true);
      if (!mounted) return;
      setState(() {
        _geography = geography;
        _location = CampusLocationPolicy(geography);
        _styleJson = style;
        _styleUri = file.uri.toString();
        _initialViewport = CameraViewportState(
          center: _point(geography.center),
          zoom: 14,
          pitch: 45,
          bearing: 0,
        );
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load campus data.');
    }
  }

  Point _point(CampusPoint p) =>
      Point(coordinates: Position(p.longitude, p.latitude));

  Future<void> _configureMap(MapboxMap map) async {
    final c = _geography!;
    await map.setBounds(
      CameraBoundsOptions(
        bounds: CoordinateBounds(
          southwest: _point(CampusPoint(c.west, c.south)),
          northeast: _point(CampusPoint(c.east, c.north)),
          infiniteBounds: false,
        ),
        minZoom: _minZoom,
        maxZoom: 19.5,
        minPitch: 45,
        maxPitch: 45,
      ),
    );
    await map.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: false,
        simultaneousRotateAndPinchToZoomEnabled: false,
        pitchEnabled: false,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
      ),
    );
    // A native unfiltered puck could appear outside campus. Use filtered source.
    await map.location.updateSettings(
      LocationComponentSettings(enabled: false),
    );
    // Leave Mapbox logo, attribution and telemetry controls intact.
  }

  Future<void> _finishStyle() async {
    if (_map == null || !_styleLoaded || !_configured) return;
    try {
      if (!mounted) return;
      await _renderPlayer();
      if (!_hasFitted) {
        await _viewCampus();
        _hasFitted = true;
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to prepare campus map. Tap retry.');
      }
    }
  }

  MbxEdgeInsets get _padding => MbxEdgeInsets(
    top: (_size?.height ?? 600) < 400 ? 52 : 76,
    left: 24,
    bottom: (_size?.height ?? 600) < 400 ? 72 : 112,
    right: 24,
  );

  Future<void> _viewCampus() async {
    final map = _map, c = _geography;
    if (map == null || c == null || _fitting) return;
    _fitting = true;
    _following = false;
    // Compute whole-campus fit for the actual viewport. Center and pitch bounds
    // stay enforced even while the minimum zoom is recalculated on resize.
    try {
      await map.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: false,
          pinchToZoomEnabled: false,
          doubleTapToZoomInEnabled: false,
          doubleTouchToZoomOutEnabled: false,
          quickZoomEnabled: false,
        ),
      );
      await map.setBounds(CameraBoundsOptions(minZoom: 12));
      final fit = await map.cameraForCoordinatesPadding(
        c.outerPoints.map(_point).toList(),
        CameraOptions(pitch: 45, bearing: 0, padding: _padding),
        null,
        17,
        null,
      );
      _minZoom = (fit.zoom ?? 14).clamp(12, 19.5);
      await map.setBounds(CameraBoundsOptions(minZoom: _minZoom));
      await _moveCamera(fit);
    } finally {
      _fitting = false;
      await map.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          doubleTapToZoomInEnabled: true,
          doubleTouchToZoomOutEnabled: true,
          quickZoomEnabled: true,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  // Single gateway for all programmatic camera changes.
  Future<void> _moveCamera(CameraOptions camera) async {
    final map = _map, c = _geography;
    if (map == null || c == null || !mounted) return;
    final p = camera.center?.coordinates;
    final center = p == null
        ? c.center
        : CampusPoint(p.lng.toDouble(), p.lat.toDouble());
    await map.setCamera(
      CameraOptions(
        center: _point(c.clampCameraCenter(center)),
        zoom: (camera.zoom ?? 17).clamp(_minZoom, 19.5),
        pitch: 45,
        bearing: 0,
        padding: camera.padding ?? _padding,
      ),
    );
  }

  void _manualCamera() {
    if (_following && mounted) setState(() => _following = false);
  }

  Future<void> _followMe() async {
    if (!_ready || _requesting || _fitting) return;
    if (_location?.marker != null && _locationEnabled) {
      setState(() => _following = true);
      await _followPosition();
      return;
    }
    setState(() => _requesting = true);
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!mounted) return;
      if (!status.isGranted) {
        _location!.clear(CampusGpsState.denied);
        return;
      }
      _locationEnabled = true;
      _following = true;
      await _startGps();
    } catch (_) {
      _location?.clear(CampusGpsState.unavailable);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _showOverview() async {
    try {
      await _viewCampus();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Campus overview could not be fitted. Tap retry.',
        );
      }
    }
  }

  Future<void> _startGps() async {
    await _stopGps();
    final generation = _locationGeneration;
    if (!await gps.Geolocator.isLocationServiceEnabled()) {
      _location!.clear(CampusGpsState.disabled);
    } else {
      _positions =
          gps.Geolocator.getPositionStream(
            locationSettings: const gps.LocationSettings(
              accuracy: gps.LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (!mounted || generation != _locationGeneration) return;
              _location!.accept(
                CampusFix(
                  CampusPoint(p.longitude, p.latitude),
                  p.accuracy,
                  p.timestamp,
                ),
                DateTime.now(),
              );
              unawaited(_refreshLocation());
            },
            onError: (Object _) {
              if (!mounted || generation != _locationGeneration) return;
              _location!.clear(CampusGpsState.unavailable);
              unawaited(_refreshLocation());
            },
          );
      _expiry = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        _location!.expire(DateTime.now());
        unawaited(_refreshLocation());
      });
    }
    _services = gps.Geolocator.getServiceStatusStream().listen((status) {
      if (!mounted || generation != _locationGeneration) return;
      if (status == gps.ServiceStatus.disabled) {
        _location!.clear(CampusGpsState.disabled);
        unawaited(_refreshLocation());
      } else {
        unawaited(_startGps());
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _stopGps() async {
    _locationGeneration++;
    _expiry?.cancel();
    _expiry = null;
    final positions = _positions, services = _services;
    _positions = null;
    _services = null;
    await positions?.cancel();
    await services?.cancel();
  }

  Future<void> _refreshLocation() async {
    if (!mounted) return;
    if (_location?.marker == null &&
        _location?.state != CampusGpsState.waiting) {
      _following = false;
    }
    setState(() {});
    try {
      await _renderPlayer();
      if (_following) await _followPosition();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Map update interrupted. Tap retry.');
      }
    }
  }

  Future<void> _renderPlayer() async {
    if (_map == null || !_styleLoaded) return;
    final p = _location?.marker;
    final data = p == null
        ? CampusStyle.empty
        : {
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'properties': <String, Object>{},
                'geometry': {'type': 'Point', 'coordinates': p.coordinates},
              },
            ],
          };
    await _map!.style.setStyleSourceProperty(
      'player',
      'data',
      jsonEncode(data),
    );
  }

  Future<void> _followPosition() async {
    final p = _location?.marker;
    if (p != null && _following) {
      await _moveCamera(CameraOptions(center: _point(p), zoom: 17.5));
    }
  }

  Future<void> _reloadStyle() async {
    if (_map == null || _styleJson == null) {
      await _loadCampus();
      return;
    }
    setState(() {
      _ready = false;
      _styleLoaded = false;
      _error = null;
    });
    try {
      if (!_configured) {
        await _configureMap(_map!);
        _configured = true;
      }
      await _map!.loadStyleJson(_styleJson!);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Campus style could not be reloaded.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _following = false;
      _location?.clear(CampusGpsState.stale);
      unawaited(_stopGps());
    } else if (state == AppLifecycleState.resumed && _locationEnabled) {
      unawaited(_resumeGps());
    }
  }

  Future<void> _resumeGps() async {
    try {
      await _renderPlayer();
      await _startGps();
    } catch (_) {
      if (mounted) setState(() => _location?.clear(CampusGpsState.unavailable));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopGps());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!hasMapboxConfiguration) return const MapboxConfigurationNotice();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_size != size) {
          final previous = _size;
          _size = size;
          if (previous != null && _ready) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_showOverview());
            });
          }
        }
        return ColoredBox(
          color: const Color(0xffe8eee7),
          child: Stack(
            children: [
              if (_styleUri != null)
                MapWidget(
                  key: const ValueKey('campus-exploration-map'),
                  styleUri: _styleUri!,
                  viewport: _initialViewport,
                  onMapCreated: (map) async {
                    _map = map;
                    try {
                      await _configureMap(map);
                      _configured = true;
                      await _finishStyle();
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'Campus camera could not initialize.',
                        );
                      }
                    }
                  },
                  onStyleLoadedListener: (_) {
                    _styleLoaded = true;
                    unawaited(_finishStyle());
                  },
                  onScrollListener: (_) => _manualCamera(),
                  onZoomListener: (_) => _manualCamera(),
                  onMapLoadErrorListener: (event) {
                    // Glyph failure should not hide locally bundled geography.
                    if (event.type == MapLoadErrorType.GLYPHS) return;
                    if (mounted) {
                      setState(
                        () => _error = 'Campus map could not load. Tap retry.',
                      );
                    }
                  },
                ),
              if (!_ready || _error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xffe8eee7),
                    child: Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                TextButton(
                                  onPressed: _reloadStyle,
                                  child: const Text('Retry campus map'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              if (_ready && _error == null) ...[
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Card(
                      color: const Color(0xfff6f9ee),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _location!.message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 44,
                  left: 12,
                  right: 12,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(_showOverview()),
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('View campus'),
                      ),
                      FilledButton.icon(
                        onPressed: _requesting ? null : _followMe,
                        icon: Icon(
                          _following ? Icons.gps_fixed : Icons.my_location,
                        ),
                        label: Text(
                          _requesting
                              ? 'Finding GPS…'
                              : _following
                              ? 'Following'
                              : 'Follow me',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
