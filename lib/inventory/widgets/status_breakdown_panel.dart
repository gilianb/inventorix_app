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

  /// Contrôle l’ExpansionTile
  final bool expanded;
  final ValueChanged<bool> onToggle;

  /// Lignes “groupées” brutes (issues de v_items_grouped)
  final List<Map<String, dynamic>> groupRows;

  /// Filtre statut actif
  final String? currentFilter;

  /// Tap sur un statut
  final ValueChanged<String> onTapStatus;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{for (final s in kStatusOrder) s: 0};
    int collection = 0;

    for (final r in groupRows) {
      for (final s in kStatusOrder) {
        final key = 'qty_$s';
        totals[s] = totals[s]! + ((r[key] as int?) ?? 0);
      }
      collection += (r['qty_collection'] as int?) ?? 0;
    }
    final grand = totals.values.fold<int>(0, (p, n) => p + n);
    if (grand == 0) return const SizedBox.shrink();

    Widget miniBar(String label, int value, double fraction, bool selected,
        Color color, VoidCallback onTap) {
      final cs = Theme.of(context).colorScheme;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal))),
              Text('$value'),
            ]),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (ctx, c) {
              return Container(
                height: 8,
                width: c.maxWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: cs.surfaceContainerHighest,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction.clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: selected ? cs.secondary : color,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    Widget legendChip(String s) => Chip(
          label: Text(s),
          // ignore: deprecated_member_use
          backgroundColor: statusColor(context, s).withOpacity(0.15),
          // ignore: deprecated_member_use
          side: BorderSide(color: statusColor(context, s).withOpacity(0.6)),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 0,
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onToggle,
          title: Text('Répartition globale par statut',
              style: Theme.of(context).textTheme.titleMedium),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const SizedBox(height: 8),
            ...kStatusOrder.map((s) {
              final v = totals[s]!;
              final pct = grand == 0 ? 0.0 : v / grand;
              final sel = currentFilter == s;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: miniBar(s, v, pct, sel, statusColor(context, s),
                    () => onTapStatus(s)),
              );
            }),
            const SizedBox(height: 8),
            // info collection (pas cliquable)
            miniBar(
                'collection',
                collection,
                grand == 0 ? 0 : collection / grand,
                false,
                Colors.brown,
                () {}),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kStatusOrder.map(legendChip).toList()),
          ],
        ),
      ),
    );
  }
}
