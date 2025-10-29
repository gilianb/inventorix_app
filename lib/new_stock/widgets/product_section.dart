import 'package:flutter/material.dart';
import 'section_card.dart';

/*Section “Produit” : choix Type, Langue, CatalogPicker (ta searchbar),
 et Jeu. Pur UI,lève des callbacks pour mettre à jour l’état parent.*/

class ProductSection extends StatelessWidget {
  const ProductSection({
    super.key,
    required this.type,
    required this.lang,
    required this.langs,
    required this.games,
    required this.selectedGameId,
    required this.catalogPicker,
    required this.onTypeChanged,
    required this.onLangChanged,
    required this.onGameChanged,
  });

  final String type;
  final String lang;
  final List<String> langs;
  final List<Map<String, dynamic>> games;
  final int? selectedGameId;

  final Widget catalogPicker;

  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onLangChanged;
  final ValueChanged<int?> onGameChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Produit',
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'single', child: Text('Single')),
                  DropdownMenuItem(value: 'sealed', child: Text('Sealed')),
                ],
                onChanged: onTypeChanged,
                decoration: const InputDecoration(labelText: 'Type *'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: lang,
                items: langs
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: onLangChanged,
                decoration: const InputDecoration(labelText: 'Langue *'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Catalog Picker (searchbar)
          catalogPicker,
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: selectedGameId,
            items: games
                .map((g) => DropdownMenuItem<int>(
                      value: g['id'] as int,
                      child: Text(g['label'] as String),
                    ))
                .toList(),
            onChanged: onGameChanged,
            validator: (v) => v == null ? 'Choisir un jeu' : null,
            decoration: const InputDecoration(labelText: 'Jeu *'),
          ),
        ],
      ),
    );
  }
}
