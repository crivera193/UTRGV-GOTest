import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game_spot.dart';

abstract interface class PointCatalogRepository {
  Future<List<LiveGamePoint>> load();
  Stream<List<LiveGamePoint>> watch();
}

class SupabasePointCatalogRepository implements PointCatalogRepository {
  SupabasePointCatalogRepository(this.client, {this.includeTest = false})
    : userId = client.auth.currentUser!.id;
  final SupabaseClient client;
  final bool includeTest;
  final String userId;
  void _check() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
  }

  List<LiveGamePoint> _combine(
    List<Map<String, dynamic>> points,
    List<Map<String, dynamic>> rules,
  ) {
    _check();
    final byId = {for (final rule in rules) rule['id']: rule};
    return List.unmodifiable(
      points
          .where(
            (p) =>
                p['enabled'] == true && (includeTest || p['is_test'] == false),
          )
          .map((p) {
            final rule = byId[p['rule_set_id']];
            if (rule == null) {
              throw const FormatException('Point rules unavailable.');
            }
            return LiveGamePoint.fromJson({...p, 'rules': rule});
          })
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id)),
    );
  }

  @override
  Future<List<LiveGamePoint>> load() async {
    _check();
    final results = await Future.wait([
      client.from('game_spots').select(),
      client.from('game_rule_sets').select(),
    ]);
    return _combine(results[0], results[1]);
  }

  @override
  Stream<List<LiveGamePoint>> watch() {
    late StreamController<List<LiveGamePoint>> output;
    StreamSubscription<List<Map<String, dynamic>>>? pointsSub, rulesSub;
    List<Map<String, dynamic>>? points, rules;
    void emit() {
      if (points != null && rules != null && !output.isClosed) {
        try {
          output.add(_combine(points!, rules!));
        } catch (e, stack) {
          output.addError(e, stack);
        }
      }
    }

    output = StreamController(
      onListen: () {
        // Unfiltered subscriptions also receive transitions to disabled/retired.
        pointsSub = client.from('game_spots').stream(primaryKey: ['id']).listen(
          (value) {
            points = value;
            emit();
          },
          onError: output.addError,
        );
        rulesSub = client
            .from('game_rule_sets')
            .stream(primaryKey: ['id'])
            .listen((value) {
              rules = value;
              emit();
            }, onError: output.addError);
      },
      onCancel: () async {
        await pointsSub?.cancel();
        await rulesSub?.cancel();
      },
    );
    return output.stream;
  }
}

class PointCatalog extends ChangeNotifier {
  PointCatalog(this.repository);
  final PointCatalogRepository repository;
  List<LiveGamePoint> points = const [];
  bool loaded = false, _disposed = false;
  String? error;
  StreamSubscription<List<LiveGamePoint>>? _subscription;
  void _accept(List<LiveGamePoint> next) {
    if (_disposed) return;
    points = next;
    loaded = true;
    error = null;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      _accept(await repository.load());
      if (_disposed) return;
      _subscription ??= repository.watch().listen(
        _accept,
        onError: (Object _) {
          if (!_disposed) {
            error = 'Game points are unavailable. Refresh to reconnect.';
            notifyListeners();
          }
        },
      );
    } catch (_) {
      if (!_disposed) {
        error = 'Unable to load game points. Check your connection and retry.';
        notifyListeners();
      }
    }
  }

  LiveGamePoint? find(String id) {
    for (final p in points) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
