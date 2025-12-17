import 'package:flutter/material.dart';

import '../ui/ix/ix.dart';
import '../models/inventory_view_mode.dart';

class InventoryListMetaBar extends StatelessWidget {
  const InventoryListMetaBar({
    super.key,
    required this.viewMode,
    required this.visibleLines,
    required this.totalLines,
    required this.visibleProducts,
    required this.totalProducts,
  });

  final InventoryListViewMode viewMode;
  final int visibleLines;
  final int totalLines;
  final int visibleProducts;
  final int totalProducts;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLines = viewMode == InventoryListViewMode.lines;

    final label = isLines
        ? 'Showing $visibleLines / $totalLines lines'
        : 'Showing $visibleProducts / $totalProducts products';

    return Padding(
      padding: IxSpace.page,
      child: Row(
        children: [
          IxPill(
            label: label,
            icon: isLines ? Icons.table_rows : Icons.grid_view,
            color: cs.primary,
          ),
          const Spacer(),
          if ((isLines ? visibleLines : visibleProducts) <
              (isLines ? totalLines : totalProducts))
            const IxHint('Scroll to load more'),
        ],
      ),
    );
  }
}
