import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as gps;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';
import '../games/game_host.dart';
import '../games/game_spot.dart';
import '../games/spot_proximity.dart';
import '../map/campus_geography.dart';
import '../map/campus_location.dart';
import '../map/campus_style.dart';
import '../map/campus_presentation.dart';
import '../map/campus_zoom_controls.dart';
import '../player/cowboy_motion.dart';
import '../player/cowboy_sprite.dart';
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
  final _cameraSession = CampusCameraSession();
  double _minZoom = 12;
  Size? _size;
  int _locationGeneration = 0;
  final _cowboyMotion = CowboyMotion();
  Offset? _cowboyGround;
  double _cameraBearing = 0,
      _cameraPitch = CampusPresentation.pitch,
      _cameraZoom = 14;
  int _projectionGeneration = 0;
  bool _projectionBusy = false, _projectionQueued = false;
  bool _foreground = true;
  final _proximity = SpotProximity(configuredGameSpots);
  bool _gameOpen = false;

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
      _cameraSession.initialize(_size?.width ?? 390);
      setState(() {
        _geography = geography;
        _location = CampusLocationPolicy(geography);
        _styleJson = style;
        _styleUri = file.uri.toString();
        _initialViewport = CameraViewportState(
          center: _point(CampusPresentation.academicCore),
          zoom: _cameraSession.explorationZoom,
          pitch: CampusPresentation.pitch,
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
        minPitch: CampusPresentation.pitch,
        maxPitch: CampusPresentation.pitch,
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
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    // Leave Mapbox logo, attribution and telemetry controls intact.
  }

  Future<void> _finishStyle() async {
    if (_map == null || !_styleLoaded || !_configured) return;
    try {
      if (!mounted) return;
      await _renderPlayer();
      if (!_hasFitted) {
        await _viewCampus();
        _cameraSession.explore();
        await _moveCamera(
          CameraOptions(
            center: _point(CampusPresentation.academicCore),
            zoom: _cameraSession.explorationZoom,
            padding: _explorationPadding,
          ),
        );
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

  MbxEdgeInsets get _explorationPadding => MbxEdgeInsets(
    top: CampusPresentation.explorationTopPadding(_size?.height ?? 600),
    left: 24,
    right: 24,
    bottom: (_size?.height ?? 600) < 400 ? 64 : 100,
  );

  Future<void> _zoomBy(double delta) async {
    final map = _map;
    if (map == null || !_ready || _fitting) return;
    _manualCamera();
    try {
      final camera = await map.getCameraState();
      _cameraSession.explore();
      _cameraSession.rememberZoom((camera.zoom + delta).clamp(_minZoom, 19.5));
      await _moveCamera(
        CameraOptions(
          center: camera.center,
          zoom: camera.zoom + delta,
          padding: camera.padding,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to change map zoom. Tap retry.');
      }
    }
  }

  Future<void> _viewCampus() async {
    final map = _map, c = _geography;
    if (map == null || c == null || _fitting || _gameOpen) return;
    _fitting = true;
    _following = false;
    _cameraSession.viewCampus();
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
        CameraOptions(
          pitch: CampusPresentation.pitch,
          bearing: 0,
          padding: _padding,
        ),
        null,
        17,
        null,
      );
      _minZoom = (fit.zoom ?? 14).clamp(12, 19.5);
      await map.setBounds(CameraBoundsOptions(minZoom: _minZoom));
      fit.padding = _padding;
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
    if (map == null || c == null || !mounted || _gameOpen) return;
    final p = camera.center?.coordinates;
    final center = p == null
        ? c.center
        : CampusPoint(p.lng.toDouble(), p.lat.toDouble());
    await map.setCamera(
      CameraOptions(
        center: _point(c.clampCameraCenter(center)),
        zoom: (camera.zoom ?? 17).clamp(_minZoom, 19.5),
        pitch: CampusPresentation.pitch,
        bearing: 0,
        padding: camera.padding ?? _explorationPadding,
      ),
    );
  }

  void _manualCamera() {
    if (!_gameOpen && _following && mounted) setState(() => _following = false);
  }

  void _cameraChanged(CameraChangedEventData event) {
    if (_hasFitted && !_fitting) {
      _cameraSession.rememberZoom(event.cameraState.zoom);
    }
    unawaited(_projectCowboy());
  }

  Future<void> _followMe() async {
    if (!_ready || _requesting || _fitting) return;
    _cameraSession.explore();
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
      if (mounted) {
        if (_location?.state != CampusGpsState.onCampus) {
          _proximity.unavailable();
        }
        setState(() => _requesting = false);
      }
    }
  }

  Future<void> _showOverview() async {
    if (_gameOpen) return;
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
    _cowboyMotion.stop();
    _cowboyGround = null;
    _location!.begin(DateTime.now());
    final enabled = await gps.Geolocator.isLocationServiceEnabled();
    if (!mounted || !_foreground || generation != _locationGeneration) return;
    if (!enabled) {
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
              final gameFix = CampusFix(
                CampusPoint(p.longitude, p.latitude),
                p.accuracy,
                p.timestamp,
              );
              _proximity.accept(
                gameFix,
                onCampus: _location!.state == CampusGpsState.onCampus,
                now: DateTime.now(),
              );
              _cowboyMotion.accept(
                longitude: p.longitude,
                latitude: p.latitude,
                accuracy: p.accuracy,
                timestamp: p.timestamp,
                now: DateTime.now(),
                onCampus: _location!.state == CampusGpsState.onCampus,
              );
              unawaited(_refreshLocation());
            },
            onError: (Object _) {
              if (!mounted || generation != _locationGeneration) return;
              _location!.clear(CampusGpsState.unavailable);
              unawaited(_refreshLocation());
            },
          );
      _expiry = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final previousState = _location!.state;
        final wasWalking = _cowboyMotion.walking;
        _location!.expire(DateTime.now());
        final previousSpot = _proximity.state;
        _proximity.refresh(DateTime.now());
        if (previousSpot != _proximity.state && mounted) setState(() {});
        _cowboyMotion.expire(DateTime.now());
        if (previousState != _location!.state ||
            wasWalking != _cowboyMotion.walking) {
          unawaited(_refreshLocation());
        }
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
    _proximity.unavailable();
    _cowboyMotion.stop();
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
    if (_location?.state != CampusGpsState.onCampus &&
        _location?.state != CampusGpsState.outside &&
        _location?.state != CampusGpsState.boundary) {
      _proximity.unavailable();
    }
    if (_gameOpen) return;
    if (_location?.marker == null) {
      _cowboyGround = null;
      _cowboyMotion.stop();
      _projectionGeneration++;
    }
    if (_location?.marker == null &&
        _location?.state != CampusGpsState.waiting) {
      _following = false;
    }
    setState(() {});
    try {
      await _renderPlayer();
      if (_following) await _followPosition();
      await _projectCowboy();
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
    await _projectCowboy();
  }

  // Mapbox returns logical screen pixels. Reproject on GPS and camera changes;
  // camera movement never changes the geographic position or walk evidence.
  Future<void> _projectCowboy() async {
    // Coalesce camera events: slow native calls must not starve all projections
    // while a gesture is ongoing, or create an unbounded queue of native work.
    _projectionQueued = true;
    if (_projectionBusy) return;
    _projectionBusy = true;
    try {
      do {
        _projectionQueued = false;
        await _readCowboyProjection();
      } while (_projectionQueued && mounted);
    } finally {
      _projectionBusy = false;
    }
  }

  Future<void> _readCowboyProjection() async {
    final generation = _projectionGeneration;
    final map = _map;
    final p = _location?.marker;
    if (map == null || !_styleLoaded || !_foreground || p == null) {
      if (mounted && _cowboyGround != null) {
        setState(() => _cowboyGround = null);
      }
      return;
    }
    try {
      final camera = await map.getCameraState();
      final screen = await map.pixelForCoordinate(_point(p));
      if (!mounted ||
          generation != _projectionGeneration ||
          !_foreground ||
          _location?.marker != p) {
        return;
      }
      final size = _size;
      final visible =
          screen.x.isFinite &&
          screen.y.isFinite &&
          size != null &&
          screen.x >= 0 &&
          screen.y >= 0 &&
          screen.x <= size.width &&
          screen.y <= size.height;
      setState(() {
        _cowboyGround = visible ? Offset(screen.x, screen.y) : null;
        _cameraBearing = camera.bearing;
        _cameraPitch = camera.pitch;
        _cameraZoom = camera.zoom;
      });
    } catch (_) {
      if (mounted && generation == _projectionGeneration) {
        setState(() => _cowboyGround = null);
      }
    }
  }

  Future<void> _followPosition() async {
    final p = _location?.marker;
    if (p != null && _following) {
      await _moveCamera(
        CameraOptions(center: _point(p), zoom: _cameraSession.explorationZoom),
      );
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
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _projectionGeneration++;
      _cowboyMotion.stop();
      if (mounted) setState(() => _cowboyGround = null);
      if (!_gameOpen) _following = false;
      _proximity.unavailable();
      _location?.clear(CampusGpsState.stale);
      unawaited(_stopGps());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_locationEnabled) unawaited(_resumeGps());
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

  Future<void> _openGame({bool debug = false}) async {
    if (_gameOpen ||
        !_foreground ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    if (debug && !kDebugMode) return;
    if (!debug && _location?.state != CampusGpsState.onCampus) {
      setState(() => _proximity.unavailable());
      return;
    }
    final spot = debug ? debugDemoSpot : _proximity.launch(DateTime.now());
    if (spot == null) {
      setState(() {});
      return;
    }
    final wasFollowing = _following;
    setState(() => _gameOpen = true);
    try {
      await Navigator.of(context).push<GameExit>(
        MaterialPageRoute(
          builder: (_) => GameHost(
            gameId: spot.gameId,
            session: GameSessionContext(
              spotId: spot.id,
              startedAt: DateTime.now(),
              debug: debug,
            ),
          ),
        ),
      );
    } finally {
      _proximity.close(DateTime.now());
      if (mounted) {
        setState(() {
          _gameOpen = false;
          _following = wasFollowing;
        });
        // Keep the existing map, camera and follow-mode untouched on return.
        // The next real GPS update may move the camera if follow was enabled.
        unawaited(_renderPlayer());
      }
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
          color: const Color(0xffc9ddd3),
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
                  onZoomListener: (_) {
                    _cameraSession.explore();
                    _manualCamera();
                  },
                  onCameraChangeListener: _cameraChanged,
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
                    color: const Color(0xffc9ddd3),
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
              if (kDebugMode)
                Positioned(
                  right: 12,
                  top: 86,
                  child: FilledButton.tonal(
                    onPressed: _gameOpen ? null : () => _openGame(debug: true),
                    child: const Text('DEBUG · Game preview'),
                  ),
                ),
              if (_ready &&
                  !_gameOpen &&
                  _proximity.state == SpotState.eligible)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 116,
                  child: SafeArea(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_proximity.selected!.name),
                            const Text(
                              'You have arrived. Stop walking before playing.',
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => setState(_proximity.dismiss),
                                  child: const Text('Dismiss'),
                                ),
                                FilledButton(
                                  onPressed: _openGame,
                                  child: const Text('Play'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_ready && _error == null) ...[
                Positioned(
                  left: 12,
                  top: 96,
                  child: CampusZoomControls(
                    onZoomIn: () => unawaited(_zoomBy(1)),
                    onZoomOut: () => unawaited(_zoomBy(-1)),
                  ),
                ),
                if (_foreground &&
                    _location?.state == CampusGpsState.onCampus &&
                    _location?.marker != null &&
                    _cowboyGround != null)
                  CowboySprite(
                    motion: _cowboyMotion,
                    ground: _cowboyGround!,
                    bearing: _cameraBearing,
                    pitch: _cameraPitch,
                    zoom: _cameraZoom,
                  ),
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
