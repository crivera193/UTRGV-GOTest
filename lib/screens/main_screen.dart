import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 44,
      backgroundColor: const Color(0xfff1f8eb),
      title: const Text('UTRGV-GO', style: TextStyle(fontSize: 18)),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Unable to sign out. Try again.'),
                  ),
                );
              }
            }
          },
        ),
      ],
    ),
    body: const MapScreen(),
  );
}
