import 'package:flutter/material.dart';
import 'marge.dart';
import 'history_popover.dart';

/* Header: titre, sous-titre, statut, quantité, marge, et bouton Historique (popover ancré). */

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class DetailsHeader extends StatelessWidget {
  const DetailsHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.qty,
    this.margin,
    this.historyEvents = const [],
    this.historyTitle,
    this.historyCount,
    this.showMargins = true, // ⬅️ NEW
// non utilisé désormais (badge calculé sur batch)
  });

  final String title;
  final String subtitle;
  final String status;
  final int qty;
  final num? margin;

  final List<Map<String, dynamic>> historyEvents;
  final String? historyTitle;
  final int? historyCount;
  final bool showMargins;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 🔎 Ne garder QUE les événements d'édition groupée
    final batchEvents = historyEvents
        .where((e) => e['kind'] == 'edit' && (e['code'] ?? '') == 'batch_edit')
        .toList(growable: false);

    final hasHistory = batchEvents.isNotEmpty;

    return Card(
      elevation: 0.8,
      color: cs.surface,
      // ignore: deprecated_member_use
      shadowColor: kAccentA.withOpacity(.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-1, 0),
            end: Alignment(1, 0),
            colors: [kAccentA, kAccentB],
          ).scale(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration:
                  const BoxDecoration(color: kAccentA, shape: BoxShape.circle),
              child:
                  const Icon(Icons.inventory_2, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre + bouton Historique (UN seul)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? 'Détails' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  fontWeight: FontWeight.w800, height: 1.1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _HistoryMenuButton(
                        enabled: hasHistory,
                        // badge = nb d'éditions groupées
                        count: batchEvents.length,
                        builder: (ctx) => HistoryPopoverCard(
                          // on passe UNIQUEMENT les batchs
                          events: batchEvents,
                          title: historyTitle ?? 'Journal des changements',
                        ),
                      ),
                    ],
                  ),

                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(
                          status.toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: kAccentB,
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.format_list_numbered,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Qté : $qty',
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: kAccentC,
                      ),
                      if (showMargins)
                        Tooltip(
                          message:
                              margin == null ? 'Not sold yet' : 'Marge moyenne',
                          child: MarginChip(marge: margin),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton qui ouvre un popover ancré avec PopupMenuButton.
class _HistoryMenuButton extends StatelessWidget {
  const _HistoryMenuButton({
    required this.enabled,
    required this.builder,
    this.count,
  });

  final bool enabled;
  final int? count;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final showBadge = (count ?? 0) > 0;

    return PopupMenuButton<int>(
      tooltip: 'Journal des changements',
      enabled: enabled,
      offset: const Offset(0, 8),
      elevation: 8,
      // ✅ important : pas de contraintes minimales implicites
      constraints: const BoxConstraints(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (ctx) => [
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          // ✅ on annule la hauteur par défaut de l'item
          height: 0,
          child: SizedBox(
            // ✅ contraintes explicites pour éviter "RenderBox was not laid out"
            width: 420,
            height: 520,
            child: builder(ctx),
          ),
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: enabled ? 1.5 : 0,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.history, color: kAccentA, size: 22),
            ),
          ),
          if (enabled && showBadge)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kAccentB,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    )
                  ],
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  child: Text((count ?? 0) > 99 ? '99+' : '${count ?? 0}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
