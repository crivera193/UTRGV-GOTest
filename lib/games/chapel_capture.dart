import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../map/campus_geography.dart';

abstract final class ChapelConfig {
  static const id = 'echap-local-v1';
  static const name = 'Chapel Point';
  static const point = CampusPoint(-98.174683, 26.305357);
  static const debugPoint = CampusPoint(-98.176061, 26.304802);
  static const description =
      'PLACEHOLDER · A campus landmark to explore. Play from a safe outdoor path or the chapel lawn; never enter the building to play.';
  static const playerTeam = 'Team A', initialOwner = 'Team B';
  static const maxHp = 100, damage = 25, shots = 3;
  static const attackMeters = 39.624;
  static const restoreHpOnCapture = true;
  // Provisional retention policy is centralized in CaptureSession:
  // earned damage survives failed questions and Close.
  static const questions = <QuizQuestion>[
    QuizQuestion('campus', 'Demo quiz · Which campus are we exploring?', [
      'Edinburg',
      'Austin',
      'Dallas',
      'El Paso',
    ], 'a'),
    QuizQuestion('region', 'Demo quiz · RGV stands for…', [
      'Red Gate View',
      'Rio Grande Valley',
      'River Green Village',
      'Royal Grove Vista',
    ], 'b'),
    QuizQuestion('chapel', 'Demo quiz · ECHAP identifies which landmark?', [
      'Library',
      'Stadium',
      'Chapel',
      'Dining hall',
    ], 'c'),
    QuizQuestion('safe', 'Demo quiz · Where should you stop to play?', [
      'In a road',
      'On stairs',
      'While cycling',
      'A safe outdoor path',
    ], 'd'),
  ];
}

class QuizQuestion {
  const QuizQuestion(this.id, this.prompt, this.answers, this.correctId);
  final String id, prompt, correctId;
  final List<String> answers;
  String answerId(int index) => String.fromCharCode(97 + index);
}

class PointState {
  const PointState(this.owner, this.hp);
  final String owner;
  final int hp;
  static const initial = PointState(
    ChapelConfig.initialOwner,
    ChapelConfig.maxHp,
  );
}

abstract interface class PointPersistence {
  Future<PointState> load();
  Future<void> save(PointState state);
}

class LocalPointPersistence implements PointPersistence {
  LocalPointPersistence({this.key = 'utrgv_go_chapel_local_v1'});
  final String key;
  @override
  Future<PointState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key)?.split('|');
    if (value == null || value.length != 2) return PointState.initial;
    final hp = int.tryParse(value[1]);
    if (![
          ChapelConfig.playerTeam,
          ChapelConfig.initialOwner,
        ].contains(value[0]) ||
        hp == null ||
        hp < 1 ||
        hp > ChapelConfig.maxHp) {
      return PointState.initial;
    }
    return PointState(value[0], hp);
  }

  @override
  Future<void> save(PointState state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, '${state.owner}|${state.hp}')) {
      throw StateError('Local save failed');
    }
  }
}

class ChapelPoint extends ChangeNotifier {
  ChapelPoint(this.persistence);
  final PointPersistence persistence;
  PointState state = PointState.initial;
  bool loaded = false, busy = false;
  Future<void> load() async {
    state = await persistence.load();
    loaded = true;
    notifyListeners();
  }

  Future<bool> damage() async {
    if (busy) throw StateError('A local write is already pending');
    if (state.owner == ChapelConfig.playerTeam) return false;
    final hp = state.hp - ChapelConfig.damage;
    final captured = hp <= 0;
    final next = PointState(
      captured ? ChapelConfig.playerTeam : state.owner,
      captured && ChapelConfig.restoreHpOnCapture ? ChapelConfig.maxHp : hp,
    );
    await _save(next);
    return captured;
  }

  Future<void> reset() async {
    if (busy) throw StateError('A local write is already pending');
    await _save(PointState.initial);
  }

  Future<void> _save(PointState next) async {
    busy = true;
    notifyListeners();
    try {
      await persistence.save(next);
      state = next;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

enum AttackPhase { questionReady, aiming, flying, resolving, sessionEnded }

enum ShotOutcome { miss, wrong, correct }

class CaptureSession extends ChangeNotifier {
  CaptureSession(this.point);
  final ChapelPoint point;
  AttackPhase phase = AttackPhase.questionReady;
  int questionIndex = 0, shots = ChapelConfig.shots, shotId = 0;
  bool closed = false, captured = false, busy = false;
  String message = 'Swipe forward from the football. Aim for your answer.';
  QuizQuestion get question =>
      ChapelConfig.questions[questionIndex % ChapelConfig.questions.length];
  void aiming() {
    if (!closed && !point.busy && phase == AttackPhase.questionReady) {
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

  Future<void> resolve(int id, ShotOutcome outcome) async {
    if (closed || phase != AttackPhase.flying || id != shotId) return;
    phase = AttackPhase.resolving;
    busy = true;
    notifyListeners();
    shots--;
    if (outcome == ShotOutcome.correct) {
      try {
        captured = await point.damage();
        message = captured
            ? 'Captured! Team A controls Chapel Point.'
            : 'Correct! −${ChapelConfig.damage} HP. Damage saved on this device.';
      } catch (_) {
        message = 'Local save failed. Close and retry; no damage was awarded.';
        phase = AttackPhase.sessionEnded;
      }
    } else {
      message = outcome == ShotOutcome.wrong
          ? 'Wrong answer. Attack ended; earned damage stays.'
          : shots == 0
          ? 'Three misses. Attack ended; earned damage stays.'
          : 'Miss! $shots shots left. Try the same question.';
    }
    if (closed) return;
    busy = false;
    if (captured || outcome == ShotOutcome.wrong || shots == 0) {
      phase = AttackPhase.sessionEnded;
    }
    _nextQuestion = outcome == ShotOutcome.correct;
    notifyListeners();
  }

  bool _nextQuestion = false;
  void continuePlay() {
    if (closed || busy || phase != AttackPhase.resolving) return;
    if (_nextQuestion) {
      questionIndex++;
      shots = ChapelConfig.shots;
    }
    phase = AttackPhase.questionReady;
    message = 'Swipe forward from the football. Aim for your answer.';
    notifyListeners();
  }

  void close() {
    closed = true;
    phase = AttackPhase.sessionEnded;
  }
}
