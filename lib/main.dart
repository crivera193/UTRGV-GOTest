import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'games/game_host.dart';
import 'auth/auth_gate.dart';
import 'config/app_configuration.dart';
import 'widgets/mapbox_configuration_notice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (hasMapboxConfiguration) MapboxOptions.setAccessToken(mapboxAccessToken);
  String? startupError;
  if (AppConfiguration.hasBackend) {
    try {
      await Supabase.initialize(
        url: AppConfiguration.supabaseUrl,
        publishableKey: AppConfiguration.supabaseKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SharedPreferencesLocalStorage(
            persistSessionKey: 'campus_explorer_v1_session',
          ),
        ),
      );
    } catch (_) {
      startupError =
          'Unable to connect to the account service. Please restart and try again.';
    }
  }
  runApp(CampusApp(startupError: startupError));
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key, this.startupError});
  final String? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UTRGV-GO',
    navigatorObservers: [gameRouteObserver],
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF795548),
    ),
    home: kDebugMode && const bool.fromEnvironment('GAME_PREVIEW')
        ? const DebugPreviewLauncher()
        : !AppConfiguration.hasBackend
        ? const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Account service is not configured yet.'),
              ),
            ),
          )
        : startupError != null
        ? Scaffold(body: Center(child: Text(startupError!)))
        : const AuthGate(),
  );
}
