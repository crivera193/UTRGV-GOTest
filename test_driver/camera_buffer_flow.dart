import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final d = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  const adb =
      r'C:\Users\sephi\AppData\Local\Android\Sdk\platform-tools\adb.exe';
  Future<void> gps() async {
    for (var i = 0; i < 4; i++) {
      await Process.run(adb, [
        '-s',
        'emulator-5554',
        'emu',
        'geo',
        'fix',
        '-98.16946621',
        '26.30304392',
      ]);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  final out = Directory('output/camera-buffer')..createSync(recursive: true);
  Future<void> shot(String name) async {
    await File('${out.path}/$name.png').writeAsBytes(await d.screenshot());
  }

  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byType('MainScreen'),
        timeout: const Duration(seconds: 40),
      );
      await d.requestData(jsonEncode({'op': 'catalog_map'}));
      await d.waitFor(
        find.text('Follow me'),
        timeout: const Duration(seconds: 30),
      );
      await gps();
      await d.tap(find.text('Follow me'));
      await gps();
      await shot('swot-close');
      for (var i = 0; i < 2; i++) {
        await d.tap(find.byTooltip('Zoom out'));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await shot('swot-wide');
      await d.scroll(
        find.byType('MapWidget'),
        0,
        -380,
        const Duration(milliseconds: 600),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await shot('swot-buffer');
      stdout.writeln(
        'PASS: native SWOT follow, zoom-out and southward camera pan exercised. Screenshots require visual review.',
      );
    });
  } finally {
    await d.close();
  }
}
