// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/search_and_filters.dart';
import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';
import '../../inventory/widgets/edit.dart';

import 'package:inventorix_app/new_stock_page.dart';
import 'package:inventorix_app/sales_archive_page.dart';
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/collection_page.dart'; // ⬅️ NEW

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
  // 'collection' est désormais hors de cette page
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
    // 'collection' retiré de "all"
  ],
};

class MainInventoryPage extends StatefulWidget {
  const MainInventoryPage({super.key});
  @override
  State<MainInventoryPage> createState() => _MainInventoryPageState();
}

class _MainInventoryPageState extends State<MainInventoryPage> {
  final _sb = Supabase.instance.client;

  // UI state
  final _searchCtrl = TextEditingController();
  String? _gameFilter;
  bool _loading = true;
  bool _breakdownExpanded = false;
  String _typeFilter = 'single'; // 'single' | 'sealed'
  String? _statusFilter; // filtre de la liste

  // Données brutes (groupes venant de la VUE stricte v_items_by_status)
  List<Map<String, dynamic>> _groups = const [];

  // KPI (excluent désormais “collection”)
  num _kpiPotentialRevenue = 0; // Σ estimated (hors collection)
  num _kpiRealRevenue = 0; // Σ realized (hors collection)

  bool get _isGilian =>
      (_sb.auth.currentUser?.email ?? '').toLowerCase() ==
      'gilian.bns@gmail.com';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _groups = await _fetchGroupedFromView();
      _recomputeKpis(); // recalcul avec exclusion “collection”
    } catch (e) {
      _snack('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Recalcule les KPI **hors collection**, en s’appuyant sur les lignes par statut
  void _recomputeKpis() {
    final lines =
        _explodeLines(); // déjà filtrées de “collection” (voir plus bas)
    // Potentiel estimé = Σ (estimated_price * qty_status) pour toutes lignes hors collection
    num potential = 0;
    num realized = 0;

    for (final r in lines) {
      final int qty = (r['qty_status'] as int?) ?? 0;
      final String s = (r['status'] ?? '').toString();
      final num estUnit = (r['estimated_price'] as num?) ?? 0;
      final num saleUnit = (r['sale_price'] as num?) ?? 0;

      // potentiel : prendre l’estimation * quantité (peu importe le statut, hors collection)
      potential += estUnit * qty;

      // réalisé : seulement sur sold/shipped/finalized
      if (s == 'sold' || s == 'shipped' || s == 'finalized') {
        realized += saleUnit * qty;
      }
    }

    _kpiPotentialRevenue = potential;
    _kpiRealRevenue = realized;
  }

  /// Récupère les groupes depuis la vue stricte v_items_by_status
  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    const cols =
        // dimensions
        'product_id, game_id, type, language, '
        'product_name, game_code, game_label, '
        'purchase_date, currency, '
        // champs homogènes
        'supplier_name, buyer_company, notes, grade_id, sale_date, sale_price, '
        'tracking, photo_url, document_url, estimated_price, sum_estimated_price, item_location, channel_id,  '
        'payment_type, buyer_infos, '
        // agrégats
        'qty_total, '
        'qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_awaiting_payment, qty_sold, qty_shipped, qty_finalized, qty_collection, '
        // totaux coûts + KPI
        'total_cost, total_cost_with_fees, realized_revenue,'
        'sum_shipping_fees, sum_commission_fees, sum_grading_fees';

    final List<dynamic> raw = await _sb
        .from('v_items_by_status')
        .select(cols)
        .eq('type', _typeFilter)
        .order('purchase_date', ascending: false)
        .limit(500);

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

  // Explose les groupes en lignes “par statut”
  // ⬅️ ICI on **exclut** explicitement 'collection'
  List<Map<String, dynamic>> _explodeLines() {
    final out = <Map<String, dynamic>>[];
    for (final r in _groups) {
      for (final s in kStatusOrder) {
        if (s == 'collection') continue; // ⛔️ exclus de la page principale
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) {
          out.add({
            ...r,
            'status': s,
            'qty_status': q,
          });
        }
      }
    }
    // filtre statut actif (mais 'collection' n’est pas proposé ici)
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

  // Investi (vue) = Σ (coût/u estimé × Qté du statut), hors collection
  num _kpiInvestedFromLines(List<Map<String, dynamic>> lines) {
    num total = 0;
    for (final r in lines) {
      final status = (r['status'] ?? '').toString();
      if (status == 'collection') continue; // ⛔️ exclu

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
            GroupDetailsPage(group: Map<String, dynamic>.from(line)),
      ),
    );

    if (changed == true) {
      _refresh(); // ⇦ recharge la page principale au retour
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

  // ======= SUPPRESSION D'UNE LIGNE (et données associées) =======

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
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Récupère les IDs d'items appartenant STRICTEMENT à la "ligne" (même logique que l’édition)
  Future<List<int>> _collectItemIdsForLine(Map<String, dynamic> line) async {
    PostgrestFilterBuilder q = _sb.from('item').select('id');

    // Clés strictes pour isoler la ligne
    const keys = <String>{
      'product_id',
      'game_id',
      'type',
      'language',
      'channel_id',
      'purchase_date',
      'currency',
      'supplier_name',
      'buyer_company',
      'notes',
      'grade_id',
      'grading_note',
      'grading_fees',
      'sale_date',
      'sale_price',
      'tracking',
      'photo_url',
      'document_url',
      'estimated_price',
      'item_location',
      'unit_cost',
      'unit_fees',
    };

    for (final k in keys) {
      if (!line.containsKey(k)) continue;
      final v = line[k];
      if (v == null) {
        q = q.filter(k, 'is', null);
      } else {
        q = q.eq(k, v);
      }
    }

    // statut EXACT de la ligne
    q = q.eq('status', (line['status'] ?? '').toString());

    final List<dynamic> raw = await q.order('id', ascending: true).limit(20000);

    return raw
        .map((e) => (e as Map)['id'])
        .whereType<int>()
        .toList(growable: false);
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
    final ok = await _confirmDeleteDialog(line);
    if (!ok) return;

    try {
      // 1) Récupérer les ids d’items strictement de cette ligne
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('Aucun item trouvé pour cette ligne.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';

      // 2) Supprimer les mouvements liés puis les items (sans .in_())
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

    // Pour masquer complètement la “collection” dans le breakdown,
    // on passe des groupes clonés avec qty_collection = 0.
    final groupsForPanel = _groups
        .map((r) => {
              ...r,
              'qty_collection': 0, // ⛔️ rien à afficher pour collection ici
            })
        .toList();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // === Encart coloré: Recherche & Filtres ===
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
                            kAccentB.withOpacity(.05),
                          ],
                        ),
                        border: Border.all(
                          color: kAccentA.withOpacity(.15),
                          width: 0.8,
                        ),
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
                            TypeTabs(
                              typeFilter: _typeFilter,
                              onTypeChanged: (t) {
                                setState(() => _typeFilter = t);
                                _refresh();
                              },
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

                  // StatusBreakdownPanel (sans collection)
                  StatusBreakdownPanel(
                    expanded: _breakdownExpanded,
                    onToggle: (v) => setState(() => _breakdownExpanded = v),
                    groupRows: groupsForPanel, // ⬅️ version “sans collection”
                    currentFilter: _statusFilter,
                    onTapStatus: (s) {
                      if (s == 'collection') {
                        // ignorer toute tentative de clic sur “collection”
                        return;
                      }
                      setState(() =>
                          _statusFilter = (_statusFilter == s ? null : s));
                    },
                  ),
                  const SizedBox(height: 12),

                  ActiveStatusFilterBar(
                    statusFilter: _statusFilter,
                    linesCount: lines.length,
                    onClear: () {
                      setState(() => _statusFilter = null);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // libellé + table “lignes — vue par statut”
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
        title: const Text('Inventorix — Inventaire'),
        actions: [
          if (_isGilian)
            IconButton(
              tooltip: 'Collection',
              icon: const Icon(Icons.collections_bookmark),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CollectionPage()),
                );
              },
            ),
          IconButton(
            tooltip: 'Archive ventes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesArchivePage()),
            ),
            icon: const Icon(Icons.receipt_long),
          ),
        ],
        // Dégradé d’appBar
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
      floatingActionButton: FloatingActionButton.extended(
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
                  color: (iconBg ?? kAccentA),
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
                Row(
                  children: [
                    Expanded(child: kpis[0]),
                    const SizedBox(width: 12),
                    Expanded(child: kpis[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: kpis[2])]),
              ],
            );
          } else {
            return Column(
              children: [
                kpis[0],
                const SizedBox(height: 12),
                kpis[1],
                const SizedBox(height: 12),
                kpis[2],
              ],
            );
          }
        },
      ),
    );
  }
}
