import 'package:flutter/material.dart';
import 'section_card.dart';

/*Section “Options (facultatif)” : Grading ID/Note/Frais,
 Item location (lookup), Tracking, Upload Photo/Doc, Notes,
  Frais d’expédition/commission, Prix de vente, Type de paiement, 
  Infos acheteur.*/

class OptionsSection extends StatelessWidget {
  const OptionsSection({
    super.key,
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
    required this.paymentTypeCtrl,
    required this.buyerInfosCtrl,
  });

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
  final TextEditingController salePriceCtrl;
  final TextEditingController paymentTypeCtrl;
  final TextEditingController buyerInfosCtrl;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Options (facultatif)',
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
                decoration: const InputDecoration(
                    labelText: 'Grading Fees (USD) — par unité'),
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
                decoration: const InputDecoration(
                    labelText: 'Frais d\'expédition (USD)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: commissionFeesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Frais de commission (USD)'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: salePriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Prix de vente (optionnel)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: paymentTypeCtrl,
                decoration:
                    const InputDecoration(labelText: 'Type de paiement'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: buyerInfosCtrl,
                decoration: const InputDecoration(labelText: 'Infos acheteur'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
