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
  final out = Directory('output/team-e2e/dynamic')..createSync(recursive: true);
  Future<dynamic> cmd(
    String op, [
    Map<String, dynamic> more = const {},
  ]) async => jsonDecode(
    await driver.requestData(
      jsonEncode({'op': op, ...more}),
      timeout: const Duration(seconds: 30),
    ),
  );
  Future<Map> until(String op, bool Function(Map) predicate) async {
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end)) {
      final value = await cmd(op) as Map;
      if (predicate(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Expected $op state was not reached');
  }

  Future<void> save(String name, Map data) async {
    await File('${out.path}/$name.json').writeAsString(jsonEncode(data));
    await File('${out.path}/$name.png').writeAsBytes(await driver.screenshot());
  }

  Map? marker(Map catalog, String name) => (catalog['markers'] as List)
      .cast<Map>()
      .where((m) => m['name'] == name)
      .firstOrNull;
  try {
    await driver.runUnsynchronized(() async {
      final info = await cmd('inspect');
      if (info['user'] == null) {
        final fixture = jsonDecode(
          await File('output/team-e2e/fixture.json').readAsString(),
        );
        await driver.tap(find.byValueKey('account-email'));
        await driver.enterText(fixture['a']);
        await driver.tap(find.byValueKey('account-password'));
        await driver.enterText(fixture['password']);
        await driver.tap(find.text('Sign in'));
      }
      if (!['catalog-edited', 'catalog-disabled'].contains(args.first)) {
        await driver.waitFor(
          find.byType('MainScreen'),
          timeout: const Duration(seconds: 40),
        );
      }
      if (args.first == 'catalog-start') {
        await cmd('catalog_map');
        final c = await until(
          'catalog',
          (c) => marker(c, 'QA map original') != null,
        );
        await save('catalog-before', c);
        stdout.writeln(
          'PASS: live Supabase catalog rendered as native Mapbox point marker.',
        );
      } else if (args.first == 'catalog-edited') {
        final before =
            jsonDecode(
                  await File('${out.path}/catalog-before.json').readAsString(),
                )
                as Map;
        final c = await until(
          'catalog',
          (c) =>
              marker(c, 'QA map renamed') != null &&
              marker(c, 'QA map newly added') != null &&
              marker(c, 'QA map original') == null,
        );
        final old = marker(before, 'QA map original')!,
            moved = marker(c, 'QA map renamed')!;
        check(
          ((old['x'] as num) - (moved['x'] as num)).abs() +
                  ((old['y'] as num) - (moved['y'] as num)).abs() >
              5,
          'Point marker did not move',
        );
        final point = (c['points'] as List).firstWhere(
          (p) => p['id'] == 'qa-dynamic-map-20261022',
        );
        check(
          point['rules']['question_seconds'] == 9 &&
              point['rules']['cooldown_seconds'] == 240,
          'Rule edit not loaded',
        );
        await driver.tap(
          find.byValueKey('point-beacon-qa-dynamic-map-20261022'),
        );
        await driver.waitFor(find.text('QA map renamed'));
        await driver.waitFor(find.text('Live edited QA description'));
        await save('catalog-after-edit', c);
        await driver.tap(find.text('Close'));
        stdout.writeln(
          'PASS: same running app received added/moved/renamed points and rule changes; native marker and point card updated without rebuild.',
        );
      } else if (args.first == 'catalog-disabled') {
        final c = await until(
          'catalog',
          (c) =>
              marker(c, 'QA map renamed') == null &&
              marker(c, 'QA map newly added') == null,
        );
        check(
          !(c['points'] as List).any(
            (p) => [
              'qa-dynamic-map-20261022',
              'qa-dynamic-map-added-20261022',
            ].contains(p['id']),
          ),
          'Disabled point remained in catalog',
        );
        await save('catalog-after-disable', c);
        stdout.writeln(
          'PASS: disabled points disappeared from live map and catalog without restart.',
        );
      } else if (args.first == 'play') {
        final point = await cmd('play');
        check(point['cooldown'] == 0, 'QA point was already used');
        await driver.scrollIntoView(find.text('Attack'));
        await driver.tap(find.text('Attack'));
        var g = await until(
          'game',
          (g) => g['phase'] == 'questionReady' && g['question_number'] == 1,
        );
        check(
          g['questions_total'] == 3 &&
              g['question_seconds'] == 9 &&
              g['max_damage_percent'] == 30,
          'Game ignored dynamic rules',
        );
        await save('native-custom-timer', g);
        g = await until(
          'game',
          (g) =>
              g['losses'] == 1 &&
              g['question_number'] == 2 &&
              g['phase'] == 'questionReady',
        );
        check(g['hp'] == 100, 'Timeout damaged point');
        const answers = {
          'qa-live-add': '4',
          'qa-live-shape': '3',
          'qa-live-light': 'Red',
          'qa-live-safe': 'Safe outdoor path',
        };
        final lane = (g['answers'] as List).indexOf(answers[g['bank_id']]);
        check(lane >= 0, 'Missing QA answer');
        // Actual Flutter pointer input, through the same free-kick physics as production.
        await driver.requestData(
          jsonEncode({'op': 'swipe', 'dx': -90 + lane * 60, 'dy': -180}),
        );
        g = await until(
          'game',
          (g) =>
              g['correct'] == 1 &&
              g['question_number'] == 3 &&
              g['phase'] == 'questionReady',
        );
        check(
          g['hp'] == 90 && g['damage_percent'] == '10',
          'Custom damage not transferred to live point',
        );
        await save('native-before-close', g);
        stdout.writeln(
          'PASS: 3-question/9-second game; timeout advances; real kick removes 10% under configured 30% maximum.',
        );
      } else if (args.first == 'resume') {
        final before = jsonDecode(
          await File('${out.path}/native-before-close.json').readAsString(),
        );
        final point = await cmd('play');
        check(
          point['hp'] == 90 &&
              point['can_resume'] == false &&
              point['cooldown'] > 0,
          'Cold restart lost HP, resumed expired question or bypassed cooldown',
        );
        final a = await cmd('read_attack', {'attack_id': before['attack_id']});
        check(
          a['sequence'] == 3 &&
              a['correct_count'] == 1 &&
              a['timeout_count'] == 2 &&
              a['status'] == 'completed',
          'Cold restart did not expire remaining configured question',
        );
        check(
          a['rules']['questions_total'] == 3 &&
              a['rules']['question_seconds'] == 9 &&
              a['rules']['cooldown_seconds'] == 240,
          'Cold restart changed rules',
        );
        await save('native-after-restart', a);
        stdout.writeln(
          'PASS: full process restart retained live damage, rule snapshot, entry cooldown and expired questions.',
        );
      } else {
        throw ArgumentError('Unknown phase');
      }
    });
  } finally {
    await driver.close();
  }
}
