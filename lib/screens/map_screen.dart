import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart' as gps;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../teams/team_membership.dart';
import '../games/live_attack_repository.dart';
import '../games/point_catalog.dart';
import '../games/game_host.dart';
import '../games/point_attack.dart';
import '../games/point_card.dart';
import '../games/spot_proximity.dart';
import '../map/campus_geography.dart';
import '../map/campus_location.dart';
import '../map/kitty_island.dart';
import '../map/campus_creatures.dart';
import '../map/building_labels.dart';
import '../widgets/building_name_card.dart';
import '../widgets/campus_creature.dart';
import '../widgets/kitty_island_cats.dart';
import '../map/campus_style.dart';
import '../map/campus_presentation.dart';
import '../map/map_lifecycle.dart';
import '../map/map_view_restoration.dart';
import '../map/campus_zoom_controls.dart';
import '../player/cowboy_motion.dart';
import '../player/cowboy_travel.dart';
import '../player/latest_projection.dart';
import '../player/cowboy_sprite.dart';
import '../widgets/mapbox_configuration_notice.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.pointRepository});
  final PointCatalogRepository? pointRepository;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin,
        RestorationMixin {
  MapboxMap? _map;
  final _buildingLabels = BuildingLabelAnnotations();
  List<BuildingLabel> _buildingNames = const [];
  BuildingLabel? _selectedBuilding;
  CampusGeography? _geography;
  CampusLocationPolicy? _location;
  CameraViewportState? _initialViewport;
  StreamSubscription<gps.Position>? _positions;
  StreamSubscription<gps.ServiceStatus>? _services;
  Timer? _expiry;
  String? _styleJson, _styleUri, _error;
  bool _ready = false, _styleLoaded = false, _following = false;
  bool _requesting = false, _locationEnabled = false, _hasFitted = false;
  bool _configured = false, _fitting = false, _disposed = false;
  Future<void>? _finishingStyle;
  final _cameraSession = CampusCameraSession();
  double _minZoom = 12;
  Size? _size;
  int _locationGeneration = 0;
  DateTime? _resumeFixAfter;
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
  final _lifecycle = MapLifecycle();
  bool get _foreground => _lifecycle.foreground;
  final _gpsOperations = SerialMapOperations();
  final _savedView = RestorableMapView();

  @override
  String get restorationId => 'campus-view';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_savedView, 'view');
    final view = _savedView.value;
    if (view != null) {
      _following = view.following;
      _locationEnabled = view.locationEnabled;
      _cameraSession.explorationZoom = view.zoom;
      _cameraSession.isOverview = view.overview;
      if (_ready) unawaited(_restoreView(view));
    }
  }

  void _rememberView() {
    final camera = _cameraState;
    if (!_hasFitted || _fitting || _gameOpen || camera == null) return;
    _savedView.value = MapViewState(
      center: CampusPoint(
        camera.center.coordinates.lng.toDouble(),
        camera.center.coordinates.lat.toDouble(),
      ),
      zoom: camera.zoom,
      overview: _cameraSession.isOverview,
      following: _following,
      locationEnabled: _locationEnabled,
    );
  }

  Future<void> _restoreView(MapViewState view) async {
    _following = view.following;
    _locationEnabled = view.locationEnabled;
    _cameraSession.isOverview = view.overview;
    _cameraSession.explorationZoom = view.zoom;
    await _moveCamera(
      CameraOptions(
        center: _point(view.center),
        zoom: view.zoom,
        padding: view.overview ? _padding : _explorationPadding,
      ),
    );
  }

  final _proximity = SpotProximity(const []);
  final _kittyPlacement = ValueNotifier<List<Offset>?>(null);
  late final LatestProjection<List<Offset>> _kittyProjector;
  final _creaturePlacement = ValueNotifier<List<CampusCreaturePlacement>?>(
    null,
  );
  late final LatestProjection<List<CampusCreaturePlacement>> _creatureProjector;
  bool _gameOpen = false, _pointCardOpen = false, _pointsInitialized = false;
  late final PointCatalog _points;
  GamePoint? _openPoint;
  CaptureSession? _activeAttack;
  final _pointPlacements = ValueNotifier<Map<String, Offset>?>(null);
  late final LatestProjection<Map<String, Offset>> _pointProjector;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _creatureProjector = LatestProjection<List<CampusCreaturePlacement>>(
      read: _readCreatureProjection,
      apply: (value) {
        if (mounted) _creaturePlacement.value = value;
      },
    );
    _kittyProjector = LatestProjection<List<Offset>>(
      read: () async {
        final map = _map;
        if (map == null || !_styleLoaded || !_foreground || _gameOpen) {
          return null;
        }
        final positions = <Offset>[];
        for (final point in KittyIsland.cats) {
          final pixel = await map.pixelForCoordinate(_point(point));
          if (!pixel.x.isFinite || !pixel.y.isFinite) return null;
          positions.add(Offset(pixel.x, pixel.y));
        }
        return positions;
      },
      apply: (value) {
        if (mounted) _kittyPlacement.value = value;
      },
    );
    _pointProjector = LatestProjection<Map<String, Offset>>(
      read: () async {
        final map = _map;
        if (map == null ||
            !_styleLoaded ||
            !_foreground ||
            !_pointsInitialized) {
          return null;
        }
        final snapshot = _points.points;
        if (snapshot.isEmpty) return const {};
        final pixels = await map.pixelsForCoordinates(
          snapshot.map((p) => _point(p.point)).toList(),
        );
        final positions = <String, Offset>{};
        for (var i = 0; i < snapshot.length; i++) {
          final pixel = pixels[i];
          if (pixel != null && pixel.x.isFinite && pixel.y.isFinite) {
            positions[snapshot[i].id] = Offset(pixel.x, pixel.y);
          }
        }
        return positions;
      },
      apply: (value) {
        if (mounted) _pointPlacements.value = value;
      },
    );
    _projector = LatestProjection<CowboyPlacement>(
      read: _readCowboyProjection,
      apply: (placement) {
        if (mounted && _foreground) _cowboyPlacement.value = placement;
      },
    );
    _travelTicker = createTicker(_advanceTravel);
    if (hasMapboxConfiguration) unawaited(_loadCampus());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pointsInitialized) {
      _pointsInitialized = true;
      _points = PointCatalog(
        widget.pointRepository ??
            SupabasePointCatalogRepository(Supabase.instance.client),
      );
      _points.addListener(_pointsChanged);
      unawaited(_points.load());
    }
  }

  void _pointsChanged() {
    if (!mounted) return;
    _proximity.replaceSpots(_points.points, DateTime.now());
    final open = _openPoint;
    if (open != null) {
      final next = _points.find(open.spotId);
      if (next == null) {
        open.retire();
        unawaited(_activeAttack?.refresh());
      } else {
        final moved = next.playVersion != open.spot.playVersion;
        open.applyDefinition(next);
        if (moved) unawaited(_activeAttack?.refresh());
      }
    }
    setState(() {});
    unawaited(_pointProjector.request(invalidate: true));
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
      final buildingNames = BuildingLabel.parse(
        await rootBundle.loadString('assets/campus/building-labels.json'),
      );
      final style = jsonEncode(CampusStyle.build(boundary, data));
      // Pass a local style at native construction; never request Standard.
      // Only public geographic data is cached, never location or credentials.
      final dir = await Directory.systemTemp.createTemp('utrgv-campus-');
      final file = await File(
        '${dir.path}/style.json',
      ).writeAsString(style, flush: true);
      if (!mounted) return;
      final saved = _savedView.value;
      if (saved == null) _cameraSession.initialize(_size?.width ?? 390);
      setState(() {
        _geography = geography;
        _buildingNames = buildingNames;
        _location = CampusLocationPolicy(geography);
        _styleJson = style;
        _styleUri = file.uri.toString();
        _initialViewport = CameraViewportState(
          center: _point(saved?.center ?? CampusPresentation.academicCore),
          zoom: saved?.zoom ?? _cameraSession.explorationZoom,
          pitch: saved?.overview == true
              ? CampusPresentation.overviewPitch
              : CampusPresentation.pitch,
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
          southwest: _point(CampusPoint(c.cameraWest, c.cameraSouth)),
          northeast: _point(CampusPoint(c.cameraEast, c.cameraNorth)),
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

  Future<void> _finishStyle() => _finishingStyle ??= _finishStyleNow()
      .whenComplete(() => _finishingStyle = null);

  Future<void> _finishStyleNow() async {
    if (_map == null || !_styleLoaded || !_configured) return;
    try {
      if (!mounted) return;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      await _renderPlayer();
      await _pointProjector.request(invalidate: true);
      await _buildingLabels.install(_map!, _buildingNames, (building) {
        if (mounted && _foreground && !_gameOpen) {
          setState(() => _selectedBuilding = building);
        }
      }, pixelRatio: pixelRatio);
      if (!_hasFitted) {
        final saved = _savedView.value;
        await _fitCampusViewport();
        _cameraSession.explore();
        await _moveCamera(
          CameraOptions(
            center: _point(CampusPresentation.academicCore),
            zoom: _cameraSession.explorationZoom,
            padding: _explorationPadding,
          ),
        );
        if (saved != null) await _restoreView(saved);
        _hasFitted = true;
        if (saved?.locationEnabled == true && _foreground) {
          unawaited(_resumeGps());
        }
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
        });
        _syncKittyCats();
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

  Future<void> _fitCampusViewport() async {
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
    _rememberView();
  }

  void _cameraChanged(CameraChangedEventData event) {
    _cameraState = event.cameraState;
    _syncKittyCats();
    unawaited(_pointProjector.request(invalidate: true));
    if (_hasFitted && !_fitting) {
      _cameraSession.rememberZoom(event.cameraState.zoom);
    }
    unawaited(_projector.request(invalidate: true));
    _rememberView();
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
        _rememberView();
      }
    }
  }

  Future<void> _refitCampusViewport() async {
    if (_gameOpen) return;
    try {
      await _fitCampusViewport();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Campus overview could not be fitted. Tap retry.',
        );
      }
    }
  }

  Future<void> _startGps({bool resuming = false}) =>
      _gpsOperations.run(() => _startGpsNow(resuming: resuming));

  Future<void> _startGpsNow({bool resuming = false}) async {
    if (_disposed || !mounted || !_foreground) return;
    await _stopGpsNow(preserveDisplay: resuming);
    if (!mounted || !_foreground) return;
    final generation = _locationGeneration;
    _cowboyMotion.stop();
    if (resuming) {
      _location!.resume(DateTime.now());
    } else {
      _clearTravel();
      _location!.begin(DateTime.now());
    }
    final enabled = await gps.Geolocator.isLocationServiceEnabled();
    if (!mounted || !_foreground || generation != _locationGeneration) return;
    if (!enabled) {
      _location!.clear(CampusGpsState.disabled);
      _clearTravel();
      await _renderPlayer();
    } else {
      _positions =
          gps.Geolocator.getPositionStream(
            locationSettings: const gps.LocationSettings(
              accuracy: gps.LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (!mounted ||
                  !_foreground ||
                  generation != _locationGeneration) {
                return;
              }
              final after = _resumeFixAfter;
              if (after != null && !p.timestamp.isAfter(after)) {
                _location!.expire(DateTime.now());
                unawaited(_refreshLocation());
                return;
              }
              _resumeFixAfter = null;
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

        _syncKittyCats();
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

  Future<void> _stopGps({bool preserveDisplay = false}) =>
      _gpsOperations.run(() => _stopGpsNow(preserveDisplay: preserveDisplay));

  Future<void> _stopGpsNow({bool preserveDisplay = false}) async {
    if (_disposed) return;
    _locationGeneration++;
    _lastFollowCenter = null;

    _syncKittyCats();
    _proximity.unavailable();
    _cowboyMotion.stop();
    _location?.expire(DateTime.now());
    if (preserveDisplay && _location?.marker != null) {
      _travel.pause();
      _travelTicker.stop();
      _previousTravelTick = null;
      _projector.cancel();
    } else {
      _clearTravel();
    }
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
    _syncKittyCats();
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
      await _buildingLabels.reset(_map!);
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
    final change = _lifecycle.accept(state);
    if (change == MapLifecycleChange.suspend) {
      _rememberView();
      _syncKittyCats();
      _projector.cancel();
      _cowboyMotion.stop();
      _proximity.unavailable();
      unawaited(_stopGps(preserveDisplay: true));
      setState(() {});
    } else if (change == MapLifecycleChange.resume) {
      _location?.expire(DateTime.now());
      if (_location?.marker == null) _clearTravel();
      setState(() {});
      _syncKittyCats();
      if (_pointsInitialized) unawaited(_points.load());
      if (_openPoint case final GamePoint open) unawaited(open.load());
      if (_locationEnabled && _ready) unawaited(_resumeGps());
    }
  }

  Future<void> _resumeGps() async {
    try {
      if (!await Permission.locationWhenInUse.status.isGranted) {
        if (!mounted) return;
        setState(() {
          _following = false;
          _locationEnabled = false;
          _location?.clear(CampusGpsState.denied);
          _clearTravel();
        });
        unawaited(_renderPlayer());
        _rememberView();
        return;
      }
      if (!mounted || !_foreground) return;
      _resumeFixAfter = DateTime.now();
      await _renderPlayer();
      await _startGps(resuming: true);
    } catch (_) {
      if (mounted) setState(() => _location?.clear(CampusGpsState.unavailable));
    }
  }

  String? _pointAttackReason(GamePoint point) {
    if (point.busy) return 'Connecting to live point…';
    if (point.retired || _points.find(point.spotId) == null) {
      return 'This point has been removed or disabled.';
    }
    if (!_foreground || !point.loaded) {
      return point.error ?? 'Loading live point…';
    }
    if (_points.error != null) return _points.error;
    if (point.error != null) return point.error;
    if (!gameRegistry.containsKey(point.spot.gameId)) {
      return 'This game is unavailable in this app version.';
    }
    if (point.cooldownReason != null) return point.cooldownReason;
    if (_location?.state != CampusGpsState.onCampus) {
      return 'Enable GPS and move safely onto campus.';
    }
    return _proximity.attackReason(point.spot, DateTime.now());
  }

  Future<void> _showPoint(LiveGamePoint spot) async {
    if (_pointCardOpen || _gameOpen) return;
    _pointCardOpen = true;
    final point = GamePoint(
      SupabaseAttackRepository(Supabase.instance.client),
      playerTeam: TeamScope.of(context).team!,
      spot: spot,
    );
    _openPoint = point;
    unawaited(point.load());
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => PointCard(
          point: point,
          reason: () => _pointAttackReason(point),
          distance: () => _proximity.distanceTo(point.spot),
          onAttack: () => _attackPoint(point),
        ),
      );
    } finally {
      if (_openPoint == point) _openPoint = null;
      point.dispose();
      _pointCardOpen = false;
    }
  }

  Future<void> _attackPoint(GamePoint point) async {
    if (_gameOpen || _pointAttackReason(point) != null || point.friendly) {
      return;
    }
    if (!_proximity.launchAttack(point.spot, DateTime.now())) return;
    final wasFollowing = _following;
    CaptureSession? attack;
    setState(() => _gameOpen = true);
    try {
      attack = await CaptureSession.open(point, _proximity.currentFix!);
      _activeAttack = attack;
      if (!mounted) return;
      await Navigator.of(context).push<GameExit>(
        MaterialPageRoute(
          builder: (_) => GameHost(
            gameId: point.spot.gameId,
            session: GameSessionContext(
              spotId: point.spotId,
              startedAt: DateTime.now(),
              capture: attack,
            ),
          ),
        ),
      );
    } finally {
      attack?.close();
      _activeAttack = null;
      unawaited(point.load());
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

  Future<void> _openGame() async {
    final id = _proximity.selected?.id;
    final spot = id == null ? null : _points.find(id);
    if (spot != null) await _showPoint(spot);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _buildingLabels.dispose();
    unawaited(_stopGpsNow());
    _disposed = true;
    _travelTicker.dispose();
    _projector.dispose();
    _cowboyPlacement.dispose();
    if (_pointsInitialized) {
      _points.removeListener(_pointsChanged);
      _points.dispose();
    }
    _activeAttack?.close();
    _pointProjector.dispose();
    _pointPlacements.dispose();
    _kittyProjector.dispose();
    _kittyPlacement.dispose();
    _creatureProjector.dispose();
    _creaturePlacement.dispose();
    _savedView.dispose();
    super.dispose();
  }

  void _syncKittyCats() {
    _syncBuildingCreatures();
    if (!_foreground || _gameOpen || !_ready || _error != null) {
      _kittyProjector.cancel();
      _kittyPlacement.value = null;
      return;
    }
    unawaited(_kittyProjector.request(invalidate: true));
  }

  void _syncBuildingCreatures() {
    if (!_foreground || _gameOpen || !_ready || _error != null) {
      _creatureProjector.cancel();
      _creaturePlacement.value = null;
      return;
    }
    unawaited(_creatureProjector.request(invalidate: true));
  }

  Future<List<CampusCreaturePlacement>?> _readCreatureProjection() async {
    final map = _map, size = _size;
    if (map == null ||
        size == null ||
        !_styleLoaded ||
        !_foreground ||
        _gameOpen) {
      return null;
    }
    final camera = _cameraState ?? await map.getCameraState();
    const landmarks = CampusCreatureLandmark.all;
    final pixels = await map.pixelsForCoordinates([
      for (final landmark in landmarks) _point(landmark.point),
    ]);
    final placements = <CampusCreaturePlacement>[];
    for (var i = 0; i < pixels.length && i < landmarks.length; i++) {
      final pixel = pixels[i], landmark = landmarks[i];
      if (pixel == null || !pixel.x.isFinite || !pixel.y.isFinite) continue;
      final position = Offset(
        pixel.x,
        pixel.y - landmark.roofRise(camera.zoom, camera.pitch),
      );
      final width = landmark.widthAtZoom(camera.zoom);
      if (position.dx < -width ||
          position.dx > size.width + width ||
          position.dy < -width ||
          position.dy > size.height + width) {
        continue;
      }
      placements.add(CampusCreaturePlacement(landmark, position, width));
    }
    return placements;
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
              if (mounted) unawaited(_refitCampusViewport());
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
              Positioned.fill(
                child: ValueListenableBuilder<List<Offset>?>(
                  valueListenable: _kittyPlacement,
                  builder: (context, positions, child) =>
                      positions == null ||
                          !_ready ||
                          _error != null ||
                          !_foreground ||
                          _gameOpen
                      ? const SizedBox.shrink()
                      : KittyIslandCats(positions: positions),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<List<CampusCreaturePlacement>?>(
                  valueListenable: _creaturePlacement,
                  builder: (context, placements, child) =>
                      placements == null ||
                          !_ready ||
                          _error != null ||
                          !_foreground ||
                          _gameOpen
                      ? const SizedBox.shrink()
                      : CampusBuildingCreatures(placements: placements),
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
              if (_ready && _pointsInitialized)
                ValueListenableBuilder<Map<String, Offset>?>(
                  valueListenable: _pointPlacements,
                  builder: (context, positions, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (positions != null)
                        for (final point in _points.points)
                          if (positions[point.id] case final Offset position)
                            if (position.dx >= 0 &&
                                position.dy >= 0 &&
                                position.dx <= (_size?.width ?? 0) &&
                                position.dy <= (_size?.height ?? 0))
                              Positioned(
                                left: position.dx - 55,
                                top: position.dy - 112,
                                width: 110,
                                child: PointBeacon(
                                  key: ValueKey('point-beacon-${point.id}'),
                                  name: point.name,
                                  owner: point.state.owner,
                                  onTap: () => _showPoint(point),
                                ),
                              ),
                    ],
                  ),
                ),
              CowboySprite(
                key: const ValueKey('persistent-campus-cowboy'),
                motion: _cowboyMotion,
                placement: _cowboyPlacement,
                active: _ready && _error == null && _foreground && !_gameOpen,
              ),
              if (_ready && _error == null) ...[
                if (_selectedBuilding != null && !_gameOpen && _foreground)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 174,
                    child: BuildingNameCard(
                      building: _selectedBuilding!,
                      onClose: () => setState(() => _selectedBuilding = null),
                    ),
                  ),
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
                  child: Center(
                    child: FilledButton.icon(
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
