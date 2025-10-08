// lib/main_inventory_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'new_stock_page.dart';
import 'sales_archive_page.dart';

class MainInventoryPage extends StatefulWidget {
  const MainInventoryPage({super.key});

  @override
  State<MainInventoryPage> createState() => _MainInventoryPageState();
}

class _MainInventoryPageState extends State<MainInventoryPage> {
  final _supabase = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _items = <Map<String, dynamic>>[];
  final _stockByItemId = <String, int>{};
  bool _loading = true;
  static const _defaultStockReason =
      'manual'; // Doit exister dans l’enum reason

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([_fetchItems(), _fetchStockAggregates()]);
    } catch (e) {
      _showMsg('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchItems() async {
    const cols =
        'id, sku, name, game, category, set_name, collector_number, rarity, '
        'language, condition, finish, image_url, location, buy_price, sell_price, updated_at';

    final q = _searchCtrl.text.trim();
    List<Map<String, dynamic>> data = [];

    if (q.isEmpty) {
      final List<dynamic> raw = await _supabase
          .from('items')
          .select(cols)
          .order('updated_at', ascending: false)
          .limit(200);
      data = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      // Un seul SQL OR avec trois ILIKE => évite d'appeler .ilike/.filter en Dart
      final List<dynamic> raw = await _supabase
          .from('items')
          .select(cols)
          .or('name.ilike.%$q%,sku.ilike.%$q%,set_name.ilike.%$q%')
          .order('updated_at', ascending: false)
          .limit(200);

      data = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    _items
      ..clear()
      ..addAll(data);
    setState(() {});
  }

  Future<void> _fetchStockAggregates() async {
    // Récupère les mouvements et agrège côté client
    // (Pour gros volumes: créer une RPC SQL "select item_id, sum(qty_change) from stock_moves group by 1")
    final List<dynamic> raw =
        await _supabase.from('stock_moves').select('item_id, qty_change');

    _stockByItemId.clear();
    for (final rowAny in raw) {
      final row = Map<String, dynamic>.from(rowAny as Map);
      final id = (row['item_id'] ?? '').toString();
      final delta = int.tryParse(row['qty_change'].toString()) ?? 0;
      _stockByItemId[id] = (_stockByItemId[id] ?? 0) + delta;
    }
    setState(() {});
  }

  int _stockFor(String itemId) => _stockByItemId[itemId] ?? 0;

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      _showMsg('Erreur de déconnexion : $e');
    }
  }

  Future<void> _openCreateOrEdit({Map<String, dynamic>? item}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewStockPage(existingItem: item)),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _quickAdjustStock(Map<String, dynamic> item) async {
    final itemId = item['id']?.toString();
    if (itemId == null) return;

    final controller = TextEditingController();
    final reasonCtrl = TextEditingController(text: _defaultStockReason);
    final formKey = GlobalKey<FormState>();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ajuster le stock'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Article : ${item['name'] ?? ''}'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Variation (ex: +5 ou -3)',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Saisir une valeur';
                    }
                    final n = int.tryParse(v.trim());
                    if (n == null || n == 0) return 'Entier non nul requis';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Raison (enum reason)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(ctx).unfocus(); // <-- défocus avant pop
                Navigator.pop(ctx, false);
              },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  FocusScope.of(ctx).unfocus(); // <-- défocus avant pop
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );

    if (res != true) return;

    final delta = int.parse(controller.text.trim());
    final reason = reasonCtrl.text.trim().isEmpty
        ? _defaultStockReason
        : reasonCtrl.text.trim();

    try {
      await _supabase.from('stock_moves').insert({
        'item_id': itemId,
        'qty_change': delta,
        'reason': reason, // doit exister dans l’enum reason
        // 'org_id': '...' // si tu utilises l’org, ajoute-la ici
      });
      _showMsg('Stock ajusté : ${delta > 0 ? '+' : ''}$delta');
      await _fetchStockAggregates();
      setState(() {});
    } on PostgrestException catch (e) {
      _showMsg('Erreur d’ajustement : ${e.message}');
    } catch (e) {
      _showMsg('Erreur d’ajustement : $e');
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l’article ?'),
        content: Text(item['name'] ?? ''),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _supabase.from('items').delete().eq('id', item['id']);
      _showMsg('Article supprimé');
      await _refreshAll();
    } on PostgrestException catch (e) {
      _showMsg('Suppression impossible : ${e.message}');
    } catch (e) {
      _showMsg('Suppression impossible : $e');
    }
  }

  Widget _buildRow(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final name = (item['name'] ?? '') as String;
    final sku = (item['sku'] ?? '') as String? ?? '';
    final setName = (item['set_name'] ?? '') as String? ?? '';
    final lang = (item['language'] ?? '') as String? ?? '';
    final rarity = (item['rarity'] ?? '') as String? ?? '';
    final sellPrice = (item['sell_price'] as num?)?.toDouble();
    final stock = _stockFor(id);

    return Dismissible(
      key: ValueKey('item-$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteItem(item);
        return false;
      },
      child: ListTile(
        leading: CircleAvatar(
          child: Text(stock.toString()),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (sku.isNotEmpty) 'SKU: $sku',
            if (setName.isNotEmpty) setName,
            if (lang.isNotEmpty) lang,
            if (rarity.isNotEmpty) rarity,
            if (sellPrice != null) '€${sellPrice.toStringAsFixed(2)}',
          ].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _openCreateOrEdit(item: item),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Ajuster stock',
          onPressed: () => _quickAdjustStock(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView.builder(
              itemCount: _items.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => _fetchItems(),
                      decoration: InputDecoration(
                        hintText: 'Rechercher (nom, sku, set...)',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            FocusScope.of(context).unfocus(); // <-- défocus
                            _searchCtrl.clear();
                            _fetchItems();
                          },
                        ),
                      ),
                    ),
                  );
                }
                final item = _items[i - 1];
                return _buildRow(item);
              },
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix — Inventaire'),
        actions: [
          IconButton(
            tooltip: 'Archive ventes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesArchivePage()),
              );
            },
            icon: const Icon(Icons.receipt_long),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel article'),
      ),
    );
  }
}
