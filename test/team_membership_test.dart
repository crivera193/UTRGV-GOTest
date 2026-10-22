import 'dart:async';
import 'package:campus_app/teams/game_team.dart';
import 'package:campus_app/teams/team_membership.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTeams implements TeamRepository {
  GameTeam? saved;
  bool loadFails = false, saveFails = false, commitThenTimeout = false;
  int writes = 0;
  Completer<GameTeam>? pending;
  @override
  Future<GameTeam?> load() async {
    if (loadFails) throw TimeoutException('offline');
    return saved;
  }

  @override
  Future<GameTeam> choose(GameTeam team) async {
    writes++;
    if (saveFails) throw TimeoutException('offline');
    if (pending != null) return pending!.future;
    saved ??= team;
    if (commitThenTimeout) throw TimeoutException('response lost');
    return saved!;
  }
}

void main() {
  test('query errors never become missing membership', () async {
    final repo = MemoryTeams()..loadFails = true;
    final state = TeamMembership(repo);
    await state.load();
    expect(state.phase, TeamPhase.error);
    await state.choose(GameTeam.artStuff);
    expect(repo.writes, 0);
    repo.loadFails = false;
    await state.load();
    expect(state.phase, TeamPhase.missing);
    state.dispose();
  });
  test(
    'failed save stays gated; retry reconciles authoritative winner',
    () async {
      final repo = MemoryTeams()..saveFails = true;
      final state = TeamMembership(repo);
      await state.load();
      await state.choose(GameTeam.artStuff);
      expect(state.phase, TeamPhase.missing);
      expect(state.team, isNull);
      repo.saved = GameTeam.mathEngineering; // Another device completed first.
      await state.choose(GameTeam.artStuff);
      expect(state.team, GameTeam.mathEngineering);
      expect(repo.writes, 1);
      state.dispose();
    },
  );
  test(
    'lost response rereads membership and confirms committed choice',
    () async {
      final repo = MemoryTeams()..commitThenTimeout = true;
      final state = TeamMembership(repo);
      await state.load();
      await state.choose(GameTeam.healthScience);
      expect(state.phase, TeamPhase.assigned);
      expect(state.team, GameTeam.healthScience);
      state.dispose();
    },
  );
  test(
    'duplicate confirmation and late response after account switch ignored',
    () async {
      final repo = MemoryTeams()..pending = Completer<GameTeam>();
      final first = TeamMembership(repo);
      await first.load();
      final save = first.choose(GameTeam.artStuff);
      await Future<void>.delayed(Duration.zero);
      await first.choose(GameTeam.mathEngineering);
      expect(repo.writes, 1);
      first.dispose();
      final second = TeamMembership(MemoryTeams());
      await second.load();
      repo.pending!.complete(GameTeam.artStuff);
      await save;
      expect(second.phase, TeamPhase.missing);
      expect(second.team, isNull);
      second.dispose();
    },
  );
  test('restart and a second client read the same stored membership', () async {
    final repo = MemoryTeams();
    final first = TeamMembership(repo);
    await first.load();
    await first.choose(GameTeam.artStuff);
    first.dispose();
    final another = TeamMembership(repo);
    await another.load();
    expect(another.phase, TeamPhase.assigned);
    expect(another.team, GameTeam.artStuff);
    another.dispose();
  });
  test('unknown server team is rejected, never silently remapped', () {
    expect(() => GameTeam.fromId('legacy'), throwsFormatException);
  });
}
