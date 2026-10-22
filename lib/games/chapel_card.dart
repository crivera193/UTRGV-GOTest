import 'dart:async';
import '../teams/game_team.dart';
import 'package:flutter/material.dart';
import 'chapel_capture.dart';

/// Original ring, suspended diamond and pedestal; owner is conveyed in text too.
class ChapelBeacon extends StatelessWidget {
  const ChapelBeacon({super.key, required this.owner, this.onTap});
  final String owner;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = owner == 'Unclaimed'
        ? Colors.grey
        : GameTeam.values.firstWhere((t) => t.displayName == owner).color;
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
      final ownerColor = point.ownerTeamId == null
          ? Colors.grey
          : GameTeam.fromId(point.ownerTeamId!).color;
      final reason = widget.point.busy
          ? 'Connecting to live point…'
          : widget.point.friendly
          ? 'Your team controls this point'
          : !widget.point.loaded
          ? 'Loading live point…'
          : widget.point.error ??
                widget.point.cooldownReason ??
                widget.reason();
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
                  Chip(
                    avatar: Icon(Icons.flag, color: ownerColor),
                    label: Text('Owner: ${point.owner}'),
                  ),
                  Text('Your team: ${widget.point.playerTeam.displayName}'),
                  const Text('Ownership and damage are saved online.'),
                  const Text(
                    '4 questions · 15 seconds each\nUp to 25% damage · one attempt every 10 minutes',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: point.hp / point.maxHp,
                    color: ownerColor,
                    minHeight: 12,
                  ),
                  Text('${point.healthLabel} health'),
                  Text(
                    d == null
                        ? 'Distance unavailable · enable foreground GPS'
                        : '${d.toStringAsFixed(1)} m away · attack within 130 ft',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    reason ?? 'In range. Stop walking before playing.',
                    key: const ValueKey('point-attack-reason'),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) Text(_error!),
                  if (widget.debug)
                    const Text(
                      'DEBUG ONLY · GPS bypass for local gameplay review',
                    ),
                  FilledButton.icon(
                    key: const ValueKey('point-attack-button'),
                    onPressed: reason != null || _launching
                        ? null
                        : () async {
                            // Recheck at press time; a stale fix never stays eligible via this card.
                            if (widget.reason() != null ||
                                widget.point.friendly ||
                                widget.point.cooldownReason != null) {
                              setState(() {});
                              return;
                            }
                            setState(() => _launching = true);
                            try {
                              await widget.onAttack();
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Could not open the live attack. Refresh the point and retry.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _launching = false);
                            }
                          },
                    icon: const Icon(Icons.sports_football),
                    label: Text(
                      widget.point.canResume ? 'Resume attack' : 'Attack',
                    ),
                  ),
                  if (widget.point.error != null || _error != null)
                    TextButton(
                      onPressed: () async {
                        await widget.point.load();
                        if (mounted) setState(() => _error = null);
                      },
                      child: const Text('Refresh point'),
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
