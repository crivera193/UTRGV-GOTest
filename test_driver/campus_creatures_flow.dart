import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  Directory('output/campus-creatures').createSync(recursive: true);
  final d = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  const adb =
      r'C:\Users\sephi\AppData\Local\Android\Sdk\platform-tools\adb.exe';
  Future<void> gps(double lon, double lat) async {
    for (var i = 0; i < 5; i++) {
      await Process.run(adb, [
        '-s',
        'emulator-5554',
        'emu',
        'geo',
        'fix',
        '$lon',
        '$lat',
      ]);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> shot(String name) async {
    await File(
      'output/campus-creatures/$name.png',
    ).writeAsBytes(await d.screenshot());
  }

  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byType('MainScreen'),
        timeout: const Duration(seconds: 45),
      );
      await d.requestData(jsonEncode({'op': 'catalog_map'}));
      await d.waitFor(
        find.text('Follow me'),
        timeout: const Duration(seconds: 30),
      );
      await gps(-98.1735, 26.3078);
      await d.tap(find.text('Follow me'));
      await gps(-98.1735, 26.3078);
      // Browse the campus while GPS remains at the same distant point.
      await d.setSemantics(true);
      for (var i = 0; i < 7; i++) {
        await d.tap(find.bySemanticsLabel('Zoom out'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      await d.waitFor(find.byValueKey('computer-science-dragon'));
      await d.waitFor(find.byValueKey('school-of-medicine-floral'));
      await d.waitFor(find.byType('KittyIslandCats'));
      await shot('always-visible');
      stdout.writeln(
        'PASS: dragon, flower and cats render while browsing away from the player.',
      );
    });
  } finally {
    await d.close();
  }
}
