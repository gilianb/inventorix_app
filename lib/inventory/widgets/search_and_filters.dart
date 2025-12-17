// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

import '../ui/ix/ix.dart';

const Map<String, String> kGroupPrettyLabel = {
  'all': 'All',
  'purchase': 'Purchase',
  'grading': 'Grading',
  'sale': 'Sale',
  'vault': 'vault',
};

String prettyStatus(String raw) {
  if (raw.isEmpty) return raw;
  final s = raw.replaceAll('_', ' ');
  return s.substring(0, 1).toUpperCase() + s.substring(1);
}

const Map<String, String> kPriceBandLabels = {
  'any': 'All prices',
  'p1': '< 50',
  'p2': '50 – 200',
  'p3': '200 – 1000',
  'p4': '> 1000',
};

class SearchAndGameFilter extends StatelessWidget {
  const SearchAndGameFilter({
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
    this.padding = const EdgeInsets.all(12),
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

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasGames = games.isNotEmpty;
    final hasLanguages = languages.isNotEmpty;

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final maxW = cons.maxWidth;
          final wide = maxW >= 900;

          final searchWidth = wide ? 460.0 : maxW;

          return Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth.clamp(260, 520),
                child: TextField(
                  controller: searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  decoration: ixDecoration(
                    context,
                    hintText: 'Search (name, language, game, vendor)',
                    prefixIcon: Iconify(
                      Mdi.magnify,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Clear',
                          icon: Iconify(Mdi.close, color: cs.onSurfaceVariant),
                          onPressed: () {
                            searchCtrl.clear();
                            onSearch();
                          },
                        ),
                        IconButton(
                          tooltip: 'Search',
                          icon: Icon(Icons.search, color: cs.primary),
                          onPressed: onSearch,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasGames)
                IxDropdownField<String?>(
                  width: 220,
                  value: selectedGame,
                  onChanged: onGameChanged,
                  labelText: 'Game',
                  leading: const Icon(Icons.videogame_asset_outlined),
                  items: [
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
                ),
              if (hasLanguages)
                IxDropdownField<String?>(
                  width: 220,
                  value: selectedLanguage,
                  onChanged: onLanguageChanged,
                  labelText: 'Language',
                  leading: const Icon(Icons.translate_outlined),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All languages'),
                    ),
                    ...languages.map(
                      (lang) => DropdownMenuItem<String?>(
                        value: lang,
                        child: Text(lang),
                      ),
                    ),
                  ],
                ),
              IxDropdownField<String>(
                width: 190,
                value: priceBand,
                onChanged: (v) {
                  if (v != null) onPriceBandChanged(v);
                },
                labelText: 'Price',
                leading: const Icon(Icons.price_change_outlined),
                items: kPriceBandLabels.entries
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class TypeTabs extends StatelessWidget {
  const TypeTabs({
    super.key,
    required this.typeFilter,
    required this.onTypeChanged,
  });

  final String typeFilter; // 'single' | 'sealed'
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'single',
          label: Text('SINGLE'),
          icon: Icon(Icons.style_outlined, size: 16),
        ),
        ButtonSegment(
          value: 'sealed',
          label: Text('SEALED'),
          icon: Icon(Icons.inventory_2_outlined, size: 16),
        ),
      ],
      selected: {typeFilter},
      onSelectionChanged: (s) => onTypeChanged(s.first),
    );
  }
}

class ActiveStatusFilterBar extends StatelessWidget {
  const ActiveStatusFilterBar({
    super.key,
    required this.statusFilter,
    required this.linesCount,
    required this.onClear,
  });

  final String? statusFilter;
  final int linesCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (statusFilter == null) return const SizedBox.shrink();

    final raw = statusFilter!;
    final label = kGroupPrettyLabel[raw] ?? prettyStatus(raw);

    return Padding(
      padding: IxSpace.page,
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: const Icon(Icons.filter_alt, size: 18),
          label: Text('Active filter: $label  ($linesCount rows)'),
          onDeleted: onClear,
          deleteIcon: const Icon(Icons.close),
        ),
      ),
    );
  }
}
