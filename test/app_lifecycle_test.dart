import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/map/map_lifecycle.dart';
import 'package:campus_app/map/map_view_restoration.dart';
import 'package:campus_app/map/campus_geography.dart';
import 'package:campus_app/teams/team_gate.dart';
import 'package:campus_app/teams/game_team.dart';
import 'team_membership_test.dart' show MemoryTeams;

class ViewHarness extends StatefulWidget {
  const ViewHarness({super.key});
  @override
  State<ViewHarness> createState() => _ViewHarnessState();
}

class _ViewHarnessState extends State<ViewHarness> with RestorationMixin {
  final view = RestorableMapView();
  @override
  String get restorationId => 'campus-view';
  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(view, 'view');
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(
      () => view.value = const MapViewState(
        center: CampusPoint(-98.16946621, 26.30304392),
        zoom: 16.8,
        overview: false,
        following: true,
        locationEnabled: true,
      ),
    ),
    child: Text(
      view.value == null
          ? 'New map'
          : 'Restored ${view.value!.zoom} ${view.value!.following}',
    ),
  );
  @override
  void dispose() {
    view.dispose();
    super.dispose();
  }
}

void main() {
  test(
    'focus changes preserve visible map; hide/pause and resume are deduplicated',
    () {
      final life = MapLifecycle();
      expect(life.accept(AppLifecycleState.inactive), MapLifecycleChange.none);
      expect(life.foreground, isTrue);
      expect(life.accept(AppLifecycleState.resumed), MapLifecycleChange.none);
      expect(life.accept(AppLifecycleState.hidden), MapLifecycleChange.suspend);
      expect(life.accept(AppLifecycleState.paused), MapLifecycleChange.none);
      expect(life.foreground, isFalse);
      expect(life.accept(AppLifecycleState.inactive), MapLifecycleChange.none);
      expect(life.accept(AppLifecycleState.resumed), MapLifecycleChange.resume);
      expect(life.accept(AppLifecycleState.resumed), MapLifecycleChange.none);
    },
  );
  test(
    'new GPS start waits for old cancellation, and errors do not poison later transitions',
    () async {
      final queue = SerialMapOperations(), cancel = Completer<void>();
      final events = <String>[];
      final stop = queue.run(() async {
        events.add('cancel');
        await cancel.future;
        events.add('cancelled');
      });
      final start = queue.run(() async {
        events.add('start');
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, ['cancel']);
      cancel.complete();
      await Future.wait([stop, start]);
      expect(events, ['cancel', 'cancelled', 'start']);
      await expectLater(
        queue.run(() async {
          throw StateError('native service error');
        }),
        throwsStateError,
      );
      await queue.run(() async {
        events.add('recovered');
      });
      expect(events.last, 'recovered');
    },
  );
  test(
    'untrusted/corrupt restored camera data cannot create invalid camera positions',
    () {
      final view = RestorableMapView();
      expect(view.fromPrimitives({'version': 999}), isNull);
      expect(
        view.fromPrimitives({
          'version': 1,
          'latitude': double.nan,
          'longitude': 0,
          'zoom': 17,
        }),
        isNull,
      );
    },
  );
  testWidgets(
    'account navigator restores map state and isolates another account',
    (tester) async {
      final repo = MemoryTeams()..saved = GameTeam.artStuff;
      Widget app(String account) => MaterialApp(
        restorationScopeId: 'utrgv-go',
        home: RestorationScope(
          restorationId: 'account-$account',
          child: TeamGate(
            key: ValueKey(account),
            repository: repo,
            onSignOut: () async {},
            child: const ViewHarness(),
          ),
        ),
      );
      await tester.pumpWidget(app('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New map'));
      await tester.pumpAndSettle();
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(find.text('Restored 16.8 true'), findsOneWidget);
      await tester.pumpWidget(app('b'));
      await tester.pumpAndSettle();
      expect(find.text('New map'), findsOneWidget);
    },
  );
  testWidgets('system Back reaches the account navigator before app exit', (
    tester,
  ) async {
    final repo = MemoryTeams()..saved = GameTeam.artStuff;
    await tester.pumpWidget(
      MaterialApp(
        home: TeamGate(
          repository: repo,
          onSignOut: () async {},
          child: const ViewHarness(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ViewHarness))).push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('PROFILE ROUTE')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('PROFILE ROUTE'), findsNothing);
    expect(find.text('New map'), findsOneWidget);
    final native = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        native.add(call.method);
        return null;
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(native, contains('SystemNavigator.pop'));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
