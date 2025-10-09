import 'package:flutter/material.dart';

class StatusChips extends StatelessWidget {
  const StatusChips({
    super.key,
    required this.allStatuses,
    required this.qtyFor,
  });

  final List<String> allStatuses;
  final int Function(String status) qtyFor;

  Color _statusColor(String status, BuildContext ctx) {
    final c = Theme.of(ctx).colorScheme;
    switch (status) {
      case 'ordered':
      case 'in_transit':
        return c.tertiaryContainer;
      case 'paid':
      case 'received':
        return c.primaryContainer;
      case 'sent_to_grader':
      case 'at_grader':
      case 'graded':
        return c.secondaryContainer;
      case 'listed':
        return const Color(0xFFFFE08A);
      case 'sold':
      case 'shipped':
      case 'finalized':
        return const Color(0xFFB7E5B4);
      default:
        return c.surfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allStatuses.map((s) {
        final q = qtyFor(s);
        return Chip(
          backgroundColor: _statusColor(s, context),
          label: Text('$s: $q'),
        );
      }).toList(),
    );
  }
}
