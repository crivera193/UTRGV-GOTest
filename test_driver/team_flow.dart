// Host-side test; synthetic credentials live only in the ignored fixture JSON.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final phase = args[0];
  final fixture =
      jsonDecode(await File(args[1]).readAsString()) as Map<String, dynamic>;
  check(
    RegExp(r'^[a-z0-9_]+$').hasMatch(fixture['run'] as String),
    'Explicit test run required',
  );
  for (final key in ['a', 'b']) {
    check(
      RegExp(
        r'^team-e2e-[ab]-[a-z0-9_]+@example\.edu$',
      ).hasMatch(fixture[key] as String),
      'Only synthetic test mailboxes are accepted',
    );
  }
  final out = Directory('output/team-e2e/${fixture['run']}')
    ..createSync(recursive: true);
  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: Platform.environment['TEAM_VM_URL'],
  );
  final evidence = <String, Object?>{};
  Future<dynamic> command(
    String op, [
    Map<String, Object?> extra = const {},
  ]) async {
    final response = await driver.requestData(
      jsonEncode({'op': op, ...extra}),
      timeout: const Duration(seconds: 30),
    );
    return jsonDecode(response);
  }

  Future<void> capture(String name) async =>
      File('${out.path}/$name.png').writeAsBytes(await driver.screenshot());
  Future<void> tapText(String text) async {
    await driver.scrollIntoView(
      find.text(text),
      timeout: const Duration(seconds: 15),
    );
    await driver.tap(find.text(text), timeout: const Duration(seconds: 15));
  }

  Future<void> form(String email, {required bool signup}) async {
    await driver.waitFor(find.byValueKey('account-email'));
    if (signup) await tapText('Create an account');
    await driver.tap(find.byValueKey('account-email'));
    await driver.enterText(email);
    await driver.tap(find.byValueKey('account-password'));
    await driver.enterText(fixture['password'] as String);
    await tapText(signup ? 'Create account' : 'Sign in');
  }

  Future<void> assertSaved(String email, String id, String name) async {
    await driver.waitFor(
      find.byType('MainScreen'),
      timeout: const Duration(seconds: 40),
    );
    await driver.waitForAbsent(find.byType('TeamSelectionScreen'));
    final saved = await command('inspect') as Map;
    check(saved['email'] == email, 'Wrong authenticated account');
    check(
      (saved['profiles'] as List).length == 1,
      'Missing own player profile',
    );
    check(
      (saved['teams'] as List).length == 1 &&
          saved['teams'][0]['team_id'] == id,
      'Wrong authoritative saved team',
    );
    check(saved['ui_team'] == id, 'App state differs from backend');
    await driver.tap(find.byTooltip('Your account and team'));
    await driver.waitFor(find.text(name));
    await capture('$phase-profile-$id');
    await tapText('Close');
    evidence[email] = saved;
  }

  try {
    await driver.runUnsynchronized(() async {
      if (phase == 'create') {
        for (final entry in [
          [fixture['a'] as String, 'art_stuff', 'Art and Stuff'],
          [fixture['b'] as String, 'math_engineering', 'Math and Engineering'],
        ]) {
          await form(entry[0], signup: true);
          await driver.waitFor(
            find.byType('TeamSelectionScreen'),
            timeout: const Duration(seconds: 40),
          );
          var before = await command('inspect') as Map;
          check(
            (before['profiles'] as List).length == 1 &&
                (before['teams'] as List).isEmpty,
            'New account should have profile and no membership',
          );
          await driver.tap(find.byValueKey('team-${entry[1]}'));
          await driver.waitFor(find.text('This choice is permanent.'));
          await capture('confirmation-${entry[1]}');
          await tapText('Choose another');
          before = await command('inspect') as Map;
          check(
            (before['teams'] as List).isEmpty,
            'Browsing/cancel wrote a membership',
          );
          await driver.tap(find.byValueKey('team-${entry[1]}'));
          await tapText('Choose team');
          await assertSaved(entry[0], entry[1], entry[2]);
          final other =
              await command('second_client', {
                    'email': entry[0],
                    'password': fixture['password'],
                  })
                  as Map;
          check(
            other['teams'][0]['team_id'] == entry[1],
            'Fresh independent client lost membership',
          );
          await driver.tap(find.byTooltip('Sign out'));
        }
        await form(fixture['a'] as String, signup: false);
        await assertSaved(fixture['a'] as String, 'art_stuff', 'Art and Stuff');
        await driver.requestData(jsonEncode({'op': 'play'}));
        await driver.waitFor(
          find.text('Demo quiz · Which campus are we exploring?'),
        );
        await capture('chapel-before-play');
        for (final dx in [-90, -30]) {
          await driver.requestData(
            jsonEncode({'op': 'swipe', 'dx': dx, 'dy': -180}),
          );
          Map result = {};
          for (var frame = 0; frame < 60; frame++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            result = await command('game') as Map;
            if (result['phase'] == 'resolving') break;
          }
          check(
            result['phase'] == 'resolving',
            'Shot did not resolve through live game loop',
          );
          evidence['shot-$dx'] = result;
          await capture('chapel-result-$dx');
          await tapText('Continue');
        }
        final game = await command('game') as Map;
        check(game['hp'] == 50, 'Two correct live shots should retain 50 HP');
        await tapText('Close');
        await assertSaved(fixture['a'] as String, 'art_stuff', 'Art and Stuff');
        await capture('before-force-stop');
      } else if (phase == 'relaunch') {
        await assertSaved(fixture['a'] as String, 'art_stuff', 'Art and Stuff');
        await capture('after-cold-relaunch');
      } else {
        throw ArgumentError('Unknown phase');
      }
    });
    await File(
      '${out.path}/$phase-result.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    stdout.writeln('PASS $phase: live backend, profile, UI and account checks');
  } finally {
    await driver.close();
  }
}
