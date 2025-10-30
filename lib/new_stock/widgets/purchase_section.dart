import 'package:flutter/material.dart';
import 'section_card.dart';

/*Section “Achat (USD)” : Fournisseur, Société, Prix total, 
Quantité, Date d’achat, Statut initial, Frais, Prix estimé/u.
 Gère uniquement la présentation + validation de base.*/

class PurchaseSection extends StatelessWidget {
  const PurchaseSection({
    super.key,
    required this.supplierField,
    required this.buyerField,
    required this.totalCostCtrl,
    required this.qtyCtrl,
    required this.dateField,
    required this.statusValue,
    required this.statuses,
    required this.onStatusChanged,
    required this.feesCtrl,
    required this.estimatedPriceCtrl,
  });

  final Widget supplierField;
  final Widget buyerField;
  final TextEditingController totalCostCtrl;
  final TextEditingController qtyCtrl;

  final Widget dateField;
  final String statusValue;
  final List<String> statuses;
  final ValueChanged<String?> onStatusChanged;

  final TextEditingController feesCtrl;
  final TextEditingController estimatedPriceCtrl;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Achat (USD)',
      child: Column(
        children: [
          supplierField,
          const SizedBox(height: 8),
          buyerField,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: totalCostCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Prix total (USD) *'),
                validator: (v) =>
                    (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) >= 0
                        ? null
                        : 'Montant invalide',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité *'),
                validator: (v) =>
                    (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Qté > 0',
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: dateField),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: statusValue,
                items: statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: onStatusChanged,
                decoration: const InputDecoration(labelText: 'Statut initial'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: feesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Frais (USD) — optionnel'),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: InputDecorator(
                decoration: InputDecoration(labelText: 'Devise'),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('USD'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: estimatedPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Prix de vente estimé par unité (USD)'),
          ),
        ],
      ),
    );
  }
}
