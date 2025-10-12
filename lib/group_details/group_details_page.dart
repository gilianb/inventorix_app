import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../inventory/utils/status_utils.dart';

import 'dialogs/update_status_dialog.dart';
import 'dialogs/edit_listing_dialog.dart';

class GroupDetailsPage extends StatefulWidget {
  /// Paramètres attendus :
  /// - product_id (int, requis)
  /// - status (String, requis)
  /// - product_name, game_label, language, currency (facultatif, pour l’entête)
  const GroupDetailsPage({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  final Set<int> _selected = {};

  int get _productId => widget.group['product_id'] as int;
  String get _status => (widget.group['status'] ?? '').toString();

  String _money(num n, {String currency = 'USD'}) =>
      '${n.toDouble().toStringAsFixed(2)} $currency';

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      // Récupération des items filtrés par product_id + status
      // On enrichit avec labels jeu et canal
      final cols =
          'id, product_id, game_id, type, language, status, channel_id, purchase_date, currency, '
          'supplier_name, buyer_company, unit_cost, unit_fees, notes, in_collection, '
          'grade, grading_submission_id, sale_date, sale_price, tracking, photo_url, document_url, created_at, '
          'product(name), games!inner(label), channel:channel_id(label)';

      final List<dynamic> raw = await _sb
          .from('item')
          .select(cols)
          .eq('product_id', _productId)
          .eq('status', _status)
          .order('purchase_date', ascending: false)
          .limit(2000);

      _items = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
      _selected.clear();
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase : ${e.message}');
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // KPIs
  int get _units => _items.length;
  num get _invested => _items.fold<num>(
      0,
      (p, e) =>
          p + ((e['unit_cost'] ?? 0) as num) + ((e['unit_fees'] ?? 0) as num));
  num get _avgUnit => _units == 0 ? 0 : _invested / _units;

  Future<void> _changeStatus() async {
    if (_items.isEmpty) return;
    final ids = _selected.isEmpty
        ? _items.map<int>((e) => (e['id'] as num).toInt()).toList()
        : _selected.toList();

    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => UpdateStatusDialog(
          itemIds: ids,
          currentStatus: _status,
          group: widget.group,
          countsByStatus: {},
          collectionCount: 0),
    );
    if (changed == true) _refresh();
  }

  Future<void> _editListing() async {
    if (_items.isEmpty) return;
    final ids = _selected.isEmpty
        ? _items.map<int>((e) => (e['id'] as num).toInt()).toList()
        : _selected.toList();

    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => EditListingDialog(itemIds: ids),
    );
    if (changed == true) _refresh();
  }

  Future<void> _showMovements(int itemId) async {
    try {
      final List<dynamic> raw = await _sb
          .from('movement')
          .select(
              'id, ts, mtype, from_status, to_status, channel_id, qty, unit_price, currency, fees, grade, tracking, note')
          .eq('item_id', itemId)
          .order('ts', ascending: false)
          .limit(50);

      final moves = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      showModalBottomSheet(
        // ignore: use_build_context_synchronously
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: ListView.separated(
              itemCount: moves.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = moves[i];
                final ts = (m['ts'] ?? '').toString();
                final sub = [
                  if ((m['from_status'] ?? '') != '' ||
                      (m['to_status'] ?? '') != '')
                    'status: ${m['from_status'] ?? '-'} → ${m['to_status'] ?? '-'}',
                  if (m['unit_price'] != null)
                    'price: ${_money(m['unit_price'] as num? ?? 0, currency: (m['currency'] ?? 'USD'))}',
                  if (m['fees'] != null) 'fees: ${(m['fees']).toString()}',
                  if ((m['note'] ?? '').toString().isNotEmpty)
                    'note: ${m['note']}',
                ].join(' • ');
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('${m['mtype']} — $ts'),
                  subtitle: Text(sub),
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      _snack('Historique: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.group['product_name']?.toString();
    final game = widget.group['game_label']?.toString();
    final lang = widget.group['language']?.toString();
    final currency = (widget.group['currency'] ?? 'USD').toString();

    final head = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              title ?? 'Produit #$_productId',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Chip(
            label: Text(_status.toUpperCase()),
            // ignore: deprecated_member_use
            backgroundColor: statusColor(context, _status).withOpacity(0.15),
            side: BorderSide(
                // ignore: deprecated_member_use
                color: statusColor(context, _status).withOpacity(0.6)),
          ),
        ]),
        const SizedBox(height: 4),
        Text([
          if (game != null && game.isNotEmpty) game,
          if (lang != null && lang.isNotEmpty) lang
        ].join(' • ')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Kpi(
              icon: Icons.format_list_numbered,
              label: 'Unités',
              value: '$_units'),
          _Kpi(
              icon: Icons.savings,
              label: 'Investi',
              value: _money(_invested, currency: currency)),
          _Kpi(
              icon: Icons.calculate,
              label: 'Prix / unité',
              value: _money(_avgUnit, currency: currency)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            onPressed: _changeStatus,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Changer statut'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _editListing,
            icon: const Icon(Icons.edit),
            label: const Text('Éditer listing'),
          ),
          const Spacer(),
          if (_selected.isNotEmpty)
            Text('${_selected.length} sélectionné(s)',
                style: Theme.of(context).textTheme.labelMedium),
        ]),
      ]),
    );

    final table = _ItemsTable(
      rows: _items,
      onTapRow: (r) => _showMovements((r['id'] as num).toInt()),
      onToggleSelect: (id, sel) => setState(() {
        if (sel) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
      }),
    );

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                head,
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Items (${_items.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 6),
                table,
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail (par statut)'),
      ),
      body: body,
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(icon)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      ]),
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({
    required this.rows,
    required this.onTapRow,
    required this.onToggleSelect,
  });

  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onTapRow;
  final void Function(int id, bool selected) onToggleSelect;

  String _m(num? n) => (n ?? 0).toDouble().toStringAsFixed(2);
  String _txt(dynamic v) =>
      (v == null || v.toString().isEmpty) ? '-' : v.toString();

  @override
  Widget build(BuildContext context) {
    DataRow row(Map<String, dynamic> r) {
      final id = (r['id'] as num).toInt();
      final s = (r['status'] ?? '').toString();
      final unit =
          ((r['unit_cost'] ?? 0) as num) + ((r['unit_fees'] ?? 0) as num);

      return DataRow(
        onSelectChanged: (_) => onTapRow(r),
        cells: [
          DataCell(Text('#$id')),
          DataCell(Text(r['product']?['name']?.toString() ?? '')),
          DataCell(Text(r['language']?.toString() ?? '')),
          DataCell(Text(r['games']?['label']?.toString() ?? '')),
          DataCell(
            Chip(
              label: Text(s.toUpperCase()),
              // ignore: deprecated_member_use
              backgroundColor: statusColor(context, s).withOpacity(0.15),
              // ignore: deprecated_member_use
              side: BorderSide(color: statusColor(context, s).withOpacity(0.6)),
            ),
          ),
          DataCell(Text(_txt(r['channel']?['label']))), // channel
          DataCell(Text(_txt(r['supplier_name']))),
          DataCell(Text(_txt(r['buyer_company']))),
          DataCell(Text(_txt(r['grade']))),
          DataCell(Text(_txt(r['grading_submission_id']))),
          DataCell(Text(_txt(r['sale_date']))),
          DataCell(Text(_txt(r['sale_price']))),
          DataCell(Text(_txt(r['tracking']))),
          DataCell(SizedBox(
              width: 90,
              child: Text(_txt(r['notes']),
                  maxLines: 1, overflow: TextOverflow.ellipsis))),
          DataCell(SizedBox(
              width: 80,
              child: Text(_txt(r['photo_url']),
                  maxLines: 1, overflow: TextOverflow.ellipsis))),
          DataCell(SizedBox(
              width: 80,
              child: Text(_txt(r['document_url']),
                  maxLines: 1, overflow: TextOverflow.ellipsis))),
          DataCell(Text(_m(unit))), // Prix / unité payé
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Produit')),
          DataColumn(label: Text('Langue')),
          DataColumn(label: Text('Jeu')),
          DataColumn(label: Text('Statut')),
          DataColumn(label: Text('Canal')),
          DataColumn(label: Text('Fournisseur')),
          DataColumn(label: Text('Société')),
          DataColumn(label: Text('Grade')),
          DataColumn(label: Text('Submission')),
          DataColumn(label: Text('Date vente')),
          DataColumn(label: Text('Prix vente')),
          DataColumn(label: Text('Tracking')),
          DataColumn(label: Text('Notes')),
          DataColumn(label: Text('Photo')),
          DataColumn(label: Text('Doc')),
          DataColumn(label: Text('Prix / unité')),
        ],
        rows: rows.map(row).toList(),
      ),
    );
  }
}
