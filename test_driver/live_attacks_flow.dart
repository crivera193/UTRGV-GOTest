import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  final out = Directory('output/team-e2e/timed')..createSync(recursive: true);
  Future<dynamic> cmd(String op, [Map<String, dynamic> more = const {}]) async {
    final value = await driver.requestData(
      jsonEncode({'op': op, ...more}),
      timeout: const Duration(seconds: 30),
    );
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  Future<void> capture(String name) async =>
      File('${out.path}/$name.png').writeAsBytes(await driver.screenshot());
  Future<Map> gameWhere(bool Function(Map) predicate) async {
    final until = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(until)) {
      final game = await cmd('game') as Map;
      if (predicate(game)) return game;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('Timed game did not reach expected state');
  }

  try {
    await driver.runUnsynchronized(() async {
      final info = await cmd('inspect');
      check(info['ui_team'] == 'art_stuff', 'Permanent team not restored');
      final point = await cmd('play');
      if (args.first == 'prepare') {
        check(point['cooldown'] == 0, 'QA point already used');
        await driver.scrollIntoView(find.text('Attack'));
        await driver.tap(find.text('Attack'));
        var game = await gameWhere(
          (g) => g['question_number'] == 1 && g['phase'] == 'questionReady',
        );
        check(
          (game['seconds'] as int) > 0 && (game['seconds'] as int) <= 15,
          'Missing live timer',
        );
        await capture('timer-question-one');
        game = await gameWhere(
          (g) =>
              g['losses'] == 1 &&
              g['question_number'] == 2 &&
              g['phase'] == 'questionReady',
        );
        check(game['hp'] == 100, 'Timeout caused damage');
        await capture('automatic-timeout');
        final answers = {
          'qa-live-add': '4',
          'qa-live-shape': '3',
          'qa-live-light': 'Red',
          'qa-live-safe': 'Safe outdoor path',
        };
        final lane = (game['answers'] as List).indexOf(
          answers[game['bank_id']],
        );
        check(lane >= 0, 'Missing QA choice');
        await cmd('swipe', {'dx': -90 + lane * 60, 'dy': -180});
        game = await gameWhere(
          (g) =>
              g['correct'] == 1 &&
              g['question_number'] == 3 &&
              g['phase'] == 'questionReady',
        );
        check(game['hp'] == 93.75, 'Correct kick did not remove exactly 6.25%');
        await File(
          '${out.path}/before-close.json',
        ).writeAsString(jsonEncode(game));
        await capture('fractional-damage');
        stdout.writeln(
          'PASS: native timer auto-advanced; real pointer kick dealt exactly 6.25%; next timed question loaded automatically.',
        );
      } else {
        final before =
            jsonDecode(
                  await File('${out.path}/before-close.json').readAsString(),
                )
                as Map;
        check(point['hp'] == 93.75, 'Cold launch lost earned damage');
        check(point['can_resume'] == false, 'Expired questions restarted');
        check((point['cooldown'] as int) > 0, 'Cold launch bypassed cooldown');
        final state = await cmd('read_attack', {
          'attack_id': before['attack_id'],
        });
        check(
          state['sequence'] == 4 && state['status'] == 'completed',
          'Offline questions did not expire',
        );
        check(
          state['correct_count'] == 1 && state['timeout_count'] == 3,
          'Offline timeout totals incorrect',
        );
        final text = await driver.getText(
          find.byValueKey('point-attack-reason'),
        );
        check(
          text.startsWith('Attack available in '),
          'Cooldown missing from point card',
        );
        await capture('cold-relaunch-cooldown');
        await File(
          '${out.path}/after-reopen.json',
        ).writeAsString(jsonEncode(state));
        stdout.writeln(
          'PASS: COLD restart preserved team/6.25% damage, counted all three unanswered questions as losses, and kept the per-point cooldown.',
        );
      }
    });
  } finally {
    await driver.close();
  }
}
