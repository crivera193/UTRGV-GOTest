import 'package:flutter/material.dart';

const mapboxAccessToken = String.fromEnvironment('ACCESS_TOKEN');
const hasMapboxConfiguration = mapboxAccessToken != '';

/// Only map screens require this configuration; authentication and other
/// application features can still run without it.
class MapboxConfigurationNotice extends StatelessWidget {
  const MapboxConfigurationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 64),
              SizedBox(height: 20),
              Text(
                'Missing Mapbox configuration',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'The map is unavailable until the project Mapbox token is '
                'configured. You can still use the rest of the app.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
