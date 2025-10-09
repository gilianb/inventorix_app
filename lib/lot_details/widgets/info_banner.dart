import 'package:flutter/material.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.qty,
    required this.productName,
    required this.language,
    required this.supplierName,
    required this.buyerCompany,
    required this.purchaseDate,
    required this.totalCostText,
    this.feesText,
  });

  final int? qty;
  final String? productName;
  final String? language;
  final String supplierName;
  final String buyerCompany;
  final String purchaseDate;
  final String totalCostText;
  final String? feesText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(child: Text('${qty ?? ''}')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName ?? '',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text([
                  if ((language ?? '').isNotEmpty) language,
                  if (supplierName.isNotEmpty) 'Fournisseur: $supplierName',
                  if (buyerCompany.isNotEmpty) 'Acheteur: $buyerCompany',
                ].join(' • ')),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.event, size: 18),
                      label: Text('Achat: $purchaseDate'),
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceVariant,
                    ),
                    Chip(
                      avatar: const Icon(Icons.payments, size: 18),
                      label: Text('Total: $totalCostText'),
                    ),
                    if (feesText != null)
                      Chip(
                        avatar: const Icon(Icons.receipt_long, size: 18),
                        label: Text('Frais: $feesText'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
