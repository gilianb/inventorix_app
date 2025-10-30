// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Liste chronologique des évènements (v_item_history ou mouvement legacy).
/// - hiérarchie visuelle renforcée
/// - tags (Achat, Vente, Statut, Prix...)
/// - valeurs Avant → Après alignées
/// - “par utilisateur” (actor_name ou actor_uid)
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.movements});
  final List<Map<String, dynamic>> movements;

  // ===== Helpers communs =====
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

  // ===== Mappings =====
  static const Map<String, String> _fieldLabels = {
    'status': 'Statut',
    'sale_price': 'Prix de vente',
    'sale_date': 'Date de vente',
    'estimated_price': 'Prix estimé',
    'tracking': 'Tracking',
    'buyer_company': 'Acheteur',
    'channel_id': 'Canal',
    'item_location': 'Emplacement',
    'notes': 'Notes',
    'unit_cost': 'Prix unitaire',
    'unit_fees': 'Frais unitaires',
    'shipping_fees': 'Frais d’expédition',
    'commission_fees': 'Frais de commission',
    'grading_fees': 'Frais de grading',
    'grade_id': 'Grade ID',
    'grading_note': 'Note de grading',
    'photo_url': 'Photo',
    'document_url': 'Document',
    'payment_type': 'Type de paiement',
    'buyer_infos': 'Infos acheteur',
  };

  static const Map<String, String> _movementLabels = {
    'purchase': 'Achat',
    'receive': 'Réception',
    'ship_to_grader': 'Envoi au grader',
    'receive_by_grader': 'Reçu par grader',
    'graded': 'Grading',
    'list_for_sale': 'Mise en vente',
    'unlist': 'Retrait de vente',
    'sell': 'Vente',
    'ship_sale': 'Expédition',
    'finalize_sale': 'Finalisation',
    'adjustment': 'Ajustement',
    'price_note': 'Note de prix',
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
      return Icons.edit;
    }
  }

  String _labelUnified(Map<String, dynamic> e) {
    final kind = e['kind'];
    final code = (e['code'] ?? '').toString();
    return kind == 'movement'
        ? (_movementLabels[code] ?? code)
        : (_fieldLabels[code] ?? code);
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

  // ---- Rendu d'un événement unifié ----
  Widget _buildUnifiedTile(BuildContext context, Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final icon = _iconUnified(e);
    final label = _labelUnified(e);
    final ts = _fmtTs(e['ts']);
    final payload = Map<String, dynamic>.from(e['payload'] ?? {});
    final actorName = _txt(e['actor_name']); // si rempli côté SQL
    final actorUid = _shortUid(e['actor_uid']?.toString());
    final actor =
        actorName != '—' ? actorName : (actorUid != '—' ? actorUid : 'Inconnu');

    // Mouvement (métier)
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
            // Icône
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
              child: Icon(icon, color: cs.primary, size: 18),
            ),
            const SizedBox(width: 10),

            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne 1: Tag + Timestampe
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

                  // Ligne 2: détails métier
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (from != '—' || to != '—')
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Statut: $from'),
                          _arrow(),
                          Text(to),
                        ]),
                      if (qty != '—')
                        _tag(context, 'Qté: $qty',
                            icon: Icons.format_list_numbered),
                      if (up != '—')
                        _tag(context, 'PU: $up ${cur != "—" ? cur : ""}'.trim(),
                            icon: Icons.price_change),
                      if (note != '—') Text('Note: $note'),
                    ],
                  ),

                  const SizedBox(height: 6),
                  // Ligne 3: auteur
                  Text('par $actor',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Changement de champ (audit)
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
          // Icône
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08), shape: BoxShape.circle),
            child: Icon(icon, color: cs.primary, size: 18),
          ),
          const SizedBox(width: 10),

          // Contenu
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne 1: Tag + horodatage
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

                // Ligne 2: Avant → Après en colonnes
                LayoutBuilder(builder: (ctx, cons) {
                  final isNarrow = cons.maxWidth < 380;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Avant', before),
                        const SizedBox(height: 2),
                        _kv('Après', after),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _kv('Avant', before)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: _kv('Après', after)),
                    ],
                  );
                }),

                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Motif: $reason'),
                ],

                const SizedBox(height: 6),
                Text('par $actor',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Ancien format (compat) ----
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
                        Text('Statut: $from'),
                        _arrow(),
                        Text(to),
                      ]),
                    if (qty != '—')
                      _tag(context, 'Qté: $qty',
                          icon: Icons.format_list_numbered),
                    if (up != '—')
                      _tag(context, 'PU: $up ${cur != "—" ? cur : ""}'.trim(),
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
        child: Text('Aucun historique.',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    // Liste compacte avec séparateurs légers
    return Column(
      children: [
        for (int i = 0; i < movements.length; i++) ...[
          _isUnified(movements[i])
              ? _buildUnifiedTile(context, movements[i])
              : _buildLegacyTile(context, movements[i]),
          if (i != movements.length - 1)
            const Divider(height: 8, indent: 44), // aligné après l’icône
        ]
      ],
    );
  }
}
