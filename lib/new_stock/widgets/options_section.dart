import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'section_card.dart';

/*Section “Options (facultatif)” : Grading ID/Note/Frais,
 Item location (lookup), Tracking, Upload Photo/Doc, Notes,
 Frais d’expédition/commission, Prix de vente (+ devise), Type de paiement,
 Infos acheteur.

✅ Nouvelle logique multi-devise :
- Les coûts (grading/shipping/commission) restent en "currency" (legacy / base de l’item).
- La vente peut avoir sa propre devise via saleCurrencyCtrl -> champ "sale_currency".
*/

class OptionsSection extends StatelessWidget {
  const OptionsSection({
    super.key,
    required this.currency, // ✅ legacy: coûts
    required this.gradeIdCtrl,
    required this.gradingNoteCtrl,
    required this.gradingFeesCtrl,
    required this.itemLocationField,
    required this.trackingCtrl,
    required this.photoTile,
    required this.docTile,
    required this.notesCtrl,
    required this.shippingFeesCtrl,
    required this.commissionFeesCtrl,
    required this.salePriceCtrl,

    // ✅ NEW: devise de vente (sale_currency). Optional pour ne rien casser.
    this.saleCurrencyCtrl,
    required this.paymentTypeCtrl,
    required this.buyerInfosCtrl,
  });

  /// Devise legacy de l’item (utilisée pour les frais / coûts).
  final String currency;

  final TextEditingController gradeIdCtrl;
  final TextEditingController gradingNoteCtrl;
  final TextEditingController gradingFeesCtrl;
  final Widget itemLocationField;
  final TextEditingController trackingCtrl;

  final Widget photoTile;
  final Widget docTile;

  final TextEditingController notesCtrl;
  final TextEditingController shippingFeesCtrl;
  final TextEditingController commissionFeesCtrl;

  /// Montant de vente (sale_price)
  final TextEditingController salePriceCtrl;

  /// Devise de vente (sale_currency) — ex: "USD", "EUR", "JPY"
  /// Si null: on reste en legacy (sale_price supposé en currency).
  final TextEditingController? saleCurrencyCtrl;

  final TextEditingController paymentTypeCtrl;
  final TextEditingController buyerInfosCtrl;

  String _curLabel(String s) {
    final t = s.trim().toUpperCase();
    return t.isEmpty ? 'USD' : t;
  }

  @override
  Widget build(BuildContext context) {
    final costCur = _curLabel(currency);
    final saleCur = _curLabel(saleCurrencyCtrl?.text ?? currency);

    return SectionCard(
      title: 'Options (non mandatory)',
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: gradeIdCtrl,
                decoration: const InputDecoration(labelText: 'Grading ID'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: gradingNoteCtrl,
                decoration: const InputDecoration(labelText: 'Grading Note'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: gradingFeesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Grading Fees ($costCur) — per unit',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: itemLocationField),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: trackingCtrl,
                decoration: const InputDecoration(labelText: 'Tracking Number'),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
          ]),
          const SizedBox(height: 8),
          photoTile,
          const SizedBox(height: 8),
          docTile,
          const SizedBox(height: 8),
          TextFormField(
            controller: notesCtrl,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: shippingFeesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Shipping Fees ($costCur)',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: commissionFeesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Commission Fees ($costCur)',
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ✅ Sale price (+ optional sale currency)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: salePriceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Sale Price ($saleCur) (optional)',
                  ),
                ),
              ),
              if (saleCurrencyCtrl != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: saleCurrencyCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(3),
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        return newValue.copyWith(
                            text: newValue.text.toUpperCase());
                      }),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Sale currency',
                      hintText: 'USD',
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: paymentTypeCtrl,
                decoration: const InputDecoration(labelText: 'Payment Type'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: buyerInfosCtrl,
                decoration: const InputDecoration(labelText: 'Buyer Infos'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
