import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart' as gps;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';
import '../games/game_host.dart';
import '../games/chapel_capture.dart';
import '../games/chapel_card.dart';
import '../games/game_spot.dart';
import '../games/spot_proximity.dart';
import '../map/campus_geography.dart';
import '../map/campus_location.dart';
import '../map/campus_style.dart';
import '../map/campus_presentation.dart';
import '../map/campus_zoom_controls.dart';
import '../player/cowboy_motion.dart';
import '../player/cowboy_travel.dart';
import '../player/latest_projection.dart';
import '../player/cowboy_sprite.dart';
import '../widgets/mapbox_configuration_notice.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  final _travel = CowboyTravel();
  final _cowboyPlacement = ValueNotifier<CowboyPlacement?>(null);
  late final Ticker _travelTicker;
  late final LatestProjection<CowboyPlacement> _projector;
  CameraState? _cameraState;
  Duration? _previousTravelTick;
  Duration _lastProjectionTick = Duration.zero, _lastFollowTick = Duration.zero;
  bool _followBusy = false, _followQueued = false, _followNeedsZoom = false;
  CampusPoint? _lastFollowCenter;
  bool _foreground = true;
  final _proximity = SpotProximity(configuredGameSpots);
  bool _gameOpen = false, _chapelCardOpen = false;
  final _chapel = ChapelPoint(LocalPointPersistence());
  final _chapelPlacement = ValueNotifier<Offset?>(null);
  late final LatestProjection<Offset> _chapelProjector;
  String? _chapelLoadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapelProjector = LatestProjection<Offset>(
      read: () async {
        if (_map == null || !_styleLoaded || !_foreground) return null;
        final pixel = await _map!.pixelForCoordinate(
          _point(ChapelConfig.point),
        );
        if (!pixel.x.isFinite || !pixel.y.isFinite) return null;
        return Offset(pixel.x, pixel.y);
      },
      apply: (value) {
        if (mounted) _chapelPlacement.value = value;
      },
    );
    unawaited(
      _chapel.load().catchError((Object _) {
        if (mounted) {
          setState(() => _chapelLoadError = 'Local point storage unavailable.');
        }
      }),
    );
    _projector = LatestProjection<CowboyPlacement>(
      read: _readCowboyProjection,
      apply: (placement) {
        if (mounted) _cowboyPlacement.value = placement;
      },
    );
    _travelTicker = createTicker(_advanceTravel);
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
      await _chapelProjector.request(invalidate: true);
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
    _followQueued = false;
    if (!_gameOpen && _following && mounted) setState(() => _following = false);
  }

  void _cameraChanged(CameraChangedEventData event) {
    _cameraState = event.cameraState;
    unawaited(_chapelProjector.request(invalidate: true));
    if (_hasFitted && !_fitting) {
      _cameraSession.rememberZoom(event.cameraState.zoom);
    }
    unawaited(_projector.request(invalidate: true));
  }

  Future<void> _followMe() async {
    if (!_ready || _requesting || _fitting) return;
    _followNeedsZoom = true;
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
    _clearTravel();
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
              _projector.cancel();
              _cowboyMotion.accept(
                longitude: p.longitude,
                latitude: p.latitude,
                accuracy: p.accuracy,
                timestamp: p.timestamp,
                now: DateTime.now(),
                onCampus: _location!.state == CampusGpsState.onCampus,
                measuredSpeed: p.hasSpeed ? p.speed : null,
                speedAccuracy: p.hasSpeedAccuracy ? p.speedAccuracy : null,
              );
              final fixAge = DateTime.now()
                  .difference(p.timestamp)
                  .inMilliseconds;
              if (_location!.state == CampusGpsState.onCampus &&
                  fixAge >= -2000 &&
                  fixAge <= 6000) {
                _travel.accept(
                  CampusPoint(p.longitude, p.latitude),
                  p.timestamp,
                  accuracy: p.accuracy,
                  walking: _cowboyMotion.walking,
                );
                if (_travel.moving && !_travelTicker.isActive && !_gameOpen) {
                  _previousTravelTick = null;
                  _lastProjectionTick = _lastFollowTick = Duration.zero;
                  _travelTicker.start();
                }
              } else {
                _clearTravel();
              }
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
    _clearTravel();
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
      _clearTravel();
      _cowboyMotion.stop();
      _projector.cancel();
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
    final p = _location?.marker == null ? null : _travel.target;
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

  void _clearTravel() {
    _travel.clear();
    _travelTicker.stop();
    _previousTravelTick = null;
    _projector.cancel();
    _cowboyPlacement.value = null;
  }

  void _advanceTravel(Duration elapsed) {
    if (!_foreground || _gameOpen || _location?.marker == null) {
      _travelTicker.stop();
      _previousTravelTick = null;
      return;
    }
    final dt = _previousTravelTick == null
        ? 0.0
        : (elapsed - _previousTravelTick!).inMicroseconds / 1000000;
    _previousTravelTick = elapsed;
    final changed = _travel.advance(dt, contains: _geography!.contains);
    if (changed &&
        elapsed - _lastProjectionTick >= const Duration(milliseconds: 33)) {
      _lastProjectionTick = elapsed;
      unawaited(_projectCowboy());
    }
    if (changed &&
        _following &&
        elapsed - _lastFollowTick >= const Duration(milliseconds: 66)) {
      _lastFollowTick = elapsed;
      unawaited(_followPosition());
    }
    if (!_travel.moving) {
      _travelTicker.stop();
      _previousTravelTick = null;
      unawaited(_projectCowboy());
      if (_following) unawaited(_followPosition());
    }
  }

  Future<void> _projectCowboy() => _projector.request();

  // One logical-pixel projection per native read. Latest camera event supplies
  // bearing/pitch; camera/new-fix invalidation discards an obsolete reply.
  Future<CowboyPlacement?> _readCowboyProjection() async {
    final map = _map, p = _travel.position;
    if (map == null ||
        !_styleLoaded ||
        !_foreground ||
        _gameOpen ||
        _location?.marker == null ||
        p == null) {
      return null;
    }
    final camera = _cameraState ?? await map.getCameraState();
    final screen = await map.pixelForCoordinate(_point(p));
    final size = _size;
    if (size == null ||
        !screen.x.isFinite ||
        !screen.y.isFinite ||
        screen.x < 0 ||
        screen.y < 0 ||
        screen.x > size.width ||
        screen.y > size.height) {
      return null;
    }
    return CowboyPlacement(
      Offset(screen.x, screen.y),
      camera.bearing,
      camera.pitch,
      camera.zoom,
    );
  }

  Future<void> _followPosition() async {
    _followQueued = true;
    if (_followBusy) return;
    _followBusy = true;
    try {
      while (_followQueued &&
          mounted &&
          _following &&
          _foreground &&
          !_gameOpen) {
        _followQueued = false;
        final map = _map, c = _geography, p = _travel.position;
        if (map == null || c == null || p == null) break;
        if (!_followNeedsZoom &&
            _lastFollowCenter != null &&
            CampusGeography.distance(_lastFollowCenter!, p) < 0.02) {
          continue;
        }
        _lastFollowCenter = p;
        if (_followNeedsZoom) {
          _followNeedsZoom = false;
          await _moveCamera(
            CameraOptions(
              center: _point(p),
              zoom: _cameraSession.explorationZoom,
            ),
          );
        } else {
          // Already interpolated: one serial center update, no competing easing,
          // no repeated zoom/pitch reset on every GPS sample.
          await map.setCamera(
            CameraOptions(center: _point(c.clampCameraCenter(p))),
          );
        }
      }
    } finally {
      _followBusy = false;
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
      _projector.cancel();
      _cowboyMotion.stop();
      _clearTravel();
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

  String? _chapelAttackReason() {
    if (_chapel.busy) return 'Saving local point state…';
    if (!_foreground || !_chapel.loaded) {
      return _chapelLoadError ?? 'Loading local point state…';
    }
    if (_location?.state != CampusGpsState.onCampus) {
      return 'Enable GPS and move safely onto campus.';
    }
    return _proximity.attackReason(chapelSpot, DateTime.now());
  }

  Future<void> _showChapel() async {
    if (_chapelCardOpen || _gameOpen) return;
    _chapelCardOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => ChapelCard(
          point: _chapel,
          reason: _chapelAttackReason,
          distance: () => _proximity.distanceTo(chapelSpot),
          onAttack: _attackChapel,
        ),
      );
    } finally {
      _chapelCardOpen = false;
    }
  }

  Future<void> _attackChapel() async {
    if (_gameOpen ||
        _chapelAttackReason() != null ||
        _chapel.state.owner == ChapelConfig.playerTeam) {
      return;
    }
    if (!_proximity.launchAttack(chapelSpot, DateTime.now())) return;
    final wasFollowing = _following;
    final attack = CaptureSession(_chapel);
    setState(() => _gameOpen = true);
    try {
      await Navigator.of(context).push<GameExit>(
        MaterialPageRoute(
          builder: (_) => GameHost(
            gameId: 'chapel-football',
            session: GameSessionContext(
              spotId: ChapelConfig.id,
              startedAt: DateTime.now(),
              capture: attack,
            ),
          ),
        ),
      );
    } finally {
      attack.close();
      _proximity.close(DateTime.now());
      if (mounted) {
        setState(() {
          _gameOpen = false;
          _following = wasFollowing;
        });
        unawaited(_renderPlayer());
      }
    }
  }

  Future<void> _openGame({bool debug = false}) async {
    if (!debug && _proximity.selected?.id == ChapelConfig.id) {
      await _showChapel();
      return;
    }
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
    _travelTicker.dispose();
    _projector.dispose();
    _cowboyPlacement.dispose();
    _chapelProjector.dispose();
    _chapelPlacement.dispose();
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
              if (_ready)
                ValueListenableBuilder<Offset?>(
                  valueListenable: _chapelPlacement,
                  builder: (context, position, _) {
                    if (position == null ||
                        position.dx < 0 ||
                        position.dy < 0 ||
                        position.dx > (_size?.width ?? 0) ||
                        position.dy > (_size?.height ?? 0)) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      left: position.dx - 38,
                      top: position.dy - 88,
                      width: 76,
                      child: ListenableBuilder(
                        listenable: _chapel,
                        builder: (context, _) => ChapelBeacon(
                          owner: _chapel.state.owner,
                          onTap: _showChapel,
                        ),
                      ),
                    );
                  },
                ),
              CowboySprite(
                key: const ValueKey('persistent-campus-cowboy'),
                motion: _cowboyMotion,
                placement: _cowboyPlacement,
                active: _ready && _error == null && _foreground && !_gameOpen,
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
                        onPressed: _showChapel,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Chapel Point'),
                      ),
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
