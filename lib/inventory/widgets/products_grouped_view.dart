// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../utils/status_utils.dart';
import '../utils/format.dart';
import 'table_by_status.dart';

/// One line in the grouped Products view
class InventoryProductSummary {
  InventoryProductSummary({
    required this.key,
    required this.productId,
    required this.productName,
    required this.gameLabel,
    required this.language,
    required this.type,
    required this.currencyDisplay,
    required this.totalQty,
    required this.qtyByStatus,
    required this.avgBuyUnit,
    required this.avgEstimatedUnit,
    required this.photoUrl,
  });

  final String key; // stable key used for expansion and grouping
  final int? productId;
  final String productName;
  final String? gameLabel;
  final String? language;
  final String type;
  final String currencyDisplay; // USD / EUR / MIXED
  final int totalQty;
  final Map<String, int> qtyByStatus;

  /// Weighted average buy price per unit (based on qty shown in the view)
  final num? avgBuyUnit;

  /// Weighted average estimated_price per unit (based on qty shown in the view)
  final num? avgEstimatedUnit;

  final String? photoUrl;
}

List<InventoryProductSummary> buildProductSummaries({
  required List<Map<String, dynamic>> lines,
  required bool canSeeUnitCosts,
  required bool showEstimated,
}) {
  final Map<String, _Acc> byKey = {};

  for (final r in lines) {
    final q = (r['qty_status'] as int?) ?? 0;
    if (q <= 0) continue;

    final key = _productKeyFromLine(r);
    final acc = byKey.putIfAbsent(key, () => _Acc.fromLine(key, r));

    acc.totalQty += q;

    final s = (r['status'] ?? '').toString();
    if (s.isNotEmpty) {
      acc.qtyByStatus[s] = (acc.qtyByStatus[s] ?? 0) + q;
    }

    final cur = (r['currency']?.toString() ?? '').trim();
    if (cur.isNotEmpty) acc.currencies.add(cur);

    if (canSeeUnitCosts) {
      final qtyTotal = (r['qty_total'] as num?) ?? 0;
      final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
      if (qtyTotal > 0) {
        final unit = totalWithFees / qtyTotal;
        acc.buyWeightedSum += unit * q;
        acc.buyWeightedQty += q;
      }
    }

    if (showEstimated) {
      final est = (r['estimated_price'] as num?);
      if (est != null) {
        acc.estWeightedSum += est * q;
        acc.estWeightedQty += q;
      }
    }

    final p = (r['photo_url']?.toString() ?? '').trim();
    if (acc.photoUrl == null && p.isNotEmpty) acc.photoUrl = p;
  }

  final out = <InventoryProductSummary>[];
  for (final acc in byKey.values) {
    final currencyDisplay = acc.currencies.isEmpty
        ? 'USD'
        : (acc.currencies.length == 1 ? acc.currencies.first : 'MIXED');

    out.add(
      InventoryProductSummary(
        key: acc.key,
        productId: acc.productId,
        productName: acc.productName,
        gameLabel: acc.gameLabel,
        language: acc.language,
        type: acc.type,
        currencyDisplay: currencyDisplay,
        totalQty: acc.totalQty,
        qtyByStatus: acc.qtyByStatus,
        avgBuyUnit: (acc.buyWeightedQty > 0)
            ? (acc.buyWeightedSum / acc.buyWeightedQty)
            : null,
        avgEstimatedUnit: (acc.estWeightedQty > 0)
            ? (acc.estWeightedSum / acc.estWeightedQty)
            : null,
        photoUrl: acc.photoUrl,
      ),
    );
  }

  // Sort: biggest stock first, then name
  out.sort((a, b) {
    final q = b.totalQty.compareTo(a.totalQty);
    if (q != 0) return q;
    return a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
  });

  return out;
}

class InventoryProductsGroupedList extends StatelessWidget {
  const InventoryProductsGroupedList({
    super.key,
    required this.summaries,
    required this.allLines,
    required this.expandedKey,
    required this.onExpandedChanged,
    required this.lineKey,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onInlineUpdate,
    required this.showDelete,
    required this.showUnitCosts,
    required this.showRevenue,
    required this.showEstimated,
  });

  final List<InventoryProductSummary> summaries;
  final List<Map<String, dynamic>> allLines;

  final String? expandedKey;
  final ValueChanged<String?> onExpandedChanged;

  final String Function(Map<String, dynamic>) lineKey;

  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;
  final void Function(Map<String, dynamic>)? onDelete;
  final Future<void> Function(
    Map<String, dynamic> line,
    String field,
    dynamic newValue,
  ) onInlineUpdate;

  final bool showDelete;
  final bool showUnitCosts;
  final bool showRevenue;
  final bool showEstimated;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No products to display.'),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final s in summaries) ...[
          _ProductSummaryCard(
            summary: s,
            expanded: expandedKey == s.key,
            onToggle: () =>
                onExpandedChanged(expandedKey == s.key ? null : s.key),
            showUnitCosts: showUnitCosts,
            showEstimated: showEstimated,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: child,
                ),
              );
            },
            child: (expandedKey == s.key)
                ? Padding(
                    key: ValueKey('exp-${s.key}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InventoryTableByStatus(
                      lines: allLines
                          .where((r) => _productKeyFromLine(r) == s.key)
                          .toList(growable: false),
                      onOpen: onOpen,
                      onEdit: onEdit,
                      onDelete: onDelete,
                      showDelete: showDelete,
                      showUnitCosts: showUnitCosts,
                      showRevenue: showRevenue,
                      showEstimated: showEstimated,
                      onInlineUpdate: onInlineUpdate,

                      // Keep it simple: disable group edit inside grouped view
                      groupMode: false,
                      selection: const <String>{},
                      lineKey: lineKey,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('collapsed')),
          ),
        ],
      ],
    );
  }
}

class _ProductSummaryCard extends StatelessWidget {
  const _ProductSummaryCard({
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.showUnitCosts,
    required this.showEstimated,
  });

  final InventoryProductSummary summary;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showUnitCosts;
  final bool showEstimated;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final subtitleParts = <String>[
      if ((summary.gameLabel ?? '').trim().isNotEmpty)
        summary.gameLabel!.trim(),
      if ((summary.language ?? '').trim().isNotEmpty) summary.language!.trim(),
      summary.type,
      if (summary.currencyDisplay.trim().isNotEmpty) summary.currencyDisplay,
    ];
    final subtitle = subtitleParts.join(' • ');

    final chips = _buildStatusChips(context, summary.qtyByStatus);

    final border = Border.all(
      color: expanded
          ? cs.primary.withOpacity(.35)
          : cs.outlineVariant.withOpacity(.55),
      width: expanded ? 1.2 : 0.8,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (expanded)
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 8),
                color: cs.primary.withOpacity(.12),
              ),
          ],
        ),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            hoverColor: cs.primary.withOpacity(.06),
            splashColor: cs.primary.withOpacity(.10),
            onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: border,
                gradient: expanded
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withOpacity(.06),
                          cs.surface,
                        ],
                      )
                    : null,
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(
                    url: summary.photoUrl,
                    badgeText: 'Qty ${summary.totalQty}',
                    expanded: expanded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: expanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.expand_more,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 2),
                        Text(
                          subtitle.isEmpty ? '—' : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),

                        const SizedBox(height: 10),

                        // Status chips + metrics
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...chips,
                            if (showUnitCosts && summary.avgBuyUnit != null)
                              _MetricChip(
                                icon: Icons.shopping_cart_outlined,
                                label:
                                    'Avg buy ${money(summary.avgBuyUnit)} ${summary.currencyDisplay}',
                              ),
                            if (showEstimated &&
                                summary.avgEstimatedUnit != null)
                              _MetricChip(
                                icon: Icons.insights_outlined,
                                label:
                                    'Avg est ${money(summary.avgEstimatedUnit)} ${summary.currencyDisplay}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatusChips(
    BuildContext context,
    Map<String, int> qtyByStatus,
  ) {
    // show up to 4 meaningful statuses, following your kStatusOrder
    final entries = <MapEntry<String, int>>[];
    for (final s in kStatusOrder) {
      final q = qtyByStatus[s] ?? 0;
      if (q > 0) entries.add(MapEntry(s, q));
      if (entries.length >= 4) break;
    }
    if (entries.isEmpty) return const [];

    return entries.map((e) {
      final color = statusColor(context, e.key);
      return Chip(
        label: Text('${e.key.toUpperCase()} ${e.value}'),
        visualDensity: VisualDensity.compact,
        backgroundColor: color.withOpacity(0.12),
        side: BorderSide(color: color.withOpacity(0.45)),
      );
    }).toList(growable: false);
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      label: Text(label),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    this.url,
    required this.badgeText,
    required this.expanded,
  });

  final String? url;
  final String badgeText;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = (url ?? '').trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 104,
        width: 84,
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.35),
          border: Border.all(
            color: expanded
                ? cs.primary.withOpacity(.35)
                : cs.outlineVariant.withOpacity(.55),
            width: expanded ? 1.2 : 0.8,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (u.isEmpty)
              const Center(
                child: Icon(Icons.photo, size: 34, color: Colors.black38),
              )
            else
              Image.network(
                u,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image, size: 26)),
              ),

            // Bottom badge
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouping key:
/// - Prefer product_id (stable)
/// - Also keep type/lang so you don't accidentally merge different product variants
String _productKeyFromLine(Map<String, dynamic> r) {
  final pid = r['product_id'];
  final type = (r['type'] ?? '').toString();
  final lang = (r['language'] ?? '').toString();

  if (pid != null) {
    return 'pid:$pid|$type|$lang';
  }

  final name = (r['product_name'] ?? '').toString().trim().toLowerCase();
  final game = (r['game_id'] ?? '').toString();
  return 'name:$name|$game|$type|$lang';
}

class _Acc {
  _Acc({
    required this.key,
    required this.productId,
    required this.productName,
    required this.gameLabel,
    required this.language,
    required this.type,
    required this.photoUrl,
  });

  factory _Acc.fromLine(String key, Map<String, dynamic> r) {
    return _Acc(
      key: key,
      productId: r['product_id'] as int?,
      productName: (r['product_name'] ?? '').toString(),
      gameLabel: r['game_label']?.toString(),
      language: r['language']?.toString(),
      type: (r['type'] ?? '').toString(),
      photoUrl: (r['photo_url']?.toString() ?? '').trim().isEmpty
          ? null
          : r['photo_url']?.toString(),
    );
  }

  final String key;
  final int? productId;
  final String productName;
  final String? gameLabel;
  final String? language;
  final String type;
  String? photoUrl;

  int totalQty = 0;
  final Map<String, int> qtyByStatus = {};
  final Set<String> currencies = {};

  num buyWeightedSum = 0;
  int buyWeightedQty = 0;

  num estWeightedSum = 0;
  int estWeightedQty = 0;
}
