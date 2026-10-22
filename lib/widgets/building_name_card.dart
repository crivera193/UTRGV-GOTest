import 'package:flutter/material.dart';
import '../map/building_labels.dart';

class BuildingNameCard extends StatelessWidget {
  const BuildingNameCard({
    super.key,
    required this.building,
    required this.onClose,
  });
  final BuildingLabel building;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xfff6f9ee),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  building.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  building.verifiedName
                      ? building.code
                      : 'Name not yet verified',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Close building name',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}
