import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../map/campus_location.dart';
import '../teams/game_team.dart';

import 'game_spot.dart';
import 'game_rules.dart';
export 'game_spot.dart';
export 'game_rules.dart';

String attackCommandId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class QuizQuestion {
  QuizQuestion.fromJson(Map<String, dynamic> j)
    : id = j['instance_id'] as String,
      bankId = j['bank_id'] as String,
      prompt = j['prompt'] as String,
      choices = List<Map<String, dynamic>>.unmodifiable(
        (j['choices'] as List).map(
          (c) => Map<String, dynamic>.unmodifiable(c as Map),
        ),
      ) {
    if (choices.length != 4) throw const FormatException('Invalid question');
  }
  final String id, bankId, prompt;
  final List<Map<String, dynamic>> choices;
  List<String> get answers =>
      choices.map((c) => c['text'] as String).toList(growable: false);
  String answerId(int index) => choices[index]['id'] as String;
}

class AttackState {
  AttackState.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      sequence = j['sequence'] as int,
      rules = AttackRules.fromJson(
        Map<String, dynamic>.from(j['rules'] as Map),
      ),
      correct = j['correct_count'] as int,
      losses =
          (j['wrong_count'] as int) +
          (j['miss_count'] as int) +
          (j['timeout_count'] as int),
      damageDealt = (j['damage_dealt'] as num).toDouble(),
      serverNow = DateTime.parse(j['server_now'] as String),
      cooldownUntil = DateTime.parse(j['cooldown_until'] as String),
      dueAt = DateTime.parse((j['question'] as Map)['due_at'] as String),
      lastOutcome = j['last_outcome'] as String?,
      point = LiveGamePoint.fromJson(
        Map<String, dynamic>.from(j['point'] as Map),
      ),
      question = QuizQuestion.fromJson(
        Map<String, dynamic>.from(j['question'] as Map),
      );
  final String id, status;
  final int sequence, correct, losses;
  final AttackRules rules;
  final double damageDealt;
  final DateTime serverNow, cooldownUntil, dueAt;
  final String? lastOutcome;
  final LiveGamePoint point;
  final QuizQuestion question;
  bool get active => status == 'active';
}

class AttackConflict implements Exception {
  const AttackConflict();
}

class AttackAccess {
  const AttackAccess({
    required this.serverNow,
    required this.cooldownUntil,
    required this.canResume,
  });
  factory AttackAccess.fromJson(Map<String, dynamic> json) => AttackAccess(
    serverNow: DateTime.parse(json['server_now'] as String),
    cooldownUntil: json['cooldown_until'] == null
        ? null
        : DateTime.parse(json['cooldown_until'] as String),
    canResume: json['can_resume'] as bool,
  );
  final DateTime serverNow;
  final DateTime? cooldownUntil;
  final bool canResume;
}

abstract interface class AttackRepository {
  Future<LiveGamePoint> loadPoint(String spotId);
  Future<AttackAccess> access(String spotId);
  Stream<LiveGamePoint> watchPoint(String spotId);
  Future<AttackState> begin(String spotId, CampusFix fix, String requestId);
  Future<AttackState> read(String attackId);
  Future<Map<String, dynamic>> kick(
    String attackId,
    String questionId,
    String commandId,
    Offset swipe,
  );
}

class GamePoint extends ChangeNotifier {
  GamePoint(
    this.repository, {
    required this.playerTeam,
    required LiveGamePoint spot,
    // Keep the public parameter independent of the private mutable field.
    // ignore: prefer_initializing_formals
  }) : _spot = spot;
  final AttackRepository repository;
  final GameTeam playerTeam;
  LiveGamePoint _spot;
  LiveGamePoint get spot => _spot;
  String get spotId => _spot.id;
  PointState get state => _spot.state;
  bool retired = false;
  bool loaded = false, busy = false, _disposed = false;
  String? error;
  StreamSubscription<LiveGamePoint>? _subscription;
  AttackAccess? _access;
  final _accessClock = Stopwatch();
  bool get canResume => _access?.canResume ?? false;
  int get cooldownSeconds {
    final access = _access;
    if (access == null || access.cooldownUntil == null) return 0;
    return ((access.cooldownUntil!.difference(access.serverNow).inMilliseconds -
                _accessClock.elapsedMilliseconds) /
            1000)
        .ceil()
        .clamp(0, 86400);
  }

  String? get cooldownReason {
    if (canResume || cooldownSeconds == 0) return null;
    final seconds = cooldownSeconds;
    return 'Attack available in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void applyAccess(AttackAccess access) {
    _access = access;
    _accessClock
      ..reset()
      ..start();
  }

  bool get friendly => state.ownerTeamId == playerTeam.id;
  void apply(PointState next) {
    if (_disposed) return;
    if (!loaded || next.revision >= state.revision) {
      _spot = _spot.withState(next);
    }
    loaded = true;
    error = null;
    notifyListeners();
  }

  void applyDefinition(LiveGamePoint next) {
    if (_disposed) return;
    if (!loaded || next.state.revision >= state.revision) {
      _spot = next;
    } else {
      _spot = LiveGamePoint.fromJson({
        ..._spot.toJson(),
        'rules': next.rules.toJson(),
      });
    }
    retired = !next.enabled;
    loaded = true;
    error = null;
    notifyListeners();
  }

  void retire() {
    if (_disposed) return;
    retired = true;
    error = 'This point has been removed or disabled.';
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait<Object>([
        repository.loadPoint(spotId),
        repository.access(spotId),
      ]);
      final next = results[0] as LiveGamePoint;
      if (_disposed) return;
      applyAccess(results[1] as AttackAccess);
      applyDefinition(next);
      _subscription ??= repository
          .watchPoint(spotId)
          .listen(
            applyDefinition,
            onError: (Object _) {
              if (!_disposed) {
                error =
                    'Live point connection interrupted. Refresh before attacking.';
                notifyListeners();
              }
            },
          );
    } catch (_) {
      if (!_disposed) {
        error =
            'Unable to load the live point. Check your connection and retry.';
        notifyListeners();
      }
    }
  }

  void _busy(bool value) {
    busy = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accessClock.stop();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

enum AttackPhase { questionReady, aiming, flying, resolving, sessionEnded }

class CaptureSession extends ChangeNotifier {
  CaptureSession._(this.point, this._state) {
    _accept(_state);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (closed) return;
      notifyListeners();
      if (_visible &&
          secondsRemaining == 0 &&
          !busy &&
          !retryNeeded &&
          _state.active) {
        unawaited(refresh());
      }
    });
  }
  static Future<CaptureSession> open(
    GamePoint point,
    CampusFix fix, {
    String? requestId,
  }) async {
    if (point.busy) throw StateError('An attack is already opening.');
    point._busy(true);
    try {
      final started = await point.repository.begin(
        point.spotId,
        fix,
        requestId ?? attackCommandId(),
      );
      final current = await point.repository.read(started.id);
      return CaptureSession._(point, current);
    } finally {
      point._busy(false);
    }
  }

  final GamePoint point;
  AttackState _state;
  final _clock = Stopwatch();
  Timer? _timer;
  bool _visible = true;
  QuizQuestion get question => _state.question;
  String get attackId => _state.id;
  int get correct => _state.correct;
  int get losses => _state.losses;
  AttackRules get rules => _state.rules;
  int get questionNumber =>
      (_state.sequence + 1).clamp(1, rules.questionsTotal);
  String get damagePercent =>
      healthText(_state.damageDealt / point.state.maxHp * 100);
  int get secondsRemaining =>
      ((_state.dueAt.difference(_state.serverNow).inMilliseconds -
                  _clock.elapsedMilliseconds) /
              1000)
          .ceil()
          .clamp(0, rules.questionSeconds);
  AttackPhase phase = AttackPhase.questionReady;
  int shotId = 0;
  bool closed = false, busy = false, retryNeeded = false;
  bool get captured => _state.status == 'captured';
  String message = 'Kick toward your answer before the timer ends.';
  String? _command, _commandQuestion;
  Offset? _swipe;
  void _accept(AttackState next) {
    final keepFlight =
        phase == AttackPhase.flying &&
        _state.question.id == next.question.id &&
        next.active;
    _state = next;
    _clock
      ..reset()
      ..start();
    point.applyAccess(
      AttackAccess(
        serverNow: next.serverNow,
        cooldownUntil: next.cooldownUntil,
        canResume: next.active,
      ),
    );
    point.applyDefinition(next.point);
    phase = keepFlight
        ? AttackPhase.flying
        : next.active
        ? AttackPhase.questionReady
        : AttackPhase.sessionEnded;
    if (!next.active && !captured) {
      message =
          'Attempt complete. $correct/${rules.questionsTotal} correct · $damagePercent% damage saved.';
    }
  }

  void setVisible(bool visible) {
    final returning = visible && !_visible;
    _visible = visible;
    if (returning && !closed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (closed || busy) return;
    if (_command != null) {
      await retryKick();
      return;
    }
    busy = true;
    notifyListeners();
    final previousSequence = _state.sequence;
    try {
      final next = await point.repository.read(_state.id);
      if (closed) return;
      _accept(next);
      if (next.active && next.sequence > previousSequence) {
        message = 'Time expired. No damage. Next question.';
      }
      retryNeeded = false;
    } catch (_) {
      if (!closed) {
        retryNeeded = true;
        message = 'Reconnect to check the timer and saved progress.';
      }
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  void aiming() {
    if (!closed &&
        !busy &&
        !retryNeeded &&
        secondsRemaining > 0 &&
        phase == AttackPhase.questionReady) {
      phase = AttackPhase.aiming;
      notifyListeners();
    }
  }

  void cancelAim() {
    if (phase == AttackPhase.aiming) {
      phase = AttackPhase.questionReady;
      notifyListeners();
    }
  }

  int? fire() {
    if (closed ||
        busy ||
        secondsRemaining == 0 ||
        phase != AttackPhase.aiming) {
      return null;
    }
    phase = AttackPhase.flying;
    notifyListeners();
    return ++shotId;
  }

  Future<void> resolveKick(int id, Offset swipe) async {
    if (closed || phase != AttackPhase.flying || id != shotId) return;
    _command = attackCommandId();
    _commandQuestion = question.id;
    _swipe = swipe;
    phase = AttackPhase.resolving;
    await retryKick();
  }

  Future<void> retryKick() async {
    if (closed || busy) return;
    if (_command == null) {
      retryNeeded = false;
      await refresh();
      return;
    }
    busy = true;
    retryNeeded = false;
    notifyListeners();
    try {
      final receipt = await point.repository.kick(
        _state.id,
        _commandQuestion!,
        _command!,
        _swipe!,
      );
      final snapshot = AttackState.fromJson(
        Map<String, dynamic>.from(receipt['state'] as Map),
      );
      final current = await point.repository.read(snapshot.id);
      if (closed) return;
      _accept(current);
      final outcome = receipt['outcome'];
      if (captured) {
        message = '${point.playerTeam.displayName} captured the point!';
      } else if (current.active) {
        message = outcome == 'correct'
            ? 'Correct! ${healthText(receipt['damage'] as num)} HP damage saved. Next question.'
            : outcome == 'timeout'
            ? 'Time expired. No damage. Next question.'
            : outcome == 'wrong'
            ? 'Wrong answer. No damage. Next question.'
            : 'Miss. No damage. Next question.';
      }
      _command = null;
      _commandQuestion = null;
      _swipe = null;
    } catch (error) {
      if (!closed && error is AttackConflict) {
        try {
          final current = await point.repository.read(_state.id);
          if (closed) return;
          _accept(current);
          _command = null;
          _commandQuestion = null;
          _swipe = null;
          if (current.active) {
            message = 'Question updated from the server. Keep playing.';
          }
          return;
        } catch (_) {
          /* Retry the same command after a connection interruption. */
        }
      }
      if (!closed) {
        retryNeeded = true;
        message =
            'Could not confirm this kick. Retry to check its saved result.';
      }
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  void close() {
    closed = true;
    phase = AttackPhase.sessionEnded;
    _timer?.cancel();
    _clock.stop();
  }
}
