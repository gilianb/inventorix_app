// lib/collection_page.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/widgets/edit.dart';
import '../../inventory/widgets/search_and_filters.dart'; // ⬅️ barre de recherche + filtre jeu
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/new_stock_page.dart';

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

  // Filtres/UI (alignés avec la page principale)
  final _searchCtrl = TextEditingController();
  String? _gameFilter; // valeur = game_label
  String _typeFilter = 'single'; // 'single' | 'sealed'

  List<Map<String, dynamic>> _groups = const [];

  // KPIs (collection uniquement)
  num _invested = 0;
  num _potential = 0;

  // ➕ KPI: somme brute des sale_price de chaque item en 'collection'
  num _soldTotal = 0;

  bool get _isGilian =>
      (_sb.auth.currentUser?.email ?? '').toLowerCase() ==
      'gilian.bns@gmail.com';

  @override
  void initState() {
    super.initState();
    // contrôle d’accès basique
    if (!_isGilian) {
      // ignore: use_build_context_synchronously
      Future.microtask(() => Navigator.of(context).pop());
      return;
    }
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _groups = await _fetchGroupedFromView();
      _computeKpisFromCollectionLines(); // investi + potentiel (sur lignes)
      _soldTotal = await _sumSoldFromItems(); // 💰 somme brute item-level
    } catch (e) {
      _snack('Erreur chargement collection : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Récupère les groupes depuis la vue stricte v_items_by_status
  /// + applique les filtres “search” et “game” (comme la page principale)
  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    const cols =
        // dimensions
        'product_id, game_id, type, language, '
        'product_name, game_code, game_label, '
        'purchase_date, currency, '
        // champs homogènes
        'supplier_name, buyer_company, notes, grade_id, grading_note, sale_date, sale_price, '
        'tracking, photo_url, document_url, estimated_price, sum_estimated_price, item_location, channel_id, '
        'payment_type, buyer_infos, '
        // agrégats
        'qty_total, '
        'qty_ordered, qty_in_transit, qty_paid, qty_received, '
        'qty_sent_to_grader, qty_at_grader, qty_graded, '
        'qty_listed, qty_awaiting_payment, qty_sold, qty_shipped, qty_finalized, qty_collection, '
        // totaux coûts + KPI
        'total_cost, total_cost_with_fees, realized_revenue, '
        'sum_shipping_fees, sum_commission_fees, sum_grading_fees';

    final List<dynamic> raw = await _sb
        .from('v_items_by_status')
        .select(cols)
        .eq('type', _typeFilter)
        .order('purchase_date', ascending: false)
        .limit(1000);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // filtre texte local (nom produit / langue / jeu / fournisseur)
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

    // filtre jeu local (par label)
    if ((_gameFilter ?? '').isNotEmpty) {
      rows = rows.where((r) => (r['game_label'] ?? '') == _gameFilter).toList();
    }

    return rows;
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

  /// ➕ Somme brute des sale_price *au niveau item* pour les items en 'collection'
  /// Respecte le filtre type et (si présent) le filtre jeu (via game_id).
  Future<num> _sumSoldFromItems() async {
    var sel = _sb
        .from('item')
        .select('sale_price, game_id')
        .eq('status', 'collection')
        .eq('type', _typeFilter)
        .not('sale_price', 'is', null);

    // Si un jeu est filtré, on traduit le label -> id pour filtrer game_id
    if ((_gameFilter ?? '').isNotEmpty) {
      final gid = await _resolveGameIdByLabel(_gameFilter!);
      if (gid != null) {
        sel = sel.eq('game_id', gid);
      } else {
        // aucun jeu ne matche ce label → somme = 0
        return 0;
      }
    }

    final List<dynamic> rows = await sel.limit(50000);
    num sum = 0;
    for (final e in rows) {
      final sp = (e['sale_price'] as num?);
      if (sp != null) sum += sp;
    }
    return sum;
  }

  /// Résout un id de jeu à partir de son label (pour le filtre jeu)
  Future<int?> _resolveGameIdByLabel(String label) async {
    try {
      final row = await _sb
          .from('games')
          .select('id, label')
          .eq('label', label)
          .maybeSingle();
      return (row?['id'] as int?);
    } catch (_) {
      return null;
    }
  }

  void _openDetails(Map<String, dynamic> line) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            GroupDetailsPage(group: Map<String, dynamic>.from(line)),
      ),
    );

    if (changed == true) {
      _refresh(); // ⇦ recharge au retour
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

  // ======= SUPPRESSION D'UNE LIGNE (collection) =======

  Future<bool> _confirmDeleteDialog(Map<String, dynamic> line) async {
    final name = (line['product_name'] ?? '').toString();
    final status = (line['status'] ?? '').toString();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer cette ligne de la collection ?'),
            content: Text(
              'Produit : $name\nStatut : $status\n\n'
              'Cette action supprimera définitivement tous les items et mouvements '
              'associés STRICTEMENT à cette ligne de la collection.',
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

  /// Récupère les IDs d'items appartenant STRICTEMENT à la "ligne"
  Future<List<int>> _collectItemIdsForLine(Map<String, dynamic> line) async {
    // --- Helpers de normalisation ---
    dynamic norm(dynamic v) {
      if (v == null) return null;
      if (v is String && v.trim().isEmpty) return null; // '' -> NULL
      return v;
    }

    String? dateStr(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) {
        return v.toIso8601String().split('T').first; // YYYY-MM-DD
      }
      if (v is String) return v; // supposé déjà au bon format
      return v.toString();
    }

    // 1) Clés raisonnables (on RETIRE photo_url / document_url)
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

    Future<List<int>> runQuery(Set<String> keys) async {
      var q = _sb.from('item').select('id');

      for (final k in keys) {
        if (!line.containsKey(k)) continue;
        var v = norm(line[k]);

        if (v == null) {
          q = q.filter(k, 'is', null);
          continue;
        }

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

      // statut EXACT de la ligne
      q = q.eq('status', (line['status'] ?? '').toString());

      final List<dynamic> raw =
          await q.order('id', ascending: true).limit(20000);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
    }

    // 2) Essai avec l’ensemble “primary”
    var ids = await runQuery(primaryKeys);
    if (ids.isNotEmpty) return ids;

    // 3) Fallback : ne garder que des clés “fortes”
    const strongKeys = <String>{
      'product_id',
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
    if (!_isGilian) return; // sécurité supplémentaire UI
    final ok = await _confirmDeleteDialog(line);
    if (!ok) return;

    try {
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('Aucun item trouvé pour cette ligne de collection.');
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
    final lines = _collectionLines();

    // jeux distincts pour le dropdown (comme la page principale)
    final gamesForFilter = _groups
        .map((r) => (r['game_label'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // === Encart: Recherche + Tabs type ===
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
                            // ⬇️ Barre de recherche + filtre jeu
                            SearchAndGameFilter(
                              searchCtrl: _searchCtrl,
                              games: gamesForFilter,
                              selectedGame: _gameFilter,
                              onGameChanged: (v) {
                                setState(() => _gameFilter = v);
                                _refresh();
                              },
                              onSearch: _refresh,
                            ),
                            const SizedBox(height: 8),
                            // ⬇️ Tabs single / sealed
                            SegmentedButton<String>(
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
                          ],
                        ),
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
                    soldTotal: _soldTotal, // 💰 somme brute item-level
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

                // Tableau
                InventoryTableByStatus(
                  lines: lines,
                  onOpen: _openDetails,
                  onEdit: _openEdit,
                  onDelete: _isGilian ? _deleteLine : null,
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

class _CollectionKpis extends StatelessWidget {
  const _CollectionKpis({
    required this.invested,
    required this.potential,
    required this.soldTotal, // 💰
    required this.currency,
  });

  final num invested;
  final num potential;
  final num soldTotal; // 💰
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
      final w = c.maxWidth;

      final k1 = _card(ctx, Icons.savings, 'Investi (collection)',
          '${_m(invested)} $currency',
          gradient: [kAccentA.withOpacity(.12), kAccentB.withOpacity(.06)],
          iconBg: kAccentA);

      final k2 = _card(
          ctx, Icons.lightbulb, 'Valeur estimée', '${_m(potential)} $currency',
          gradient: [kAccentB.withOpacity(.12), kAccentC.withOpacity(.06)],
          iconBg: kAccentB);

      final k3 = _card(ctx, Icons.monetization_on, 'Total sold',
          '${_m(soldTotal)} $currency',
          gradient: [kAccentG.withOpacity(.14), kAccentB.withOpacity(.06)],
          iconBg: kAccentG);

      if (w > 1200) {
        return Row(children: [
          Expanded(child: k1),
          const SizedBox(width: 12),
          Expanded(child: k2),
          const SizedBox(width: 12),
          Expanded(child: k3),
        ]);
      } else if (w > 800) {
        return Column(
          children: [
            Row(children: [
              Expanded(child: k1),
              const SizedBox(width: 12),
              Expanded(child: k2),
            ]),
            const SizedBox(height: 12),
            k3,
          ],
        );
      } else {
        return Column(children: [
          k1,
          const SizedBox(height: 12),
          k2,
          const SizedBox(height: 12),
          k3
        ]);
      }
    });
  }
}
