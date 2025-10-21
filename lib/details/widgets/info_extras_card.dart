// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class InfoExtrasCard extends StatelessWidget {
  const InfoExtrasCard({
    super.key,
    required this.data,
    required this.currencyFallback,
  });

  final Map<String, dynamic> data;
  final String currencyFallback;

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
        const SnackBar(content: Text('Impossible d’ouvrir le lien.')),
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
                            style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = _txt(data['currency']) == '—'
        ? currencyFallback
        : _txt(data['currency']);

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
      _kv(context, 'Shipping fees', _money(data['shipping_fees'], currency)),
      _kv(context, 'Commission fees',
          _money(data['commission_fees'], currency)),
      _kv(context, 'Payment type', _txt(data['payment_type'])),
      _kv(context, 'Buyer infos', _txt(data['buyer_infos'])),
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
              color: kAccentA.withOpacity(.18), width: 1), // filet coloré
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
                      Text('Informations',
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
