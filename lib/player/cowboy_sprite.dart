import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'cowboy_motion.dart';

/// Transparent screen overlay. Feet use Mapbox's projected GPS ground point.
/// This deliberate always-visible marker does not share building depth.
class CowboySprite extends StatefulWidget {
  const CowboySprite({
    super.key,
    required this.motion,
    required this.ground,
    required this.bearing,
    required this.pitch,
    required this.zoom,
  });
  final CowboyMotion motion;
  final Offset ground;
  final double bearing, pitch, zoom;

  @override
  State<CowboySprite> createState() => _CowboySpriteState();
}

class _CowboySpriteState extends State<CowboySprite>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<ui.Image> _images = [];
  List<Offset> _anchors = [];
  Duration? _previous;
  double _phase = 0;
  double _cycle = 40 / 30;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = _previous == null
          ? 0.0
          : (elapsed - _previous!).inMicroseconds / 1000000;
      _previous = elapsed;
      if (widget.motion.walking && dt < 0.25 && _images.length == 3) {
        setState(
          () =>
              _phase = (_phase + dt * widget.motion.playbackRate / _cycle) % 1,
        );
      }
    })..start();
    _load();
  }

  Future<void> _load() async {
    final loaded = <ui.Image>[];
    try {
      const base = 'assets/player/cowboy/';
      final manifest =
          jsonDecode(await rootBundle.loadString('${base}manifest.json'))
              as Map<String, dynamic>;
      for (final name in manifest['atlases'] as List) {
        final bytes = await rootBundle.load('$base$name');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        loaded.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
      if (!mounted) {
        for (final image in loaded) {
          image.dispose();
        }
        return;
      }
      setState(() {
        _images.addAll(loaded);
        _cycle = (manifest['duration_seconds'] as num).toDouble();
        _anchors = [
          for (final a in manifest['anchors'] as List)
            Offset((a[0] as num).toDouble(), (a[1] as num).toDouble()),
        ];
      });
    } catch (_) {
      for (final image in loaded) {
        image.dispose();
      }
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final image in _images) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Positioned(
        bottom: 100,
        left: 16,
        child: Text(
          'Cowboy asset unavailable',
          style: TextStyle(backgroundColor: Colors.white),
        ),
      );
    }
    if (_images.length != 3) return const SizedBox.shrink();
    final pitchIndex = widget.pitch < 15
        ? 0
        : widget.pitch < 40
        ? 1
        : 2;
    final direction =
        (((widget.motion.heading - widget.bearing + 360) % 360) / 45).round() %
        8;
    final frame = widget.motion.walking
        ? (_phase * 12).floor().clamp(0, 11)
        : 12;
    // Bounded cartographic exaggeration: never scale exponentially with zoom.
    final height = (64 + (widget.zoom - 16) * 5).clamp(48.0, 84.0);
    final width = height * 160 / 192;
    final anchor = _anchors[pitchIndex];
    return Positioned(
      left: widget.ground.dx - anchor.dx * width,
      top: widget.ground.dy - anchor.dy * height,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Semantics(
          label: widget.motion.walking
              ? 'Cowboy walking at your GPS position'
              : 'Cowboy standing at your GPS position',
          child: CustomPaint(
            key: const ValueKey('cowboy-runtime-frame'),
            painter: _SpritePainter(_images[pitchIndex], direction, frame),
          ),
        ),
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.image, this.direction, this.frame);
  final ui.Image image;
  final int direction, frame;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(frame * 160, direction * 192, 160, 192),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image || old.direction != direction || old.frame != frame;
}
