import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

void check(bool v, String m) {
  if (!v) throw StateError(m);
}

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  final out = Directory('output/team-e2e/live')..createSync(recursive: true);
  Future<dynamic> cmd(String op, [Map<String, dynamic> more = const {}]) async {
    final value = await d.requestData(
      jsonEncode({'op': op, ...more}),
      timeout: const Duration(seconds: 55),
    );
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  Future<void> tap(String text) async {
    await d.scrollIntoView(
      find.text(text),
      timeout: const Duration(seconds: 15),
    );
    await d.tap(find.text(text));
  }

  Future<void> screen(String name) async {
    await File('${out.path}/$name.png').writeAsBytes(await d.screenshot());
  }

  try {
    await d.runUnsynchronized(() async {
      final info = await cmd('inspect');
      stdout.writeln(jsonEncode(info));
      check(info['user'] != null, 'Existing synthetic login required');
      check(
        info['ui_team'] != null,
        'Permanent team must load without onboarding',
      );
      await cmd('play');
      await tap('Attack');
      await d.waitFor(
        find.text('Swipe forward from the football. Aim for your answer.'),
        timeout: const Duration(seconds: 55),
      );
      var g = await cmd('game');
      stdout.writeln(jsonEncode(g));
      await screen('open');
      if (args.first == 'prepare') {
        // Real pointer miss must consume the current question, even after >3 losses.
        final before = g;
        await cmd('swipe', {'dx': 0, 'dy': -180});
        await d.waitFor(
          find.text('Miss. No damage. Next question.'),
          timeout: const Duration(seconds: 55),
        );
        await tap('Continue');
        g = await cmd('game');
        check(
          g['question_id'] != before['question_id'],
          'Miss did not advance',
        );
        check(g['hp'] == before['hp'], 'Miss damaged point');
        await File(
          '${out.path}/before-close.json',
        ).writeAsString(jsonEncode(g));
        await screen('before-close');
        stdout.writeln(
          'PASS: actual card > Attack > pointer miss > next question',
        );
      } else {
        final before =
            jsonDecode(
                  await File('${out.path}/before-close.json').readAsString(),
                )
                as Map;
        check(
          g['attack_id'] == before['attack_id'],
          'Cold launch rerolled attack',
        );
        check(
          g['question_id'] == before['question_id'],
          'Cold launch rerolled question',
        );
        check(g['hp'] == before['hp'], 'Cold launch lost damage');
        final answers = {
          'qa-live-add': '4',
          'qa-live-shape': '3',
          'qa-live-light': 'Red',
          'qa-live-safe': 'Safe outdoor path',
        };
        final lane = (g['answers'] as List).indexOf(answers[g['bank_id']]);
        check(lane >= 0, 'QA answer missing');
        await cmd('swipe', {'dx': -90 + lane * 60, 'dy': -180});
        await d.waitFor(
          find.text('Continue'),
          timeout: const Duration(seconds: 55),
        );
        final after = await cmd('game');
        check(
          after['hp'] == (g['hp'] as int) - 25,
          'Correct pointer kick failed to damage live point',
        );
        await screen('correct-saved');
        await tap('Continue');
        final next = await cmd('game');
        final nextLane = (next['answers'] as List).indexOf(
          answers[next['bank_id']],
        );
        await cmd('swipe', {'dx': -90 + nextLane * 60, 'dy': -180});
        await d.waitFor(
          find.text('Capture complete · Return to map'),
          timeout: const Duration(seconds: 55),
        );
        final captured = await cmd('game');
        check(
          captured['hp'] == 100 && captured['phase'] == 'sessionEnded',
          'Capture failed',
        );
        await screen('captured-online');
        await File(
          '${out.path}/after-reopen.json',
        ).writeAsString(jsonEncode(after));
        await tap('Close');
        await d.waitFor(find.text('Attack'));
        await screen('back-to-card');
        stdout.writeln(
          'PASS: cold restart preserved team/attack/question/HP; actual correct pointer kick saved 25 damage and returned to card',
        );
      }
    });
  } finally {
    await d.close();
  }
}
