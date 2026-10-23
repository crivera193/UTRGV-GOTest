import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

const adb = r'C:\Users\sephi\AppData\Local\Android\Sdk\platform-tools\adb.exe';
const package = 'com.example.campus_app';
Future<String> android(List<String> args) async {
  final r = await Process.run(adb, ['-s', 'emulator-5554', ...args]);
  if (r.exitCode != 0) {
    throw StateError('ADB failed: ${args.take(3).join(' ')}');
  }
  return r.stdout.toString().trim();
}

Future<void> launcher() async {
  await android([
    'shell',
    'am',
    'start',
    '-W',
    '--display',
    '0',
    '-a',
    'android.intent.action.MAIN',
    '-c',
    'android.intent.category.LAUNCHER',
    '-f',
    '0x10200000',
    '-n',
    '$package/.MainActivity',
  ]);
}

Future<void> main(List<String> args) async {
  final out = Directory('output/app-lifecycle')..createSync(recursive: true);
  final d = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  Future<Map> state() async =>
      jsonDecode(await d.requestData(jsonEncode({'op': 'map_view'}))) as Map;
  void same(Map a, Map b, {bool instance = true}) {
    final x = a['view'] as Map, y = b['view'] as Map;
    if (instance && a['instance'] != b['instance']) {
      throw StateError('Map widget recreated');
    }
    for (final k in ['latitude', 'longitude', 'zoom']) {
      if (((x[k] as num) - (y[k] as num)).abs() >
          (k == 'zoom' ? 0.03 : 0.00003)) {
        throw StateError('Map $k changed');
      }
    }
    for (final k in ['following', 'locationEnabled', 'overview']) {
      if (x[k] != y[k]) throw StateError('Lost $k');
    }
  }

  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byType('MainScreen'),
        timeout: const Duration(seconds: 45),
      );
      await d.waitFor(
        find.byValueKey('campus-exploration-map'),
        timeout: const Duration(seconds: 30),
      );
      if (args.first == 'restore') {
        final expected =
            jsonDecode(await File('${out.path}/expected.json').readAsString())
                as Map;
        await Future<void>.delayed(const Duration(seconds: 5));
        await d.waitFor(
          find.text('Following'),
          timeout: const Duration(seconds: 15),
        );
        same(expected, await state(), instance: false);
        await File(
          '${out.path}/restored.png',
        ).writeAsBytes(await d.screenshot());
        stdout.writeln(
          'PASS: OS background process death restored camera, zoom, mode and follow intent in a new engine.',
        );
        return;
      }
      for (var i = 0; i < 3; i++) {
        await android(['emu', 'geo', 'fix', '-98.16946621', '26.30304392']);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await d.tap(find.text('Follow me'));
      await Future<void>.delayed(const Duration(seconds: 4));
      await d.tap(find.byTooltip('Zoom out'));
      await Future<void>.delayed(const Duration(seconds: 1));
      await d.tap(find.text('Follow me'));
      await Future<void>.delayed(const Duration(seconds: 2));
      final before = await state();
      if (before['view'] == null || before['view']['following'] != true) {
        throw StateError('Missing restoration/follow state');
      }
      final pid = await android(['shell', 'pidof', package]);
      await File('${out.path}/expected.json').writeAsString(jsonEncode(before));
      await File('${out.path}/before.png').writeAsBytes(await d.screenshot());
      await android(['shell', 'cmd', 'statusbar', 'expand-notifications']);
      await Future<void>.delayed(const Duration(seconds: 1));
      await android(['shell', 'cmd', 'statusbar', 'collapse']);
      await Future<void>.delayed(const Duration(seconds: 1));
      same(before, await state());
      stdout.writeln(
        'PASS: notification shade preserved map instance, camera and following.',
      );
      await d.tap(find.byTooltip('Your account and team'));
      await d.waitFor(find.text('Your trainer'));
      await android(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
      await d.waitForAbsent(find.text('Your trainer'));
      same(before, await state());
      stdout.writeln(
        'PASS: system Back closes trainer route without exiting the app.',
      );
      for (var i = 0; i < 3; i++) {
        await android(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
        await Future<void>.delayed(const Duration(seconds: 1));
        await launcher();
        await Future<void>.delayed(const Duration(seconds: 1));
        same(before, await state());
      }
      stdout.writeln(
        'PASS: three Home/one-second/launcher cycles retained same map and following.',
      );
      await android(['shell', 'input', 'keyevent', 'KEYCODE_APP_SWITCH']);
      await Future<void>.delayed(const Duration(seconds: 1));
      await launcher();
      same(before, await state());
      await android(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
      await Future<void>.delayed(const Duration(seconds: 1));
      await launcher();
      same(before, await state());
      stdout.writeln(
        'PASS: Recents and root Back return to same map, not a fresh engine.',
      );
      await android([
        'shell',
        'am',
        'start',
        '-W',
        '--display',
        '0',
        '-n',
        '$package/.MainActivity',
      ]);
      same(before, await state());
      final recent = await android(['shell', 'dumpsys', 'activity', 'recents']);
      final count = RegExp(
        r'Recent #[^\n]*I=com\.example\.campus_app/\.MainActivity',
      ).allMatches(recent).length;
      if (count != 1 || await android(['shell', 'pidof', package]) != pid) {
        throw StateError('Duplicate task/process found ($count)');
      }
      await File('${out.path}/after.png').writeAsBytes(await d.screenshot());
      stdout.writeln(
        'PASS: launcher and explicit launch reuse one task, activity and process; one Recents entry.',
      );
    });
  } finally {
    await d.close();
  }
}
