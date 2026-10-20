import 'package:campus_app/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('DMSerifDisplay')
      ..addFont(rootBundle.load('assets/fonts/DMSerifDisplay-Regular.ttf'));
    await font.load();
    final body = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await body.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> showLogin(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: const LoginScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/auth/field-notes-map.png'),
        tester.element(find.byType(LoginScreen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('field notes portrait render and signup transition', (
    tester,
  ) async {
    await showLogin(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_AUTH_REVIEW')) {
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('../output/auth-review/sign-in-390x844.png'),
      );
    }
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('JOIN THE ADVENTURE'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_AUTH_REVIEW')) {
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('../output/auth-review/sign-up-390x844.png'),
      );
    }
  });

  testWidgets('small screen large text keyboard validation and visibility', (
    tester,
  ) async {
    await showLogin(tester, const Size(320, 640), scale: 1.6, keyboard: 260);
    await tester.enterText(
      find.byType(TextFormField).first,
      'invalid@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use a valid email address ending in .edu.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('JOIN THE ADVENTURE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_AUTH_REVIEW')) {
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../output/auth-review/keyboard-large-text-320x640.png',
        ),
      );
    }
  });
}
