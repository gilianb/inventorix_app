// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

class FinanceOverview extends StatelessWidget {
  const FinanceOverview({
    super.key,
    required this.items,
    required this.currency,
    this.titleInvested = 'Invested',
    this.titleEstimated = 'Estimated value',
    this.titleSold = 'Realized',
    this.subtitleInvested,
    this.subtitleEstimated,
    this.subtitleSold,
  });

  /// Items bruts (doivent contenir au moins):
  /// unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
  /// estimated_price, sale_price (nullable), currency (optionnel)
  final List<Map<String, dynamic>> items;
  final String currency;

  final String titleInvested;
  final String titleEstimated;
  final String titleSold;

  final String? subtitleInvested;
  final String? subtitleEstimated;
  final String? subtitleSold;

  num _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _money(num n) => n.toDouble().toStringAsFixed(2);

  /// Calcule les 3 KPI selon la règle:
  /// - Investi + Estimé: uniquement sale_price == null
  /// - Réalisé (sold):   uniquement sale_price != null
  (num invested, num estimated, num sold) _compute() {
    num invested = 0;
    num estimated = 0;
    num sold = 0;

    for (final r in items) {
      final sale = r['sale_price'];
      final isSold = sale != null;

      if (isSold) {
        sold += _asNum(sale);
      } else {
        // coûts unitaires (investi)
        invested += _asNum(r['unit_cost']) +
            _asNum(r['unit_fees']) +
            _asNum(r['shipping_fees']) +
            _asNum(r['commission_fees']) +
            _asNum(r['grading_fees']);
        // valeur estimée
        estimated += _asNum(r['estimated_price']);
      }
    }
    return (invested, estimated, sold);
  }

  Widget _kpiCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required List<Color> gradient,
    required String title,
    required String value,
    String? subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shadowColor: kAccentA.withOpacity(.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          border: Border.all(color: kAccentA.withOpacity(.14), width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              // ⚠️ Pas d’Expanded vertical ici (on est souvent dans un ListView)
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (inv, est, sold) = _compute();

    final investedCard = _kpiCard(
      context,
      icon: Icons.savings,
      iconBg: kAccentA,
      gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
      title: titleInvested,
      value: '${_money(inv)} $currency',
      subtitle: subtitleInvested,
    );

    final estimatedCard = _kpiCard(
      context,
      icon: Icons.lightbulb,
      iconBg: kAccentB,
      gradient: [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
      title: titleEstimated,
      value: '${_money(est)} $currency',
      subtitle: subtitleEstimated,
    );

    final soldCard = _kpiCard(
      context,
      icon: Icons.payments,
      iconBg: kAccentG,
      gradient: [kAccentG.withOpacity(.14), kAccentB.withOpacity(.06)],
      title: titleSold,
      value: '${_money(sold)} $currency',
      subtitle: subtitleSold,
    );

    return LayoutBuilder(
      builder: (ctx, cons) {
        final maxW = cons.maxWidth;
        // ⚠️ IMPORTANT: pas d’Expanded/Flexible VERTICAL dans des Column non bornées
        if (maxW >= 960) {
          // Large: 3 cartes côte à côte (Expanded HORIZONTAL ok)
          return Row(
            children: [
              Expanded(child: investedCard),
              const SizedBox(width: 12),
              Expanded(child: estimatedCard),
              const SizedBox(width: 12),
              Expanded(child: soldCard),
            ],
          );
        } else if (maxW >= 680) {
          // Medium: 2 + 1
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: investedCard),
                  const SizedBox(width: 12),
                  Expanded(child: estimatedCard),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: soldCard)]),
            ],
          );
        } else {
          // Small: empilé
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              investedCard,
              const SizedBox(height: 12),
              estimatedCard,
              const SizedBox(height: 12),
              soldCard,
            ],
          );
        }
      },
    );
  }
}
