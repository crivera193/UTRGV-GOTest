// Explicit emulator-only test entry point. Never used by lib/main.dart.
import 'dart:convert';
import 'package:geolocator/geolocator.dart' as gps;
import 'package:campus_app/config/app_configuration.dart';
import 'package:campus_app/main.dart';
import 'package:campus_app/screens/main_screen.dart';
import 'package:campus_app/trainer/trainer_profile.dart';
import 'package:campus_app/teams/team_membership.dart';
import 'package:campus_app/games/point_attack.dart';
import 'package:campus_app/games/game_host.dart';
import 'package:campus_app/games/point_card.dart';
import 'package:campus_app/games/live_attack_repository.dart';
import 'package:campus_app/games/point_catalog.dart';
import 'package:campus_app/screens/map_screen.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/widgets/mapbox_configuration_notice.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const runId = String.fromEnvironment('TEAM_E2E_RUN');
bool holdGps = false;

class DelayedQaGps extends gps.GeolocatorPlatform {
  DelayedQaGps(this.delegate);
  final gps.GeolocatorPlatform delegate;
  @override
  Future<bool> isLocationServiceEnabled() =>
      delegate.isLocationServiceEnabled();
  @override
  Stream<gps.ServiceStatus> getServiceStatusStream() =>
      delegate.getServiceStatusStream();
  @override
  Stream<gps.Position> getPositionStream({
    gps.LocationSettings? locationSettings,
  }) => delegate
      .getPositionStream(locationSettings: locationSettings)
      .where((_) => !holdGps);
}

CaptureSession? attack;
GamePoint? point;

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
  gps.GeolocatorPlatform.instance = DelayedQaGps(
    gps.GeolocatorPlatform.instance,
  );
  enableFlutterDriverExtension(
    handler: (message) async {
      final data = jsonDecode(message!) as Map<String, dynamic>;
      final client = Supabase.instance.client;
      switch (data['op']) {
        case 'delay_gps':
          holdGps = data['hold'] == true;
          return jsonEncode({'held': holdGps});
        case 'map_lifecycle':
          WidgetsBinding.instance.handleAppLifecycleStateChanged(
            AppLifecycleState.values.byName(data['state'] as String),
          );
          return jsonEncode({'sent': data['state']});
        case 'map_view':
          final element =
              ft.find.byType(MapScreen).evaluate().single as StatefulElement;
          final dynamic state = element.state;
          return jsonEncode({
            'view': state.bucket?.read<Object?>('view'),
            'instance': identityHashCode(state),
            'cowboy_visible': ft.find
                .byKey(const ValueKey('cowboy-runtime-frame'))
                .evaluate()
                .isNotEmpty,
            'gps_waiting': ft.find
                .text('Waiting for a reliable GPS fix')
                .evaluate()
                .isNotEmpty,
          });
        case 'trainer':
          final trainer = await SupabaseTrainerRepository(client).load();
          return jsonEncode({
            'profile': trainer.profile,
            'xp': trainer.xp,
            'level': trainer.level,
            'rank': trainer.rank,
            'earned': trainer.achievements
                .where((a) => a['earned_at'] != null)
                .map((a) => a['id'])
                .toList(),
          });
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
          point?.dispose();
          final repo = SupabaseAttackRepository(client);
          final spot = await repo.loadPoint(
            data['spot_id'] as String? ?? 'qa-dynamic-play-20261022',
          );
          if (!spot.id.startsWith('qa-')) {
            throw StateError(
              'Only isolated QA points are allowed in this test entry',
            );
          }
          point = GamePoint(
            repo,
            playerTeam: TeamScope.of(main).team!,
            spot: spot,
          );
          await point!.load();
          if (point!.error != null) throw StateError(point!.error!);
          showDialog<void>(
            context: main,
            useRootNavigator: false,
            builder: (_) => PointCard(
              point: point!,
              reason: () => null,
              distance: () => 0,
              onAttack: () async {
                attack = await CaptureSession.open(
                  point!,
                  CampusFix(
                    point!.spot.point,
                    0,
                    DateTime.now().subtract(const Duration(milliseconds: 500)),
                  ),
                );
                if (!main.mounted) return;
                await Navigator.of(main).push<GameExit>(
                  MaterialPageRoute(
                    builder: (_) => GameHost(
                      gameId: point!.spot.gameId,
                      session: GameSessionContext(
                        spotId: point!.spotId,
                        startedAt: DateTime.now(),
                        capture: attack,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
          return jsonEncode({
            'opened': 'live QA point card',
            'hp': point!.state.hp,
            'can_resume': point!.canResume,
            'cooldown': point!.cooldownSeconds,
          });
        case 'catalog_map':
          final main = ft.find.byType(MainScreen).evaluate().single;
          Navigator.of(main).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: MapScreen(
                  pointRepository: SupabasePointCatalogRepository(
                    client,
                    includeTest: true,
                  ),
                ),
              ),
            ),
          );
          return jsonEncode({'opened': 'live catalog map'});
        case 'catalog':
          final rows = await SupabasePointCatalogRepository(
            client,
            includeTest: true,
          ).load();
          return jsonEncode({
            'points': rows.map((p) => p.toJson()).toList(),
            'markers': ft.find.byType(PointBeacon).evaluate().map((e) {
              final beacon = e.widget as PointBeacon;
              final box = e.renderObject as RenderBox;
              final origin = box.localToGlobal(Offset.zero);
              return {
                'key': beacon.key.toString(),
                'name': beacon.name,
                'x': origin.dx,
                'y': origin.dy,
              };
            }).toList(),
          });
        case 'read_attack':
          return jsonEncode(
            await client.rpc(
              'read_point_attack',
              params: {'attack_id': data['attack_id']},
            ),
          );
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
            'losses': attack?.losses,
            'correct': attack?.correct,
            'questions_total': attack?.rules.questionsTotal,
            'question_seconds': attack?.rules.questionSeconds,
            'max_damage_percent': attack?.rules.maxDamagePercent,
            'question_number': attack?.questionNumber,
            'seconds': attack?.secondsRemaining,
            'damage_percent': attack?.damagePercent,
            'owner': point?.state.ownerTeamId,
            'cooldown': point?.cooldownSeconds,
            'can_resume': point?.canResume,
            'attack_id': attack?.attackId,
            'question_id': attack?.question.id,
            'bank_id': attack?.question.bankId,
            'answers': attack?.question.answers,
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
