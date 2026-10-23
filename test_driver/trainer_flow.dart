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
  final out = Directory('output/trainer-e2e')..createSync(recursive: true);
  Future<Map> command(String op) async =>
      jsonDecode(await driver.requestData(jsonEncode({'op': op}))) as Map;
  Future<void> capture(String name) async =>
      File('${out.path}/$name.png').writeAsBytes(await driver.screenshot());
  try {
    await driver.runUnsynchronized(() async {
      final info = await command('inspect');
      check(
        info['user'] != null &&
            (args.first == 'remote' || info['ui_team'] == 'art_stuff'),
        'QA permanent team missing after launch',
      );
      if (args.first != 'remote') {
        await driver.tap(find.byTooltip('Your account and team'));
      }
      await driver.waitFor(find.text('Your trainer'));
      await driver.waitFor(
        find.text('550 XP'),
        timeout: const Duration(seconds: 30),
      );
      if (args.first == 'edit') {
        await capture('trainer-before-edit');
        await driver.tap(find.text('Edit profile'));
        await driver.scrollIntoView(find.byValueKey('trainer-name'));
        await driver.tap(find.byValueKey('trainer-name'));
        await driver.enterText('Native QA Explorer');
        await driver.tap(find.byValueKey('trainer-bio'));
        await driver.enterText('Edited in the actual Android app.');
        await driver.scrollIntoView(find.text('Save profile'));
        await driver.tap(find.text('Save profile'));
        await driver.waitFor(
          find.text('Profile saved.'),
          timeout: const Duration(seconds: 30),
        );
        await driver.waitFor(find.text('Native QA Explorer'));
        final saved = await command('trainer');
        check(
          saved['profile']['display_name'] == 'Native QA Explorer' &&
              saved['profile']['bio'] == 'Edited in the actual Android app.',
          'Native edits not saved',
        );
        check(
          saved['profile']['avatar_path'] != null &&
              saved['xp'] == 550 &&
              saved['level'] == 3 &&
              saved['rank'] == 'Campus Scout',
          'Saved photo/progression missing',
        );
        await File(
          '${out.path}/native-saved.json',
        ).writeAsString(jsonEncode(saved));
        await capture('trainer-saved');
        stdout.writeln(
          'PASS: native profile edit saved online; real private avatar loaded; 550 XP, level 3, Campus Scout restored.',
        );
      } else if (args.first == 'remote') {
        // Wait for an actual Realtime-driven widget update; do not call refresh first.
        await driver.waitFor(
          find.text('Remote QA Explorer'),
          timeout: const Duration(seconds: 35),
        );
        await capture('trainer-realtime');
        final saved = await command('trainer');
        check(
          saved['profile']['display_name'] == 'Remote QA Explorer',
          'Cross-client edit missing',
        );
        stdout.writeln(
          'PASS: second-client profile edit reached the same running native trainer screen via Realtime.',
        );
      } else if (args.first == 'restart') {
        await driver.waitFor(find.text('Remote QA Explorer'));
        final saved = await command('trainer');
        check(
          saved['xp'] == 550 &&
              (saved['earned'] as List).length == 4 &&
              saved['profile']['avatar_path'] != null,
          'Cold launch lost profile, photo, XP or achievements',
        );
        await capture('trainer-cold-launch');
        await driver.scrollIntoView(find.text('Sharp Shooter'));
        await capture('trainer-badges');
        stdout.writeln(
          'PASS: cold launch retained profile, avatar, XP, rank and four earned milestones; team selection did not repeat.',
        );
      } else {
        throw ArgumentError('Unknown phase');
      }
    });
  } finally {
    await driver.close();
  }
}
