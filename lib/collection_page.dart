// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/widgets/edit.dart';
import 'package:inventorix_app/details/details_page.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String _typeFilter = 'single'; // 'single' | 'sealed'
  List<Map<String, dynamic>> _groups = const [];

  // KPIs (collection uniquement)
  num _invested = 0;
  num _potential = 0;

  bool get _isGilian =>
      (_sb.auth.currentUser?.email ?? '').toLowerCase() ==
      'gilian.bns@gmail.com';

  @override
  void initState() {
    super.initState();
    // contrôle d’accès basique
    if (!_isGilian) {
      Future.microtask(() => Navigator.of(context).pop());
      return;
    }
    _refresh();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _groups = await _fetchGroupedFromView();
      _computeKpisFromCollectionLines();
    } catch (e) {
      _snack('Erreur chargement collection : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    const cols = 'product_id, game_id, type, language, '
        'product_name, game_code, game_label, purchase_date, currency, '
        'supplier_name, buyer_company, notes, grade_id, sale_date, sale_price, '
        'tracking, photo_url, document_url, estimated_price, sum_estimated_price, item_location, channel_id, '
        'payment_type, buyer_infos, '
        'qty_total, qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_awaiting_payment, qty_sold, qty_shipped, qty_finalized, qty_collection, '
        'total_cost, total_cost_with_fees, realized_revenue, '
        'sum_shipping_fees, sum_commission_fees, sum_grading_fees';

    final List<dynamic> raw = await _sb
        .from('v_items_by_status')
        .select(cols)
        .eq('type', _typeFilter)
        .order('purchase_date', ascending: false)
        .limit(1000);

    return raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // Explose uniquement la collection
  List<Map<String, dynamic>> _collectionLines() {
    final out = <Map<String, dynamic>>[];
    for (final r in _groups) {
      final q = (r['qty_collection'] as int?) ?? 0;
      if (q > 0) {
        out.add({
          ...r,
          'status': 'collection',
          'qty_status': q,
        });
      }
    }
    return out;
  }

  void _computeKpisFromCollectionLines() {
    final lines = _collectionLines();
    num invested = 0;
    num potential = 0;

    for (final r in lines) {
      final qtyTotal = (r['qty_total'] as num?) ?? 0;
      final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
      final sumShipping = (r['sum_shipping_fees'] as num?) ?? 0;
      final sumCommission = (r['sum_commission_fees'] as num?) ?? 0;
      final sumGrading = (r['sum_grading_fees'] as num?) ?? 0;

      final perUnitBase = qtyTotal > 0 ? (totalWithFees / qtyTotal) : 0;
      final perUnitShipping = qtyTotal > 0 ? (sumShipping / qtyTotal) : 0;
      final perUnitCommission = qtyTotal > 0 ? (sumCommission / qtyTotal) : 0;
      final perUnitGrading = qtyTotal > 0 ? (sumGrading / qtyTotal) : 0;
      final unit =
          perUnitBase + perUnitShipping + perUnitCommission + perUnitGrading;

      final int q = (r['qty_status'] as int?) ?? 0;
      invested += unit * q;

      final estUnit = (r['estimated_price'] as num?) ?? 0;
      potential += estUnit * q;
    }

    _invested = invested;
    _potential = potential;
  }

  void _openDetails(Map<String, dynamic> line) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailsPage(group: Map<String, dynamic>.from(line)),
    ));
  }

  void _openEdit(Map<String, dynamic> line) async {
    final productId = line['product_id'] as int?;
    final status = (line['status'] ?? '').toString();
    final qty = (line['qty_status'] as int?) ?? 0;

    if (productId == null || status.isEmpty || qty <= 0) {
      _snack('Impossible d’éditer: données manquantes.');
      return;
    }

    final changed = await EditItemsDialog.show(
      context,
      productId: productId,
      status: status,
      availableQty: qty,
      initialSample: line,
    );

    if (changed == true) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _collectionLines();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // Tabs type (single / sealed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Card(
                    elevation: 1,
                    shadowColor: kAccentA.withOpacity(.18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'single', label: Text('Single')),
                                ButtonSegment(
                                    value: 'sealed', label: Text('Sealed')),
                              ],
                              selected: {_typeFilter},
                              onSelectionChanged: (s) {
                                setState(() => _typeFilter = s.first);
                                _refresh();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _CollectionKpis(
                    invested: _invested,
                    potential: _potential,
                    currency: lines.isNotEmpty
                        ? (lines.first['currency']?.toString() ?? 'USD')
                        : 'USD',
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Collection — Lignes (${lines.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                InventoryTableByStatus(
                  lines: lines,
                  onOpen: _openDetails,
                  onEdit: _openEdit,
                  onDelete: null, // par défaut pas de suppression rapide ici
                ),
                const SizedBox(height: 48),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix — Collection'),
        actions: const [],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1, -1),
              end: Alignment(1, 1),
              colors: [kAccentA, kAccentB],
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}

class _CollectionKpis extends StatelessWidget {
  const _CollectionKpis({
    required this.invested,
    required this.potential,
    required this.currency,
  });

  final num invested;
  final num potential;
  final String currency;

  String _m(num n) => n.toDouble().toStringAsFixed(2);

  Widget _card(BuildContext context, IconData icon, String title, String value,
      {List<Color>? gradient, Color? iconBg}) {
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
            colors: gradient ??
                [kAccentA.withOpacity(.08), kAccentB.withOpacity(.06)],
          ),
          border: Border.all(color: kAccentA.withOpacity(.14), width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg ?? kAccentA,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
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
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth > 800;
      final k1 = _card(ctx, Icons.savings, 'Investi (collection)',
          '${_m(invested)} $currency',
          gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
          iconBg: kAccentA);
      final k2 = _card(
          ctx, Icons.lightbulb, 'Valeur estimée', '${_m(potential)} $currency',
          gradient: [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
          iconBg: kAccentB);

      if (wide) {
        return Row(children: [
          Expanded(child: k1),
          const SizedBox(width: 12),
          Expanded(child: k2)
        ]);
      } else {
        return Column(children: [k1, const SizedBox(height: 12), k2]);
      }
    });
  }
}
