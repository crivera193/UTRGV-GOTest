import 'dart:async';
import 'package:campus_app/games/chapel_capture.dart';
import 'package:campus_app/games/chapel_card.dart';
import 'package:campus_app/games/football_shot.dart';
import 'package:campus_app/games/game_host.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:campus_app/teams/game_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Transport double only. Production contains no offline combat implementation.
class Transport implements AttackRepository {
  int sequence = 0, hp = 100, correct = 0, losses = 0, calls = 0;
  String outcome = 'miss';
  bool loseResponse = false, conflict = false;
  final receipts = <String, Map<String, dynamic>>{};
  Map<String, dynamic> payload() => {
    'id': 'attack',
    'status': hp == 0 ? 'captured' : 'active',
    'sequence': sequence,
    'correct_count': correct,
    'wrong_count': losses,
    'miss_count': 0,
    'point': {
      'owner_team_id': hp == 0 ? 'art_stuff' : null,
      'hp': hp == 0 ? 100 : hp,
      'max_hp': 100,
      'revision': correct,
    },
    'question': {
      'instance_id': 'q$sequence',
      'bank_id': 'bank$sequence',
      'prompt': 'Question $sequence',
      'choices': List.generate(4, (i) => {'id': '$i', 'text': 'Choice $i'}),
    },
  };
  @override
  Future<PointState> loadPoint(String _) async =>
      AttackState.fromJson(payload()).point;
  @override
  Stream<PointState> watchPoint(String _) => const Stream.empty();
  @override
  Future<AttackState> begin(String _, CampusFix fix, String requestId) async =>
      AttackState.fromJson(payload());
  @override
  Future<AttackState> read(String _) async => AttackState.fromJson(payload());
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
    final saved = receipts.putIfAbsent(cmd, () {
      expect(q, 'q$sequence');
      sequence++;
      if (outcome == 'correct') {
        hp -= 25;
        correct++;
      } else {
        losses++;
      }
      return {
        'outcome': outcome,
        'damage': outcome == 'correct' ? 25 : 0,
        'state': payload(),
      };
    });
    if (loseResponse) {
      loseResponse = false;
      throw StateError('Simulated lost response after commit');
    }
    return saved;
  }
}

Future<void> kick(CaptureSession s) async {
  s.aiming();
  await s.resolveKick(s.fire()!, const Offset(-90, -180));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fix = CampusFix(ChapelConfig.point, 1, DateTime.now());
  test(
    'each loss advances once; no three-question cutoff; damage only follows server receipt',
    () async {
      final repo = Transport();
      final p = ChapelPoint(repo, playerTeam: GameTeam.artStuff);
      final s = await CaptureSession.open(p, fix);
      for (var i = 0; i < 5; i++) {
        final old = s.question.id;
        await kick(s);
        expect(s.question.id, old);
        expect(p.state.hp, 100);
        expect(s.phase, AttackPhase.resolving);
        s.continuePlay();
        expect(s.question.id, isNot(old));
        expect(s.phase, AttackPhase.questionReady);
      }
      repo.outcome = 'correct';
      await kick(s);
      expect(p.state.hp, 75);
      s.continuePlay();
      s.close();
      final resumed = await CaptureSession.open(p, fix);
      expect(resumed.question.id, s.question.id);
      expect(resumed.losses, 5);
      expect(p.state.hp, 75);
      resumed.close();
      p.dispose();
    },
  );
  test(
    'lost commit response retries identical command without double damage or question skip',
    () async {
      final repo = Transport()
        ..outcome = 'correct'
        ..loseResponse = true;
      final p = ChapelPoint(repo, playerTeam: GameTeam.artStuff);
      final s = await CaptureSession.open(p, fix);
      await kick(s);
      expect(s.retryNeeded, true);
      expect(p.state.hp, 100);
      expect(repo.hp, 75);
      s.continuePlay();
      expect(s.phase, AttackPhase.resolving);
      await s.retryKick();
      expect(s.retryNeeded, false);
      expect(p.state.hp, 75);
      expect(repo.sequence, 1);
      expect(repo.calls, 2);
      s.continuePlay();
      expect(s.question.id, 'q1');
      s.close();
      p.dispose();
    },
  );
  test(
    'another device resolving a question refreshes without repeating the kick',
    () async {
      final repo = Transport()..conflict = true;
      final p = ChapelPoint(repo, playerTeam: GameTeam.artStuff);
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
  test('capture uses permanent team and keeps the captured message', () async {
    final repo = Transport()..outcome = 'correct';
    final p = ChapelPoint(repo, playerTeam: GameTeam.artStuff);
    final s = await CaptureSession.open(p, fix);
    for (var i = 0; i < 4; i++) {
      await kick(s);
      if (i < 3) s.continuePlay();
    }
    expect(s.captured, true);
    expect(p.friendly, true);
    expect(p.state.hp, 100);
    expect(s.message, contains('Art and Stuff captured'));
    expect(s.phase, AttackPhase.sessionEnded);
    s.close();
    p.dispose();
  });
  test('stale point responses cannot undo newer shared health', () {
    final p = ChapelPoint(Transport(), playerTeam: GameTeam.artStuff);
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
      final p = ChapelPoint(repo, playerTeam: GameTeam.artStuff);
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
                    builder: (_) => ChapelCard(
                      point: p,
                      reason: () => null,
                      distance: () => 0,
                      onAttack: () async {
                        s = await CaptureSession.open(p, fix);
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GameHost(
                              gameId: 'chapel-football',
                              session: GameSessionContext(
                                spotId: ChapelConfig.id,
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
      await tester.tap(find.text('Attack'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Question 0'), findsOneWidget);
      expect(find.byType(ChapelCard), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ChapelCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      s?.close();
      p.dispose();
    },
  );
}
