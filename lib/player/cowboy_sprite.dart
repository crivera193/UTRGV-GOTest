import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'cowboy_motion.dart';
import 'cowboy_playback.dart';

class CowboyPlacement {
  const CowboyPlacement(this.ground, this.bearing, this.pitch, this.zoom);
  final Offset ground;
  final double bearing, pitch, zoom;
}

/// One persistent overlay and animation clock. Projection updates rebuild only
/// this overlay; loop advancement repaints only its canvas, never the map tree.
class CowboySprite extends StatefulWidget {
  const CowboySprite({
    super.key,
    required this.motion,
    this.ground = Offset.zero,
    this.bearing = 0,
    this.pitch = 45,
    this.zoom = 17.5,
    this.placement,
    this.active = true,
  });
  final CowboyMotion motion;
  final Offset ground;
  final double bearing, pitch, zoom;
  final ValueListenable<CowboyPlacement?>? placement;
  final bool active;
  @override
  State<CowboySprite> createState() => _CowboySpriteState();
}

class _CowboySpriteState extends State<CowboySprite>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _playback = CowboyPlayback();
  final _facing = CowboyFacing();
  final List<ui.Image> _images = [];
  List<Offset> _anchors = [];
  Duration? _previous;
  bool _failed = false;
  CowboyPlacement? get _placement => widget.placement == null
      ? CowboyPlacement(
          widget.ground,
          widget.bearing,
          widget.pitch,
          widget.zoom,
        )
      : widget.placement!.value;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final seconds = _previous == null
          ? 0.0
          : (elapsed - _previous!).inMicroseconds / 1000000;
      _previous = elapsed;
      _playback.advance(
        seconds,
        walking: widget.motion.walking,
        rate: widget.motion.playbackRate,
      );
    });
    widget.placement?.addListener(_syncTicker);
    _load();
  }

  void _syncTicker() {
    if (!mounted) return;
    _playback.advance(
      0,
      walking: widget.motion.walking,
      rate: widget.motion.playbackRate,
    );
    final enabled =
        widget.active &&
        _placement != null &&
        _images.length == 3 &&
        widget.motion.walking &&
        TickerMode.valuesOf(context).enabled;
    if (enabled && !_ticker.isActive) {
      _previous = null;
      _ticker.start();
    } else if (!enabled && _ticker.isActive) {
      _ticker.stop();
      _previous = null;
    }
  }

  @override
  void didUpdateWidget(CowboySprite old) {
    super.didUpdateWidget(old);
    if (old.placement != widget.placement) {
      old.placement?.removeListener(_syncTicker);
      widget.placement?.addListener(_syncTicker);
    }
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _previous = null;
    _syncTicker();
  }

  Future<void> _load() async {
    final loaded = <ui.Image>[];
    try {
      const base = 'assets/player/cowboy/';
      final m =
          jsonDecode(await rootBundle.loadString('${base}manifest.json'))
              as Map<String, dynamic>;
      final anchors = [
        for (final a in m['anchors'] as List)
          Offset((a[0] as num).toDouble(), (a[1] as num).toDouble()),
      ];
      for (final name in m['atlases'] as List) {
        final b = await rootBundle.load('$base$name');
        final codec = await ui.instantiateImageCodec(
          b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
        );
        loaded.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
      if (!mounted) {
        for (final i in loaded) {
          i.dispose();
        }
        return;
      }
      setState(() {
        _images.addAll(loaded);
        _anchors = anchors;
        _playback.cycleSeconds = (m['duration_seconds'] as num).toDouble();
      });
      _syncTicker();
    } catch (_) {
      for (final i in loaded) {
        i.dispose();
      }
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    widget.placement?.removeListener(_syncTicker);
    _ticker.dispose();
    _playback.dispose();
    for (final i in _images) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.placement != null) {
      return ValueListenableBuilder<CowboyPlacement?>(
        valueListenable: widget.placement!,
        builder: (_, p, _) => _buildSprite(p),
      );
    }
    return _buildSprite(_placement);
  }

  Widget _buildSprite(CowboyPlacement? p) {
    if (!widget.active || p == null) return const SizedBox.shrink();
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
    final pitch = _facing.pitch(p.pitch),
        direction = _facing.direction(widget.motion.heading, p.bearing);
    final height = (64 + (p.zoom - 16) * 5).clamp(48.0, 84.0),
        width = height * 160 / 192;
    final anchor = _anchors[pitch];
    return Positioned(
      left: p.ground.dx - anchor.dx * width,
      top: p.ground.dy - anchor.dy * height,
      width: width,
      height: height,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Semantics(
            label: widget.motion.walking
                ? 'Cowboy walking at your GPS position'
                : 'Cowboy standing at your GPS position',
            child: CustomPaint(
              key: const ValueKey('cowboy-runtime-frame'),
              painter: CowboyFramePainter(_images[pitch], direction, _playback),
            ),
          ),
        ),
      ),
    );
  }
}

class CowboyFramePainter extends CustomPainter {
  CowboyFramePainter(this.image, this.direction, this.playback)
    : super(repaint: playback);
  final ui.Image image;
  final int direction;
  final CowboyPlayback playback;
  int get frame => playback.frame;
  @override
  void paint(Canvas c, Size size) {
    c.drawImageRect(
      image,
      Rect.fromLTWH(playback.frame * 160, direction * 192, 160, 192),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(CowboyFramePainter old) =>
      old.image != image ||
      old.direction != direction ||
      old.playback != playback;
}
