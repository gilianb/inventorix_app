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
import 'package:inventorix_app/group_details/group_details_page.dart';

/// Mapping des groupes logiques -> liste de statuts inclus
const Map<String, List<String>> kGroupToStatuses = {
  'purchase': ['ordered', 'in_transit', 'paid', 'received'],
  'grading': ['sent_to_grader', 'at_grader', 'graded'],
  'sale': ['listed', 'sold', 'shipped', 'finalized'],
  'collection': ['collection'],
  'all': [
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
    'collection',
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
  bool _breakdownExpanded = true;
  String _typeFilter = 'single'; // 'single' | 'sealed'
  String? _statusFilter; // filtre de la liste

  // Données brutes (groupes venant de la VUE unique v_items_by_status)
  List<Map<String, dynamic>> _groups = const [];

  // Cache d'enrichissement: key = "$productId|$status"
  final Map<String, Map<String, dynamic>> _extrasByKey = {};

  // KPIs supplémentaires
  num _kpiPotentialRevenue = 0; // Σ estimated_price (tous items)
  num _kpiRealRevenue = 0; // Σ sale_price (statut ∈ [sold, shipped, finalized])

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
      _groups = await _fetchGroupedFromView(); // <- lit v_items_by_status
      await _hydrateOptionalFieldsAndKpis(); // <- récupère échantillon d'items + calcule KPI revenus
    } catch (e) {
      _snack('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Récupère les groupes depuis la **nouvelle vue unique** v_items_by_status
  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    const cols =
        'product_id, game_id, type, language, currency, purchase_date, '
        'product_name, game_code, game_label, '
        'qty_total, '
        'qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_sold, qty_shipped, qty_finalized, qty_collection, '
        'total_cost, total_cost_with_fees, realized_revenue';

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

  // Construit la chaîne "(1,2,3)" pour filter('in')
  String _idListForIn(List<int> ids) => '(${ids.join(",")})';

  /// Récupère des infos items (échantillon par statut) + calcule les KPI revenus
  ///
  /// - Hydrate _extrasByKey pour avoir quelques champs affichables au tableau (min id par (product_id,status))
  /// - Calcule _kpiPotentialRevenue = Σ estimated_price de TOUS les items des produits visibles
  /// - Calcule _kpiRealRevenue = Σ sale_price des items avec status ∈ (sold,shipped,finalized)
  Future<void> _hydrateOptionalFieldsAndKpis() async {
    _extrasByKey.clear();
    _kpiPotentialRevenue = 0;
    _kpiRealRevenue = 0;

    if (_groups.isEmpty) return;

    final productIds = _groups
        .map((r) => (r['product_id'] as int?))
        .whereType<int>()
        .toSet()
        .toList();

    if (productIds.isEmpty) return;

    final String idsIn = _idListForIn(productIds);

    final List<dynamic> raw = await _sb
        .from('item')
        .select(
          'id, product_id, status, channel_id, supplier_name, buyer_company, '
          'notes, grade_id, sale_date, sale_price, estimated_price, '
          'tracking, photo_url, document_url, language, purchase_date, currency, item_location',
        )
        .filter('product_id', 'in', idsIn)
        .order('id', ascending: true)
        .limit(20000);

    for (final e in raw) {
      final m = Map<String, dynamic>.from(e as Map);

      // ---- Hydratation échantillon (min id) par (product_id, status)
      final pid = m['product_id'] as int?;
      final st = (m['status'] ?? '').toString();
      if (pid != null && st.isNotEmpty) {
        final key = '$pid|$st';
        _extrasByKey.putIfAbsent(key, () => m);
      }

      // ---- KPI Revenus
      final est = (m['estimated_price'] as num?) ?? 0;
      if (est > 0) _kpiPotentialRevenue += est;

      if (st == 'sold' || st == 'shipped' || st == 'finalized') {
        final sp = (m['sale_price'] as num?) ?? 0;
        if (sp > 0) _kpiRealRevenue += sp;
      }
    }
  }

  // Explose les groupes en lignes “par statut” + fusionne les extras
  List<Map<String, dynamic>> _explodeLines() {
    final out = <Map<String, dynamic>>[];
    for (final r in _groups) {
      for (final s in kStatusOrder) {
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) {
          final pid = r['product_id'] as int?;
          final key = pid == null ? null : '$pid|$s';
          final extra = (key != null) ? _extrasByKey[key] : null;

          out.add({
            ...r,
            if (extra != null) ...extra, // champs item optionnels
            'status': s,
            'qty_status': q,
          });
        }
      }
    }
    // filtre statut actif
    // filtre actif : accepte soit un statut unitaire, soit un id de groupe
    if ((_statusFilter ?? '').isNotEmpty) {
      final f = _statusFilter!;
      final grouped = kGroupToStatuses[f];
      if (grouped != null) {
        // filtre par groupe (ex: 'purchase' => ordered,in_transit,paid,received)
        return out
            .where((e) => grouped.contains(e['status'] as String))
            .toList();
      } else {
        // filtre par statut unitaire
        return out.where((e) => e['status'] == f).toList();
      }
    }
    return out;
  }

  // ===== KPIs (vue par statut) =====
  int _kpiLinesCount(List<Map<String, dynamic>> lines) => lines.length;

  int _kpiUnits(List<Map<String, dynamic>> lines) =>
      lines.fold<int>(0, (p, e) => p + ((e['qty_status'] as int?) ?? 0));

  /// Investi (vue) = Σ (Prix/unité estimé × Qté du statut)
  /// Prix/unité estimé (fallback) = total_cost_with_fees / qty_total
  num _kpiInvestedFromLines(List<Map<String, dynamic>> lines) {
    num total = 0;
    for (final r in lines) {
      final qtyTotal = (r['qty_total'] as int?) ?? 0;
      final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
      final unit = qtyTotal > 0 ? (totalWithFees / qtyTotal) : 0;
      final q = (r['qty_status'] as int?) ?? 0;
      total += unit * q;
    }
    return total;
  }

  void _openDetails(Map<String, dynamic> line) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailsPage(group: {
        'product_id': line['product_id'],
        'status': line['status'],
        'product_name': line['product_name'],
        'game_label': line['game_label'],
        'language': line['language'],
        'currency': line['currency'],
      }),
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

    // l'échantillon (valeurs actuelles) est déjà fusionné dans "line" via _extrasByKey
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
    final lines = _explodeLines();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
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
                const SizedBox(height: 8),
                if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _OverviewKpis(
                    typeFilter: _typeFilter,
                    linesCount: _kpiLinesCount(lines),
                    units: _kpiUnits(lines),
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
                    groupRows: _groups,
                    currentFilter: _statusFilter,
                    onTapStatus: (s) {
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Lignes (${lines.length}) — vue par statut',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 4),
                InventoryTableByStatus(
                  lines: lines,
                  onOpen: _openDetails,
                  onEdit: _openEdit, // <— AJOUT : ouvre le dialog d’édition
                ),
                const SizedBox(height: 48),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix — Inventaire'),
        actions: [
          IconButton(
            tooltip: 'Archive ventes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesArchivePage()),
            ),
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
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
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20),
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _kpiCard(
        context: context,
        icon: Icons.view_list,
        title: 'Lignes',
        value: '$linesCount',
        subtitle: 'Type: ${typeFilter.toUpperCase()}',
      ),
      _kpiCard(
        context: context,
        icon: Icons.format_list_numbered,
        title: 'Unités (total)',
        value: '$units',
        subtitle: 'Somme des quantités',
      ),
      _kpiCard(
        context: context,
        icon: Icons.savings,
        title: 'Investi (vue)',
        value: '${_money(investedView)} $currency',
        subtitle: 'Σ (Qté × coût/u estimé)',
      ),
      _kpiCard(
        context: context,
        icon: Icons.trending_up,
        title: 'Revenu potentiel',
        value: '${_money(potentialRevenue)} $currency',
        subtitle: 'Σ estimated_price (tous items)',
      ),
      _kpiCard(
        context: context,
        icon: Icons.payments,
        title: 'Revenu réel',
        value: '${_money(realRevenue)} $currency',
        subtitle: 'Σ sale_price (sold/shipped/finalized)',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth > 960;
          final isMedium = c.maxWidth > 680;
          if (isWide) {
            // 5 cartes sur 2 lignes (3 + 2)
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: kpis[0]),
                    const SizedBox(width: 12),
                    Expanded(child: kpis[1]),
                    const SizedBox(width: 12),
                    Expanded(child: kpis[2]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: kpis[3]),
                    const SizedBox(width: 12),
                    Expanded(child: kpis[4]),
                  ],
                ),
              ],
            );
          } else if (isMedium) {
            // 2 colonnes
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
                Row(
                  children: [
                    Expanded(child: kpis[2]),
                    const SizedBox(width: 12),
                    Expanded(child: kpis[3]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: kpis[4]),
                  ],
                ),
              ],
            );
          } else {
            // 1 colonne
            return Column(
              children: [
                kpis[0],
                const SizedBox(height: 12),
                kpis[1],
                const SizedBox(height: 12),
                kpis[2],
                const SizedBox(height: 12),
                kpis[3],
                const SizedBox(height: 12),
                kpis[4],
              ],
            );
          }
        },
      ),
    );
  }
}
