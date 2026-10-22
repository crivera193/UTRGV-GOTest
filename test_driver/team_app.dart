// Explicit emulator-only test entry point. Never used by lib/main.dart.
import 'dart:convert';
import 'package:campus_app/config/app_configuration.dart';
import 'package:campus_app/main.dart';
import 'package:campus_app/screens/main_screen.dart';
import 'package:campus_app/teams/team_membership.dart';
import 'package:campus_app/games/chapel_capture.dart';
import 'package:campus_app/games/game_host.dart';
import 'package:campus_app/widgets/mapbox_configuration_notice.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const runId = String.fromEnvironment('TEAM_E2E_RUN');
CaptureSession? attack;
ChapelPoint? point;

Future<Map<String, Object?>> inspect(SupabaseClient client) async {
  final user = client.auth.currentUser;
  if (user == null) return {'user': null};
  final profiles = await client
      .from('player_profiles')
      .select('id')
      .eq('id', user.id);
  final teams = await client
      .from('account_teams')
      .select()
      .eq('user_id', user.id);
  return {
    'user': user.id,
    'email': user.email,
    'profiles': profiles,
    'teams': teams,
  };
}

Future<void> main() async {
  if (!kDebugMode ||
      runId.isEmpty ||
      !RegExp(r'^[a-z0-9_]+$').hasMatch(runId) ||
      Uri.parse(AppConfiguration.supabaseUrl).host !=
          'oipidltfvzodpiumdsaq.supabase.co') {
    throw StateError('Explicit debug test run and verified project required.');
  }
  enableFlutterDriverExtension(
    handler: (message) async {
      final data = jsonDecode(message!) as Map<String, dynamic>;
      final client = Supabase.instance.client;
      switch (data['op']) {
        case 'inspect':
          final result = await inspect(client);
          final main = ft.find.byType(MainScreen).evaluate();
          if (main.isNotEmpty) {
            result['ui_team'] = TeamScope.of(main.single).team?.id;
          }
          return jsonEncode(result);
        case 'second_client':
          final other = SupabaseClient(
            AppConfiguration.supabaseUrl,
            AppConfiguration.supabaseKey,
          );
          try {
            await other.auth.signInWithPassword(
              email: data['email'] as String,
              password: data['password'] as String,
            );
            return jsonEncode(await inspect(other));
          } finally {
            await other.auth.signOut(scope: SignOutScope.local);
            await other.dispose();
          }
        case 'play':
          final main = ft.find.byType(MainScreen).evaluate().single;
          if (TeamScope.of(main).team == null) {
            throw StateError('Membership required');
          }
          point = ChapelPoint(
            LocalPointPersistence(key: 'team_e2e_chapel_$runId'),
          );
          await point!.load();
          attack = CaptureSession(point!);
          Navigator.of(main).push<GameExit>(
            MaterialPageRoute(
              builder: (_) => GameHost(
                gameId: 'chapel-football',
                session: GameSessionContext(
                  spotId: ChapelConfig.id,
                  startedAt: DateTime.now(),
                  debug: true,
                  capture: attack,
                ),
              ),
            ),
          );
          return 'opened isolated chapel game; no GPS eligibility asserted';
        case 'swipe':
          final element = ft.find
              .byType(GameWidget<SessionGame>)
              .evaluate()
              .single;
          final box = element.renderObject! as RenderBox;
          final start = box.localToGlobal(
            Offset(box.size.width * .5, box.size.height * 520 / 650),
          );
          final controller = ft.LiveWidgetController(WidgetsBinding.instance);
          await controller.timedDragFrom(
            start,
            Offset(
              (data['dx'] as num).toDouble() * box.size.width / 400,
              (data['dy'] as num).toDouble() * box.size.height / 650,
            ),
            const Duration(milliseconds: 350),
          );
          return 'swipe delivered through Flutter pointer events';
        case 'game':
          return jsonEncode({
            'phase': attack?.phase.name,
            'shots': attack?.shots,
            'hp': point?.state.hp,
            'message': attack?.message,
          });
        default:
          throw ArgumentError('Unsupported test command');
      }
    },
  );
  if (hasMapboxConfiguration) MapboxOptions.setAccessToken(mapboxAccessToken);
  await Supabase.initialize(
    url: AppConfiguration.supabaseUrl,
    publishableKey: AppConfiguration.supabaseKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: 'team_e2e_${runId}_session',
      ),
    ),
  );
  runApp(const CampusApp());
}
