import 'package:flutter/material.dart';
import '../utils/format.dart';

class FinanceSummary extends StatelessWidget {
  const FinanceSummary({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final currency = (items.first['currency'] ?? 'USD').toString();
    final n = items.length;

    final invested = items.fold<double>(
        0,
        (p, e) =>
            p +
            (e['unit_cost'] as num).toDouble() +
            (e['unit_fees'] as num).toDouble());
    final soldRevenue = items
        .where((e) => const ['sold', 'shipped', 'finalized']
            .contains((e['status'] ?? '').toString()))
        .fold<double>(
            0, (p, e) => p + ((e['sale_price'] as num?)?.toDouble() ?? 0));

    final avgCost = n == 0 ? 0.0 : invested / n;
    final margin = invested == 0 ? 0.0 : (soldRevenue - invested) / invested;

    Widget tile(String label, String value, {IconData? icon}) => ListTile(
          dense: true,
          leading: icon == null ? null : Icon(icon),
          title: Text(label),
          trailing: Text(value),
          contentPadding: EdgeInsets.zero,
        );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                  child:
                      tile('Unités', '$n', icon: Icons.format_list_numbered)),
              Expanded(
                  child: tile(
                      'Investi (coût+frais)', '${money(invested)} $currency',
                      icon: Icons.savings)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: tile(
                      'Revenu sur vendus', '${money(soldRevenue)} $currency',
                      icon: Icons.trending_up)),
              Expanded(
                  child: tile(
                      'Coût moyen / unité', '${money(avgCost)} $currency',
                      icon: Icons.calculate)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: tile(
                      'P&L', '${money(soldRevenue - invested)} $currency',
                      icon: Icons.balance)),
              Expanded(
                  child: tile('Marge', '${(margin * 100).toStringAsFixed(1)} %',
                      icon: Icons.percent)),
            ]),
          ],
        ),
      ),
    );
  }
}
