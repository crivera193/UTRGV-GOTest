import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../games/point_attack.dart' show attackCommandId;

class TrainerSnapshot {
  TrainerSnapshot(
    this.profile,
    this.progress,
    this.levels,
    this.ranks,
    this.achievements,
    this.settings, {
    this.avatarUrl,
    this.photoUnavailable = false,
  }) {
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
  factory TrainerSnapshot.fromJson(
    Map<String, dynamic> j, {
    String? avatarUrl,
    bool photoUnavailable = false,
  }) => TrainerSnapshot(
    Map<String, dynamic>.from(j['profile']),
    Map<String, dynamic>.from(j['progress']),
    (j['levels'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
    (j['ranks'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
    (j['achievements'] as List)
        .map((v) => Map<String, dynamic>.from(v))
        .toList(),
    Map<String, dynamic>.from(j['settings']),
    avatarUrl: avatarUrl,
    photoUnavailable: photoUnavailable,
  );
  final Map<String, dynamic> profile, progress, settings;
  final List<Map<String, dynamic>> levels, ranks, achievements;
  final String? avatarUrl;
  final bool photoUnavailable;
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
  Future<String> upload(Uint8List jpeg);
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
    String? url;
    bool unavailable = false;
    final path = j['profile']['avatar_path'] as String?;
    if (path != null) {
      try {
        url = await client.storage
            .from('trainer-avatars')
            .createSignedUrl(path, 3600)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        unavailable = true;
      }
    }
    _check();
    return TrainerSnapshot.fromJson(
      j,
      avatarUrl: url,
      photoUnavailable: unavailable,
    );
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
  Future<String> upload(Uint8List jpeg) async {
    _check();
    final path = '$userId/${attackCommandId()}.jpg';
    await client.storage
        .from('trainer-avatars')
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        )
        .timeout(const Duration(seconds: 30));
    _check();
    return path;
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

/// Re-encode pixels into a new JPEG: strips EXIF/GPS and bounds upload dimensions.
Uint8List prepareTrainerPhoto(Uint8List bytes) {
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 10 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) {
    throw const FormatException(
      'Choose a JPEG, PNG or WebP photo under 24 megapixels.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('This photo could not be read.');
  }
  final crop = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: 512,
  );
  final clean = img.Image(width: 512, height: 512, numChannels: 3);
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, crop);
  return Uint8List.fromList(img.encodeJpg(clean, quality: 85));
}
