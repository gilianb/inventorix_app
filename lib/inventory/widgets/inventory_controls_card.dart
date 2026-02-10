// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../ui/ix/ix.dart';
import '../models/inventory_view_mode.dart';
import 'search_and_filters.dart';

class InventoryControlsCard extends StatelessWidget {
  const InventoryControlsCard({
    super.key,
    required this.searchCtrl,
    required this.games,
    required this.selectedGame,
    required this.onGameChanged,
    required this.onSearch,
    required this.languages,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.priceBand,
    required this.onPriceBandChanged,
    required this.typeFilter,
    required this.onTypeChanged,
    required this.dateBase,
    required this.onDateBaseChanged,
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final TextEditingController searchCtrl;

  final List<String> games;
  final String? selectedGame;
  final ValueChanged<String?> onGameChanged;

  final VoidCallback onSearch;

  final List<String> languages;
  final String? selectedLanguage;
  final ValueChanged<String?> onLanguageChanged;

  final String priceBand;
  final ValueChanged<String> onPriceBandChanged;

  final String typeFilter;
  final ValueChanged<String> onTypeChanged;

  final String dateBase;
  final ValueChanged<String> onDateBaseChanged;

  final String dateRange;
  final ValueChanged<String> onDateRangeChanged;

  final InventoryListViewMode viewMode;
  final ValueChanged<InventoryListViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return IxCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      borderColor: IxColors.violet.withOpacity(.18),
      gradient: [
        IxColors.violet.withOpacity(.07),
        IxColors.mint.withOpacity(.06),
      ],
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest.withOpacity(.65),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
                ),
                child: Icon(Icons.tune, size: 18, color: cs.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search & Filters',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Refine your view without losing context',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onSearch,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SearchAndGameFilter(
            searchCtrl: searchCtrl,
            games: games,
            selectedGame: selectedGame,
            onGameChanged: onGameChanged,
            onSearch: onSearch,
            languages: languages,
            selectedLanguage: selectedLanguage,
            onLanguageChanged: onLanguageChanged,
            priceBand: priceBand,
            onPriceBandChanged: onPriceBandChanged,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, cons) {
              final wide = cons.maxWidth >= 880;

              return Wrap(
                spacing: wide ? 10 : 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TypeTabs(
                    typeFilter: typeFilter,
                    onTypeChanged: onTypeChanged,
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'purchase',
                        label: Text('Purchase'),
                        icon: Icon(Icons.shopping_bag_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'sale',
                        label: Text('Sale'),
                        icon: Icon(Icons.sell_outlined, size: 16),
                      ),
                    ],
                    selected: {dateBase},
                    onSelectionChanged: (s) => onDateBaseChanged(s.first),
                  ),
                  DateRangeTabs(
                    dateRange: dateRange,
                    onDateRangeChanged: onDateRangeChanged,
                  ),
                  SegmentedButton<InventoryListViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: InventoryListViewMode.products,
                        label: Text('Products'),
                        icon: Icon(Icons.grid_view, size: 16),
                      ),
                      ButtonSegment(
                        value: InventoryListViewMode.lines,
                        label: Text('Lines'),
                        icon: Icon(Icons.table_rows, size: 16),
                      ),
                    ],
                    selected: {viewMode},
                    onSelectionChanged: (s) => onViewModeChanged(s.first),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
