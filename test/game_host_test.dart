import 'dart:async';
import 'package:campus_app/games/game_host.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LoadingGame extends PreviewGame {
  LoadingGame(super.session, super.onExit, this.loading);
  final Future<void> loading;
  bool disposed = false;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await loading;
  }

  @override
  void onDispose() {
    disposed = true;
    super.onDispose();
  }
}

void main() {
  final session = GameSessionContext(
    spotId: 'synthetic',
    startedAt: DateTime.utc(2026),
  );
  testWidgets(
    'real GameWidget updates, pauses under route/background, exits to retained map',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      var creates = 0;
      late PreviewGame game;
      final mapKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [gameRouteObserver],
          home: Scaffold(body: SizedBox(key: mapKey)),
        ),
      );
      final mapElement = mapKey.currentContext;
      GameExit? result;
      unawaited(
        nav.currentState!
            .push<GameExit>(
              MaterialPageRoute(
                builder: (_) => GameHost(
                  gameId: 'preview',
                  session: session,
                  factory: (s, exit) {
                    creates++;
                    return game = PreviewGame(s, exit);
                  },
                ),
              ),
            )
            .then((value) => result = value),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(GameWidget<SessionGame>), findsOneWidget);
      final elapsed = game.elapsed;
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.elapsed, greaterThan(elapsed));
      expect(creates, 1);
      expect(identical(game.images, Flame.images), isFalse);
      unawaited(
        nav.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(game.paused, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(game.paused, isTrue); // still covered
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(game.paused, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(game.paused, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(game.paused, isFalse);
      game.onExit(
        GameExit.previewClosed,
      ); // direct callback, no input automation
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(result, GameExit.previewClosed);
      expect(mapKey.currentContext, same(mapElement));
      expect(creates, 1);
    },
  );
  testWidgets(
    'loading error retries with a new instance and disposes the failed one',
    (tester) async {
      final load = Completer<void>();
      final games = <LoadingGame>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [gameRouteObserver],
          home: GameHost(
            gameId: 'preview',
            session: session,
            factory: (s, exit) {
              final g = LoadingGame(
                s,
                exit,
                games.isEmpty ? load.future : Future.value(),
              );
              games.add(g);
              return g;
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      load.completeError(StateError('synthetic loading failure'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Unable to load game.'), findsOneWidget);
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
          .onPressed!();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(games, hasLength(2));
      expect(games.first.disposed, isTrue);
      expect(find.text('Unable to load game.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(games.last.disposed, isTrue);
    },
  );
}
