import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/mapbox_configuration_notice.dart';

/// Geographic foundation; cowboy rendering and Flame gameplay remain the next slice.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static final _campus = Point(coordinates: Position(-98.174165, 26.304551));
  MapboxMap? _map;
  bool _requestingLocation = false;
  ViewportState _viewport = CameraViewportState(
    center: _campus,
    zoom: 16,
    pitch: 0,
    bearing: 0,
  );

  Future<void> _showMyLocation() async {
    if (_map == null || _requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is needed to show your position.',
            ),
          ),
        );
        return;
      }
      await _map!.location.updateSettings(
        LocationComponentSettings(enabled: true, showAccuracyRing: true),
      );
      // Do not follow outside campus before the verified campus camera policy exists.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to show your location. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _requestingLocation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasMapboxConfiguration) return const MapboxConfigurationNotice();
    return Stack(
      children: [
        MapWidget(
          key: const ValueKey('campus-exploration-map'),
          viewport: _viewport,
          onMapCreated: (map) {
            _map = map;
          },
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'campus-overview',
                tooltip: 'Center on campus',
                onPressed: () => setState(() {
                  _viewport = CameraViewportState(
                    center: _campus,
                    zoom: 16,
                    pitch: 0,
                    bearing: 0,
                  );
                }),
                child: const Icon(Icons.school_outlined),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'show-location',
                tooltip: 'Show my position',
                onPressed: _requestingLocation ? null : _showMyLocation,
                child: Icon(
                  _requestingLocation
                      ? Icons.hourglass_empty
                      : Icons.my_location,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
