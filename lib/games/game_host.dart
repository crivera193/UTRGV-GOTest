import 'dart:math' as math;
import 'chapel_capture.dart';
import 'chapel_football_game.dart';
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

final gameRouteObserver = RouteObserver<ModalRoute<void>>();

enum GameExit { previewClosed }

class GameSessionContext {
  const GameSessionContext({
    required this.spotId,
    required this.startedAt,
    this.debug = false,
    this.capture,
  });
  final String spotId;
  final DateTime startedAt;
  final bool debug;
  final CaptureSession? capture;
}

typedef SessionFactory =
    SessionGame Function(GameSessionContext, ValueChanged<GameExit>);

/// Games own their caches; disposing a session never clears global Flame caches.
abstract class SessionGame extends FlameGame {
  SessionGame(this.session, this.onExit) {
    images = Images();
    assets = AssetsCache();
    pauseWhenBackgrounded = false; // Host combines route and app visibility.
  }
  final GameSessionContext session;
  final ValueChanged<GameExit> onExit;
  bool sessionVisible = false;
  void setVisible(bool visible) {
    sessionVisible = visible;
    visible ? resumeEngine() : pauseEngine();
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    // GameWidget sends a synthetic resumed event on construction. It must not
    // override host visibility (e.g. loading completes behind another route).
    super.lifecycleStateChange(state);
    if (state != AppLifecycleState.resumed || !sessionVisible) pauseEngine();
  }

  @override
  void onDispose() {
    dispose();
    super.onDispose();
  }
}

class PreviewGame extends SessionGame {
  PreviewGame(super.session, super.onExit);
  double elapsed = 0;
  @override
  Color backgroundColor() => const Color(0xffedf2e8);
  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final radius = math.min(canvasSize.x, canvasSize.y) * 0.08;
    canvas.drawCircle(
      Offset(
        canvasSize.x / 2,
        canvasSize.y / 2 + math.sin(elapsed * 2) * radius,
      ),
      radius * (1 + 0.1 * math.sin(elapsed * 3)),
      Paint()..color = const Color(0xffb65e32),
    );
  }
}

final Map<String, SessionFactory> gameRegistry = Map.unmodifiable({
  'chapel-football': ChapelFootballGame.new,
});

class GameHost extends StatefulWidget {
  const GameHost({
    super.key,
    required this.gameId,
    required this.session,
    this.factory,
  });
  final String gameId;
  final GameSessionContext session;
  final SessionFactory? factory;
  @override
  State<GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<GameHost>
    with WidgetsBindingObserver, RouteAware {
  SessionGame? _game;
  Object? _creationError;
  ModalRoute<void>? _route;
  bool _foreground = true, _visible = true, _closing = false;
  int _attempt = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _createGame();
  }

  void _createGame() {
    try {
      final factory = widget.factory ?? gameRegistry[widget.gameId];
      if (factory == null) throw StateError('Unknown game');
      _game = factory(widget.session, _exit);
      _creationError = null;
      _sync();
    } catch (error) {
      _creationError = error;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != _route) {
      gameRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) gameRouteObserver.subscribe(this, route);
    }
    _visible = route?.isCurrent ?? true;
    _sync();
  }

  void _sync() {
    final visible = _foreground && _visible && !_closing;
    _game?.setVisible(visible);
    widget.session.capture?.setVisible(visible);
  }

  @override
  void didPushNext() {
    _visible = false;
    _sync();
  }

  @override
  void didPopNext() {
    _visible = true;
    _sync();
  }

  @override
  void didPop() {
    _visible = false;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _exit(GameExit result) {
    if (_closing || !mounted) return;
    _closing = true;
    widget.session.capture?.close();
    _sync();
    Navigator.of(context).pop(result);
  }

  void _retry() {
    // New instance only for an explicit failed-load retry. GameWidget disposes
    // the previous keyed session, including its own resources and caches.
    setState(() {
      _attempt++;
      _createGame();
    });
  }

  Widget _error() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Unable to load game.'),
        TextButton(onPressed: _retry, child: const Text('Retry')),
      ],
    ),
  );
  @override
  void dispose() {
    widget.session.capture?.close();
    gameRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _game?.setVisible(false);
    // GameWidget calls onDispose; do not dispose twice or clear shared services.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('UTRGV-GO'),
      actions: [
        TextButton(
          onPressed: () => _exit(GameExit.previewClosed),
          child: const Text('Close'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.session.capture == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Game preview — gameplay coming next.'),
            )
          else
            ListenableBuilder(
              listenable: widget.session.capture!,
              builder: (context, _) {
                final attack = widget.session.capture!;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      if (widget.session.debug)
                        const Text('DEBUG ONLY · no GPS eligibility'),
                      Text(
                        'Chapel Point · ${attack.point.state.healthLabel} health',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        attack.phase == AttackPhase.sessionEnded
                            ? '${attack.correct}/4 correct · ${attack.damagePercent}% damage'
                            : 'Question ${attack.questionNumber}/4 · ${attack.secondsRemaining}s',
                        key: const ValueKey('attack-timer'),
                      ),
                      Text(
                        attack.question.prompt,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18),
                      ),
                      Text(attack.message, textAlign: TextAlign.center),
                      if (attack.busy) const LinearProgressIndicator(),
                      if (attack.retryNeeded && !attack.busy)
                        FilledButton(
                          onPressed: attack.retryKick,
                          child: const Text('Retry saved kick'),
                        ),
                      if (attack.phase == AttackPhase.sessionEnded)
                        FilledButton(
                          onPressed: () => _exit(GameExit.previewClosed),
                          child: Text(
                            attack.captured
                                ? 'Capture complete · Return to map'
                                : 'Return to map',
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          Expanded(
            child: ClipRect(
              child: _creationError != null
                  ? _error()
                  : GameWidget<SessionGame>(
                      key: ValueKey(_attempt),
                      game: _game!,
                      autofocus: false,
                      loadingBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, _) => _error(),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
