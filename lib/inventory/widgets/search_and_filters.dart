import 'package:flutter/material.dart';

/// Mapping groupes -> libellé lisible
const Map<String, String> kGroupPrettyLabel = {
  'all': 'Tous',
  'purchase': 'Achat',
  'grading': 'Gradation',
  'sale': 'Vente',
  'collection': 'Collection',
};

/// Mise en forme simple d’un statut unitaire: "sent_to_grader" -> "Sent to grader"
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
                hintText: 'Rechercher (nom, langue, jeu, fournisseur)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
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
              hint: const Text('Filtrer par jeu'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Tous les jeux')),
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
    final isSingle = typeFilter == 'single';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ToggleButtons(
        isSelected: [isSingle, !isSingle],
        onPressed: (i) => onTypeChanged(i == 0 ? 'single' : 'sealed'),
        borderRadius: BorderRadius.circular(999),
        children: const [
          Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Single')),
          Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Sealed')),
        ],
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

    // Joli libellé : groupe → label FR ; sinon statut "human readable"
    final raw = statusFilter!;
    final label = kGroupPrettyLabel[raw] ?? prettyStatus(raw);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.filter_alt, size: 18),
            label: Text('Filtre actif : $label  ($linesCount lignes)'),
            onDeleted: onClear,
          ),
        ],
      ),
    );
  }
}
