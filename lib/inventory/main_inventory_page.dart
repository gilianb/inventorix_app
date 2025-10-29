// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/search_and_filters.dart';
import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';
import '../../inventory/widgets/edit.dart';

import 'package:inventorix_app/new_stock/new_stock_page.dart';
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/collection/collection_page.dart';

import '../top_sold/top_sold_page.dart'; // ⬅️ Top Sold tab

/// Accents (UI only)
const kAccentA = Color(0xFF6C5CE7); // violet
const kAccentB = Color(0xFF00D1B2); // menthe
const kAccentC = Color(0xFFFFB545); // amber
const kAccentG = Color(0xFF22C55E); // green

/// Mapping des groupes logiques -> liste de statuts inclus
const Map<String, List<String>> kGroupToStatuses = {
  'purchase': ['ordered', 'in_transit', 'paid', 'received'],
  'grading': ['sent_to_grader', 'at_grader', 'graded'],
  'sale': ['listed', 'awaiting_payment', 'sold', 'shipped', 'finalized'],
  'all': [
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
  ],
};

class MainInventoryPage extends StatefulWidget {
  const MainInventoryPage({super.key});
  @override
  State<MainInventoryPage> createState() => _MainInventoryPageState();
}

class _MainInventoryPageState extends State<MainInventoryPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  // UI state
  final _searchCtrl = TextEditingController();
  String? _gameFilter;
  bool _loading = true;
  bool _breakdownExpanded = false;
  String _typeFilter = 'single'; // 'single' | 'sealed'
  String? _statusFilter; // filtre de la liste

  /// NEW: filtre de période (sur purchase_date)
  /// 'all' | 'month' (30j) | 'week' (7j)
  String _dateFilter = 'all';

  late final TabController _tabCtrl;

  // Données
  List<Map<String, dynamic>> _groups = const [];
  num _kpiPotentialRevenue = 0; // Σ estimated (hors collection)
  num _kpiRealRevenue = 0; // Σ realized (hors collection)

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Helper pour la date de début selon le _dateFilter
  DateTime? _purchaseDateStart() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return now.subtract(const Duration(days: 30));
      default:
        return null; // all time
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _groups = await _fetchGroupedFromView();
      _recomputeKpis();
    } catch (e) {
      _snack('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recomputeKpis() {
    final lines = _explodeLines(); // hors collection
    num potential = 0;
    num realized = 0;

    for (final r in lines) {
      final int qty = (r['qty_status'] as int?) ?? 0;
      final String s = (r['status'] ?? '').toString();
      final num estUnit = (r['estimated_price'] as num?) ?? 0;
      final num saleUnit = (r['sale_price'] as num?) ?? 0;

      potential += estUnit * qty;
      if (s == 'sold' || s == 'shipped' || s == 'finalized') {
        realized += saleUnit * qty;
      }
    }

    _kpiPotentialRevenue = potential;
    _kpiRealRevenue = realized;
  }

  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    const cols = 'product_id, game_id, type, language, '
        'product_name, game_code, game_label, '
        'purchase_date, currency, '
        'supplier_name, buyer_company, notes, grade_id, grading_note, sale_date, sale_price, '
        'tracking, photo_url, document_url, estimated_price, sum_estimated_price, item_location, channel_id, '
        'payment_type, buyer_infos, '
        'qty_total, '
        'qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_awaiting_payment, qty_sold, qty_shipped, qty_finalized, qty_collection, '
        'total_cost, total_cost_with_fees, realized_revenue, '
        'sum_shipping_fees, sum_commission_fees, sum_grading_fees, '
        // ✅ nouveaux champs pour la séparation par coût unitaire
        'unit_cost, unit_fees';

    // Base query
    var query =
        _sb.from('v_items_by_status').select(cols).eq('type', _typeFilter);

    // NEW: filtre période sur purchase_date
    final after = _purchaseDateStart();
    if (after != null) {
      final afterStr = after.toIso8601String().split('T').first; // 'YYYY-MM-DD'
      query = query.gte('purchase_date', afterStr);
    }

    final List<dynamic> raw =
        await query.order('purchase_date', ascending: false).limit(500);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // filtre texte local
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((r) {
        final n = (r['product_name'] ?? '').toString().toLowerCase();
        final l = (r['language'] ?? '').toString().toLowerCase();
        final g = (r['game_label'] ?? '').toString().toLowerCase();
        final s = (r['supplier_name'] ?? '').toString().toLowerCase();
        return n.contains(q) || l.contains(q) || g.contains(q) || s.contains(q);
      }).toList();
    }

    // filtre jeu
    if ((_gameFilter ?? '').isNotEmpty) {
      rows = rows.where((r) => (r['game_label'] ?? '') == _gameFilter).toList();
    }

    return rows;
  }

  // Lignes par statut (hors collection)
  List<Map<String, dynamic>> _explodeLines() {
    final out = <Map<String, dynamic>>[];
    for (final r in _groups) {
      for (final s in kStatusOrder) {
        if (s == 'collection') continue;
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) {
          out.add({...r, 'status': s, 'qty_status': q});
        }
      }
    }
    if ((_statusFilter ?? '').isNotEmpty) {
      final f = _statusFilter!;
      final grouped = kGroupToStatuses[f];
      if (grouped != null) {
        return out
            .where((e) => grouped.contains(e['status'] as String))
            .toList();
      } else {
        return out.where((e) => e['status'] == f).toList();
      }
    }
    return out;
  }

  num _kpiInvestedFromLines(List<Map<String, dynamic>> lines) {
    num total = 0;
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
      final q = (r['qty_status'] as int?) ?? 0;
      total += unit * q;
    }
    return total;
  }

  void _openDetails(Map<String, dynamic> line) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) =>
              GroupDetailsPage(group: Map<String, dynamic>.from(line))),
    );
    if (changed == true) {
      _refresh();
    }
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

  Future<bool> _confirmDeleteDialog(Map<String, dynamic> line) async {
    final name = (line['product_name'] ?? '').toString();
    final status = (line['status'] ?? '').toString();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer cette ligne ?'),
            content: Text(
              'Produit : $name\nStatut : $status\n\n'
              'Cette action supprimera définitivement tous les items et mouvements '
              'associés à CETTE ligne (strictement) et uniquement ceux-là.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<List<int>> _collectItemIdsForLine(Map<String, dynamic> line) async {
    // Helpers de normalisation
    dynamic norm(dynamic v) {
      if (v == null) return null;
      if (v is String && v.trim().isEmpty) return null;
      return v;
    }

    String? dateStr(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v.toIso8601String().split('T').first;
      if (v is String) return v; // supposé déjà 'YYYY-MM-DD'
      return v.toString();
    }

    // 1) Sélection des clés raisonnables (on supprime photo_url/document_url)
    const primaryKeys = <String>{
      'product_id',
      'game_id',
      'type',
      'language',
      'channel_id',
      'purchase_date',
      'currency',
      'supplier_name',
      'buyer_company',
      'grade_id',
      'grading_note',
      'grading_fees',
      'sale_date',
      'sale_price',
      'tracking',
      'estimated_price',
      'item_location',
      'unit_cost',
      'unit_fees',
      'shipping_fees',
      'commission_fees',
      'payment_type',
      'buyer_infos',
    };

    // Construit la requête avec normalisation NULL/vides et dates
    Future<List<int>> runQuery(Set<String> keys) async {
      var q = _sb.from('item').select('id');

      for (final k in keys) {
        if (!line.containsKey(k)) continue;
        var v = line[k];

        // normalisation
        v = norm(v);
        if (v == null) {
          q = q.filter(k, 'is', null);
          continue;
        }

        // dates -> 'YYYY-MM-DD'
        if (k == 'purchase_date' || k == 'sale_date') {
          final ds = dateStr(v);
          if (ds == null) {
            q = q.filter(k, 'is', null);
          } else {
            q = q.eq(k, ds);
          }
        } else {
          q = q.eq(k, v);
        }
      }

      // statut toujours requis
      q = q.eq('status', (line['status'] ?? '').toString());

      final List<dynamic> raw =
          await q.order('id', ascending: true).limit(20000);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
    }

    // 2) essai avec l’ensemble “primary”
    var ids = await runQuery(primaryKeys);
    if (ids.isNotEmpty) return ids;

    // 3) Fallback : ne garder que les champs "forts"
    const strongKeys = <String>{
      'product_id',
      'status', // géré à part mais on le garde conceptuellement
      'type',
      'language',
      'game_id',
      'channel_id',
      'purchase_date',
      'supplier_name',
      'buyer_company',
      'item_location',
      'tracking',
    };
    ids = await runQuery(strongKeys);
    return ids;
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
    final ok = await _confirmDeleteDialog(line);
    if (!ok) return;

    try {
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('Aucun item trouvé pour cette ligne.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';
      await _sb.from('movement').delete().filter('item_id', 'in', idsCsv);
      await _sb.from('item').delete().filter('id', 'in', idsCsv);

      _snack('Ligne supprimée (${ids.length} item(s) + mouvements).');
      _refresh();
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _explodeLines();

    final inventoryBody = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // Recherche & Filtres
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Card(
                    elevation: 1,
                    shadowColor: kAccentA.withOpacity(.18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kAccentA.withOpacity(.06),
                            kAccentB.withOpacity(.05)
                          ],
                        ),
                        border: Border.all(
                            color: kAccentA.withOpacity(.15), width: 0.8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Column(
                          children: [
                            SearchAndGameFilter(
                              searchCtrl: _searchCtrl,
                              games: _groups
                                  .map((r) => (r['game_label'] ?? '') as String)
                                  .where((s) => s.isNotEmpty)
                                  .toSet()
                                  .toList()
                                ..sort(),
                              selectedGame: _gameFilter,
                              onGameChanged: (v) {
                                setState(() => _gameFilter = v);
                                _refresh();
                              },
                              onSearch: _refresh,
                            ),
                            const SizedBox(height: 8),
                            // Ligne de filtres: Type + Période
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TypeTabs(
                                  typeFilter: _typeFilter,
                                  onTypeChanged: (t) {
                                    setState(() => _typeFilter = t);
                                    _refresh();
                                  },
                                ),
                                // NEW: filtre période (purchase_date)
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                        value: 'all', label: Text('All time')),
                                    ButtonSegment(
                                        value: 'month',
                                        label: Text('Last month')),
                                    ButtonSegment(
                                        value: 'week',
                                        label: Text('Last week')),
                                  ],
                                  selected: {_dateFilter},
                                  onSelectionChanged: (s) {
                                    setState(() => _dateFilter = s.first);
                                    _refresh();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _OverviewKpis(
                    typeFilter: _typeFilter,
                    linesCount: lines.length,
                    units: lines.fold<int>(
                        0, (p, e) => p + ((e['qty_status'] as int?) ?? 0)),
                    investedView: _kpiInvestedFromLines(lines),
                    potentialRevenue: _kpiPotentialRevenue,
                    realRevenue: _kpiRealRevenue,
                    currency: lines.isNotEmpty
                        ? (lines.first['currency']?.toString() ?? 'USD')
                        : 'USD',
                  ),
                  const SizedBox(height: 12),
                  StatusBreakdownPanel(
                    expanded: _breakdownExpanded,
                    onToggle: (v) => setState(() => _breakdownExpanded = v),
                    groupRows: _groups
                        .map((r) => {...r, 'qty_collection': 0})
                        .toList(),
                    currentFilter: _statusFilter,
                    onTapStatus: (s) {
                      if (s == 'collection') return;
                      setState(() =>
                          _statusFilter = (_statusFilter == s ? null : s));
                    },
                  ),
                  const SizedBox(height: 12),
                  ActiveStatusFilterBar(
                    statusFilter: _statusFilter,
                    linesCount: lines.length,
                    onClear: () => setState(() => _statusFilter = null),
                  ),
                  const SizedBox(height: 12),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Lignes (${lines.length}) — vue par statut',
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
                  onDelete: _deleteLine,
                ),
                const SizedBox(height: 48),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Inventaire'),
            Tab(icon: Icon(Icons.trending_up), text: 'Top Sold'),
            Tab(icon: Icon(Icons.collections_bookmark), text: 'Collection'),
          ],
        ),
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
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Onglet 0 : Inventaire
          inventoryBody,
          // Onglet 1 : Top Sold
          TopSoldPage(
            onOpenDetails: (itemRow) {
              final status = (itemRow['status'] ?? 'sold').toString();
              final productId = itemRow['product_id'] as int?;
              if (productId != null) {
                _openDetails({
                  'product_id': productId,
                  'status': status,
                  'currency': itemRow['currency'],
                  'photo_url': itemRow['photo_url'],
                });
              }
            },
          ),
          // Onglet 2 : Collection
          const CollectionPage(),
        ],
      ),
      // FAB visible uniquement sur l’onglet Inventaire
      floatingActionButton: AnimatedBuilder(
        animation: _tabCtrl,
        builder: (context, _) {
          if (_tabCtrl.index != 0) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: kAccentA,
            foregroundColor: Colors.white,
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const NewStockPage()),
              );
              if (changed == true) _refresh();
            },
            icon: const Icon(Icons.add),
            label: const Text('Nouveau stock'),
          );
        },
      ),
    );
  }
}

/* ===== petits widgets locaux ===== */

class _OverviewKpis extends StatelessWidget {
  const _OverviewKpis({
    required this.typeFilter,
    required this.linesCount,
    required this.units,
    required this.investedView,
    required this.potentialRevenue,
    required this.realRevenue,
    required this.currency,
  });

  final String typeFilter;
  final int linesCount;
  final int units;
  final num investedView;
  final num potentialRevenue;
  final num realRevenue;
  final String currency;

  String _money(num n) => n.toDouble().toStringAsFixed(2);

  Widget _kpiCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    List<Color>? gradient,
    Color? iconBg,
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
                    color: (iconBg ?? kAccentA), shape: BoxShape.circle),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _kpiCard(
        context: context,
        icon: Icons.savings,
        title: 'Investi (vue)',
        value: '${_money(investedView)} $currency',
        subtitle: 'Σ (Qté × coût/u estimé) — hors collection',
        gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
        iconBg: kAccentA,
      ),
      _kpiCard(
        context: context,
        icon: Icons.trending_up,
        title: 'Revenu potentiel',
        value: '${_money(potentialRevenue)} $currency',
        subtitle: 'Σ estimated — hors collection',
        gradient: [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
        iconBg: kAccentB,
      ),
      _kpiCard(
        context: context,
        icon: Icons.payments,
        title: 'Revenu réel',
        value: '${_money(realRevenue)} $currency',
        subtitle: 'Σ sale (sold/shipped/finalized)',
        gradient: [kAccentG.withOpacity(.14), kAccentB.withOpacity(.06)],
        iconBg: kAccentG,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth > 960;
          final isMedium = c.maxWidth > 680;

          if (isWide) {
            return Row(
              children: [
                Expanded(child: kpis[0]),
                const SizedBox(width: 12),
                Expanded(child: kpis[1]),
                const SizedBox(width: 12),
                Expanded(child: kpis[2]),
              ],
            );
          } else if (isMedium) {
            return Column(
              children: [
                Row(children: [
                  Expanded(child: kpis[0]),
                  const SizedBox(width: 12),
                  Expanded(child: kpis[1])
                ]),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: kpis[2])]),
              ],
            );
          } else {
            return Column(children: [
              kpis[0],
              const SizedBox(height: 12),
              kpis[1],
              const SizedBox(height: 12),
              kpis[2]
            ]);
          }
        },
      ),
    );
  }
}
