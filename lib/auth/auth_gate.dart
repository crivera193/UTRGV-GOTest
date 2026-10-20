import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/main_screen.dart';
import 'login_screen.dart';
import 'student_email.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await client.auth.signOut();
                },
                child: const Text(
                  'Session unavailable. Sign out and try again.',
                ),
              ),
            ),
          );
        }
        final user =
            (snapshot.data?.session ?? client.auth.currentSession)?.user;
        if (user == null) return const LoginScreen();
        if (!StudentEmail.isEligible(user.email ?? '')) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Use a .edu email account to enter campus exploration.',
                    ),
                    TextButton(
                      onPressed: () async {
                        await client.auth.signOut();
                      },
                      child: const Text('Return to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const MainScreen();
      },
    );
  }
}
