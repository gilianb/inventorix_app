import 'package:flutter/material.dart';
import '../utils/format.dart';

class FinanceSummary extends StatelessWidget {
  const FinanceSummary({
    super.key,
    required this.lot,
    required this.moves,
  });

  /// lot row (purchase, total_cost, currency, fees…)
  final Map<String, dynamic> lot;

  /// movement rows (sell/list/…)
  final List<Map<String, dynamic>> moves;

  @override
  Widget build(BuildContext context) {
    final currency = (lot['currency'] ?? 'USD').toString();
    final totalCost = (lot['total_cost'] as num?)?.toDouble() ?? 0;
    final lotFees = (lot['fees'] as num?)?.toDouble() ?? 0;

    // revenus réalisés = somme des ventes (unit_price * qty)
    double revenue = 0;
    double salesFees = 0;
    for (final m in moves) {
      final mtype = (m['mtype'] ?? '').toString();
      if (mtype == 'sell') {
        final q = (m['qty'] as num?)?.toDouble() ?? 0;
        final up = (m['unit_price'] as num?)?.toDouble() ?? 0;
        revenue += q * up;
        salesFees += (m['fees'] as num?)?.toDouble() ?? 0;
      }
    }

    final totalFees = lotFees + salesFees;
    final pnl = revenue - totalCost - totalFees;
    final margin = revenue > 0 ? (pnl / revenue) : 0;

    Widget tile(String title, String value, {IconData? icon}) {
      return Chip(
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text('$title: $value'),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Résumé financier',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                tile('Coût achat', '${money(totalCost)} $currency',
                    icon: Icons.shopping_bag),
                tile('Frais lot', '${money(lotFees)} $currency',
                    icon: Icons.receipt_long),
                tile('Revenus (ventes)', '${money(revenue)} $currency',
                    icon: Icons.payments),
                tile('Frais vente', '${money(salesFees)} $currency',
                    icon: Icons.money_off_csred),
                tile('P&L', '${money(pnl)} $currency', icon: Icons.balance),
                tile('Marge', '${(margin * 100).toStringAsFixed(1)} %',
                    icon: Icons.percent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
