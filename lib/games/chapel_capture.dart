import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../map/campus_geography.dart';
import '../map/campus_location.dart';
import '../teams/game_team.dart';

abstract final class ChapelConfig {
  static const id = 'echap-local-v1', name = 'Chapel Point';
  static const point = CampusPoint(-98.174683, 26.305357);
  static const description =
      'Play from a safe outdoor path or the chapel lawn; never enter the building to play.';
  static const maxHp = 100, damage = 25;
  static const attackMeters = 39.624;
}

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

class PointState {
  const PointState({
    this.ownerTeamId,
    this.hp = 100,
    this.maxHp = 100,
    this.revision = 0,
  });
  factory PointState.fromJson(Map<String, dynamic> j) => PointState(
    ownerTeamId: j['owner_team_id'] as String?,
    hp: j['hp'] as int,
    maxHp: j['max_hp'] as int,
    revision: j['revision'] as int,
  );
  final String? ownerTeamId;
  final int hp, maxHp, revision;
  String get owner => ownerTeamId == null
      ? 'Unclaimed'
      : GameTeam.fromId(ownerTeamId!).displayName;
}

class AttackState {
  AttackState.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      sequence = j['sequence'] as int,
      correct = j['correct_count'] as int,
      losses = (j['wrong_count'] as int) + (j['miss_count'] as int),
      point = PointState.fromJson(Map<String, dynamic>.from(j['point'] as Map)),
      question = QuizQuestion.fromJson(
        Map<String, dynamic>.from(j['question'] as Map),
      );
  final String id, status;
  final int sequence, correct, losses;
  final PointState point;
  final QuizQuestion question;
  bool get active => status == 'active';
}

class AttackConflict implements Exception {
  const AttackConflict();
}

abstract interface class AttackRepository {
  Future<PointState> loadPoint(String spotId);
  Stream<PointState> watchPoint(String spotId);
  Future<AttackState> begin(String spotId, CampusFix fix, String requestId);
  Future<AttackState> read(String attackId);
  Future<Map<String, dynamic>> kick(
    String attackId,
    String questionId,
    String commandId,
    Offset swipe,
  );
}

class ChapelPoint extends ChangeNotifier {
  ChapelPoint(
    this.repository, {
    required this.playerTeam,
    this.spotId = ChapelConfig.id,
  });
  final AttackRepository repository;
  final GameTeam playerTeam;
  final String spotId;
  PointState state = const PointState();
  bool loaded = false, busy = false, _disposed = false;
  String? error;
  StreamSubscription<PointState>? _subscription;
  bool get friendly => state.ownerTeamId == playerTeam.id;
  void apply(PointState next) {
    if (_disposed) return;
    if (!loaded || next.revision >= state.revision) state = next;
    loaded = true;
    error = null;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final next = await repository.loadPoint(spotId);
      if (_disposed) return;
      apply(next);
      _subscription ??= repository
          .watchPoint(spotId)
          .listen(
            apply,
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
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

enum AttackPhase { questionReady, aiming, flying, resolving, sessionEnded }

class CaptureSession extends ChangeNotifier {
  CaptureSession._(this.point, this._state) : _question = _state.question {
    if (!_state.active) {
      phase = AttackPhase.sessionEnded;
      message = 'This attack has ended. Return to the map.';
    }
  }
  static Future<CaptureSession> open(
    ChapelPoint point,
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
      point.apply(current.point);
      return CaptureSession._(point, current);
    } finally {
      point._busy(false);
    }
  }

  final ChapelPoint point;
  AttackState _state;
  QuizQuestion _question;
  QuizQuestion get question => _question;
  String get attackId => _state.id;
  int get correct => _state.correct;
  int get losses => _state.losses;
  AttackPhase phase = AttackPhase.questionReady;
  int shotId = 0;
  bool closed = false, busy = false, retryNeeded = false;
  bool get captured => _state.status == 'captured';
  String message = 'Swipe forward from the football. Aim for your answer.';
  String? _command;
  Offset? _swipe;
  void aiming() {
    if (!closed && phase == AttackPhase.questionReady) {
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
    if (closed || phase != AttackPhase.aiming) return null;
    phase = AttackPhase.flying;
    notifyListeners();
    return ++shotId;
  }

  Future<void> resolveKick(int id, Offset swipe) async {
    if (closed || phase != AttackPhase.flying || id != shotId) return;
    _command = attackCommandId();
    _swipe = swipe;
    phase = AttackPhase.resolving;
    await retryKick();
  }

  Future<void> retryKick() async {
    if (closed || busy || _command == null || _swipe == null) return;
    busy = true;
    retryNeeded = false;
    notifyListeners();
    try {
      final receipt = await point.repository.kick(
        _state.id,
        _question.id,
        _command!,
        _swipe!,
      );
      final next = AttackState.fromJson(
        Map<String, dynamic>.from(receipt['state'] as Map),
      );
      final current = await point.repository.read(next.id);
      point.apply(current.point);
      if (closed) return;
      _state = current;
      message = receipt['outcome'] == 'correct'
          ? captured
                ? '${point.playerTeam.displayName} captured the point!'
                : 'Correct! −${receipt['damage']} HP. Saved online.'
          : receipt['outcome'] == 'wrong'
          ? 'Wrong answer. No damage. Next question.'
          : 'Miss. No damage. Next question.';
      _command = null;
      _swipe = null;
      if (!_state.active) phase = AttackPhase.sessionEnded;
    } catch (error) {
      if (!closed && error is AttackConflict) {
        try {
          final current = await point.repository.read(_state.id);
          point.apply(current.point);
          if (closed) return;
          _state = current;
          _question = current.question;
          _command = null;
          _swipe = null;
          phase = current.active
              ? AttackPhase.questionReady
              : AttackPhase.sessionEnded;
          message = current.active
              ? 'This question was resolved on another device. Next question loaded.'
              : 'This attack has ended or the point changed. Return to the map.';
          return;
        } catch (_) {
          /* Keep the original command for a safe retry. */
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

  void continuePlay() {
    if (closed || busy || retryNeeded || phase != AttackPhase.resolving) return;
    _question = _state.question;
    phase = AttackPhase.questionReady;
    message = 'Swipe forward from the football. Aim for your answer.';
    notifyListeners();
  }

  void close() {
    closed = true;
    phase = AttackPhase.sessionEnded;
  }
}
