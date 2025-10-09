import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widgets/info_banner.dart';
import 'widgets/info_extras_card.dart';
import 'widgets/status_chips.dart';
import 'widgets/history_list.dart';
import 'widgets/finance_summary.dart';
import 'dialogs/update_status_dialog.dart';
import 'utils/format.dart';

class LotDetailsPage extends StatefulWidget {
  const LotDetailsPage({super.key, required this.lotId});
  final int lotId;

  @override
  State<LotDetailsPage> createState() => _LotDetailsPageState();
}

class _LotDetailsPageState extends State<LotDetailsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _header;
  List<Map<String, dynamic>> _allocs = const [];
  List<Map<String, dynamic>> _moves = const [];

  static const allStatuses = <String>[
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'sold',
    'shipped',
    'finalized',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hdr = await _sb.from('lot').select('''
        id, purchase_date, total_cost, currency, qty, fees,
        buyer_company, supplier_name, photo_url, document_url,
        notes, sale_date, sale_price,
        product:product_id(id, name, language)
      ''').eq('id', widget.lotId).maybeSingle();

      final allocs = await _sb
          .from('inventory_allocation')
          .select('status, qty, grade, channel:channel_id(code,label)')
          .eq('lot_id', widget.lotId)
          .order('status', ascending: true);

      final moves = await _sb
          .from('movement')
          .select(
              'ts, mtype, from_status, to_status, qty, unit_price, currency, fees, grader, grade, note, channel:channel_id(code,label)')
          .eq('lot_id', widget.lotId)
          .order('ts', ascending: false)
          .limit(200);

      setState(() {
        _header = hdr == null ? null : Map<String, dynamic>.from(hdr as Map);
        _allocs = allocs
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _moves = moves
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
      _snack('Erreur Supabase: ${e.message}');
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      _snack('Erreur: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int qtyFor(String status) => _allocs
      .where((a) => a['status'] == status)
      .fold(0, (p, a) => p + (a['qty'] as int));

  String _inferMtype(String from, String to) {
    if (from == 'paid' && to == 'received') return 'receive';
    if (from == 'received' && to == 'sent_to_grader') return 'ship_to_grader';
    if (to == 'listed') return 'list_for_sale';
    if (from == 'listed' && to == 'sold') return 'sell';
    if (from == 'sold' && to == 'finalized') return 'finalize_sale';
    return 'adjustment';
  }

  Future<void> _openUpdate() async {
    final req = await showUpdateStatusDialog(
      context: context,
      allStatuses: allStatuses,
      hasQtyFor: qtyFor,
      loadChannels: () async {
        final raw =
            await _sb.from('channel').select('id, code, label').order('label');
        return raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      },
    );
    if (req == null) return;

    try {
      final ts = req.effectiveTimestamp?.toIso8601String();
      final unitPrice = req.sellingPrice ?? req.listingPrice;

      await _sb.rpc('fn_move_qty_smart', params: {
        'p_lot_id': widget.lotId,
        'p_from_status': req.from,
        'p_to_status': req.to,
        'p_qty': req.qty,
        'p_channel_id': req.channelId,
        'p_mtype': _inferMtype(req.from, req.to),
        'p_unit_price': unitPrice,
        'p_currency': unitPrice != null ? 'USD' : null,
        'p_fees': req.totalFees,
        'p_note': req.note,
        'p_ts': ts,
      });

      _snack('Opération enregistrée');
      await _load();
    } on PostgrestException catch (e) {
      _snack('Erreur: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détail du lot')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              Text('Erreur: $_error'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ]),
          ),
        ),
      );
    }
    if (_header == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détail du lot')),
        body: const Center(child: Text('Lot introuvable')),
      );
    }

    final h = _header!;
    final product = Map<String, dynamic>.from(h['product'] as Map);

    final listedChips = _allocs
        .where((a) => a['status'] == 'listed')
        .map((a) => Chip(
              label: Text('${(a['channel']?['label']) ?? '—'}: ${a['qty']}'),
              backgroundColor: Colors.amber.shade100,
            ))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du lot')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Bandeau
            InfoBanner(
              qty: h['qty'] as int?,
              productName: product['name'] as String?,
              language: product['language'] as String?,
              supplierName: (h['supplier_name'] ?? '').toString(),
              buyerCompany: (h['buyer_company'] ?? '').toString(),
              purchaseDate: '${h['purchase_date']}',
              totalCostText:
                  '${money(h['total_cost'])} ${h['currency'] ?? 'USD'}',
              feesText: (h['fees'] as num?) != null ? money(h['fees']) : null,
            ),

            const SizedBox(height: 12),

            // Résumé financier
            FinanceSummary(lot: h, moves: _moves),

            const SizedBox(height: 12),

            // Infos complémentaires
            InfoExtrasCard(
              photoUrl: (h['photo_url'] ?? '').toString(),
              documentUrl: (h['document_url'] ?? '').toString(),
              notes: (h['notes'] ?? '').toString(),
              saleInfoText: (h['sale_date'] != null || h['sale_price'] != null)
                  ? 'Vente prévue/faite: ${h['sale_date'] ?? '—'} • ${h['sale_price'] != null ? money(h['sale_price']) : '—'} ${h['currency'] ?? ''}'
                  : null,
              onShowDocSnack: (msg) => _snack(msg),
            ),

            const SizedBox(height: 12),

            // Statuts + action
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Répartition par statut',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    StatusChips(allStatuses: allStatuses, qtyFor: qtyFor),
                    if (listedChips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Listé par canal',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: listedChips),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _openUpdate,
                        icon: const Icon(Icons.sync_alt),
                        label: const Text('Mettre à jour le statut'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Historique
            HistoryList(moves: _moves),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
