// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../utils/fx_to_usd.dart'; // ✅ <-- ajuste le chemin si besoin

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

class FinanceOverview extends StatelessWidget {
  const FinanceOverview({
    super.key,
    required this.items,
    required this.currency,
    this.finalizedMode = false,
    this.overrideInvested,
    this.titleInvested = 'Invested',
    this.titleEstimated = 'Estimated value',
    this.titleSold = 'Realized',
    this.subtitleInvested,
    this.subtitleEstimated,
    this.subtitleSold,

    // ✅ Multi-devise sale_price -> USD
    this.baseCurrency = 'USD',

    /// Optionnel: permet de surcharger les constantes
    this.fxToUsd,
  });

  final List<Map<String, dynamic>> items;

  /// Ancien param (fallback si l’item n’a pas de devise).
  final String currency;

  final bool finalizedMode;
  final num? overrideInvested;

  final String titleInvested;
  final String titleEstimated;
  final String titleSold;

  final String? subtitleInvested;
  final String? subtitleEstimated;
  final String? subtitleSold;

  /// Devise cible d’affichage / homogénéisation (par défaut USD).
  final String baseCurrency;

  /// Surcharge optionnelle (sinon on utilise kFxToUsd).
  final Map<String, num>? fxToUsd;

  Map<String, num> get _fx => fxToUsd ?? kFxToUsd; // ✅ fallback constants

  num _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _money(num n) => n.toDouble().toStringAsFixed(2);

  String _cur(dynamic v) =>
      (v == null) ? '' : v.toString().trim().toUpperCase();

  bool _isBase(String cur) =>
      cur.trim().toUpperCase() == baseCurrency.toUpperCase();

  /// Retourne le taux "1 unité de cur -> USD" si connu.
  /// - baseCurrency => 1
  /// - sinon => null si fx manquant/inconnu
  num? _rateToBaseOrNull(String cur) {
    final c = cur.trim().toUpperCase();
    if (c.isEmpty) return null;
    if (_isBase(c)) return 1;

    final r = _fx[c];
    if (r == null) return null;

    final rr = _asNum(r);
    return rr == 0 ? null : rr;
  }

  /// Convertit sale_price en baseCurrency (USD).
  /// Retourne null si sale_currency != baseCurrency et pas de taux FX.
  num? _saleToBaseOrNull(Map<String, dynamic> r) {
    final sale = r['sale_price'];
    if (sale == null) return 0;

    final amount = _asNum(sale);

    // ✅ Multi-devise sale_price: sale_currency > currency (legacy) > widget.currency
    final saleCur = _cur(r['sale_currency']);
    final legacyCur = _cur(r['currency']);
    final usedCur = saleCur.isNotEmpty
        ? saleCur
        : (legacyCur.isNotEmpty ? legacyCur : _cur(currency));

    if (usedCur.isEmpty) {
      // Pas de devise: on suppose legacy déjà en baseCurrency
      return amount;
    }

    if (_isBase(usedCur)) return amount;

    final rate = _rateToBaseOrNull(usedCur);
    if (rate == null) return null; // ✅ pas de taux => on exclut
    return amount * rate;
  }

  (num invested, num middle, num sold, Set<String> missingFx) _compute() {
    final missing = <String>{};

    String _usedSaleCurrency(Map<String, dynamic> r) {
      final saleCur = _cur(r['sale_currency']);
      final legacyCur = _cur(r['currency']);
      return saleCur.isNotEmpty
          ? saleCur
          : (legacyCur.isNotEmpty ? legacyCur : _cur(currency));
    }

    if (finalizedMode) {
      num sold = 0;

      for (final r in items) {
        if (r['sale_price'] == null) continue;

        final conv = _saleToBaseOrNull(r);
        if (conv == null) {
          final usedCur = _usedSaleCurrency(r);
          if (usedCur.isNotEmpty && !_isBase(usedCur)) missing.add(usedCur);
          continue;
        }
        sold += conv;
      }

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
      return (invested, margin, sold, Set<String>.unmodifiable(missing));
    } else {
      num invested = 0;
      num estimated = 0;
      num sold = 0;

      for (final r in items) {
        final isSold = r['sale_price'] != null;

        if (isSold) {
          final conv = _saleToBaseOrNull(r);
          if (conv == null) {
            final usedCur = _usedSaleCurrency(r);
            if (usedCur.isNotEmpty && !_isBase(usedCur)) missing.add(usedCur);
            continue;
          }
          sold += conv;
        } else {
          invested += _asNum(r['unit_cost']) +
              _asNum(r['unit_fees']) +
              _asNum(r['shipping_fees']) +
              _asNum(r['commission_fees']) +
              _asNum(r['grading_fees']);
          estimated += _asNum(r['estimated_price']);
        }
      }

      return (invested, estimated, sold, Set<String>.unmodifiable(missing));
    }
  }

  String? _mergeSubtitle(String? base, String? extra) {
    final b = (base ?? '').trim();
    final e = (extra ?? '').trim();
    if (b.isEmpty && e.isEmpty) return null;
    if (b.isEmpty) return e;
    if (e.isEmpty) return b;
    return '$b • $e';
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
    final (inv, mid, sold, missingFx) = _compute();
    final displayCur = baseCurrency;

    final warnFx = missingFx.isEmpty
        ? null
        : '⚠ Missing FX: ${(missingFx.toList()..sort()).join(", ")}';

    final investedCard = _kpiCard(
      context,
      icon: Icons.savings,
      iconBg: kAccentA,
      gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
      title: titleInvested,
      value: '${_money(inv)} $displayCur',
      subtitle: subtitleInvested,
    );

    final middleCard = _kpiCard(
      context,
      icon: finalizedMode ? Icons.trending_up : Icons.lightbulb,
      iconBg: finalizedMode ? kAccentC : kAccentB,
      gradient: finalizedMode
          ? [kAccentC.withOpacity(.14), kAccentB.withOpacity(.06)]
          : [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
      title: titleEstimated,
      value: '${_money(mid)} $displayCur',
      subtitle: subtitleEstimated,
    );

    final soldCard = _kpiCard(
      context,
      icon: Icons.payments,
      iconBg: kAccentG,
      gradient: [kAccentG.withOpacity(.14), kAccentB.withOpacity(.06)],
      title: titleSold,
      value: '${_money(sold)} $displayCur',
      subtitle: _mergeSubtitle(subtitleSold, warnFx),
    );

    return LayoutBuilder(
      builder: (ctx, cons) {
        final maxW = cons.maxWidth;
        if (maxW >= 960) {
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
