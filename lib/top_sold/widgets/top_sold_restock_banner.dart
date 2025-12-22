// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/top_sold_models.dart';

class TopSoldRestockBanner extends StatelessWidget {
  const TopSoldRestockBanner({
    super.key,
    required this.topN,
    required this.oosItems,
    required this.onTapItem,
    required this.accentA,
    required this.accentG,
  });

  final int topN;
  final List<TopSoldProductVM> oosItems;
  final void Function(TopSoldProductVM p) onTapItem;

  final Color accentA;
  final Color accentG;

  String _buildClipboardText() {
    return oosItems.map((p) {
      final bits = <String>[
        if (p.gameLabel.isNotEmpty) p.gameLabel,
        p.productName,
        if (p.sku.isNotEmpty) 'SKU: ${p.sku}',
      ];
      return '- ${bits.join(' • ')}';
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (oosItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Card(
          elevation: 0,
          color: accentG.withOpacity(.08),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: accentG.withOpacity(.9)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Top $topN : Nothing to restock ✅ All top selling items have stock available.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenH = MediaQuery.of(context).size.height;

    // ✅ hauteur max pour éviter le overflow (ajuste si tu veux)
    final double maxListHeight = math.max(180, screenH * 0.30);

    // estimation de hauteur par ligne pour calculer une hauteur "naturelle"
    const double tileExtent = 64;
    final double naturalHeight = oosItems.length * tileExtent;

    final double listHeight = math.min(naturalHeight, maxListHeight);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Card(
        elevation: 0.8,
        shadowColor: accentA.withOpacity(.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.redAccent.withOpacity(.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.redAccent.withOpacity(.08),
                Colors.orangeAccent.withOpacity(.05),
              ],
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'To Restock (Top $topN)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            subtitle: Text(
              '${oosItems.length} item(s) Top sellers with no stock remaining (excluding sold/awaiting payment/shipped/finalized).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              tooltip: 'Copy the liste',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: _buildClipboardText()),
                );
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Liste copied ✅')),
                );
              },
              icon: const Icon(Icons.copy),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // ✅ clé anti-overflow
                    maxHeight: listHeight,
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: oosItems.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.6),
                      itemBuilder: (_, i) {
                        final p = oosItems[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.shopping_cart_outlined),
                          title: Text(
                            p.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (p.gameLabel.isNotEmpty) p.gameLabel,
                              if (p.sku.isNotEmpty) p.sku,
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onTapItem(p),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
