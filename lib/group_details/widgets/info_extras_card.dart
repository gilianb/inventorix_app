import 'package:flutter/material.dart';

class InfoExtrasCard extends StatelessWidget {
  const InfoExtrasCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final currency = (item['currency'] ?? 'USD').toString();
    final supplier = (item['supplier_name'] ?? '').toString();
    final buyer = (item['buyer_company'] ?? '').toString();
    final type = (item['type'] ?? '').toString();
    final lang = (item['language'] ?? '').toString();

    Widget tile(IconData i, String l, String v) => ListTile(
          dense: true,
          leading: Icon(i),
          title: Text(l),
          trailing: Text(v),
          contentPadding: EdgeInsets.zero,
        );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: tile(Icons.store, 'Fournisseur', supplier)),
              Expanded(
                  child: tile(Icons.business, 'Société acheteuse',
                      buyer.isEmpty ? '—' : buyer)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: tile(
                      Icons.language, 'Langue', lang.isEmpty ? '—' : lang)),
              Expanded(child: tile(Icons.category, 'Type', type)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: tile(Icons.currency_exchange, 'Devise', currency)),
              Expanded(
                  child: tile(Icons.confirmation_number, 'Tracking',
                      (item['tracking'] ?? '—').toString())),
            ]),
          ],
        ),
      ),
    );
  }
}
