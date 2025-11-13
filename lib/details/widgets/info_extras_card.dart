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

  Widget _kv(BuildContext ctx, String label, String value) {
    final styleLabel = Theme.of(ctx).textTheme.labelMedium?.copyWith(
          letterSpacing: .15,
          fontWeight: FontWeight.w700,
          color: kAccentA,
        );
    final styleValue =
        Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.15);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: styleLabel)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: styleValue)),
        ],
      ),
    );
  }

  // Widget version to allow colored chips
  Widget _kvW(BuildContext ctx, String label, Widget value) {
    final styleLabel = Theme.of(ctx).textTheme.labelMedium?.copyWith(
          letterSpacing: .15,
          fontWeight: FontWeight.w700,
          color: kAccentA,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 160, child: Text(label, style: styleLabel)),
          const SizedBox(width: 8),
          value,
        ],
      ),
    );
  }

  Widget _kvLink(BuildContext ctx, String label, String? url) {
    final u = (url ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      letterSpacing: .15,
                      fontWeight: FontWeight.w700,
                      color: kAccentA,
                    )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: u.isEmpty
                ? const Text('—')
                : InkWell(
                    onTap: () => _openUrl(ctx, u),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            u,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              color: kAccentA,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.open_in_new,
                            size: 16, color: kAccentA),
                      ],
                    ),
                  ),
          ),
        ],
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
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = _txt(data['currency']) == '—'
        ? currencyFallback
        : _txt(data['currency']);

    // === Margin calculations ===
    final num? pct = _asNum(data['marge']); // % if present
    final num? sale = _asNum(data['sale_price']);
    final num cost =
        (_asNum(data['unit_cost']) ?? 0) + (_asNum(data['unit_fees']) ?? 0);
    final num fees = (_asNum(data['shipping_fees']) ?? 0) +
        (_asNum(data['commission_fees']) ?? 0) +
        (_asNum(data['grading_fees']) ?? 0);
    final num invested = cost + fees;

    final num? valueMargin = showMargins
        ? (sale == null ? null : (sale - invested))
        : null; // absolute value
    // if % absent but sold and invested > 0, derive it
    final num? pctDerived = (pct != null)
        ? pct
        : ((sale != null && invested > 0)
            ? ((sale - invested) / invested * 100)
            : null);

    final left = <Widget>[
      _kv(context, 'Product name', _txt(data['product_name'])),
      _kv(context, 'Game', _txt(data['game_label'] ?? data['game_code'])),
      _kv(context, 'Language', _txt(data['language'])),
      _kv(context, 'Type', _txt(data['type'])),
      _kv(context, 'Purchase date', _date(data['purchase_date'])),
      _kv(context, 'Supplier', _txt(data['supplier_name'])),
      _kv(context, 'Buyer', _txt(data['buyer_company'])),
      _kv(context, 'Channel ID', _txt(data['channel_id'])),
      _kv(context, 'Item location', _txt(data['item_location'])),
      _kv(context, 'Tracking', _txt(data['tracking'])),
      _kv(context, 'Grade ID', _txt(data['grade_id'])),
      _kv(context, 'Grading note', _txt(data['grading_note'])),
      _kv(context, 'Grading fees', _money(data['grading_fees'], currency)),
      // === Margins (left for visibility) ===
      if (showMargins)
        _kvW(context, 'Margin (%)',
            MarginChip(marge: pctDerived, compact: true)),
    ];

    final right = <Widget>[
      _kv(context, 'Unit cost', _money(data['unit_cost'], currency)),
      _kv(context, 'Unit fees', _money(data['unit_fees'], currency)),
      _kv(context, 'Estimated price',
          _money(data['estimated_price'], currency)),
      _kv(context, 'Sale price', _money(data['sale_price'], currency)),
      _kv(context, 'Sale date', _date(data['sale_date'])),
      _kv(context, 'Currency', currency),
      _kv(context, 'Created at', _date(data['created_at'])),
      _kvLink(context, 'Photo URL', data['photo_url']),
      _kvLink(context, 'Document URL', data['document_url']),
      _kv(context, 'Shipping fees per unit',
          _money(data['shipping_fees'], currency)),
      _kv(context, 'Commission fees per unit',
          _money(data['commission_fees'], currency)),
      _kv(context, 'Payment type', _txt(data['payment_type'])),
      _kv(context, 'Buyer info', _txt(data['buyer_infos'])),
      if (showMargins)
        _kvW(context, 'Margin (value per unit)',
            _marginValueChip(valueMargin, currency, pctDerived)),
    ];

    final notes = (data['notes'] ?? '').toString();

    return Card(
      elevation: 0.8,
      shadowColor: kAccentA.withOpacity(.18),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: kAccentA.withOpacity(.18), width: 1), // colored border
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kAccentA.withOpacity(.05),
              kAccentB.withOpacity(.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: LayoutBuilder(
            builder: (ctx, cons) {
              final twoCols = cons.maxWidth >= 680;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, size: 18, color: kAccentA),
                      SizedBox(width: 8),
                      Text('Information',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (twoCols)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: left)),
                        const SizedBox(width: 28),
                        Expanded(child: Column(children: right)),
                      ],
                    )
                  else
                    Column(
                      children: [
                        ...left,
                        const SizedBox(height: 8),
                        ...right,
                      ],
                    ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: kAccentA.withOpacity(.25),
                  ),
                  const SizedBox(height: 10),
                  Text('Notes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: kAccentA,
                          )),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kAccentA.withOpacity(.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      notes.isEmpty ? '—' : notes,
                      style: Theme.of(context).textTheme.bodyMedium,
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
