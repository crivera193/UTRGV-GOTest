import 'package:flutter/material.dart';

class CampusZoomControls extends StatelessWidget {
  const CampusZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
  });
  final VoidCallback onZoomIn, onZoomOut;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xfff1f8eb),
    elevation: 3,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          color: const Color(0xff285649),
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: 28, child: Divider(height: 1)),
        IconButton(
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          color: const Color(0xff285649),
          icon: const Icon(Icons.remove),
        ),
      ],
    ),
  );
}
