// ignore_for_file: deprecated_member_use
/* Section: Informations (left/right), clickable links,
  calculates and displays margin (%) and margin value as chips
  (based on fields unit_cost/fees/sale_price/marge). Translated to English. */

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'marge.dart'; // ⬅️ for MarginChip (%)

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class InfoExtrasCard extends StatelessWidget {
  const InfoExtrasCard({
    super.key,
    required this.data,
    required this.currencyFallback,
    this.showMargins = true,
  });

  final Map<String, dynamic> data;
  final String currencyFallback;
  final bool showMargins;

  String _txt(dynamic v) {
    if (v == null) return '—';
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? '—' : s;
    }
    return v.toString();
  }

  String _date(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _money(dynamic v, String cur) {
    if (v == null) return '—';
    if (v is num) return '${v.toDouble().toStringAsFixed(2)} $cur';
    final parsed = num.tryParse(v.toString());
    return parsed == null ? '—' : '${parsed.toStringAsFixed(2)} $cur';
  }

  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  Future<void> _openUrl(BuildContext ctx, String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Unable to open the link.')),
      );
    }
  }

  // ======== UI helpers ========

  TextStyle? _labelStyle(BuildContext ctx) =>
      Theme.of(ctx).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: .35,
            color: Colors.black54,
          );

  TextStyle? _valueStyle(BuildContext ctx) =>
      Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            height: 1.15,
            fontWeight: FontWeight.w600,
          );

  Widget _sectionTitle(BuildContext ctx, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kAccentA),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext ctx,
      {required String label, required Widget child}) {
    final cs = Theme.of(ctx).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccentA.withOpacity(.14), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: kAccentA.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kAccentA.withOpacity(.035),
            kAccentB.withOpacity(.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _labelStyle(ctx)),
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: _valueStyle(ctx) ?? const TextStyle(),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _tileText(BuildContext ctx, String label, String value) {
    return _tile(
      ctx,
      label: label,
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tileLink(BuildContext ctx, String label, String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty) {
      return _tileText(ctx, label, '—');
    }

    return _tile(
      ctx,
      label: label,
      child: InkWell(
        onTap: () => _openUrl(ctx, u),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: u,
                waitDuration: const Duration(milliseconds: 400),
                child: Text(
                  u,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kAccentA,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kAccentA.withOpacity(.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kAccentA.withOpacity(.22)),
              ),
              child: const Icon(Icons.open_in_new, size: 16, color: kAccentA),
            ),
          ],
        ),
      ),
    );
  }

  Color _marginColorFor(num? pct) {
    if (pct == null) return Colors.grey;
    if (pct < 0) return Colors.black;
    if (pct < 30) return Colors.redAccent;
    if (pct < 60) return Colors.orangeAccent;
    return Colors.green;
  }

  /// Chip for margin value (color = based on %)
  Widget _marginValueChip(num? value, String currency, num? pct) {
    final bg = _marginColorFor(pct);
    final label = value == null
        ? '—'
        : (value >= 0
            ? '+${value.toDouble().toStringAsFixed(2)} $currency'
            : '${value.toDouble().toStringAsFixed(2)} $currency');

    return Chip(
      avatar: const Icon(Icons.attach_money, size: 16, color: Colors.white),
      label: Text(
        label,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }

  Widget _grid(BuildContext ctx, List<Widget> tiles, {required bool twoCols}) {
    return LayoutBuilder(
      builder: (_, cons) {
        final double gap = 10;
        final double w = cons.maxWidth;
        final double tileW = twoCols ? (w - gap) / 2 : w;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileW, child: t),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Devise "coût / item"
    final currency = _txt(data['currency']) == '—'
        ? currencyFallback
        : _txt(data['currency']);

    // ✅ MULTI-DEVISE (lié à sale_price)
    final saleCurrencyRaw = _txt(
      data['sale_currency'] ??
          data['sale_price_currency'] ??
          data['sale_currency_code'],
    );
    final saleCurrency = (saleCurrencyRaw == '—' || saleCurrencyRaw.isEmpty)
        ? currency
        : saleCurrencyRaw;

    final bool sameCurrencyForMargin = (saleCurrency == currency);

    // === Margin calculations ===
    final num? pct = _asNum(data['marge']); // % if present
    final num? sale = _asNum(data['sale_price']);

    final num cost =
        (_asNum(data['unit_cost']) ?? 0) + (_asNum(data['unit_fees']) ?? 0);
    final num fees = (_asNum(data['shipping_fees']) ?? 0) +
        (_asNum(data['commission_fees']) ?? 0) +
        (_asNum(data['grading_fees']) ?? 0);
    final num invested = cost + fees;

    final num? valueMargin = (showMargins && sameCurrencyForMargin)
        ? (sale == null ? null : (sale - invested))
        : null;

    final num? pctDerived = (pct != null)
        ? pct
        : ((sameCurrencyForMargin && sale != null && invested > 0)
            ? ((sale - invested) / invested * 100)
            : null);

    final notes = (data['notes'] ?? '').toString().trim();

    // ===== Sections (tiles) =====
    final basics = <Widget>[
      _tileText(context, 'Product name', _txt(data['product_name'])),
      _tileText(context, 'Game', _txt(data['game_label'] ?? data['game_code'])),
      _tileText(context, 'Language', _txt(data['language'])),
      _tileText(context, 'Type', _txt(data['type'])),
      _tileText(context, 'Purchase date', _date(data['purchase_date'])),
      _tileText(context, 'Status', _txt(data['status'])),
    ];

    final people = <Widget>[
      _tileText(context, 'Supplier', _txt(data['supplier_name'])),
      _tileText(context, 'Buyer company', _txt(data['buyer_company'])),
      _tileText(context, 'Buyer info', _txt(data['buyer_infos'])),
      _tileText(context, 'Payment type', _txt(data['payment_type'])),
    ];

    final logistics = <Widget>[
      _tileText(context, 'Channel ID', _txt(data['channel_id'])),
      _tileText(context, 'Item location', _txt(data['item_location'])),
      _tileText(context, 'Tracking', _txt(data['tracking'])),
      _tileText(context, 'Grade ID', _txt(data['grade_id'])),
      _tileText(context, 'Grading note', _txt(data['grading_note'])),
    ];

    final pricing = <Widget>[
      _tileText(context, 'Unit cost', _money(data['unit_cost'], currency)),
      _tileText(context, 'Unit fees', _money(data['unit_fees'], currency)),
      _tileText(context, 'Estimated price',
          _money(data['estimated_price'], currency)),
      _tileText(context, 'Shipping fees / unit',
          _money(data['shipping_fees'], currency)),
      _tileText(context, 'Commission fees / unit',
          _money(data['commission_fees'], currency)),
      _tileText(
          context, 'Grading fees', _money(data['grading_fees'], currency)),
    ];

    final saleTiles = <Widget>[
      _tileText(
          context, 'Sale price', _money(data['sale_price'], saleCurrency)),
      _tileText(context, 'Sale currency', saleCurrency),
      _tileText(context, 'Sale date', _date(data['sale_date'])),
      _tileText(context, 'Currency (cost)', currency),
      _tileText(context, 'Created at', _date(data['created_at'])),
    ];

    final links = <Widget>[
      _tileLink(context, 'Photo URL', data['photo_url']?.toString()),
      _tileLink(context, 'Document URL', data['document_url']?.toString()),
    ];

    final margins = <Widget>[
      _tile(
        context,
        label: 'Margin (%)',
        child: Align(
          alignment: Alignment.centerLeft,
          child: MarginChip(marge: pctDerived, compact: true),
        ),
      ),
      _tile(
        context,
        label: 'Margin value / unit',
        child: Align(
          alignment: Alignment.centerLeft,
          child: _marginValueChip(valueMargin, currency, pctDerived),
        ),
      ),
    ];

    return Card(
      elevation: 1,
      shadowColor: kAccentA.withOpacity(.16),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kAccentA.withOpacity(.16), width: 1),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kAccentA.withOpacity(.055),
              kAccentB.withOpacity(.045),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: LayoutBuilder(
            builder: (ctx, cons) {
              final twoCols = cons.maxWidth >= 820;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(ctx, Icons.info_outline, 'Information'),
                  const SizedBox(height: 10),
                  _grid(ctx, basics, twoCols: twoCols),
                  const SizedBox(height: 14),
                  _sectionTitle(ctx, Icons.people_alt_outlined, 'Parties'),
                  const SizedBox(height: 10),
                  _grid(ctx, people, twoCols: twoCols),
                  const SizedBox(height: 14),
                  _sectionTitle(
                      ctx, Icons.local_shipping_outlined, 'Logistics'),
                  const SizedBox(height: 10),
                  _grid(ctx, logistics, twoCols: twoCols),
                  const SizedBox(height: 14),
                  _sectionTitle(ctx, Icons.attach_money, 'Pricing'),
                  const SizedBox(height: 10),
                  _grid(ctx, pricing, twoCols: twoCols),
                  const SizedBox(height: 14),
                  _sectionTitle(ctx, Icons.sell_outlined, 'Sale'),
                  const SizedBox(height: 10),
                  _grid(ctx, saleTiles, twoCols: twoCols),
                  const SizedBox(height: 14),
                  _sectionTitle(ctx, Icons.link, 'Links'),
                  const SizedBox(height: 10),
                  _grid(ctx, links, twoCols: twoCols),
                  const SizedBox(height: 14),
                  if (showMargins) ...[
                    _sectionTitle(ctx, Icons.percent, 'Margins'),
                    const SizedBox(height: 10),
                    _grid(ctx, margins, twoCols: twoCols),
                    const SizedBox(height: 14),
                  ],
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: kAccentA.withOpacity(.20)),
                  const SizedBox(height: 10),
                  _sectionTitle(ctx, Icons.sticky_note_2_outlined, 'Notes'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: kAccentA.withOpacity(.18), width: 0.9),
                    ),
                    child: Text(
                      notes.isEmpty ? '—' : notes,
                      style: Theme.of(ctx)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.25),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
