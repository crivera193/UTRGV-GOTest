import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  final out = Directory('output/gps-resume')..createSync(recursive: true);
  Future<Map> op(String name, [Map<String, Object> extra = const {}]) async =>
      jsonDecode(await d.requestData(jsonEncode({'op': name, ...extra})))
          as Map;
  Future<void> cycle() async {
    await op('map_lifecycle', {'state': 'hidden'});
    await op('map_lifecycle', {'state': 'paused'});
    await Future<void>.delayed(const Duration(seconds: 1));
    await op('map_lifecycle', {'state': 'resumed'});
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byType('MainScreen'),
        timeout: const Duration(seconds: 40),
      );
      await d.waitFor(
        find.byValueKey('campus-exploration-map'),
        timeout: const Duration(seconds: 25),
      );
      const adb =
          r'C:\Users\sephi\AppData\Local\Android\Sdk\platform-tools\adb.exe';
      await Process.run(adb, [
        '-s',
        'emulator-5554',
        'emu',
        'geo',
        'fix',
        '-98.16946621',
        '26.30304392',
      ]);
      final initial = await op('map_view');
      if (initial['view']?['following'] != true) {
        await d.tap(find.text('Follow me'));
      }
      await d.waitFor(
        find.byValueKey('cowboy-runtime-frame'),
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await op('delay_gps', {'hold': true});
      if (args.first == 'home') {
        final before = await op('map_view');
        await Process.run(adb, [
          '-s',
          'emulator-5554',
          'shell',
          'input',
          'keyevent',
          'KEYCODE_HOME',
        ]);
        await Future<void>.delayed(const Duration(seconds: 1));
        await Process.run(adb, [
          '-s',
          'emulator-5554',
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
          'com.example.campus_app/.MainActivity',
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final after = await op('map_view');
        if (after['instance'] != before['instance'] ||
            after['cowboy_visible'] != true ||
            after['gps_waiting'] == true) {
          throw StateError('Actual Home/return lost the cowboy');
        }
        await File(
          '${out.path}/actual-home.png',
        ).writeAsBytes(await d.screenshot());
        stdout.writeln(
          'PASS: actual Android Home, one-second exit and launcher return retain cowboy with GPS updates held.',
        );
        return;
      }
      await cycle();
      final immediate = await op('map_view');
      await File(
        '${out.path}/${args.first}-immediate.png',
      ).writeAsBytes(await d.screenshot());
      if (args.first == 'before') {
        if (immediate['cowboy_visible'] != false ||
            immediate['gps_waiting'] != true) {
          throw StateError('Original disappearance not reproduced');
        }
        stdout.writeln(
          'REPRODUCED: one-second hidden/resumed clears cowboy and shows GPS waiting before next provider update.',
        );
        return;
      }
      if (immediate['cowboy_visible'] != true ||
          immediate['gps_waiting'] == true) {
        throw StateError('Quick resume still resets GPS/display');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if ((await op('map_view'))['cowboy_visible'] != true) {
        throw StateError(
          'Fresh retained cowboy disappeared before provider update',
        );
      }
      stdout.writeln(
        'PASS: one-second resume retained visible cowboy while replacement GPS updates were deliberately delayed.',
      );
      await Future<void>.delayed(const Duration(seconds: 20));
      if ((await op('map_view'))['cowboy_visible'] != false) {
        throw StateError('Expired position remained visible');
      }
      await File('${out.path}/expired.png').writeAsBytes(await d.screenshot());
      stdout.writeln(
        'PASS: old position expires without new fixes, rather than remaining falsely current.',
      );
      await op('delay_gps', {'hold': false});
      await d.waitFor(
        find.byValueKey('cowboy-runtime-frame'),
        timeout: const Duration(seconds: 15),
      );
      await File(
        '${out.path}/recovered.png',
      ).writeAsBytes(await d.screenshot());
      stdout.writeln(
        'PASS: fresh provider fix restores the cowboy after real expiry.',
      );
    });
  } finally {
    try {
      await op('delay_gps', {'hold': false});
    } catch (_) {}
    await d.close();
  }
}
