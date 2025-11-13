// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../utils/status_utils.dart';

class StatusBreakdownPanel extends StatelessWidget {
  const StatusBreakdownPanel({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.groupRows,
    required this.currentFilter,
    required this.onTapStatus,
  });

  final bool expanded;
  final ValueChanged<bool> onToggle;
  final List<Map<String, dynamic>> groupRows;
  final String? currentFilter;
  final ValueChanged<String> onTapStatus;

  static const List<String> _purchase = [
    'ordered',
    'paid',
    'in_transit',
    'received',
    'waiting_for_gradation'
  ];
  static const List<String> _grading = [
    'sent_to_grader',
    'at_grader',
    'graded'
  ];

  static const List<String> _sale = [
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized'
  ];

  static const String _collection = 'collection';

  static const Map<String, String> _groupLabels = {
    'all': 'All',
    'purchase': 'Purchase',
    'grading': 'Grading',
    'sale': 'Sale',
  };

  @override
  Widget build(BuildContext context) {
    // Totaux par statut (inclut 'collection')
    final totals = <String, int>{for (final s in kStatusOrder) s: 0};

    for (final r in groupRows) {
      for (final s in kStatusOrder) {
        final key = 'qty_$s';
        totals[s] = (totals[s] ?? 0) + ((r[key] as int?) ?? 0);
      }
    }

    int sumOf(Iterable<String> keys) =>
        keys.fold(0, (p, s) => p + (totals[s] ?? 0));
    final purchaseTotal = sumOf(_purchase);
    final gradingTotal = sumOf(_grading);
    final saleTotal = sumOf(_sale);
    final collectionTotal = totals[_collection] ?? 0;
    final allTotal = purchaseTotal + gradingTotal + saleTotal + collectionTotal;

    if (allTotal == 0) return const SizedBox.shrink();

    Widget groupHeader({
      required String id,
      required String label,
      required int count,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final cs = Theme.of(context).colorScheme;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.secondary : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onSecondaryContainer : cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? cs.onSecondaryContainer.withOpacity(0.9)
                      : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget statusPill({
      required String status,
      required int count,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final color = statusColor(context, status);
      final cs = Theme.of(context).colorScheme;
      final bg = color.withOpacity(selected ? 0.35 : 0.18);
      final border = color.withOpacity(0.60);
      final textColor = cs.onSurface;

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget subStatusOneLine(List<Widget> children) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              children[i],
            ],
          ],
        ),
      );
    }

    Widget categoryColumn({
      required String id,
      required String label,
      required int total,
      required List<String> statuses,
    }) {
      final selected = currentFilter == id;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: groupHeader(
              id: id,
              label: label,
              count: total,
              selected: selected,
              onTap: () => onTapStatus(id),
            ),
          ),
          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: subStatusOneLine(
                statuses.map((s) {
                  final sel = currentFilter == s;
                  return statusPill(
                    status: s,
                    count: totals[s] ?? 0,
                    selected: sel,
                    onTap: () => onTapStatus(s),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 0,
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onToggle,
          title: Text(
            'Status List',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  categoryColumn(
                    id: 'purchase',
                    label: _groupLabels['purchase']!,
                    total: purchaseTotal,
                    statuses: _purchase,
                  ),
                  const SizedBox(width: 24),
                  categoryColumn(
                    id: 'grading',
                    label: _groupLabels['grading']!,
                    total: gradingTotal,
                    statuses: _grading,
                  ),
                  const SizedBox(width: 24),
                  categoryColumn(
                    id: 'sale',
                    label: _groupLabels['sale']!,
                    total: saleTotal,
                    statuses: _sale,
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
