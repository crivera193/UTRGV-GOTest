import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/campus_location.dart';
import 'point_attack.dart';
import 'point_catalog.dart';

/// All combat authority lives in Supabase. No device-local fallback or answer key.
class SupabaseAttackRepository implements AttackRepository {
  SupabaseAttackRepository(this.client) : userId = client.auth.currentUser!.id;
  final SupabaseClient client;
  final String userId;
  void _check() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String name,
    Map<String, dynamic> params,
  ) async {
    _check();
    try {
      final value = await client
          .rpc(name, params: params)
          .timeout(const Duration(seconds: 20));
      _check();
      return Map<String, dynamic>.from(value as Map);
    } on PostgrestException catch (error) {
      if (error.code == 'PT409') throw const AttackConflict();
      rethrow;
    }
  }

  @override
  Future<AttackAccess> access(String spotId) async => AttackAccess.fromJson(
    await _rpc('point_attack_access', {'spot_id': spotId}),
  );
  @override
  Future<LiveGamePoint> loadPoint(String spotId) async {
    _check();
    final value = await client
        .from('game_spots')
        .select('*, rules:game_rule_sets(*)')
        .eq('id', spotId)
        .single();
    _check();
    return LiveGamePoint.fromJson(value);
  }

  @override
  Stream<LiveGamePoint> watchPoint(String spotId) =>
      SupabasePointCatalogRepository(client, includeTest: true).watch().map((
        points,
      ) {
        _check();
        for (final p in points) {
          if (p.id == spotId) return p;
        }
        throw StateError('Point removed or disabled.');
      });
  @override
  Future<AttackState> begin(
    String spotId,
    CampusFix fix,
    String requestId,
  ) async => AttackState.fromJson(
    await _rpc('begin_point_attack', {
      'spot_id': spotId,
      'request_id': requestId,
      'latitude': fix.point.latitude,
      'longitude': fix.point.longitude,
      'accuracy_meters': fix.accuracy,
      'fix_at': fix.timestamp.toUtc().toIso8601String(),
    }),
  );
  @override
  Future<AttackState> read(String attackId) async => AttackState.fromJson(
    await _rpc('read_point_attack', {'attack_id': attackId}),
  );
  @override
  Future<Map<String, dynamic>> kick(
    String attackId,
    String questionId,
    String commandId,
    Offset swipe,
  ) => _rpc('submit_point_kick', {
    'attack_id': attackId,
    'question_id': questionId,
    'command_id': commandId,
    'swipe_dx': swipe.dx,
    'swipe_dy': swipe.dy,
  });
}
