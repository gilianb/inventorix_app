// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

/// Affiche 3 KPI financiers.
/// Mode standard (par défaut) :
///  - Investi + Estimé : uniquement pour les items NON vendus
///  - Réalisé (Sold)   : uniquement pour les items vendus
///
/// Mode finalized (finalizedMode = true) :
///  - Investi = Σ de tous les coûts (unit_cost + unit_fees + shipping_fees + commission_fees + grading_fees)
///              ou bien la valeur fournie par [overrideInvested] si non nul,
///  - KPI du milieu = Marge réelle = (Σ sale_price) - Investi
///  - Réalisé = Σ sale_price
class FinanceOverview extends StatelessWidget {
  const FinanceOverview({
    super.key,
    required this.items,
    required this.currency,
    this.finalizedMode = false,
    this.overrideInvested, // 👈 total investi calculé côté serveur (RPC) pour Finalized
    this.titleInvested = 'Invested',
    this.titleEstimated =
        'Estimated value', // devient "Marge réelle" en finalized
    this.titleSold = 'Realized',
    this.subtitleInvested,
    this.subtitleEstimated,
    this.subtitleSold,
  });

  /// Items bruts (doivent contenir au moins en standard) :
  /// unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
  /// estimated_price, sale_price (nullable)
  ///
  /// En finalizedMode avec overrideInvested, seuls sale_price sont réellement nécessaires.
  final List<Map<String, dynamic>> items;
  final String currency;

  /// Active le mode "finalized" (investi = tous coûts, KPI milieu = marge réelle).
  final bool finalizedMode;

  /// Si présent (et finalizedMode = true), remplace le calcul local d’Investi.
  /// Utile pour fournir un total exact calculé côté serveur (sécurisé) pour
  /// les rôles qui n’ont pas accès aux coûts unitaires.
  final num? overrideInvested;

  final String titleInvested;
  final String titleEstimated; // "Marge réelle" en finalized
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

  /// Renvoie un record (invested, middle, sold)
  /// - standard: middle = estimated (non vendus)
  /// - finalized: middle = margin = sold - invested
  (num invested, num middle, num sold) _compute() {
    if (finalizedMode) {
      num sold = 0;
      for (final r in items) {
        final sale = r['sale_price'];
        if (sale != null) sold += _asNum(sale);
      }

      // 👇 Utilise l'override s'il est fourni, sinon calcule localement.
      num invested;
      if (overrideInvested != null) {
        invested = _asNum(overrideInvested);
      } else {
        invested = 0;
        for (final r in items) {
          invested += _asNum(r['unit_cost']) +
              _asNum(r['unit_fees']) +
              _asNum(r['shipping_fees']) +
              _asNum(r['commission_fees']) +
              _asNum(r['grading_fees']);
        }
      }

      final margin = sold - invested;
      return (invested, margin, sold);
    } else {
      // Mode standard (inventaire normal)
      num invested = 0;
      num estimated = 0;
      num sold = 0;

      for (final r in items) {
        final sale = r['sale_price'];
        final isSold = sale != null;

        if (isSold) {
          sold += _asNum(sale);
        } else {
          // coûts unitaires (investi) pour NON vendus
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
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
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
    final (inv, mid, sold) = _compute();

    final investedCard = _kpiCard(
      context,
      icon: Icons.savings,
      iconBg: kAccentA,
      gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
      title: titleInvested,
      value: '${_money(inv)} $currency',
      subtitle: subtitleInvested,
    );

    final middleCard = _kpiCard(
      context,
      icon: finalizedMode ? Icons.trending_up : Icons.lightbulb,
      iconBg: finalizedMode ? kAccentC : kAccentB,
      gradient: finalizedMode
          ? [kAccentC.withOpacity(.14), kAccentB.withOpacity(.06)]
          : [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
      title:
          titleEstimated, // "Marge réelle" en finalized, sinon "Revenu potentiel"
      value: '${_money(mid)} $currency',
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
        if (maxW >= 960) {
          // Large
          return Row(
            children: [
              Expanded(child: investedCard),
              const SizedBox(width: 12),
              Expanded(child: middleCard),
              const SizedBox(width: 12),
              Expanded(child: soldCard),
            ],
          );
        } else if (maxW >= 680) {
          // Medium
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: investedCard),
                  const SizedBox(width: 12),
                  Expanded(child: middleCard),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: soldCard)]),
            ],
          );
        } else {
          // Small
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              investedCard,
              const SizedBox(height: 12),
              middleCard,
              const SizedBox(height: 12),
              soldCard,
            ],
          );
        }
      },
    );
  }
}
