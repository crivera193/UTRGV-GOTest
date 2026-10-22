import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_team.dart';
import 'team_membership.dart';
import 'team_selection_game.dart';

const _paper = Color(0xfff3ebd8);
const _muted = Color(0xffbfc4c9);

class TeamSelectionScreen extends StatefulWidget {
  const TeamSelectionScreen({
    super.key,
    required this.membership,
    required this.onSignOut,
  });
  final TeamMembership membership;
  final Future<void> Function() onSignOut;
  @override
  State<TeamSelectionScreen> createState() => _TeamSelectionScreenState();
}

class _TeamSelectionScreenState extends State<TeamSelectionScreen>
    with WidgetsBindingObserver {
  late TeamSelectionGame _game;
  bool _dialogOpen = false, _signingOut = false;
  int _assetAttempt = 0;
  bool _sceneFailed = false;

  TeamSelectionGame _createGame() => TeamSelectionGame(
    onAssetError: () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sceneFailed = true);
      });
    },
  );

  @override
  void initState() {
    super.initState();
    _game = _createGame();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game.reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_dialogOpen) {
      _game.resumeEngine();
    } else {
      _game.pauseEngine();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose(); // GameWidget disposes its game and private cache.
  }

  Future<void> _inspect(GameTeam team) async {
    if (_dialogOpen || widget.membership.busy || _signingOut) return;
    _dialogOpen = true;
    _game.pauseEngine();
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(
            seedColor: team.color,
            brightness: Brightness.dark,
          ),
        ),
        child: TeamConfirmationDialog(
          team: team,
          membership: widget.membership,
        ),
      ),
    );
    if (!mounted) return;
    _dialogOpen = false;
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _game.resumeEngine();
    }
  }

  Future<void> _signOut() async {
    if (_signingOut || widget.membership.busy) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to sign out. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _paper,
            brightness: Brightness.dark,
            surface: const Color(0xff10171f),
          ),
          textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'Inter',
            bodyColor: _paper,
            displayColor: _paper,
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xff10171f),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'UTRGV-GO',
                                  style: TextStyle(
                                    color: _muted,
                                    letterSpacing: 2,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed:
                                      _signingOut || widget.membership.busy
                                      ? null
                                      : _signOut,
                                  icon: const Icon(Icons.logout, size: 16),
                                  label: const Text('Sign out'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'A new chapter',
                              style: TextStyle(
                                color: _muted,
                                letterSpacing: 2.5,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Find your team.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'DMSerifDisplay',
                                fontSize: 38,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Three paths. One campus.\nTap a floating hat to discover your team.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                height: 1.6,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, bounds) {
                                final height = (bounds.maxWidth * 1.05).clamp(
                                  310.0,
                                  490.0,
                                );
                                return SizedBox(
                                  height: height,
                                  child: Stack(
                                    children: [
                                      ExcludeSemantics(
                                        child: IgnorePointer(
                                          child: GameWidget<TeamSelectionGame>(
                                            key: ValueKey(_assetAttempt),
                                            game: _game,
                                            loadingBuilder: (_) => const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                            errorBuilder: (_, _) => Center(
                                              child: TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _game = TeamSelectionGame()
                                                      ..reducedMotion =
                                                          MediaQuery.disableAnimationsOf(
                                                            context,
                                                          );
                                                    ++_assetAttempt;
                                                  });
                                                },
                                                child: const Text(
                                                  'Scene unavailable · Retry',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      for (
                                        var i = 0;
                                        i < GameTeam.values.length;
                                        i++
                                      )
                                        Positioned(
                                          left: bounds.maxWidth * i / 3,
                                          width: bounds.maxWidth / 3,
                                          top: 0,
                                          bottom: 0,
                                          child: Semantics(
                                            button: true,
                                            label:
                                                '${GameTeam.values[i].displayName}, ${GameTeam.values[i].colorName}. View team information.',
                                            child: Tooltip(
                                              message:
                                                  'Learn about ${GameTeam.values[i].displayName}',
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  key: ValueKey(
                                                    'team-${GameTeam.values[i].id}',
                                                  ),
                                                  excludeFromSemantics: true,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  onTap: widget.membership.busy
                                                      ? null
                                                      : () => _inspect(
                                                          GameTeam.values[i],
                                                        ),
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_sceneFailed)
                                        Positioned.fill(
                                          child: ColoredBox(
                                            color: const Color(0xff10171f),
                                            child: Center(
                                              child: TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _sceneFailed = false;
                                                    _game = _createGame()
                                                      ..reducedMotion =
                                                          MediaQuery.disableAnimationsOf(
                                                            context,
                                                          );
                                                    ++_assetAttempt;
                                                  });
                                                },
                                                child: const Text(
                                                  'Scene unavailable · Retry',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final team in GameTeam.values)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: TextButton(
                                        onPressed: widget.membership.busy
                                            ? null
                                            : () => _inspect(team),
                                        style: TextButton.styleFrom(
                                          foregroundColor: team.color,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 12,
                                          ),
                                        ),
                                        child: Text(
                                          team.displayName,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            const Icon(
                              Icons.lock_outline,
                              color: _muted,
                              size: 17,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your choice stays with this account.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _paper, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Any major. Any team. Choose once, explore together.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                            if (widget.membership.message case final message?)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: _paper),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TeamConfirmationDialog extends StatelessWidget {
  const TeamConfirmationDialog({
    super.key,
    required this.team,
    required this.membership,
  });
  final GameTeam team;
  final TeamMembership membership;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: membership,
    builder: (context, _) => PopScope(
      canPop: !membership.busy,
      child: AlertDialog(
        backgroundColor: const Color(0xff19232d),
        title: Text(
          team.displayName,
          style: TextStyle(
            color: team.color,
            fontFamily: 'DMSerifDisplay',
            fontSize: 27,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${team.colorName} team',
                style: TextStyle(
                  color: team.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                team.description,
                style: const TextStyle(color: _paper, height: 1.6),
              ),
              const SizedBox(height: 12),
              const Text(
                'Open to every major. These are game teams, not official university departments.',
                style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
              ),
              const SizedBox(height: 22),
              const Row(
                children: [
                  Icon(Icons.lock_outline, color: _paper, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This choice is permanent.',
                      style: TextStyle(
                        color: _paper,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'You cannot switch or reset your team for this account. Your cowboy and hat will stay the same.',
                style: TextStyle(color: _paper, height: 1.5),
              ),
              if (membership.message case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(message, style: const TextStyle(color: _paper)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: membership.busy
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text(
              'Choose another',
              style: TextStyle(color: _paper),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: team.color,
              foregroundColor: const Color(0xff10171f),
            ),
            onPressed: membership.busy || membership.phase == TeamPhase.error
                ? null
                : () async {
                    await membership.choose(team);
                    if (context.mounted &&
                        membership.phase == TeamPhase.assigned) {
                      Navigator.of(context).pop();
                    }
                  },
            child: membership.busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Choose team'),
          ),
        ],
      ),
    ),
  );
}
