import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_screen.dart';
import '../teams/team_membership.dart';

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
          tooltip: 'Your account and team',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () {
            final team = TeamScope.of(context).team!;
            showDialog<void>(
              context: context,
              useRootNavigator: false,
              builder: (_) => AlertDialog(
                title: const Text('Your account'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Supabase.instance.client.auth.currentUser?.email ?? '',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      team.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('${team.colorName} team · Permanent membership'),
                    const SizedBox(height: 12),
                    Text(team.description),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
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
