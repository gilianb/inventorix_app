// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../utils/fx_to_usd.dart';
import '../ui/ix/ix.dart';

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
    this.baseCurrency = 'USD',
    this.fxToUsd,
  });

  final List<Map<String, dynamic>> items;

  /// Legacy param (fallback if item has no currency).
  final String currency;

  final bool finalizedMode;
  final num? overrideInvested;

  final String titleInvested;
  final String titleEstimated;
  final String titleSold;

  final String? subtitleInvested;
  final String? subtitleEstimated;
  final String? subtitleSold;

  final String baseCurrency;
  final Map<String, num>? fxToUsd;

  Map<String, num> get _fx => fxToUsd ?? kFxToUsd;

  num _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _cur(dynamic v) =>
      (v == null) ? '' : v.toString().trim().toUpperCase();

  bool _isBase(String cur) =>
      cur.trim().toUpperCase() == baseCurrency.toUpperCase();

  num? _rateToBaseOrNull(String cur) {
    final c = cur.trim().toUpperCase();
    if (c.isEmpty) return null;
    if (_isBase(c)) return 1;

    final r = _fx[c];
    if (r == null) return null;

    final rr = _asNum(r);
    return rr == 0 ? null : rr;
  }

  num? _saleToBaseOrNull(Map<String, dynamic> r) {
    final sale = r['sale_price'];
    if (sale == null) return 0;

    final amount = _asNum(sale);

    // sale_currency > currency (legacy) > widget.currency
    final saleCur = _cur(r['sale_currency']);
    final legacyCur = _cur(r['currency']);
    final usedCur = saleCur.isNotEmpty
        ? saleCur
        : (legacyCur.isNotEmpty ? legacyCur : _cur(currency));

    if (usedCur.isEmpty) return amount;
    if (_isBase(usedCur)) return amount;

    final rate = _rateToBaseOrNull(usedCur);
    if (rate == null) return null;
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
    }

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

  String? _mergeSubtitle(String? base, String? extra) {
    final b = (base ?? '').trim();
    final e = (extra ?? '').trim();
    if (b.isEmpty && e.isEmpty) return null;
    if (b.isEmpty) return e;
    if (e.isEmpty) return b;
    return '$b • $e';
  }

  @override
  Widget build(BuildContext context) {
    final (inv, mid, sold, missingFx) = _compute();
    final displayCur = baseCurrency;

    final warnFx = missingFx.isEmpty
        ? null
        : 'Missing FX: ${(missingFx.toList()..sort()).join(", ")}';

    final investedCard = IxKpiCard(
      icon: Icons.savings_outlined,
      accent: IxColors.violet,
      title: titleInvested,
      value: IxAnimatedNumberText(value: inv, suffix: ' $displayCur'),
      subtitle: subtitleInvested,
      gradient: [
        IxColors.violet.withOpacity(.14),
        IxColors.mint.withOpacity(.06)
      ],
    );

    final middleCard = IxKpiCard(
      icon: finalizedMode ? Icons.trending_up : Icons.lightbulb_outline,
      accent: finalizedMode ? IxColors.amber : IxColors.mint,
      title: titleEstimated,
      value: IxAnimatedNumberText(value: mid, suffix: ' $displayCur'),
      subtitle: subtitleEstimated,
      gradient: finalizedMode
          ? [IxColors.amber.withOpacity(.16), IxColors.mint.withOpacity(.06)]
          : [IxColors.mint.withOpacity(.14), IxColors.amber.withOpacity(.06)],
    );

    final soldCard = IxKpiCard(
      icon: Icons.payments_outlined,
      accent: IxColors.green,
      title: titleSold,
      value: IxAnimatedNumberText(value: sold, suffix: ' $displayCur'),
      subtitle: _mergeSubtitle(subtitleSold, warnFx),
      badge: warnFx == null
          ? null
          : IxBadgeDot(color: Colors.redAccent, tooltip: warnFx),
      gradient: [
        IxColors.green.withOpacity(.16),
        IxColors.mint.withOpacity(.06)
      ],
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
