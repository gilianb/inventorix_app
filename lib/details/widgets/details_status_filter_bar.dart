// lib/details/widgets/details_status_filter_bar.dart
import 'package:flutter/material.dart';

import '../../inventory/utils/status_utils.dart';

/// Compact status chips bar for the Details page.
/// - shows all statuses present in the group + counts
/// - lets user switch the current local filter (no network call)
class DetailsStatusFilterBar extends StatelessWidget {
  const DetailsStatusFilterBar({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelected,
    required this.total,
  });

  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onSelected;
  final int total;

  List<String> _orderedStatuses() {
    final keys = counts.keys.toSet();
    final ordered = <String>[];

    for (final s in kStatusOrder) {
      if (s == 'vault') continue;
      if (keys.contains(s)) ordered.add(s);
    }

    // Append unknown statuses at the end (stable)
    for (final s in keys) {
      if (!ordered.contains(s)) ordered.add(s);
    }

    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final statuses = _orderedStatuses();
    final selectedCount = counts[selected] ?? 0;

    return Card(
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Status view',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$selectedCount / $total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onSurface.withOpacity(.60),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in statuses) ...[
                    _StatusChip(
                      status: s,
                      count: counts[s] ?? 0,
                      selected: s == selected,
                      onTap: () => onSelected(s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = statusColor(context, status);
    final onSurface = theme.colorScheme.onSurface;

    return ChoiceChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${status.toUpperCase()} ($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: selected ? c : onSurface.withOpacity(.85),
        letterSpacing: 0.2,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: c.withOpacity(.18),
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: selected ? c.withOpacity(.85) : c.withOpacity(.55),
        width: 1,
      ),
      onSelected: (_) => onTap(),
    );
  }
}
