import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/campus_location.dart';
import 'chapel_capture.dart';

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
  Future<PointState> loadPoint(String spotId) async {
    _check();
    final value = await client
        .from('game_spots')
        .select()
        .eq('id', spotId)
        .single();
    _check();
    return PointState.fromJson(value);
  }

  @override
  Stream<PointState> watchPoint(String spotId) => client
      .from('game_spots')
      .stream(primaryKey: ['id'])
      .eq('id', spotId)
      .map((rows) {
        _check();
        if (rows.length != 1) throw StateError('Point unavailable.');
        return PointState.fromJson(rows.single);
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
