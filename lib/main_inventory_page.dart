import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'new_stock_page.dart';
import 'sales_archive_page.dart';
import 'lot_details_page.dart';

class MainInventoryPage extends StatefulWidget {
  const MainInventoryPage({super.key});
  @override
  State<MainInventoryPage> createState() => _MainInventoryPageState();
}

class _MainInventoryPageState extends State<MainInventoryPage> {
  final _supabase = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

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
    final cols =
        'lot_id, product_name, language, purchase_date, total_cost, currency, '
        'qty_total, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_sold, qty_shipped, qty_finalized, '
        'total_cost_with_fees, realized_revenue';

    // On récupère un petit set et on filtre en Dart si besoin
    final List<dynamic> raw = await _supabase
        .from('v_main_inventory')
        .select(cols)
        .order('purchase_date', ascending: false)
        .limit(300);

    final rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return rows;

    // Filtre local (product_name ou language contient q)
    return rows.where((r) {
      final name = (r['product_name'] ?? '').toString().toLowerCase();
      final lang = (r['language'] ?? '').toString().toLowerCase();
      return name.contains(q) || lang.contains(q);
    }).toList();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openCreateLot() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const NewStockPage()));
    if (changed == true) _refresh();
  }

  void _openLot(int lotId) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LotDetailsPage(lotId: lotId)));
  }

  DataRow _row(Map<String, dynamic> r) {
    final lotId = r['lot_id'] as int;
    String money(num? n) => ((n ?? 0).toDouble()).toStringAsFixed(2);
    final sent = (r['qty_sent_to_grader'] ?? 0) as int;
    final at = (r['qty_at_grader'] ?? 0) as int;
    final grd = (r['qty_graded'] ?? 0) as int;

    return DataRow(cells: [
      DataCell(Text(r['product_name']?.toString() ?? '')),
      DataCell(Text(r['language']?.toString() ?? '')),
      DataCell(Text(r['purchase_date']?.toString() ?? '')),
      DataCell(Text('${money(r['total_cost'])} ${r['currency'] ?? 'EUR'}')),
      DataCell(Text('${r['qty_total']}')),
      DataCell(Text(
          '${r['qty_in_transit']} / ${r['qty_paid']} / ${r['qty_received']}')),
      DataCell(Text('$sent / $at / $grd')),
      DataCell(Text(
          '${r['qty_listed']} / ${r['qty_sold']} / ${r['qty_shipped']} / ${r['qty_finalized']}')),
      DataCell(Text(
          '${money(r['total_cost_with_fees'])} ${r['currency'] ?? 'EUR'}')),
      DataCell(
          Text('${money(r['realized_revenue'])} ${r['currency'] ?? 'EUR'}')),
      DataCell(IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _openLot(lotId))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _refresh(),
                  decoration: InputDecoration(
                    hintText: 'Rechercher (nom, langue)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _refresh();
                        }),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [
                  DataColumn(label: Text('Produit')),
                  DataColumn(label: Text('Langue')),
                  DataColumn(label: Text('Achat (date)')),
                  DataColumn(label: Text('Prix total')),
                  DataColumn(label: Text('Qté')),
                  DataColumn(label: Text('Achat (in_transit/paid/received)')),
                  DataColumn(label: Text('Gradation (sent/at/graded)')),
                  DataColumn(
                      label: Text('Vente (listed/sold/shipped/finalized)')),
                  DataColumn(label: Text('Coût total+frais')),
                  DataColumn(label: Text('Revenu réalisé')),
                  DataColumn(label: Text('Actions')),
                ], rows: _rows.map(_row).toList()),
              ),
              const SizedBox(height: 80),
            ]),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix — Inventaire (par lot)'),
        actions: [
          IconButton(
            tooltip: 'Archive ventes',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesArchivePage())),
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCreateLot,
          icon: const Icon(Icons.add),
          label: const Text('Nouveau lot')),
    );
  }
}
