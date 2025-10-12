import 'package:flutter/material.dart';

/// Requête retournée par le dialog
class MoveRequest {
  MoveRequest({
    required this.to,
    required this.qty,
    this.onlyFromCollection, // null: indifférent, true: prendre depuis collection, false: hors collection
  });

  final String
      to; // statut cible OU marqueur 'collection_true' | 'collection_false'
  final int qty;
  final bool? onlyFromCollection;
}

class UpdateStatusDialog extends StatefulWidget {
  const UpdateStatusDialog({
    super.key,
    required this.group,
    required this.countsByStatus,
    required this.collectionCount,
    required List<int> itemIds,
    required String currentStatus,
  });

  final Map<String, dynamic> group; // bundle des clés
  final Map<String, int> countsByStatus;
  final int collectionCount;

  @override
  State<UpdateStatusDialog> createState() => _UpdateStatusDialogState();
}

class _UpdateStatusDialogState extends State<UpdateStatusDialog> {
  // Liste des statuts autorisés (DB)
  static const allStatuses = <String>[
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'sold',
    'shipped',
    'finalized',
  ];

  String? _target; // statut cible OU 'collection_true'/'collection_false'
  int _qty = 1;
  bool? _takeFromCollection; // null indifférent

  int _availablePool() {
    // Si on push vers collection_true: on ne filtre pas par statut, on prend n'importe lequel
    // Idem collection_false (on retire depuis ceux en collection)
    if (_target == 'collection_true') {
      // total hors collection
      final total = widget.countsByStatus.values.fold<int>(0, (p, n) => p + n);
      return total - widget.collectionCount;
    }
    if (_target == 'collection_false') {
      return widget.collectionCount;
    }
    // sinon, on peut choisir de prendre depuis collection uniquement / hors collection / indifférent
    final total = widget.countsByStatus.values.fold<int>(0, (p, n) => p + n);
    if (_takeFromCollection == true) return widget.collectionCount;
    if (_takeFromCollection == false) return total - widget.collectionCount;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.countsByStatus.values.fold<int>(0, (p, n) => p + n);

    return AlertDialog(
      title: const Text('Mettre à jour le groupe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Choix action
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Action'),
            initialValue: _target,
            items: [
              const DropdownMenuItem(
                  value: 'collection_true',
                  child: Text('Ajouter à la collection')),
              const DropdownMenuItem(
                  value: 'collection_false',
                  child: Text('Retirer de la collection')),
              const DropdownMenuItem(
                  enabled: false, value: null, child: Divider(height: 1)),
              ...allStatuses.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('Changer statut ➜ $s'),
                  )),
            ],
            onChanged: (v) => setState(() => _target = v),
          ),
          const SizedBox(height: 12),
          // Source (collection / hors collection / indifférent)
          if (_target != 'collection_true' && _target != 'collection_false')
            DropdownButtonFormField<bool?>(
              decoration: const InputDecoration(labelText: 'Prendre depuis'),
              initialValue: _takeFromCollection,
              items: const [
                DropdownMenuItem(value: null, child: Text('Indifférent')),
                DropdownMenuItem(
                    value: true, child: Text('Seulement collection')),
                DropdownMenuItem(
                    value: false, child: Text('Seulement hors collection')),
              ],
              onChanged: (v) => setState(() => _takeFromCollection = v),
            ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: InputDecoration(
              labelText: 'Quantité (max ${_availablePool()})',
              helperText:
                  'Total groupe: $total • En collection: ${widget.collectionCount}',
            ),
            keyboardType: TextInputType.number,
            initialValue: '1',
            onChanged: (v) {
              final n = int.tryParse(v.trim()) ?? 1;
              setState(() => _qty = n);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allStatuses.map((s) {
              final q = widget.countsByStatus[s] ?? 0;
              return Chip(
                label: Text('$s: $q'),
              );
            }).toList()
              ..add(Chip(label: Text('collection: ${widget.collectionCount}'))),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: (_target == null || _qty <= 0 || _qty > _availablePool())
              ? null
              : () {
                  Navigator.pop(
                      context,
                      MoveRequest(
                        to: _target!,
                        qty: _qty,
                        onlyFromCollection: _takeFromCollection,
                      ));
                },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
