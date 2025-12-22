// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../models/top_sold_models.dart';

class TopSoldProductTile extends StatelessWidget {
  const TopSoldProductTile({
    super.key,
    required this.p,
    required this.canSeeRevenue,
    required this.canSeeCosts,
    required this.onTap,
    required this.cardThumb,
    required this.money,
    required this.statusChipColor,
    required this.marginChip,
    required this.accentA,
    required this.accentB,
    required this.accentC,
  });

  final TopSoldProductVM p;
  final bool canSeeRevenue;
  final bool canSeeCosts;

  final VoidCallback onTap;

  final Widget Function(String url) cardThumb;
  final String Function(num? n) money;

  final Color Function(String pseudoStatus) statusChipColor;
  final Widget Function(num? marge) marginChip;

  final Color accentA;
  final Color accentB;
  final Color accentC;

  String _prettyRevenue() {
    if (!canSeeRevenue || p.revenueByCurrency.isEmpty) return '—';
    if (p.revenueByCurrency.length == 1) {
      final cur = p.revenueByCurrency.keys.first;
      final v = p.revenueByCurrency[cur] ?? 0;
      final avg = p.soldQty == 0 ? 0 : (v / p.soldQty);
      return '${money(avg)} $cur';
    }
    return 'Multi';
  }

  String _prettyCost() {
    if (!canSeeCosts || p.costByCurrency.isEmpty) return '—';
    if (p.costByCurrency.length == 1) {
      final cur = p.costByCurrency.keys.first;
      final v = p.costByCurrency[cur] ?? 0;
      final avg = p.soldQty == 0 ? 0 : (v / p.soldQty);
      return '${money(avg)} $cur';
    }
    return 'Multi';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (p.gameLabel.isNotEmpty) p.gameLabel,
      if (p.sku.isNotEmpty) p.sku,
    ].join(' • ');

    return Card(
      elevation: 0.8,
      shadowColor: accentA.withOpacity(.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  cardThumb(p.photoUrl),
                  if (p.isOutOfStockTopN)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(.95),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'OUT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.productName.isNotEmpty
                          ? p.productName
                          : 'Produit #${p.productId}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            'SOLD: ${p.soldQty}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: statusChipColor('sold'),
                        ),
                        marginChip(p.avgMarge),
                        if (canSeeRevenue)
                          Chip(
                            avatar: const Icon(Icons.sell,
                                size: 16, color: Colors.white),
                            label: Text(
                              _prettyRevenue(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: accentB,
                          ),
                        if (canSeeCosts)
                          Chip(
                            avatar: const Icon(Icons.savings,
                                size: 16, color: Colors.white),
                            label: Text(
                              _prettyCost(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: accentC,
                          ),
                        if (p.isOutOfStockTopN)
                          Chip(
                            label: const Text(
                              'To Restock',
                              style: TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
