import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/search_and_filters.dart';
import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';

import 'package:inventorix_app/new_stock_page.dart';
import 'package:inventorix_app/sales_archive_page.dart';
import 'package:inventorix_app/group_details/group_details_page.dart';

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

  // Données brutes (groupes)
  List<Map<String, dynamic>> _groups = const [];

  // Cache d'enrichissement: key = "$productId|$status"
  final Map<String, Map<String, dynamic>> _extrasByKey = {};

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
      _groups = await _fetchGrouped();
      await _hydrateOptionalFields(); // << charge les champs item manquants
    } catch (e) {
      _snack('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGrouped() async {
    final cols =
        'product_id, game_id, type, language, supplier_name, buyer_company, currency, purchase_date, '
        'product_name, game_code, game_label, '
        'qty_total, qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, qty_listed, qty_sold, qty_shipped, qty_finalized, '
        'qty_collection, total_cost, total_cost_with_fees, realized_revenue';

    final List<dynamic> raw = await _sb
        .from('v_items_grouped')
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

  // Hydrate _extrasByKey à partir de item (par product_id + status)
  Future<void> _hydrateOptionalFields() async {
    _extrasByKey.clear();
    if (_groups.isEmpty) return;

    final productIds = _groups
        .map((r) => (r['product_id'] as int?))
        .whereType<int>()
        .toSet()
        .toList();

    if (productIds.isEmpty) return;

    // On récupère 1 “échantillon” d’item par (product_id, status) :
    // Ici on prend le MIN(id) pour chaque couple, ce qui suffit pour avoir des valeurs non nulles.
    // Si tu préfères côté SQL (vue matérialisée), on pourra déplacer cette logique.
    final String idsIn = _idListForIn(productIds);

    final List<dynamic> raw = await _sb
        .from('item')
        .select(
          'id, product_id, status, channel_id, supplier_name, buyer_company, '
          'notes, grade, grading_submission_id, sale_date, sale_price, '
          'tracking, photo_url, document_url, language, purchase_date, currency',
        )
        .filter('product_id', 'in', idsIn)
        .order('id', ascending: true)
        .limit(5000);

    // Pour chaque (product_id,status), garde la première ligne non vide déjà suffisante
    for (final e in raw) {
      final m = Map<String, dynamic>.from(e as Map);
      final pid = m['product_id'] as int?;
      final st = (m['status'] ?? '').toString();
      if (pid == null || st.isEmpty) continue;
      final key = '$pid|$st';
      // si déjà présent, on garde la première (min id)
      _extrasByKey.putIfAbsent(key, () => m);
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
            if (extra != null) ...extra, // << fusion des champs item optionnels
            'status': s,
            'qty_status': q,
          });
        }
      }
    }
    // filtre statut actif
    if ((_statusFilter ?? '').isNotEmpty) {
      return out.where((e) => e['status'] == _statusFilter).toList();
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
        'status': line['status'], // important
        // méta pour l’entête
        'product_name': line['product_name'],
        'game_label': line['game_label'],
        'language': line['language'],
        'currency': line['currency'],
      }),
    ));
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
                ActiveStatusFilterBar(
                  statusFilter: _statusFilter,
                  linesCount: lines.length,
                  onClear: () {
                    setState(() => _statusFilter = null);
                    _refresh();
                  },
                ),
                if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _OverviewKpis(
                    typeFilter: _typeFilter,
                    linesCount: _kpiLinesCount(lines),
                    units: _kpiUnits(lines),
                    investedView: _kpiInvestedFromLines(lines),
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
                      _refresh();
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
  });

  final String typeFilter;
  final int linesCount;
  final int units;
  final num investedView;

  String _money(num n) => n.toDouble().toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget tile(IconData icon, String label, String value, String subtitle) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: cs.primaryContainer, child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(value,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
          ],
        ),
      );
    }

    final kpis = [
      tile(Icons.view_list, 'Lignes', '$linesCount',
          'Type: ${typeFilter.toUpperCase()}'),
      tile(Icons.format_list_numbered, 'Unités (total)', '$units',
          'Somme des quantités'),
      tile(Icons.savings, 'Investi (vue)', _money(investedView),
          'Σ Prix(Qté×u)'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth > 680;
          if (isWide) {
            return Row(
              children: kpis
                  .map((k) => Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(right: 12), child: k)))
                  .toList()
                ..last = Expanded(child: kpis.last),
            );
          }
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
        },
      ),
    );
  }
}
