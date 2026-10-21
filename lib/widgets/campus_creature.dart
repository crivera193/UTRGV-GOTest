import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../map/campus_creatures.dart';

/// Decorative foreground art; gestures continue to the map underneath.
class CampusCreature extends StatefulWidget {
  const CampusCreature({
    super.key,
    required this.asset,
    required this.position,
    this.width = 140,
    this.height = 140,
    this.anchor = const Offset(.5, 1),
    this.poster,
  });
  final String asset;
  final Offset position;
  final double width, height;
  final Offset anchor;
  final String? poster;
  @override
  State<CampusCreature> createState() => _CampusCreatureState();
}

class _CampusCreatureState extends State<CampusCreature>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  bool _loaded = false;

  void _syncAnimation() {
    if (!_loaded) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: widget.position.dx - widget.width * widget.anchor.dx,
    top: widget.position.dy - widget.height * widget.anchor.dy,
    width: widget.width,
    height: widget.height,
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: widget.asset.endsWith('.webp')
              ? Image.asset(
                  MediaQuery.disableAnimationsOf(context) &&
                          widget.poster != null
                      ? widget.poster!
                      : widget.asset,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                )
              : Lottie.asset(
                  widget.asset,
                  controller: _controller,
                  fit: BoxFit.contain,
                  onLoaded: (composition) {
                    _controller.duration = composition.duration;
                    _loaded = true;
                    _syncAnimation();
                  },
                ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class CampusBuildingCreatures extends StatelessWidget {
  const CampusBuildingCreatures({super.key, required this.placements});
  final List<CampusCreaturePlacement> placements;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.hardEdge,
    children: [
      for (final placement in placements)
        CampusCreature(
          key: ValueKey(placement.landmark.id),
          asset: placement.landmark.asset,
          poster: placement.landmark.poster,
          anchor: placement.landmark.anchor,
          position: placement.position,
          width: placement.width,
          height: placement.width / placement.landmark.aspectRatio,
        ),
    ],
  );
}
