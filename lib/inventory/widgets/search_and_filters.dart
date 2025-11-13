// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

/// Mapping group -> readable label
const Map<String, String> kGroupPrettyLabel = {
  'all': 'All',
  'purchase': 'Purchase',
  'grading': 'Grading',
  'sale': 'Sale',
  'vault': 'vault',
};

/// Simple formatting of a single status: "sent_to_grader" -> "Sent to grader"
String prettyStatus(String raw) {
  if (raw.isEmpty) return raw;
  final s = raw.replaceAll('_', ' ');
  return s.substring(0, 1).toUpperCase() + s.substring(1);
}

class SearchAndGameFilter extends StatelessWidget {
  const SearchAndGameFilter({
    super.key,
    required this.searchCtrl,
    required this.games,
    required this.selectedGame,
    required this.onGameChanged,
    required this.onSearch,
  });

  final TextEditingController searchCtrl;
  final List<String> games;
  final String? selectedGame;
  final ValueChanged<String?> onGameChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final hasGames = games.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: searchCtrl,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Search (name, language, game, vendor)',
                prefixIcon: const Iconify(Mdi.magnify, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Iconify(Mdi.close, color: Colors.grey),
                  onPressed: () {
                    searchCtrl.clear();
                    onSearch();
                  },
                ),
              ),
            ),
          ),
          if (hasGames)
            DropdownButton<String>(
              value: selectedGame,
              hint: const Text('Filter by game'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All games')),
                ...games.map((g) => DropdownMenuItem(value: g, child: Text(g))),
              ],
              onChanged: onGameChanged,
            ),
        ],
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
    final cs = Theme.of(context).colorScheme;
    final isSingle = typeFilter == 'single';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withOpacity(.20), width: 1),
          ),
          child: ToggleButtons(
            isSelected: [isSingle, !isSingle],
            onPressed: (i) => onTypeChanged(i == 0 ? 'single' : 'sealed'),
            borderRadius: BorderRadius.circular(999),
            borderWidth: 0,
            borderColor: Colors.transparent,
            selectedBorderColor: Colors.transparent,
            color: cs.primary, // unselected text
            selectedColor: cs.onPrimary, // selected text
            fillColor: cs.primary, // selected background
            splashColor: cs.primary.withOpacity(.15),
            hoverColor: cs.primary.withOpacity(.08),
            constraints: const BoxConstraints(
              minHeight: 48, // taller
              minWidth: 140, // wider
            ),
            textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800, // bold
                  letterSpacing: .3,
                ),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text('SINGLE'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text('SEALED'),
              ),
            ],
          ),
        ),
      ),
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

    // Nice label: group -> EN label ; otherwise human readable status
    final raw = statusFilter!;
    final label = kGroupPrettyLabel[raw] ?? prettyStatus(raw);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.filter_alt, size: 18),
            label: Text('Active filter: $label  ($linesCount rows)'),
            onDeleted: onClear,
          ),
        ],
      ),
    );
  }
}
