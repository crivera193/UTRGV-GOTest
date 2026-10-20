import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_app/games/chapel_capture.dart';
import 'package:campus_app/games/chapel_card.dart';
import 'package:campus_app/games/chapel_football_game.dart';
import 'package:campus_app/games/football_shot.dart';
import 'package:campus_app/games/game_host.dart';
import 'package:campus_app/games/game_spot.dart';
import 'package:campus_app/games/spot_proximity.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/map/campus_location.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryPoint implements PointPersistence {
  PointState state = PointState.initial;
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<PointState> load() async => state;
  @override
  Future<void> save(PointState next) async {
    writes++;
    await pending?.future;
    state = next;
  }
}

Future<void> outcome(CaptureSession s, ShotOutcome result) async {
  s.aiming();
  final id = s.fire()!;
  await s.resolve(id, result);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final packages =
        jsonDecode(
              await File('.dart_tool/package_config.json').readAsString(),
            )['packages']
            as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
    final iconFile = File.fromUri(
      Uri.parse('${flutter['rootUri']}/').resolve(
        '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
    await (FontLoader(
      'MaterialIcons',
    )..addFont(iconFile.readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
  });
  test(
    '130-foot exact radius; uncertainty, age, accuracy, campus and exit hysteresis',
    () {
      const spot = GameSpot(
        id: 'synthetic',
        name: 'Synthetic chapel',
        point: CampusPoint(0, 0),
        entryMeters: 39.624,
        exitMeters: 45,
        attackMeters: 39.624,
      );
      final p = SpotProximity([spot]), now = DateTime.utc(2026);
      void fix(
        double meters, {
        double accuracy = 0,
        int seconds = 0,
        bool campus = true,
      }) => p.accept(
        CampusFix(
          CampusPoint(meters / 6378137 * 180 / 3.141592653589793, 0),
          accuracy,
          now.add(Duration(seconds: seconds)),
        ),
        onCampus: campus,
        now: now.add(Duration(seconds: seconds)),
      );
      fix(39.623);
      expect(p.attackReason(spot, now), isNull);
      fix(39.625, seconds: 1);
      expect(
        p.attackReason(spot, now.add(const Duration(seconds: 1))),
        isNotNull,
      );
      fix(0, seconds: 2);
      fix(0, seconds: 5);
      expect(p.state, SpotState.eligible);
      fix(41, seconds: 6);
      expect(p.state, SpotState.eligible);
      expect(p.launch(now.add(const Duration(seconds: 6))), isNull);
      fix(35, accuracy: 5, seconds: 7);
      expect(
        p.attackReason(spot, now.add(const Duration(seconds: 7))),
        isNotNull,
      );
      fix(0, seconds: 8);
      expect(
        p.attackReason(spot, now.add(const Duration(seconds: 19))),
        isNotNull,
      );
      fix(0, accuracy: 16, seconds: 20);
      expect(
        p.attackReason(spot, now.add(const Duration(seconds: 20))),
        isNotNull,
      );
      fix(0, seconds: 21, campus: false);
      expect(
        p.attackReason(spot, now.add(const Duration(seconds: 21))),
        isNotNull,
      );
    },
  );
  test(
    'all four goals reachable; no answer steering; aperture and bad swipes',
    () {
      for (var i = 0; i < 4; i++) {
        final shot = FootballShot.fromSwipe(
          Offset(FootballShot.centers[i] / 30 * 180, -180),
        )!;
        expect(shot.goal, i);
        expect(shot.h(shot.crossingTime), greaterThan(3));
        expect(shot.vh - 9.8 * shot.crossingTime, lessThan(0));
      }
      expect(FootballShot.fromSwipe(const Offset(0, -10)), isNull);
      expect(FootballShot.fromSwipe(const Offset(0, 100)), isNull);
      expect(FootballShot.fromSwipe(const Offset(500, -180))!.goal, isNull);
      expect(FootballShot(0, 24, 9).goal, isNull); // gap between goals
      expect(FootballShot(-9.6, 24, 0).goal, isNull); // below crossbar
      expect(FootballShot(-9.6, 24, 30).goal, isNull); // above posts
    },
  );
  test(
    'three misses, immediate wrong loss and stable question on retry',
    () async {
      final point = ChapelPoint(MemoryPoint());
      await point.load();
      final s = CaptureSession(point);
      final q = s.question;
      await outcome(s, ShotOutcome.miss);
      expect(s.shots, 2);
      s.continuePlay();
      expect(s.question, same(q));
      await outcome(s, ShotOutcome.miss);
      s.continuePlay();
      await outcome(s, ShotOutcome.miss);
      expect(s.phase, AttackPhase.sessionEnded);
      expect(point.state.hp, 100);
      final wrong = CaptureSession(point);
      await outcome(wrong, ShotOutcome.wrong);
      expect(wrong.shots, 2);
      expect(wrong.phase, AttackPhase.sessionEnded);
    },
  );
  test(
    'exactly once damage, new question resets shots, capture restores HP, friendly blocked',
    () async {
      final memory = MemoryPoint();
      final point = ChapelPoint(memory);
      await point.load();
      final s = CaptureSession(point);
      await outcome(s, ShotOutcome.miss);
      s.continuePlay();
      s.aiming();
      final id = s.fire()!;
      expect(s.fire(), isNull);
      await Future.wait([
        s.resolve(id, ShotOutcome.correct),
        s.resolve(id, ShotOutcome.correct),
      ]);
      expect(point.state.hp, 75);
      expect(memory.writes, 1);
      s.continuePlay();
      expect(s.shots, 3);
      expect(s.questionIndex, 1);
      for (var i = 0; i < 3; i++) {
        await outcome(s, ShotOutcome.correct);
        if (i < 2) s.continuePlay();
      }
      expect(s.captured, isTrue);
      expect(s.phase, AttackPhase.sessionEnded);
      expect(point.state.owner, 'Team A');
      expect(point.state.hp, 100);
      expect(await point.damage(), isFalse);
      expect(memory.writes, 4);
    },
  );
  test(
    'damage survives failed later answer and close/reopen; stale callbacks ignored',
    () async {
      final point = ChapelPoint(MemoryPoint());
      await point.load();
      final s = CaptureSession(point);
      await outcome(s, ShotOutcome.correct);
      s.continuePlay();
      await outcome(s, ShotOutcome.wrong);
      s.close();
      final reopened = CaptureSession(point);
      expect(point.state.hp, 75);
      expect(reopened.shots, 3);
      reopened.aiming();
      final id = reopened.fire()!;
      reopened.close();
      await reopened.resolve(id, ShotOutcome.correct);
      expect(point.state.hp, 75);
      reopened.cancelAim();
      expect(reopened.fire(), isNull);
    },
  );
  test('local persistence roundtrip and debug reset without backend', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalPointPersistence();
    final point = ChapelPoint(store);
    await point.load();
    await point.damage();
    expect((await store.load()).hp, 75);
    await point.reset();
    expect((await store.load()).owner, 'Team B');
    expect((await store.load()).hp, 100);
  });
  test(
    'close during a valid earned write does not advance or notify closed session',
    () async {
      final memory = MemoryPoint()..pending = Completer<void>();
      final point = ChapelPoint(memory);
      await point.load();
      final s = CaptureSession(point);
      s.aiming();
      final id = s.fire()!;
      final save = s.resolve(id, ShotOutcome.correct);
      expect(point.busy, isTrue);
      final premature = CaptureSession(point);
      premature.aiming();
      expect(premature.fire(), isNull);
      s.close();
      memory.pending!.complete();
      await save;
      expect(point.state.hp, 75);
      expect(s.phase, AttackPhase.sessionEnded);
      expect(s.questionIndex, 0);
    },
  );
  testWidgets(
    'real Flame render, analytic long frame crossing, pause, close and reopen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final point = ChapelPoint(MemoryPoint());
      await point.load();
      final attack = CaptureSession(point);
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('output/chapel-review/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          navigatorObservers: [gameRouteObserver],
          home: RepaintBoundary(
            key: boundary,
            child: GameHost(
              gameId: 'chapel-football',
              session: GameSessionContext(
                spotId: 'synthetic',
                startedAt: DateTime.utc(2026),
                debug: true,
                capture: attack,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(GameWidget<SessionGame>), findsOneWidget);
      await capture('four-goal-widget');
      final game =
          tester
                  .widget<GameWidget<SessionGame>>(
                    find.byType(GameWidget<SessionGame>),
                  )
                  .game!
              as ChapelFootballGame;
      final widgetFinder = find.byType(GameWidget<SessionGame>);
      final origin = tester.getTopLeft(widgetFinder),
          field = tester.getSize(widgetFinder);
      Offset device(double x, double y) =>
          origin + Offset(x / 400 * field.width, y / 650 * field.height);
      game.onDragStart(
        DragStartEvent(
          1,
          game,
          DragStartDetails(globalPosition: device(200, 520)),
        ),
      );
      expect(attack.phase, AttackPhase.aiming);
      game.onDragStart(
        DragStartEvent(
          2,
          game,
          DragStartDetails(globalPosition: device(200, 520)),
        ),
      );
      game.onDragUpdate(
        DragUpdateEvent(
          1,
          game,
          DragUpdateDetails(
            globalPosition: device(200, 520),
            delta: device(110, 340) - device(200, 520),
          ),
        ),
      );
      game.onDragCancel(DragCancelEvent(1));
      expect(attack.phase, AttackPhase.questionReady);
      expect(
        attack.shotId,
        0,
      ); // Flame's cancel-to-end delegation must not fire.
      game.onDragEnd(DragEndEvent(2, DragEndDetails()));
      expect(attack.shotId, 0);
      attack.aiming();
      game.setVisible(false);
      expect(attack.phase, AttackPhase.questionReady);
      expect(game.paused, isTrue);
      game.setVisible(true);
      for (var i = 0; i < 4; i++) {
        attack.aiming();
        final target = FootballShot.centers[i];
        game.shootSwipe(Offset(target / 30 * 180, -180));
        game.update(5); // Deliberately skip across the plane in one update.
        await tester.pump();
        expect(point.state.hp, i == 3 ? 100 : 100 - 25 * (i + 1));
        game.update(5); // A second update must never award another hit.
        if (i < 3) attack.continuePlay();
      }
      await tester.pump();
      await capture('capture-result-widget');
      await tester.pumpWidget(const SizedBox());
      expect(attack.closed, isTrue);
      final next = CaptureSession(point);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          home: GameHost(
            gameId: 'chapel-football',
            session: GameSessionContext(
              spotId: 'synthetic',
              startedAt: DateTime.utc(2026),
              capture: next,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(next.shots, 3);
      expect(next.questionIndex, 0);
      await tester.pumpWidget(const SizedBox());
      await point.reset();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          home: RepaintBoundary(
            key: boundary,
            child: ChapelCard(
              point: point,
              reason: () => 'Outside attack range',
              distance: () => 150,
              onAttack: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await capture('chapel-card-widget');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Attack'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          home: RepaintBoundary(
            key: boundary,
            child: const Scaffold(
              body: Center(child: ChapelBeacon(owner: 'Team B')),
            ),
          ),
        ),
      );
      await tester.pump();
      await capture('beacon-only-widget');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
