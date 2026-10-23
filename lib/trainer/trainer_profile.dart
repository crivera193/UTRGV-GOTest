import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrainerSnapshot {
  TrainerSnapshot(
    this.profile,
    this.progress,
    this.levels,
    this.ranks,
    this.achievements,
    this.settings,
    this.avatars,
  ) {
    if (levels.isEmpty || levels.first['min_xp'] != 0 || ranks.isEmpty) {
      throw const FormatException('Progression catalog unavailable.');
    }
    if (levels.first['level'] != 1 ||
        (ranks.first['min_level'] as num) > 1 ||
        xp < 0) {
      throw const FormatException('Invalid progression baseline.');
    }
    for (var i = 1; i < levels.length; i++) {
      if ((levels[i]['level'] as num) <= (levels[i - 1]['level'] as num) ||
          (levels[i]['min_xp'] as num) <= (levels[i - 1]['min_xp'] as num)) {
        throw const FormatException('Invalid level thresholds.');
      }
    }
  }
  factory TrainerSnapshot.fromJson(Map<String, dynamic> j) => TrainerSnapshot(
    Map<String, dynamic>.from(j['profile']),
    Map<String, dynamic>.from(j['progress']),
    (j['levels'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
    (j['ranks'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
    (j['achievements'] as List)
        .map((v) => Map<String, dynamic>.from(v))
        .toList(),
    Map<String, dynamic>.from(j['settings']),
    (j['avatars'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
  );
  final Map<String, dynamic> profile, progress, settings;
  final List<Map<String, dynamic>> levels, ranks, achievements;
  final List<Map<String, dynamic>> avatars;
  Map<String, dynamic>? avatar(String? id) =>
      avatars.where((v) => v['id'] == id).firstOrNull;
  int get xp => (progress['xp'] as num).toInt();
  Map<String, dynamic> get currentLevel =>
      levels.lastWhere((l) => (l['min_xp'] as num) <= xp);
  int get level => currentLevel['level'] as int;
  Map<String, dynamic>? get nextLevel =>
      levels.where((l) => (l['min_xp'] as num) > xp).firstOrNull;
  String get rank =>
      ranks.lastWhere((r) => (r['min_level'] as num) <= level)['name']
          as String;
  double get fraction => nextLevel == null
      ? 1
      : ((xp - (currentLevel['min_xp'] as num)) /
                ((nextLevel!['min_xp'] as num) -
                    (currentLevel['min_xp'] as num)))
            .clamp(0, 1)
            .toDouble();
  String get name => (profile['display_name'] as String).isNotEmpty
      ? profile['display_name'] as String
      : profile['username'] == null
      ? 'Your trainer'
      : '@${profile['username']}';
}

abstract interface class TrainerRepository {
  Future<TrainerSnapshot> load();
  Future<void> save({
    required String username,
    required String name,
    required String bio,
    required String? avatar,
    required int revision,
  });
  Stream<void> watch();
}

class SupabaseTrainerRepository implements TrainerRepository {
  SupabaseTrainerRepository(this.client) : userId = client.auth.currentUser!.id;
  final SupabaseClient client;
  final String userId;
  void _check() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
  }

  @override
  Future<TrainerSnapshot> load() async {
    _check();
    final j = Map<String, dynamic>.from(
      await client.rpc('read_trainer').timeout(const Duration(seconds: 20))
          as Map,
    );
    _check();
    return TrainerSnapshot.fromJson(j);
  }

  @override
  Future<void> save({
    required String username,
    required String name,
    required String bio,
    required String? avatar,
    required int revision,
  }) async {
    _check();
    await client
        .rpc(
          'update_trainer_profile',
          params: {
            'trainer_username': username,
            'trainer_name': name,
            'trainer_bio': bio,
            'trainer_avatar': avatar,
            'expected_revision': revision,
          },
        )
        .timeout(const Duration(seconds: 20));
    _check();
  }

  @override
  Stream<void> watch() {
    late StreamController<void> output;
    final subscriptions = <StreamSubscription>[];
    Timer? debounce;
    void changed(Object? _) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), () {
        if (!output.isClosed) output.add(null);
      });
    }

    output = StreamController<void>(
      onListen: () {
        for (final table in [
          'trainer_avatars',
          'progression_settings',
          'progression_levels',
          'progression_ranks',
          'progression_achievements',
        ]) {
          subscriptions.add(
            client
                .from(table)
                .stream(
                  primaryKey: [table == 'progression_levels' ? 'level' : 'id'],
                )
                .listen(changed, onError: output.addError),
          );
        }
        subscriptions.add(
          client
              .from('player_progress')
              .stream(primaryKey: ['user_id'])
              .eq('user_id', userId)
              .listen(changed, onError: output.addError),
        );
        subscriptions.add(
          client
              .from('player_profiles')
              .stream(primaryKey: ['id'])
              .eq('id', userId)
              .listen(changed, onError: output.addError),
        );
      },
      onCancel: () async {
        debounce?.cancel();
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      },
    );
    return output.stream;
  }
}
