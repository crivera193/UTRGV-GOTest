import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'chapel_capture.dart';
import 'game_host.dart';

/// Original ring, suspended diamond and pedestal; owner is conveyed in text too.
class ChapelBeacon extends StatelessWidget {
  const ChapelBeacon({super.key, required this.owner, this.onTap});
  final String owner;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = owner == ChapelConfig.playerTeam
        ? const Color(0xff007d88)
        : const Color(0xff9c4bd1);
    return Semantics(
      label: 'Chapel Point, $owner. Open point card',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xeeffffff),
                border: Border.all(color: color, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .25),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(Icons.diamond_outlined, color: color, size: 30),
            ),
            Container(width: 4, height: 12, color: color),
            Container(
              width: 36,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                owner,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChapelCard extends StatefulWidget {
  const ChapelCard({
    super.key,
    required this.point,
    required this.reason,
    required this.distance,
    required this.onAttack,
    this.debug = false,
  });
  final ChapelPoint point;
  final String? Function() reason;
  final double? Function() distance;
  final Future<void> Function() onAttack;
  final bool debug;
  @override
  State<ChapelCard> createState() => _ChapelCardState();
}

class _ChapelCardState extends State<ChapelCard> {
  Timer? _timer;
  bool _launching = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.point,
    builder: (context, _) {
      final point = widget.point.state, d = widget.distance();
      final reason = widget.point.busy
          ? 'Saving local point state…'
          : point.owner == ChapelConfig.playerTeam
          ? 'Your team controls this point'
          : widget.reason();
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text(ChapelConfig.name),
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: _launching ? null : () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xffe5f2e9),
                      border: Border.all(
                        color: const Color(0xff59998d),
                        width: 3,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_city_outlined,
                          size: 85,
                          color: Color(0xff487469),
                        ),
                        Text(
                          'PLACEHOLDER IMAGE',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    ChapelConfig.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    ChapelConfig.description,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text('◆ ${point.owner} · You: ${ChapelConfig.playerTeam}'),
                  const Text('Ownership and damage are local to this device.'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: point.hp / ChapelConfig.maxHp,
                    minHeight: 12,
                  ),
                  Text('${point.hp} / ${ChapelConfig.maxHp} HP'),
                  Text(
                    d == null
                        ? 'Distance unavailable · enable foreground GPS'
                        : '${d.toStringAsFixed(1)} m away · attack within 130 ft',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    reason ?? 'In range. Stop walking before playing.',
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) Text(_error!),
                  if (widget.debug)
                    const Text(
                      'DEBUG ONLY · GPS bypass for local gameplay review',
                    ),
                  FilledButton.icon(
                    onPressed: reason != null || _launching
                        ? null
                        : () async {
                            // Recheck at press time; a stale fix never stays eligible via this card.
                            if (widget.reason() != null ||
                                widget.point.state.owner ==
                                    ChapelConfig.playerTeam) {
                              setState(() {});
                              return;
                            }
                            setState(() => _launching = true);
                            try {
                              await widget.onAttack();
                            } finally {
                              if (mounted) setState(() => _launching = false);
                            }
                          },
                    icon: const Icon(Icons.sports_football),
                    label: const Text('Attack'),
                  ),
                  if (kDebugMode)
                    TextButton(
                      onPressed: _launching
                          ? null
                          : () async {
                              try {
                                await widget.point.reset();
                                setState(() => _error = null);
                              } catch (_) {
                                setState(
                                  () => _error = 'Could not save debug reset.',
                                );
                              }
                            },
                      child: const Text('DEBUG · Reset local owner and HP'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ChapelDebugLauncher extends StatefulWidget {
  const ChapelDebugLauncher({super.key});
  @override
  State<ChapelDebugLauncher> createState() => _ChapelDebugLauncherState();
}

class _ChapelDebugLauncherState extends State<ChapelDebugLauncher> {
  // Separate key adapter below keeps debug reviews away from normal local state.
  final point = ChapelPoint(
    LocalPointPersistence(key: 'utrgv_go_chapel_debug_v1'),
  );
  String? error;
  @override
  void initState() {
    super.initState();
    point
        .load()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = 'Local save unavailable');
        });
  }

  @override
  void dispose() {
    point.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DEBUG · Chapel capture')),
    body: Center(
      child: error != null
          ? Text(error!)
          : !point.loaded
          ? const CircularProgressIndicator()
          : FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ChapelCard(
                  point: point,
                  reason: () => null,
                  distance: () => null,
                  debug: true,
                  onAttack: () async {
                    final attack = CaptureSession(point);
                    try {
                      await Navigator.of(context).push<GameExit>(
                        MaterialPageRoute(
                          builder: (_) => GameHost(
                            gameId: 'chapel-football',
                            session: GameSessionContext(
                              spotId: ChapelConfig.id,
                              startedAt: DateTime.now(),
                              debug: true,
                              capture: attack,
                            ),
                          ),
                        ),
                      );
                    } finally {
                      attack.close();
                    }
                  },
                ),
              ),
              child: const Text('Open chapel · no GPS eligibility'),
            ),
    ),
  );
}
