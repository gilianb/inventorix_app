// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Chronological list of events (v_item_history or legacy movement).
/// Displays the email of the event author (not the current user).
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.movements});
  final List<Map<String, dynamic>> movements;

  // ===== Common helpers =====
  String _txt(dynamic v) =>
      (v == null || (v is String && v.toString().trim().isEmpty))
          ? '—'
          : v.toString();

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  String _fmtTs(dynamic v) {
    final dt = _parseTs(v);
    if (dt == null) return _txt(v);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d  $hh:$mm';
  }

  String _shortUid(String? uid) {
    if (uid == null || uid.isEmpty) return '—';
    return uid.length <= 8
        ? uid
        : '${uid.substring(0, 4)}…${uid.substring(uid.length - 4)}';
  }

  bool _isUnified(Map<String, dynamic> e) =>
      e.containsKey('kind') && e.containsKey('code');

  // ===== Actor label (email priority) =====
  String _actorLabel(Map<String, dynamic> e) {
    final payload = Map<String, dynamic>.from(e['payload'] ?? const {});
    String? candidate;

    // Prefer emails if present in different forms
    for (final key in const ['actor_email', 'email']) {
      final v = e[key];
      if (v is String && v.trim().isNotEmpty) {
        candidate = v.trim();
        break;
      }
    }
    if (candidate == null) {
      for (final key in const ['actor_email', 'email']) {
        final v = payload[key];
        if (v is String && v.trim().isNotEmpty) {
          candidate = v.trim();
          break;
        }
      }
    }
    if (candidate == null) {
      // sometimes the actor is an object { email: ... }
      final actorObj = e['actor'];
      if (actorObj is Map) {
        final v = actorObj['email'];
        if (v is String && v.trim().isNotEmpty) {
          candidate = v.trim();
        }
      }
    }

    // Fallbacks: name then shortened uid
    if (candidate != null) return candidate;
    final actorName = (e['actor_name'] ?? '').toString().trim();
    if (actorName.isNotEmpty) return actorName;
    final uid = _shortUid(e['actor_uid']?.toString());
    return uid == '—' ? 'unknown' : uid;
  }

  // ===== Mappings =====
  static const Map<String, String> _fieldLabels = {
    // item fields
    'status': 'Status',
    'sale_price': 'Sale price',
    'sale_date': 'Sale date',
    'estimated_price': 'Estimated price',
    'tracking': 'Tracking',
    'buyer_company': 'Buyer',
    'channel_id': 'Channel',
    'item_location': 'Location',
    'notes': 'Notes',
    'unit_cost': 'Unit price',
    'unit_fees': 'Unit fees',
    'shipping_fees': 'Shipping fees',
    'commission_fees': 'Commission fees',
    'grading_fees': 'Grading fees',
    'grade_id': 'Grade ID',
    'grading_note': 'Grading note',
    'photo_url': 'Photo',
    'document_url': 'Document',
    'payment_type': 'Payment type',
    'buyer_infos': 'Buyer info',
    'language': 'Language',
    'game_id': 'Game',
    // product-mapped
    'product_name': 'Product name',
    'type': 'Type',
  };

  static const Map<String, String> _movementLabels = {
    'purchase': 'Purchase',
    'receive': 'Receive',
    'ship_to_grader': 'Send to grader',
    'receive_by_grader': 'Received by grader',
    'graded': 'Graded',
    'list_for_sale': 'List for sale',
    'unlist': 'Unlist',
    'sell': 'Sale',
    'ship_sale': 'Ship sale',
    'finalize_sale': 'Finalize',
    'adjustment': 'Adjustment',
    'price_note': 'Price note',
  };

  IconData _iconUnified(Map<String, dynamic> e) {
    final kind = e['kind'];
    final code = (e['code'] ?? '').toString();
    if (kind == 'movement') {
      switch (code) {
        case 'purchase':
          return Icons.shopping_cart;
        case 'receive':
          return Icons.download_done;
        case 'ship_to_grader':
          return Icons.local_shipping;
        case 'receive_by_grader':
          return Icons.how_to_vote;
        case 'graded':
          return Icons.verified;
        case 'list_for_sale':
          return Icons.list_alt;
        case 'unlist':
          return Icons.remove_circle_outline;
        case 'sell':
          return Icons.sell;
        case 'ship_sale':
          return Icons.local_shipping;
        case 'finalize_sale':
          return Icons.flag_circle;
        case 'adjustment':
          return Icons.tune;
        case 'price_note':
          return Icons.price_change;
        default:
          return Icons.event;
      }
    } else {
      if (code == 'status') return Icons.swap_horiz;
      if (code.contains('price')) return Icons.price_change;
      if (code == 'tracking') return Icons.local_shipping;
      if (code == 'item_location') return Icons.place;
      if (code == 'notes') return Icons.note_alt;
      if (code == 'batch_edit') return Icons.edit_note;
      return Icons.edit;
    }
  }

  String _labelUnified(Map<String, dynamic> e) {
    final kind = e['kind'];
    final code = (e['code'] ?? '').toString();
    if (kind == 'movement') {
      return _movementLabels[code] ?? code;
    }
    if (kind == 'edit' && code == 'batch_edit') {
      return 'update';
    }
    return _fieldLabels[code] ?? code;
  }

  Widget _tag(BuildContext context, String text, {IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: cs.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 90,
            child:
                Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(v)),
      ],
    );
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.arrow_forward, size: 16),
      );

  // ---- Render a batch_edit event ----
  Widget _buildBatchTile(BuildContext context, Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final ts = _fmtTs(e['ts']);
    final payload = Map<String, dynamic>.from(e['payload'] ?? {});
    final changes = Map<String, dynamic>.from(payload['changes'] ?? {});
    final count = payload['count']?.toString() ?? '—';
    final actor = _actorLabel(e);

    final List<Widget> rows = [];
    changes.forEach((code, diff) {
      final label = _fieldLabels[code] ?? code.toString();
      final m = Map<String, dynamic>.from(diff as Map);
      final before = _txt(m['old']);
      final after = _txt(m['new']);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(builder: (ctx, cons) {
          final isNarrow = cons.maxWidth < 380;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                _kv('Before', before),
                const SizedBox(height: 2),
                _kv('After', after),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 120,
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(before)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(after)),
            ],
          );
        }),
      ));
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
            child: const Icon(Icons.edit_note, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _tag(context, 'update'),
                  if (count != '—') ...[
                    const SizedBox(width: 8),
                    _tag(context, 'Items: $count',
                        icon: Icons.format_list_numbered),
                  ],
                  const Spacer(),
                  Text(ts,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                ...rows,
                const SizedBox(height: 6),
                Text('by $actor',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Render a unified event (movement / field change) ----
  Widget _buildUnifiedTile(BuildContext context, Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final icon = _iconUnified(e);
    final label = _labelUnified(e);
    final ts = _fmtTs(e['ts']);
    final payload = Map<String, dynamic>.from(e['payload'] ?? {});
    final actor = _actorLabel(e);

    // Business movement
    if ((e['kind'] ?? '') == 'movement') {
      final from = _txt(payload['from_status']);
      final to = _txt(payload['to_status']);
      final qty = _txt(payload['qty']);
      final up = _txt(payload['unit_price']);
      final cur = _txt(payload['currency']);
      final note = _txt(payload['note']);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
              child: Icon(icon, color: cs.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _tag(context, label),
                      const Spacer(),
                      Text(ts,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (from != '—' || to != '—')
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Status: $from'),
                          _arrow(),
                          Text(to),
                        ]),
                      if (qty != '—')
                        _tag(context, 'Qty: $qty',
                            icon: Icons.format_list_numbered),
                      if (up != '—')
                        _tag(context,
                            'Unit price: $up ${cur != "—" ? cur : ""}'.trim(),
                            icon: Icons.price_change),
                      if (note != '—') Text('Note: $note'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('by $actor',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Field change (audit)
    final oldV = payload['old'];
    final newV = payload['new'];
    final before = (oldV is Map || oldV is List)
        ? oldV.toString()
        : (oldV ?? '—').toString();
    final after = (newV is Map || newV is List)
        ? newV.toString()
        : (newV ?? '—').toString();
    final reason = (payload['reason'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
            child: Icon(icon, color: cs.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _tag(context, _labelUnified(e)),
                    const Spacer(),
                    Text(ts,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(builder: (ctx, cons) {
                  final isNarrow = cons.maxWidth < 380;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Before', before),
                        const SizedBox(height: 2),
                        _kv('After', after),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _kv('Before', before)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: _kv('After', after)),
                    ],
                  );
                }),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Reason: $reason'),
                ],
                const SizedBox(height: 6),
                Text('by $actor',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Legacy format (compat) ----
  IconData _iconLegacy(String mtype) {
    switch (mtype) {
      case 'purchase':
        return Icons.shopping_cart;
      case 'receive':
        return Icons.download_done;
      case 'ship_to_grader':
        return Icons.local_shipping;
      case 'receive_by_grader':
        return Icons.how_to_vote;
      case 'graded':
        return Icons.verified;
      case 'list_for_sale':
        return Icons.list_alt;
      case 'unlist':
        return Icons.remove_circle_outline;
      case 'sell':
        return Icons.sell;
      case 'ship_sale':
        return Icons.local_shipping;
      case 'finalize_sale':
        return Icons.flag_circle;
      case 'adjustment':
        return Icons.tune;
      case 'price_note':
        return Icons.price_change;
      default:
        return Icons.history;
    }
  }

  Widget _buildLegacyTile(BuildContext context, Map<String, dynamic> m) {
    final cs = Theme.of(context).colorScheme;
    final ts = _fmtTs(m['ts']);
    final mtype = _txt(m['mtype']);
    final from = _txt(m['from_status']);
    final to = _txt(m['to_status']);
    final qty = _txt(m['qty']);
    final up = _txt(m['unit_price']);
    final cur = _txt(m['currency']);
    final note = _txt(m['note']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
            child: Icon(_iconLegacy(mtype), color: cs.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _tag(context, mtype),
                    const Spacer(),
                    Text(ts,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (from != '—' || to != '—')
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Status: $from'),
                        _arrow(),
                        Text(to),
                      ]),
                    if (qty != '—')
                      _tag(context, 'Qty: $qty',
                          icon: Icons.format_list_numbered),
                    if (up != '—')
                      _tag(context,
                          'Unit price: $up ${cur != "—" ? cur : ""}'.trim(),
                          icon: Icons.price_change),
                    if (note != '—') Text('Note: $note'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Text('No history.', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    bool isBatch(Map<String, dynamic> e) =>
        (e['kind'] == 'edit' && e['code'] == 'batch_edit');
    bool isMovement(Map<String, dynamic> e) => (e['kind'] == 'movement');

    // If there's at least one batch edit, hide all small edit lines
    final hasAnyBatch = movements.any(isBatch);

    final filtered = hasAnyBatch
        ? movements.where((e) => isBatch(e) || isMovement(e)).toList()
        : movements;

    return Column(
      children: [
        for (int i = 0; i < filtered.length; i++) ...[
          isBatch(filtered[i])
              ? _buildBatchTile(context, filtered[i])
              : (_isUnified(filtered[i])
                  ? _buildUnifiedTile(context, filtered[i])
                  : _buildLegacyTile(context, filtered[i])),
          if (i != filtered.length - 1)
            const Divider(height: 8, indent: 44), // aligned after the icon
        ]
      ],
    );
  }
}
