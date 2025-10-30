// lib/collection_page.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../inventory/widgets/table_by_status.dart';
import '../../../inventory/widgets/edit.dart';
import '../../../inventory/widgets/search_and_filters.dart'; // ⬅️ barre de recherche + filtre jeu
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/new_stock/new_stock_page.dart';

// ✅ KPI factorisé (Investi / Estimé / Vendu) basé sur sale_price null / non-null
import '../../../inventory/widgets/finance_overview.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, this.orgId}); // ← orgId optionnel
  final String? orgId;

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

  // Données pour le tableau (groupes)
  List<Map<String, dynamic>> _groups = const [];

  // Données brutes items pour le KPI factorisé
  List<Map<String, dynamic>> _kpiItems = const [];

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
      // 1) Groupes pour le tableau
      _groups = await _fetchGroupedFromView();
      // 2) Items bruts pour le KPI FinanceOverview
      _kpiItems = await _fetchCollectionItemsForKpis();
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
        'org_id, product_id, game_id, type, language, '
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

    var q = _sb.from('v_items_by_status').select(cols).eq('type', _typeFilter);

    // 🔐 filtre org si fourni
    if ((widget.orgId ?? '').isNotEmpty) {
      q = q.eq('org_id', widget.orgId as Object);
    }

    final List<dynamic> raw =
        await q.order('purchase_date', ascending: false).limit(1000);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // filtre texte local (nom produit / langue / jeu / fournisseur)
    final qtxt = _searchCtrl.text.trim().toLowerCase();
    if (qtxt.isNotEmpty) {
      rows = rows.where((r) {
        final n = (r['product_name'] ?? '').toString().toLowerCase();
        final l = (r['language'] ?? '').toString().toLowerCase();
        final g = (r['game_label'] ?? '').toString().toLowerCase();
        final s = (r['supplier_name'] ?? '').toString().toLowerCase();
        return n.contains(qtxt) ||
            l.contains(qtxt) ||
            g.contains(qtxt) ||
            s.contains(qtxt);
      }).toList();
    }

    // filtre jeu local (par label)
    if ((_gameFilter ?? '').isNotEmpty) {
      rows = rows.where((r) => (r['game_label'] ?? '') == _gameFilter).toList();
    }

    return rows;
  }

  /// Items bruts de la collection (pour KPI FinanceOverview)
  /// Logique KPI:
  /// - Investi / Estimé → items avec sale_price == null
  /// - Vendu → items avec sale_price != null
  Future<List<Map<String, dynamic>>> _fetchCollectionItemsForKpis() async {
    var sel = _sb.from('item').select('''
          id, org_id, game_id, type, status, sale_price,
          unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
          estimated_price, currency
        ''').eq('status', 'collection').eq('type', _typeFilter);

    // 🔐 filtre org
    if ((widget.orgId ?? '').isNotEmpty) {
      sel = sel.eq('org_id', widget.orgId as Object);
    }

    // filtre jeu si label choisi
    if ((_gameFilter ?? '').isNotEmpty) {
      final gid = await _resolveGameIdByLabel(_gameFilter!);
      if (gid != null) {
        sel = sel.eq('game_id', gid);
      } else {
        return const [];
      }
    }

    final List<dynamic> rows = await sel.limit(50000);
    return rows
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
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

  // Explose uniquement la collection pour le tableau
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

      // 🔐 filtre org_id
      if ((widget.orgId ?? '').isNotEmpty) {
        q = q.eq('org_id', widget.orgId as Object);
      }

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

    // 3) Fallback : clés “fortes”
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

      final moveDel =
          _sb.from('movement').delete().filter('item_id', 'in', idsCsv);
      final itemDel = _sb.from('item').delete().filter('id', 'in', idsCsv);

      // 🔐 sécuriser les deletes par org si fournie
      if ((widget.orgId ?? '').isNotEmpty) {
        moveDel.eq('org_id', widget.orgId as Object);
        itemDel.eq('org_id', widget.orgId as Object);
      }

      await moveDel;
      await itemDel;

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

                // ===== KPI factorisé, réutilisable partout =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FinanceOverview(
                    items: _kpiItems,
                    currency: lines.isNotEmpty
                        ? (lines.first['currency']?.toString() ?? 'USD')
                        : 'USD',
                    titleInvested: 'Investi (collection)',
                    titleEstimated: 'Valeur estimée',
                    titleSold: 'Total sold',
                    subtitleInvested: 'Σ coûts (items non vendus)',
                    subtitleEstimated: 'Σ estimated_price (non vendus)',
                    subtitleSold: 'Σ sale_price (vendus)',
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
        title: const Text(' Collection'),
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
          final orgId = widget.orgId;
          if (orgId == null || orgId.isEmpty) {
            _snack('Aucune organisation sélectionnée.');
            return;
          }
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => NewStockPage(orgId: orgId)),
          );
          if (changed == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouveau stock'),
      ),
    );
  }
}
