import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'new_stock_page.dart';
import 'sales_archive_page.dart';
import 'package:inventorix_app/lot_details/lot_details_page.dart';

class MainInventoryPage extends StatefulWidget {
  const MainInventoryPage({super.key});
  @override
  State<MainInventoryPage> createState() => _MainInventoryPageState();
}

class _MainInventoryPageState extends State<MainInventoryPage> {
  final _sb = Supabase.instance.client;

  final _searchCtrl = TextEditingController();
  String? _gameFilter; // game_label choisi (ou null)
  bool _loading = true;
  bool _asTable = false; // bascule cartes/table

  List<Map<String, dynamic>> _rows = const [];

  static const _statusOrder = <String>[
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
    _refresh();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _rows = await _fetchMainInventory();
    } catch (e) {
      _msg('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMainInventory() async {
    // NOTE: game_code / game_label viennent de la vue mise à jour
    final cols =
        'lot_id, product_name, language, game_code, game_label, purchase_date, '
        'total_cost, currency, qty_total, '
        'qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_sold, qty_shipped, qty_finalized, '
        'total_cost_with_fees, realized_revenue';

    final List<dynamic> raw = await _sb
        .from('v_main_inventory')
        .select(cols)
        .order('purchase_date', ascending: false)
        .limit(500);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Filtre texte local
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((r) {
        final n = (r['product_name'] ?? '').toString().toLowerCase();
        final l = (r['language'] ?? '').toString().toLowerCase();
        final g = (r['game_label'] ?? '').toString().toLowerCase();
        return n.contains(q) || l.contains(q) || g.contains(q);
      }).toList();
    }

    // Filtre jeu
    if (_gameFilter != null && _gameFilter!.isNotEmpty) {
      rows = rows.where((r) => (r['game_label'] ?? '') == _gameFilter).toList();
    }

    return rows;
  }

  Future<void> _openCreateLot() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const NewStockPage()));
    if (changed == true) _refresh();
  }

  void _openLot(int lotId) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LotDetailsPage(lotId: lotId)));
  }

  // ====== AGGREGATIONS ======
  num _sum(String key) =>
      _rows.fold<num>(0, (p, r) => p + ((r[key] as num?) ?? 0));

  // ====== WIDGETS ======

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildSearchAndFilter(),
                const SizedBox(height: 8),
                _buildOverview(context),
                const SizedBox(height: 12),
                _buildStatusBreakdownCard(context),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text('Lots (${_rows.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        tooltip: _asTable ? 'Vue cartes' : 'Vue table',
                        onPressed: () => setState(() => _asTable = !_asTable),
                        icon: Icon(
                            _asTable ? Icons.view_agenda : Icons.table_rows),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _asTable ? _buildTable() : _buildCardsList(),
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
        onPressed: _openCreateLot,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau lot'),
      ),
    );
  }

  // ====== Search + Filter ======
  Widget _buildSearchAndFilter() {
    final games = _rows
        .map((r) => (r['game_label'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final hasGames = games.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        runSpacing: 8,
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Rechercher (nom, langue, jeu)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _refresh();
                  },
                ),
              ),
            ),
          ),
          if (hasGames)
            DropdownButton<String>(
              value: _gameFilter,
              hint: const Text('Filtrer par jeu'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Tous les jeux')),
                ...games.map((g) => DropdownMenuItem(value: g, child: Text(g))),
              ],
              onChanged: (v) => setState(() {
                _gameFilter = v;
                _refresh();
              }),
            ),
        ],
      ),
    );
  }

  // ====== Overview KPIs ======
  Widget _buildOverview(BuildContext context) {
    String money(num n) => n.toDouble().toStringAsFixed(2);

    final invested = _sum('total_cost_with_fees');
    final realized = _sum('realized_revenue');
    final lots = _rows.length;
    final qtyTotal = _sum('qty_total');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth > 680;
          final kpis = [
            _KpiTile(
              icon: Icons.inventory_2,
              label: 'Lots',
              value: '$lots',
              subtitle: 'Total lots',
            ),
            _KpiTile(
              icon: Icons.format_list_numbered,
              label: 'Qté totale',
              value: '$qtyTotal',
              subtitle: 'Unités',
            ),
            _KpiTile(
              icon: Icons.savings,
              label: 'Investi (USD)',
              value: money(invested),
              subtitle: 'Coût + frais',
            ),
            _KpiTile(
              icon: Icons.trending_up,
              label: 'Revenu réalisé',
              value: money(realized),
              subtitle: 'Ventes',
            ),
          ];

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
                Expanded(child: kpis[1]),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: kpis[2]),
                const SizedBox(width: 12),
                Expanded(child: kpis[3]),
              ]),
            ],
          );
        },
      ),
    );
  }

  // ====== Status Breakdown ======
  Widget _buildStatusBreakdownCard(BuildContext context) {
    final totals = <String, int>{
      for (final s in _statusOrder) s: 0,
    };
    for (final r in _rows) {
      for (final s in _statusOrder) {
        final key = 'qty_$s';
        totals[s] = totals[s]! + ((r[key] as int?) ?? 0);
      }
    }
    final grand = totals.values.fold<int>(0, (p, n) => p + n);
    if (grand == 0) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Répartition globale par statut',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._statusOrder.map((s) {
            final v = totals[s]!;
            final pct = grand == 0 ? 0.0 : v / grand;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _MiniBar(
                label: s,
                value: v,
                fraction: pct,
              ),
            );
          }),
        ]),
      ),
    );
  }

  // ====== Cards view ======
  Widget _buildCardsList() {
    if (_rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Aucun lot')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: _rows
            .map((r) => _LotCard(
                  data: r,
                  onOpen: () => _openLot(r['lot_id'] as int),
                ))
            .toList(),
      ),
    );
  }

  // ====== Table view (optionnel) ======
  Widget _buildTable() {
    String money(num? n) => ((n ?? 0).toDouble()).toStringAsFixed(2);

    DataRow _row(Map<String, dynamic> r) {
      final lotId = r['lot_id'] as int;
      final sent = (r['qty_sent_to_grader'] ?? 0) as int;
      final at = (r['qty_at_grader'] ?? 0) as int;
      final grd = (r['qty_graded'] ?? 0) as int;

      return DataRow(cells: [
        DataCell(Text(r['product_name']?.toString() ?? '')),
        DataCell(Text(r['language']?.toString() ?? '')),
        DataCell(Text(r['game_label']?.toString() ?? '—')),
        DataCell(Text(r['purchase_date']?.toString() ?? '')),
        DataCell(Text('${money(r['total_cost'])} ${r['currency'] ?? 'USD'}')),
        DataCell(Text('${r['qty_total']}')),
        DataCell(Text(
            '${r['qty_in_transit']} / ${r['qty_paid']} / ${r['qty_received']}')),
        DataCell(Text('$sent / $at / $grd')),
        DataCell(Text(
            '${r['qty_listed']} / ${r['qty_sold']} / ${r['qty_shipped']} / ${r['qty_finalized']}')),
        DataCell(Text(
            '${money(r['total_cost_with_fees'])} ${r['currency'] ?? 'USD'}')),
        DataCell(
            Text('${money(r['realized_revenue'])} ${r['currency'] ?? 'USD'}')),
        DataCell(IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openLot(lotId))),
      ]);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Produit')),
          DataColumn(label: Text('Langue')),
          DataColumn(label: Text('Jeu')),
          DataColumn(label: Text('Achat (date)')),
          DataColumn(label: Text('Prix total')),
          DataColumn(label: Text('Qté')),
          DataColumn(label: Text('Achat (transit/paid/received)')),
          DataColumn(label: Text('Gradation (sent/at/graded)')),
          DataColumn(label: Text('Vente (listed/sold/shipped/finalized)')),
          DataColumn(label: Text('Coût total+frais')),
          DataColumn(label: Text('Revenu réalisé')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _rows.map(_row).toList(),
      ),
    );
  }
}

/* ===================== Small UI helpers ===================== */

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar(
      {required this.label, required this.value, required this.fraction});
  final String label;
  final int value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text('$value'),
        ]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          return Container(
            height: 8,
            width: w,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: cs.surfaceVariant,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _LotCard extends StatelessWidget {
  const _LotCard({required this.data, required this.onOpen});
  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  String _money(num? n) => ((n ?? 0).toDouble()).toStringAsFixed(2);

  Widget _chip(BuildContext ctx, String label, int v, {Color? bg}) {
    return Chip(
      label: Text('$label: $v'),
      backgroundColor: bg ?? Theme.of(ctx).colorScheme.surfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['product_name'] ?? '').toString();
    final lang = (data['language'] ?? '').toString();
    final game = (data['game_label'] ?? '').toString();
    final date = (data['purchase_date'] ?? '').toString();

    final cost = _money(data['total_cost'] as num?);
    final costWithFees = _money(data['total_cost_with_fees'] as num?);
    final revenue = _money(data['realized_revenue'] as num?);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(child: Text('${data['qty_total'] ?? ''}')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text([if (game.isNotEmpty) game, if (lang.isNotEmpty) lang]
                        .join(' • ')),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Chip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text('Achat: $date'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.payments, size: 18),
                        label: Text('Total: $cost USD'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.receipt_long, size: 18),
                        label: Text('Coût+frais: $costWithFees USD'),
                      ),
                      if ((data['realized_revenue'] as num? ?? 0) > 0)
                        Chip(
                          avatar: const Icon(Icons.trending_up, size: 18),
                          label: Text('Revenu: $revenue USD'),
                        ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ouvrir',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, 'Transit', (data['qty_in_transit'] ?? 0) as int),
                _chip(context, 'Paid', (data['qty_paid'] ?? 0) as int),
                _chip(context, 'Reçu', (data['qty_received'] ?? 0) as int),
                _chip(
                    context, 'Sent', (data['qty_sent_to_grader'] ?? 0) as int),
                _chip(context, 'At', (data['qty_at_grader'] ?? 0) as int),
                _chip(context, 'Graded', (data['qty_graded'] ?? 0) as int),
                _chip(context, 'Listé', (data['qty_listed'] ?? 0) as int),
                _chip(context, 'Vendu', (data['qty_sold'] ?? 0) as int),
                _chip(context, 'Ship', (data['qty_shipped'] ?? 0) as int),
                _chip(context, 'Final', (data['qty_finalized'] ?? 0) as int),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
