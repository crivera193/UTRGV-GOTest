import 'dart:async';
import 'package:campus_app/games/point_attack.dart';
import 'package:campus_app/games/point_card.dart';
import 'package:campus_app/games/football_shot.dart';
import 'package:campus_app/games/game_host.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/teams/game_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> pointFixture() => {
  'id': 'synthetic-point',
  'name': 'Synthetic point',
  'description': 'Stop safely to play.',
  'image_url': null,
  'latitude': 0.0,
  'longitude': 0.0,
  'game_id': 'free-kick',
  'enabled': true,
  'attack_meters': 39.624,
  'entry_meters': 39.624,
  'exit_meters': 45.0,
  'play_version': 0,
  'hp': 100,
  'max_hp': 100,
  'owner_team_id': null,
  'revision': 0,
  'rules': {
    'id': 'test-rules',
    'version': 1,
    'questions_total': 4,
    'question_seconds': 15,
    'cooldown_seconds': 600,
    'max_damage_percent': 25,
  },
};
LiveGamePoint testSpot() => LiveGamePoint.fromJson(pointFixture());

// Test transport only; the live database separately verifies all rules.
class Transport implements AttackRepository {
  int sequence = 0, correct = 0, wrong = 0, miss = 0, timeouts = 0, calls = 0;
  double hp = 100;
  bool loseResponse = false, conflict = false, started = false;
  String outcome = 'miss';
  final receipts = <String, Map<String, dynamic>>{};
  final startedAt = DateTime.now();
  DateTime dueAt = DateTime.now().add(const Duration(seconds: 15));
  Map<String, dynamic> payload() => {
    'id': 'attack',
    'status': hp <= 0
        ? 'captured'
        : sequence >= 4
        ? 'completed'
        : 'active',
    'sequence': sequence,
    'rules': pointFixture()['rules'],
    'correct_count': correct,
    'wrong_count': wrong,
    'miss_count': miss,
    'timeout_count': timeouts,
    'damage_dealt': correct * 6.25,
    'last_outcome': timeouts > 0 ? 'timeout' : outcome,
    'server_now': DateTime.now().toUtc().toIso8601String(),
    'cooldown_until': startedAt
        .add(const Duration(minutes: 10))
        .toUtc()
        .toIso8601String(),
    'point': {
      ...pointFixture(),
      'owner_team_id': hp <= 0 ? 'art_stuff' : null,
      'hp': hp <= 0 ? 100 : hp,
      'max_hp': 100,
      'revision': correct,
    },
    'question': {
      'instance_id': 'q$sequence',
      'bank_id': 'bank$sequence',
      'prompt': 'Question $sequence',
      'due_at': dueAt.toUtc().toIso8601String(),
      'choices': List.generate(4, (i) => {'id': '$i', 'text': 'Choice $i'}),
    },
  };
  @override
  Future<LiveGamePoint> loadPoint(String _) async =>
      AttackState.fromJson(payload()).point;
  @override
  Stream<LiveGamePoint> watchPoint(String _) => const Stream.empty();
  @override
  Future<AttackAccess> access(String _) async => AttackAccess(
    serverNow: DateTime.now(),
    cooldownUntil: started ? startedAt.add(const Duration(minutes: 10)) : null,
    canResume: started && sequence < 4,
  );
  @override
  Future<AttackState> begin(String _, CampusFix fix, String requestId) async {
    started = true;
    return AttackState.fromJson(payload());
  }

  @override
  Future<AttackState> read(String _) async => AttackState.fromJson(payload());
  void expire(int count) {
    sequence += count;
    timeouts += count;
    dueAt = DateTime.now().add(const Duration(seconds: 15));
  }

  @override
  Future<Map<String, dynamic>> kick(
    String a,
    String q,
    String cmd,
    Offset swipe,
  ) async {
    calls++;
    if (conflict) {
      conflict = false;
      sequence++;
      throw const AttackConflict();
    }
    final receipt = receipts.putIfAbsent(cmd, () {
      expect(q, 'q$sequence');
      expect(sequence, lessThan(4));
      sequence++;
      if (outcome == 'correct') {
        hp -= 6.25;
        correct++;
      } else if (outcome == 'wrong') {
        wrong++;
      } else {
        miss++;
      }
      dueAt = DateTime.now().add(const Duration(seconds: 15));
      return {
        'outcome': outcome,
        'damage': outcome == 'correct' ? 6.25 : 0,
        'state': payload(),
      };
    });
    if (loseResponse) {
      loseResponse = false;
      throw StateError('Response lost after commit');
    }
    return receipt;
  }
}

Future<void> kick(CaptureSession s) async {
  s.aiming();
  final shot = s.fire();
  if (shot != null) await s.resolveKick(shot, const Offset(-90, -180));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fix = CampusFix(const CampusPoint(0, 0), 1, DateTime.now());
  test(
    'four perfect questions end at exactly 25% damage, not a solo capture',
    () async {
      final repo = Transport()..outcome = 'correct';
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      for (var i = 0; i < 4; i++) {
        await kick(s);
        expect(p.state.hp, 100 - (i + 1) * 6.25);
      }
      expect(s.phase, AttackPhase.sessionEnded);
      expect(s.captured, false);
      expect(s.damagePercent, '25');
      await kick(s);
      expect(repo.calls, 4);
      expect(p.state.ownerTeamId, isNull);
      expect(p.cooldownReason, startsWith('Attack available in '));
      expect(p.cooldownSeconds, inInclusiveRange(599, 600));
      s.close();
      p.dispose();
    },
  );
  test(
    'wrong, miss, correct and timeout all consume a question; only correct damages',
    () async {
      final repo = Transport();
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      final q = s.question.id;
      await kick(s);
      expect(s.question.id, isNot(q));
      expect(s.losses, 1);
      expect(p.state.hp, 100);
      repo.outcome = 'wrong';
      await kick(s);
      expect(s.losses, 2);
      repo.outcome = 'correct';
      await kick(s);
      expect(p.state.hp, 93.75);
      repo.expire(1);
      await s.refresh();
      expect(s.phase, AttackPhase.sessionEnded);
      expect(s.losses, 3);
      expect(s.damagePercent, '6.25');
      s.close();
      p.dispose();
    },
  );
  test(
    'timer refresh advances automatically and catches up while away',
    () async {
      final repo = Transport();
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      repo.expire(1);
      await s.refresh();
      expect(s.question.id, 'q1');
      expect(s.message, contains('Time expired'));
      expect(s.secondsRemaining, inInclusiveRange(14, 15));
      repo.expire(3);
      await s.refresh();
      expect(s.phase, AttackPhase.sessionEnded);
      expect(s.losses, 4);
      expect(p.state.hp, 100);
      expect(p.canResume, false);
      expect(p.cooldownReason, isNotNull);
      s.close();
      p.dispose();
    },
  );
  test(
    'lost response retries the identical command without double damage or skipped questions',
    () async {
      final repo = Transport()
        ..outcome = 'correct'
        ..loseResponse = true;
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      await kick(s);
      expect(s.retryNeeded, true);
      expect(p.state.hp, 100);
      expect(repo.hp, 93.75);
      await s.retryKick();
      expect(s.retryNeeded, false);
      expect(p.state.hp, 93.75);
      expect(repo.sequence, 1);
      expect(repo.calls, 2);
      expect(s.question.id, 'q1');
      s.close();
      p.dispose();
    },
  );
  test(
    'another device resolving a question refreshes without repeating the kick',
    () async {
      final repo = Transport()..conflict = true;
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      await kick(s);
      expect(s.retryNeeded, false);
      expect(s.phase, AttackPhase.questionReady);
      expect(s.question.id, 'q1');
      expect(repo.calls, 1);
      expect(p.state.hp, 100);
      s.close();
      p.dispose();
    },
  );
  test(
    'last correct kick takes ownership for the permanent team and restores health',
    () async {
      final repo = Transport()
        ..hp = 6.25
        ..outcome = 'correct';
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final s = await CaptureSession.open(p, fix);
      await kick(s);
      expect(s.captured, true);
      expect(p.friendly, true);
      expect(p.state.hp, 100);
      expect(s.message, contains('Art and Stuff captured'));
      s.close();
      p.dispose();
    },
  );
  test(
    'resuming during a flight preserves the pending kick when its question is still current',
    () async {
      final repo = Transport()..outcome = 'correct';
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      final session = await CaptureSession.open(p, fix);
      session.aiming();
      final shot = session.fire()!;
      await session.refresh();
      expect(session.phase, AttackPhase.flying);
      await session.resolveKick(shot, const Offset(-90, -180));
      expect(p.state.hp, 93.75);
      expect(session.correct, 1);
      session.close();
      p.dispose();
    },
  );
  test('stale point responses cannot undo newer shared health', () {
    final p = GamePoint(
      Transport(),
      playerTeam: GameTeam.artStuff,
      spot: testSpot(),
    );
    p.apply(const PointState(hp: 50, revision: 2));
    p.apply(const PointState(hp: 75, revision: 1));
    expect(p.state.hp, 50);
    p.dispose();
  });
  test(
    'four answer lanes agree with kick geometry and invalid swipes are rejected',
    () {
      for (var i = 0; i < 4; i++) {
        expect(FootballShot.fromSwipe(Offset(-90 + i * 60, -180))!.goal, i);
      }
      expect(FootballShot.fromSwipe(const Offset(0, -180))!.goal, isNull);
      expect(FootballShot.fromSwipe(const Offset(401, -180)), isNull);
      expect(FootballShot.fromSwipe(const Offset(0, -651)), isNull);
      expect(FootballShot.fromSwipe(const Offset(0, 40)), isNull);
    },
  );
  testWidgets(
    'point card and Attack use the same nested navigator; game is visible above card',
    (tester) async {
      final repo = Transport();
      final p = GamePoint(
        repo,
        playerTeam: GameTeam.artStuff,
        spot: testSpot(),
      );
      await p.load();
      final inner = GlobalKey<NavigatorState>();
      CaptureSession? s;
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: inner,
            observers: [gameRouteObserver],
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => PointCard(
                      point: p,
                      reason: () => null,
                      distance: () => 0,
                      onAttack: () async {
                        s = await CaptureSession.open(p, fix);
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GameHost(
                              gameId: 'free-kick',
                              session: GameSessionContext(
                                spotId: s!.point.spotId,
                                startedAt: DateTime.now(),
                                capture: s,
                              ),
                              factory: (session, exit) =>
                                  PreviewGame(session, exit),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  child: const Text('Point'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Attack'));
      await tester.tap(find.text('Attack'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Question 0'), findsOneWidget);
      expect(find.byType(PointCard), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PointCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      s?.close();
      p.dispose();
    },
  );
}
