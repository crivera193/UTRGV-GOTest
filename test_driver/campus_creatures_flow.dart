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
      await d.waitForAbsent(find.byValueKey('computer-science-dragon'));
      await d.waitForAbsent(find.byValueKey('school-of-medicine-floral'));
      await shot('creatures-far');
      await gps(-98.1747739, 26.3062088);
      await d.waitFor(
        find.byValueKey('computer-science-dragon'),
        timeout: const Duration(seconds: 15),
      );
      await d.waitForAbsent(find.byValueKey('school-of-medicine-floral'));
      await shot('dragon-near');
      await gps(-98.17508, 26.30995);
      await d.waitFor(
        find.byValueKey('school-of-medicine-floral'),
        timeout: const Duration(seconds: 15),
      );
      await d.waitForAbsent(find.byValueKey('computer-science-dragon'));
      await shot('flower-near');
      await gps(-98.1735, 26.3078);
      await d.waitForAbsent(find.byValueKey('computer-science-dragon'));
      await d.waitForAbsent(find.byValueKey('school-of-medicine-floral'));
      stdout.writeln(
        'PASS: far hides both; nearby dragon/flower reveal independently; leaving hides both.',
      );
    });
  } finally {
    await d.close();
  }
}
