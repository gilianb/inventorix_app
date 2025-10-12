import 'package:flutter/material.dart';

class StatusChips extends StatelessWidget {
  const StatusChips({
    super.key,
    required this.countsByStatus,
    required this.collectionCount,
  });

  final Map<String, int> countsByStatus;
  final int collectionCount;

  static const _order = [
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'sold',
    'shipped',
    'finalized',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._order
            .map((s) => Chip(label: Text('$s: ${countsByStatus[s] ?? 0}'))),
        Chip(
          label: Text('collection: $collectionCount'),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}
