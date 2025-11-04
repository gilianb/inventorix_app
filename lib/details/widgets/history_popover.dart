import 'package:flutter/material.dart';
import 'history_list.dart';

/// Popover ancré affichant l'historique sous forme claire.
class HistoryPopoverCard extends StatelessWidget {
  const HistoryPopoverCard({
    super.key,
    required this.events,
    this.title = 'Journal des changements',
    this.statusChip,
  });

  final List<Map<String, dynamic>> events;
  final String title;
  final Widget? statusChip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.history, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (statusChip != null) statusChip!,
              ],
            ),
          ),
          const Divider(height: 1),
          // Pas de Flexible ici, juste un scroll dans un espace fini
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: HistoryList(movements: events),
            ),
          ),
        ],
      ),
    );
  }
}
