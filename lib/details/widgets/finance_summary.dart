// ignore_for_file: deprecated_member_use
/* 3 KPIs (Invested / Potential / Realized) —
 pure UI, receives ready numbers + currency. */
import 'package:flutter/material.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class FinanceSummary extends StatelessWidget {
  const FinanceSummary({
    super.key,
    required this.currency,
    required this.investedForView,
    required this.potentialRevenue,
    required this.realizedRevenue,
  });

  final String currency;
  final num investedForView;
  final num potentialRevenue;
  final num realizedRevenue;

  String _money(num n) => n.toDouble().toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget card(IconData ic, String title, String value, String? subtitle,
        {List<Color>? gradient}) {
      return Expanded(
        child: Card(
          elevation: 1,
          shadowColor: kAccentA.withOpacity(.18),
          color: cs.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient ??
                    [
                      kAccentA.withOpacity(.08),
                      kAccentB.withOpacity(.08),
                    ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: kAccentA,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.analytics,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
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
                  )
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, cons) {
        final compact = cons.maxWidth < 760;

        final w1 = card(
          Icons.savings,
          'Invested (view)',
          '${_money(investedForView)} $currency',
          'Σ qty×estimated cost/unit',
          gradient: [kAccentB.withOpacity(.12), kAccentC.withOpacity(.08)],
        );
        final w2 = card(
          Icons.trending_up,
          'Potential revenue',
          '${_money(potentialRevenue)} $currency',
          'Σ estimated price',
          gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.08)],
        );
        final w3 = card(
          Icons.payments,
          'Realized revenue',
          '${_money(realizedRevenue)} $currency',
          'Σ sale price (sold)',
          gradient: [
            const Color(0xFF22C55E).withOpacity(.14),
            kAccentB.withOpacity(.06)
          ],
        );

        if (!compact) {
          return Row(children: [
            w1,
            const SizedBox(width: 12),
            w2,
            const SizedBox(width: 12),
            w3,
          ]);
        }

        // compact: stacked
        return Column(
          children: [
            Row(children: [w1]),
            const SizedBox(height: 12),
            Row(children: [w2]),
            const SizedBox(height: 12),
            Row(children: [w3]),
          ],
        );
      },
    );
  }
}
