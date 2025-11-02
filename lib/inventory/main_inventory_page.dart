// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/search_and_filters.dart';
import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';
import '../../inventory/widgets/edit.dart';
import '../../inventory/widgets/finance_overview.dart'; // ⬅️ widget KPI factorisé

import 'package:inventorix_app/new_stock/new_stock_page.dart';
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/collection/collection_page.dart';

import '../top_sold/top_sold_page.dart'; // ⬅️ Top Sold tab

// 🔁 Multi-org
import 'package:inventorix_app/org/organization_models.dart';
import 'package:inventorix_app/org/organizations_page.dart';

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
  const MainInventoryPage({super.key, required this.orgId});
  final String orgId;

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

  /// Filtre de période (sur purchase_date)
  /// 'all' | 'month' (30j) | 'week' (7j)
  String _dateFilter = 'all';

  late final TabController _tabCtrl;

  // Données
  List<Map<String, dynamic>> _groups = const [];

  // Items servant aux KPI (passés à FinanceOverview)
  List<Map<String, dynamic>> _kpiItems = const [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this); // ← 4 onglets (Finalized)
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
      _kpiItems =
          await _fetchItemsForKpis(); // ⬅️ items bruts pour FinanceOverview
    } catch (e) {
      _snack('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        'unit_cost, unit_fees, '
        'org_id';

    // Base query
    var query = _sb
        .from('v_items_by_status')
        .select(cols)
        .eq('type', _typeFilter)
        .eq('org_id', widget.orgId); // ← IMPORTANT : filtre org

    // Filtre période sur purchase_date
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
    final rawQ = _searchCtrl.text.trim().toLowerCase();
    if (rawQ.isNotEmpty) {
      // Découpe sur espaces (un ou plusieurs) et supprime les vides
      final tokens =
          rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      bool rowMatches(Map<String, dynamic> r) {
        // Champs sur lesquels on cherche
        final fields = [
          (r['product_name'] ?? '').toString(),
          (r['language'] ?? '').toString(),
          (r['game_label'] ?? '').toString(),
          (r['supplier_name'] ?? '').toString(),
          (r['buyer_company'] ?? '').toString(),
          (r['tracking'] ?? '').toString(),
        ].map((s) => s.toLowerCase()).toList();

        // Chaque token doit être présent dans au moins UN champ
        return tokens.every(
          (t) => fields.any((f) => f.contains(t)),
        );
      }

      rows = rows.where(rowMatches).toList();
    }
    return rows;
  }

  /// Items pour KPI (hors collection), respectant tous les filtres actifs.
  Future<List<Map<String, dynamic>>> _fetchItemsForKpis() async {
    // Statuts à inclure selon le filtre courant (hors 'collection')
    List<String> statuses;
    if ((_statusFilter ?? '').isNotEmpty) {
      final f = _statusFilter!;
      final grouped = kGroupToStatuses[f];
      if (grouped != null) {
        statuses = grouped.where((s) => s != 'collection').toList();
      } else {
        statuses = [f];
      }
    } else {
      // tous les statuts sauf 'collection'
      statuses = kStatusOrder.where((s) => s != 'collection').toList();
    }

    var q = _sb
        .from('item')
        .select('''
          unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
          estimated_price, sale_price, game_id, org_id, type, status, purchase_date
        ''')
        .eq('org_id', widget.orgId)
        .eq('type', _typeFilter)
        .inFilter('status', statuses);

    // Période (purchase_date)
    final after = _purchaseDateStart();
    if (after != null) {
      final d = after.toIso8601String().split('T').first;
      q = q.gte('purchase_date', d);
    }

    // Filtre jeu (par label → id)
    if ((_gameFilter ?? '').isNotEmpty) {
      final row = await _sb
          .from('games')
          .select('id,label')
          .eq('label', _gameFilter!)
          .maybeSingle();
      final gid = (row?['id'] as int?);
      if (gid != null) q = q.eq('game_id', gid);
    }

    final List<dynamic> raw = await q.limit(50000);
    return raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ===== Explosion des lignes (avec option de forcer un statut) =====
  // ⚠️ Par défaut (pas de filtre), on CACHE les lignes "finalized" uniquement dans la liste.
  // Si un filtre est actif OU override, on affiche normalement.
  List<Map<String, dynamic>> _explodeLines({String? overrideFilter}) {
    final out = <Map<String, dynamic>>[];

    // Déplie v_items_by_status -> lignes par statut (sauf collection)
    for (final r in _groups) {
      for (final s in kStatusOrder) {
        if (s == 'collection') continue;
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) {
          out.add({...r, 'status': s, 'qty_status': q});
        }
      }
    }

    // Filtre effectif (override prioritaire)
    final effectiveFilter = (overrideFilter ?? _statusFilter)?.toString() ?? '';

    if (effectiveFilter.isNotEmpty) {
      final grouped = kGroupToStatuses[effectiveFilter];
      if (grouped != null) {
        return out
            .where((e) => grouped.contains(e['status'] as String))
            .toList();
      } else {
        return out.where((e) => e['status'] == effectiveFilter).toList();
      }
    }

    // 👉 Aucun filtre : on MASQUE uniquement les lignes 'finalized' (affichage)
    return out.where((e) => e['status'] != 'finalized').toList();
  }

  // ====== Body d’inventaire réutilisable (optionnellement forcé sur un statut) ======
  Widget _buildInventoryBody({String? forceStatus}) {
    // KPI : si on force un statut, on filtre localement _kpiItems au lieu de re-fetch.
    final effectiveKpiItems = (forceStatus == null)
        ? _kpiItems
        : _kpiItems
            .where((e) => (e['status']?.toString() ?? '') == forceStatus)
            .toList();

    final lines = _explodeLines(overrideFilter: forceStatus);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
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
                  border:
                      Border.all(color: kAccentA.withOpacity(.15), width: 0.8),
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
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'all', label: Text('All time')),
                              ButtonSegment(
                                  value: 'month', label: Text('Last month')),
                              ButtonSegment(
                                  value: 'week', label: Text('Last week')),
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
            // KPIs (prennent les items effectifs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FinanceOverview(
                items: effectiveKpiItems,
                currency: lines.isNotEmpty
                    ? (lines.first['currency']?.toString() ?? 'USD')
                    : 'USD',
                titleInvested: 'Investi (vue)',
                titleEstimated: 'Revenu potentiel',
                titleSold: 'Revenu réel',
                subtitleInvested: 'Σ coûts (non vendus) — hors collection',
                subtitleEstimated:
                    'Σ estimated_price (non vendus) — hors collection',
                subtitleSold: 'Σ sale_price (vendus) — hors collection',
              ),
            ),
            const SizedBox(height: 12),
            StatusBreakdownPanel(
              expanded: _breakdownExpanded,
              onToggle: (v) => setState(() => _breakdownExpanded = v),
              groupRows:
                  _groups.map((r) => {...r, 'qty_collection': 0}).toList(),
              currentFilter: forceStatus ?? _statusFilter,
              onTapStatus: (s) {
                if (s == 'collection') return;

                if (forceStatus != null) {
                  // Depuis l’onglet Finalized : si on clique un autre statut,
                  // on bascule sur l’onglet Inventaire avec ce filtre.
                  if (s != forceStatus) {
                    setState(() => _statusFilter = s);
                    _tabCtrl.index = 0; // go Inventaire
                    _refresh();
                  }
                  return; // si "finalized", on reste
                }

                setState(() => _statusFilter = (_statusFilter == s ? null : s));
                _refresh();
              },
            ),
            const SizedBox(height: 12),

            // Barre de filtre actif : inutile si forceStatus (car fixé par l’onglet)
            if (forceStatus == null)
              ActiveStatusFilterBar(
                statusFilter: _statusFilter,
                linesCount: lines.length,
                onClear: () {
                  setState(() => _statusFilter = null);
                  _refresh();
                },
              ),
            if (forceStatus == null) const SizedBox(height: 12),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              forceStatus == null
                  ? 'Lignes (${lines.length}) — vue par statut'
                  : 'Finalized — Lignes (${lines.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
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
  }

  // 👉 Version robuste : identifie un item réel (par status) sans champs fragiles
  void _openDetails(Map<String, dynamic> line) async {
    final String orgId = widget.orgId;
    final String status = (line['status'] ?? '').toString();
    final String type = (line['type'] ?? '').toString();
    final String language = (line['language'] ?? '').toString();
    final int? productId = line['product_id'] as int?;
    final int? gameId = line['game_id'] as int?;

    if (productId == null || gameId == null || status.isEmpty) {
      _snack('Données insuffisantes pour ouvrir les détails.');
      return;
    }

    Map<String, dynamic>? rep;

    // Probe générique triée par id DESC (pas de updated_at)
    Future<Map<String, dynamic>?> _probe(List<List<dynamic>> conds) async {
      var q = _sb.from('item').select('id, group_sig').eq('org_id', orgId);
      for (final c in conds) {
        final k = c[0] as String;
        final op = c[1] as String;
        final v = c.length > 2 ? c[2] : null;
        if (op == 'is') {
          q = q.filter(k, 'is', null);
        } else if (op == 'eq') {
          q = q.eq(k, v);
        }
      }
      final r = await q.order('id', ascending: false).limit(1).maybeSingle();
      return r == null ? null : Map<String, dynamic>.from(r);
    }

    try {
      // PASS 1 — clés fortes + status
      rep = await _probe([
        ['status', 'eq', status],
        ['type', 'eq', type],
        ['language', 'eq', language],
        ['product_id', 'eq', productId],
        ['game_id', 'eq', gameId],
      ]);

      // PASS 2 — on élargit (si la vue a un type/lang divergent)
      rep ??= await _probe([
        ['status', 'eq', status],
        ['product_id', 'eq', productId],
        ['game_id', 'eq', gameId],
      ]);

      // PASS 3 — ultime secours : status + product
      rep ??= await _probe([
        ['status', 'eq', status],
        ['product_id', 'eq', productId],
      ]);

      if (rep == null || rep['id'] == null) {
        _snack("Impossible d'identifier le groupe d'items pour cette ligne.");
        return;
      }
    } on PostgrestException catch (e) {
      _snack('Erreur de résolution du groupe (Supabase): ${e.message}');
      return;
    } catch (e) {
      _snack('Erreur de résolution du groupe: $e');
      return;
    }

    final payload = {
      'org_id': orgId,
      ...line,
      'id': rep['id'],
      if ((rep['group_sig']?.toString().isNotEmpty ?? false))
        'group_sig': rep['group_sig'],
    };

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            GroupDetailsPage(group: Map<String, dynamic>.from(payload)),
      ),
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
      var q = _sb
          .from('item')
          .select('id')
          .eq('org_id', widget.orgId); // ← filtre org

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
      await _sb
          .from('movement')
          .delete()
          .eq('org_id', widget.orgId) // ← sécurité org
          .filter('item_id', 'in', idsCsv);
      await _sb
          .from('item')
          .delete()
          .eq('org_id', widget.orgId) // ← sécurité org
          .filter('id', 'in', idsCsv);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix'),
        actions: [
          IconButton(
            tooltip: 'Changer d’organisation',
            icon: const Icon(Icons.switch_account),
            onPressed: () async {
              await OrgPrefs.clear();
              if (!mounted) return;
              final picked = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const OrganizationsPage()),
              );
              if (picked != null && mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => MainInventoryPage(orgId: picked)),
                );
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Inventaire'),
            Tab(icon: Icon(Icons.trending_up), text: 'Top Sold'),
            Tab(icon: Icon(Icons.collections_bookmark), text: 'Collection'),
            Tab(icon: Icon(Icons.check_circle), text: 'Finalized'), // ← NEW
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
          // Onglet 0 : Inventaire (normal, finalized masqué par défaut)
          _buildInventoryBody(),

          // Onglet 1 : Top Sold
          TopSoldPage(
            orgId: widget.orgId, // ✅ passe l’org à TopSold
            onOpenDetails: (payload) {
              _openDetails({
                'org_id': widget.orgId, // 🔐 utile pour les requêtes Détails
                ...payload,
              });
            },
          ),

          // Onglet 2 : Collection
          const CollectionPage(),

          // Onglet 3 : Finalized — même page, filtre forcé
          _buildInventoryBody(forceStatus: 'finalized'),
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
              final orgId = widget.orgId;
              if (orgId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Aucune organisation sélectionnée.')),
                );
                return;
              }

              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => NewStockPage(orgId: orgId)),
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
