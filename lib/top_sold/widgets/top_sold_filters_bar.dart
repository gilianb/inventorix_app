// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

import '../models/top_sold_models.dart';

class TopSoldFiltersBar extends StatelessWidget {
  const TopSoldFiltersBar({
    super.key,
    required this.typeFilter,
    required this.dateFilter,
    required this.gameFilter,
    required this.sort,
    required this.topN,
    required this.searchCtrl,
    required this.gamesFuture,
    required this.onTypeChanged,
    required this.onDateChanged,
    required this.onGameChanged,
    required this.onSortChanged,
    required this.onTopNChanged,
    required this.onRefresh,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.accentA,
    required this.accentB,
  });

  final String typeFilter; // all|single|sealed
  final String dateFilter; // all|month|week
  final String? gameFilter; // label
  final TopSoldSort sort;
  final int topN;

  final TextEditingController searchCtrl;
  final Future<List<String>> gamesFuture;

  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String?> onGameChanged;
  final ValueChanged<TopSoldSort> onSortChanged;
  final ValueChanged<int> onTopNChanged;

  final VoidCallback onRefresh;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;

  final Color accentA;
  final Color accentB;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Card(
        elevation: 1,
        shadowColor: accentA.withOpacity(.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentA.withOpacity(.06), accentB.withOpacity(.05)],
            ),
            border: Border.all(color: accentA.withOpacity(.15), width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Tous')),
                    ButtonSegment(value: 'single', label: Text('Single')),
                    ButtonSegment(value: 'sealed', label: Text('Sealed')),
                  ],
                  selected: {typeFilter},
                  onSelectionChanged: (s) => onTypeChanged(s.first),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All time')),
                    ButtonSegment(value: 'month', label: Text('Last month')),
                    ButtonSegment(value: 'week', label: Text('Last week')),
                  ],
                  selected: {dateFilter},
                  onSelectionChanged: (s) => onDateChanged(s.first),
                ),

                // Sort
                DropdownButton<TopSoldSort>(
                  value: sort,
                  items: TopSoldSort.values
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('Sort: ${s.label}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSortChanged(v);
                  },
                ),

                // Top N
                DropdownButton<int>(
                  value: topN,
                  items: const [15, 20, 30, 50]
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text('Top $n'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onTopNChanged(v);
                  },
                ),

                // Games
                FutureBuilder<List<String>>(
                  future: gamesFuture,
                  builder: (ctx, snap) {
                    final games = (snap.data ?? const []);
                    final safeValue =
                        (gameFilter != null && games.contains(gameFilter))
                            ? gameFilter
                            : null;
                    return DropdownButton<String?>(
                      value: safeValue,
                      hint: const Text('Filter by game'),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All games'),
                        ),
                        ...games.map(
                          (g) => DropdownMenuItem<String?>(
                            value: g,
                            child: Text(g),
                          ),
                        ),
                      ],
                      onChanged: onGameChanged,
                    );
                  },
                ),

                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Iconify(Mdi.magnify),
                      hintText: 'Search (name/sku/game...)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Iconify(Mdi.close),
                              onPressed: onClearSearch,
                            ),
                    ),
                    onSubmitted: onSearchSubmitted,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Iconify(Mdi.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
