import 'dart:async';
import 'dart:typed_data';
import 'package:campus_app/trainer/trainer_profile.dart';
import 'package:campus_app/trainer/trainer_screen.dart';
import 'package:campus_app/teams/team_membership.dart';
import 'package:campus_app/teams/game_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'team_membership_test.dart' show MemoryTeams;

Map<String, dynamic> fixture({int xp = 150, int revision = 0}) => {
  'profile': {
    'username': 'qa_trainer',
    'display_name': 'QA Explorer',
    'bio': 'Campus explorer',
    'avatar_path': null,
    'revision': revision,
  },
  'progress': {
    'xp': xp,
    'correct_kicks': 4,
    'perfect_attacks': 1,
    'completed_attacks': 1,
    'captures': 0,
  },
  'levels': [
    {'level': 1, 'min_xp': 0},
    {'level': 2, 'min_xp': 100},
    {'level': 3, 'min_xp': 400},
  ],
  'ranks': [
    {'name': 'Newcomer', 'min_level': 1},
    {'name': 'Scout', 'min_level': 3},
  ],
  'settings': {'correct_xp': 25, 'perfect_xp': 50, 'capture_xp': 100},
  'achievements': [
    {
      'id': 'first',
      'title': 'First on Target',
      'description': 'One correct kick',
      'kind': 'achievement',
      'emblem': '★',
      'value': 4,
      'target': 1,
      'earned_at': '2026-10-22T12:00:00Z',
    },
    {
      'id': 'ten',
      'title': 'Sharp Shooter',
      'description': 'Ten correct kicks',
      'kind': 'badge',
      'emblem': '◎',
      'value': 4,
      'target': 10,
      'earned_at': null,
    },
  ],
};

class TrainerTransport implements TrainerRepository {
  Map<String, dynamic> json = fixture();
  final changes = StreamController<void>();
  int? savedRevision;
  bool fail = false;
  @override
  Future<TrainerSnapshot> load() async {
    if (fail) throw StateError('Offline');
    return TrainerSnapshot.fromJson(json);
  }

  @override
  Stream<void> watch() => changes.stream;
  @override
  Future<String> upload(Uint8List jpeg) async => 'own/photo.jpg';
  @override
  Future<void> save({
    required String username,
    required String name,
    required String bio,
    required String? avatar,
    required int revision,
  }) async {
    savedRevision = revision;
    if (revision != json['profile']['revision']) throw StateError('Conflict');
    json = {
      ...json,
      'profile': {
        ...json['profile'],
        'username': username,
        'display_name': name,
        'bio': bio,
        'avatar_path': avatar,
        'revision': revision + 1,
      },
    };
  }
}

void main() {
  test('level, rank and next threshold derive from editable catalog', () {
    var d = TrainerSnapshot.fromJson(fixture());
    expect(d.level, 2);
    expect(d.rank, 'Newcomer');
    expect(d.fraction, closeTo(1 / 6, .001));
    final j = fixture(xp: 400);
    d = TrainerSnapshot.fromJson(j);
    expect(d.level, 3);
    expect(d.rank, 'Scout');
    expect(d.nextLevel, isNull);
    expect(d.fraction, 1);
    expect(
      () => TrainerSnapshot.fromJson({...j, 'levels': []}),
      throwsFormatException,
    );
  });
  test('photo is bounded JPEG without original metadata', () {
    final original = img.Image(width: 100, height: 200);
    original.exif.gpsIfd[1] = 'N';
    final result = prepareTrainerPhoto(
      Uint8List.fromList(img.encodePng(original)),
    );
    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 512);
    expect(decoded.height, 512);
    expect(decoded.exif.gpsIfd.isEmpty, isTrue);
    expect(result.length, lessThan(2097152));
    expect(
      () => prepareTrainerPhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
  Future<void> screen(WidgetTester tester, TrainerTransport repo) async {
    final teams = TeamMembership(MemoryTeams()..saved = GameTeam.artStuff);
    await teams.load();
    await tester.pumpWidget(
      TeamScope(
        membership: teams,
        child: MaterialApp(home: TrainerScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'profile editing validates, saves and preserves server progress',
    (tester) async {
      final repo = TrainerTransport();
      await screen(tester, repo);
      expect(find.text('Level 2 · Newcomer'), findsOneWidget);
      expect(find.text('150 XP'), findsOneWidget);
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('trainer-username')),
        '!',
      );
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.savedRevision, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('trainer-username')),
        'new_trainer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('trainer-name')),
        'New Explorer',
      );
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.json['profile']['display_name'], 'New Explorer');
      expect(repo.json['progress']['xp'], 150);
      expect(find.text('Profile saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(repo.changes.close());
      await tester.pump();
    },
  );
  testWidgets('live updates do not replace an unsaved edit revision', (
    tester,
  ) async {
    final repo = TrainerTransport();
    await screen(tester, repo);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    repo.json = fixture(xp: 400, revision: 1);
    repo.changes.add(null);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save profile'));
    await tester.tap(find.text('Save profile'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.savedRevision, 0);
    expect(find.byKey(const ValueKey('trainer-error')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trainer-level')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Level 3 · Scout'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(repo.changes.close());
    await tester.pump();
  });
  testWidgets('load failure exposes retry instead of invented profile', (
    tester,
  ) async {
    final repo = TrainerTransport()..fail = true;
    await screen(tester, repo);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('150 XP'), findsNothing);
    repo.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('150 XP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(repo.changes.close());
    await tester.pump();
  });
}
