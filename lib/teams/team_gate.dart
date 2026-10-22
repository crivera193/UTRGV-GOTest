import 'package:flutter/material.dart';
import 'team_membership.dart';
import 'team_selection_screen.dart';
import '../games/game_host.dart';

/// Lives below authentication; its navigator (including all game routes and
/// dialogs) is discarded with the authenticated account, preventing route leaks.
class TeamGate extends StatefulWidget {
  const TeamGate({
    super.key,
    required this.repository,
    required this.onSignOut,
    required this.child,
  });
  final TeamRepository repository;
  final Future<void> Function() onSignOut;
  final Widget child;
  @override
  State<TeamGate> createState() => _TeamGateState();
}

class _TeamGateState extends State<TeamGate> {
  late final TeamMembership membership;
  @override
  void initState() {
    super.initState();
    membership = TeamMembership(widget.repository)..load();
  }

  @override
  void dispose() {
    membership.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TeamScope(
    membership: membership,
    child: Navigator(
      observers: [gameRouteObserver],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (context) => ListenableBuilder(
          listenable: membership,
          builder: (context, _) {
            if (membership.phase == TeamPhase.assigned) return widget.child;
            if (membership.phase == TeamPhase.missing ||
                membership.phase == TeamPhase.saving) {
              return TeamSelectionScreen(
                membership: membership,
                onSignOut: widget.onSignOut,
              );
            }
            return PopScope(
              canPop: false,
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (membership.phase == TeamPhase.loading) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            const Text('Checking your team…'),
                          ] else ...[
                            Text(
                              membership.message!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: membership.load,
                              child: const Text('Retry team check'),
                            ),
                          ],
                          TextButton(
                            onPressed: () async {
                              try {
                                await widget.onSignOut();
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to sign out. Try again.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
