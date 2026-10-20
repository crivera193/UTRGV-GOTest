import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/auth/student_email.dart';
import 'package:campus_app/auth/login_screen.dart';
import 'package:campus_app/main.dart';

void main() {
  testWidgets('account form fits portrait, landscape and keyboard insets', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              viewInsets: const EdgeInsets.only(bottom: 250),
            ),
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('School email'), findsOneWidget);
      await tester.ensureVisible(find.text('Create an account'));
      await tester.tap(find.text('Create an account'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  test('accepts .edu mailboxes and rejects deceptive suffixes', () {
    for (final email in [
      'example@utrgv.edu',
      ' Student@Campus.EDU ',
      'a@students.school.edu',
    ]) {
      expect(StudentEmail.isEligible(email), isTrue, reason: email);
    }
    for (final email in [
      'a@gmail.com',
      'a@utrgv.edu.evil.com',
      'a@edu',
      'a@@school.edu',
      'a b@school.edu',
      'a@-school.edu',
      '',
    ]) {
      expect(StudentEmail.isEligible(email), isFalse, reason: email);
    }
  });
  testWidgets('unconfigured backend does not initialize old accounts', (
    tester,
  ) async {
    await tester.pumpWidget(const CampusApp());
    expect(find.text('Account service is not configured yet.'), findsOneWidget);
  });
  testWidgets('signup rejects non-edu before any service call', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField).first,
      'person@gmail.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'longpassword');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(
      find.text('Use a valid email address ending in .edu.'),
      findsOneWidget,
    );
  });
}
