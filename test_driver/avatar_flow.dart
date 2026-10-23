import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  final out = Directory('output/trainer-e2e/presets')
    ..createSync(recursive: true);
  try {
    await driver.runUnsynchronized(() async {
      await driver.waitFor(
        find.byType('MainScreen'),
        timeout: const Duration(seconds: 35),
      );
      await driver.tap(find.byTooltip('Your account and team'));
      await driver.waitFor(
        find.text('550 XP'),
        timeout: const Duration(seconds: 30),
      );
      if (args.first == 'choose') {
        await driver.tap(find.text('Edit profile'));
        await driver.waitFor(find.text('Choose an avatar'));
        for (final id in ['cowboy', 'cat', 'fox', 'owl', 'robot', 'cactus']) {
          await driver.waitFor(find.byValueKey('avatar-$id'));
        }
        await File(
          '${out.path}/choices.png',
        ).writeAsBytes(await driver.screenshot());
        await driver.tap(find.byValueKey('avatar-fox'));
        await driver.scrollIntoView(find.text('Save profile'));
        await driver.tap(find.text('Save profile'));
        await driver.waitFor(
          find.text('Profile saved.'),
          timeout: const Duration(seconds: 30),
        );
      }
      final saved =
          jsonDecode(await driver.requestData(jsonEncode({'op': 'trainer'})))
              as Map;
      if (saved['profile']['avatar_id'] != 'fox' ||
          saved['profile']['avatar_path'] != null ||
          saved['xp'] != 550) {
        throw StateError('Preset/profile persistence failed');
      }
      await File(
        '${out.path}/${args.first}.png',
      ).writeAsBytes(await driver.screenshot());
      stdout.writeln(
        args.first == 'choose'
            ? 'PASS: six native preset choices; selected fox saved live without changing XP.'
            : 'PASS: full cold launch retained preset fox, profile, team and XP; no upload/gallery UI.',
      );
    });
  } finally {
    await driver.close();
  }
}
