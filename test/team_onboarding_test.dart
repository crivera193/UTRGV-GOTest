import 'dart:async';
import 'package:campus_app/teams/game_team.dart';
import 'package:campus_app/teams/team_gate.dart';
import 'package:campus_app/teams/team_selection_game.dart';
import 'package:campus_app/teams/team_selection_screen.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'team_membership_test.dart' show MemoryTeams;

void main() {
  setUpAll(() async {
    for (final entry in {
      'DMSerifDisplay': 'assets/fonts/DMSerifDisplay-Regular.ttf',
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  Future<void> open(
    WidgetTester tester,
    MemoryTeams repo, {
    Size size = const Size(390, 844),
    double scale = 1,
    String account = 'a',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: TeamGate(
            key: ValueKey(account),
            repository: repo,
            onSignOut: () async {},
            child: const Scaffold(body: Text('MAIN APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    if (find.byType(GameWidget<TeamSelectionGame>).evaluate().isNotEmpty) {
      final game = tester
          .widget<GameWidget<TeamSelectionGame>>(
            find.byType(GameWidget<TeamSelectionGame>),
          )
          .game!;
      for (var frame = 0; frame < 100 && !game.isLoaded; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(game.isLoaded, isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets(
    'all pillars show info; cancel and system back never save or bypass',
    (tester) async {
      final repo = MemoryTeams();
      await open(tester, repo);
      expect(find.text('MAIN APP'), findsNothing);
      for (final team in GameTeam.values) {
        await tester.tap(find.byKey(ValueKey('team-${team.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('This choice is permanent.'), findsOneWidget);
        expect(find.text('${team.colorName} team'), findsOneWidget);
        expect(repo.writes, 0);
        await tester.tap(find.text('Choose another'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TeamConfirmationDialog), findsNothing);
        expect(repo.writes, 0);
      }
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Find your team.'), findsOneWidget);
      expect(find.text('MAIN APP'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit confirmation disables duplicate save and enters app only after server success',
    (tester) async {
      final repo = MemoryTeams()..pending = Completer<GameTeam>();
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('team-art_stuff')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Choose team'));
      await tester.pump();
      expect(repo.writes, 1);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Choose another'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('MAIN APP'), findsNothing);
      repo.pending!.complete(GameTeam.artStuff);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('MAIN APP'), findsOneWidget);
      expect(find.byType(TeamConfirmationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save stays in dialog and never unlocks app', (
    tester,
  ) async {
    await open(tester, MemoryTeams()..saveFails = true);
    await tester.tap(find.byKey(const ValueKey('team-health_science')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose team'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(TeamConfirmationDialog),
        matching: find.textContaining('Your choice was not saved'),
      ),
      findsOneWidget,
    );
    expect(find.text('MAIN APP'), findsNothing);
    expect(find.byType(TeamConfirmationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assigned restored account skips; switching to teamless account discards routes and state',
    (tester) async {
      await open(tester, MemoryTeams()..saved = GameTeam.healthScience);
      expect(find.text('MAIN APP'), findsOneWidget);
      final context = tester.element(find.text('MAIN APP'));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('PRIVATE GAME ROUTE')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await open(tester, MemoryTeams(), account: 'b');
      expect(find.text('PRIVATE GAME ROUTE'), findsNothing);
      expect(find.text('MAIN APP'), findsNothing);
      expect(find.text('Find your team.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed membership check exposes retry instead of choices or main app',
    (tester) async {
      final repo = MemoryTeams()..loadFails = true;
      await open(tester, repo);
      expect(find.text('Retry team check'), findsOneWidget);
      expect(find.text('MAIN APP'), findsNothing);
      expect(find.byType(TeamSelectionScreen), findsNothing);
      repo.loadFails = false;
      await tester.tap(find.text('Retry team check'));
      await tester.pump();
      expect(find.byType(TeamSelectionScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scene pauses under dialog and stays paused through background/resume',
    (tester) async {
      await open(tester, MemoryTeams());
      final game = tester
          .widget<GameWidget<TeamSelectionGame>>(
            find.byType(GameWidget<TeamSelectionGame>),
          )
          .game!;
      expect(game.reducedMotion, isTrue);
      await tester.tap(find.byKey(const ValueKey('team-health_science')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.paused, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(game.paused, isTrue);
      await tester.tap(find.text('Choose another'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.paused, isFalse);
    },
  );

  testWidgets('real scene and confirmation review captures', (tester) async {
    await open(tester, MemoryTeams());
    if (const bool.fromEnvironment('CAPTURE_TEAM_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../output/team-review/scene-390x844.png'),
      );
    }
    await tester.tap(find.byKey(const ValueKey('team-math_engineering')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (const bool.fromEnvironment('CAPTURE_TEAM_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../output/team-review/confirmation-390x844.png'),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small phone, landscape and large text retain reachable semantic choices',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        await open(
          tester,
          MemoryTeams(),
          size: size,
          scale: 1.6,
          account: size.toString(),
        );
        for (final team in GameTeam.values) {
          final button = find.widgetWithText(TextButton, team.displayName);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('Choose another'));
          await tester.tap(find.text('Choose another'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
}
