// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/widgets/search_and_filters.dart';
import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';
import '../../inventory/widgets/edit.dart';
import '../../inventory/widgets/finance_overview.dart';

import 'package:inventorix_app/new_stock/new_stock_page.dart';
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/vault/vault_page.dart';

import '../top_sold/top_sold_page.dart';

// 🔁 Multi-org
import 'package:inventorix_app/org/organization_models.dart';
import 'package:inventorix_app/org/organizations_page.dart';

// 🔐 RBAC
import 'package:inventorix_app/org/roles.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

/// Accents (UI only)
const kAccentA = Color(0xFF6C5CE7); // violet
const kAccentB = Color(0xFF00D1B2); // menthe
const kAccentC = Color(0xFFFFB545); // amber
const kAccentG = Color(0xFF22C55E); // green

/// Mapping des groupes logiques -> liste de statuts inclus
const Map<String, List<String>> kGroupToStatuses = {
  'purchase': [
    'ordered',
    'paid',
    'in_transit',
    'received',
    'waiting_for_gradation'
  ],
  'grading': ['sent_to_grader', 'at_grader', 'graded'],
  'sale': ['listed', 'awaiting_payment', 'sold', 'shipped', 'finalized'],
  'all': [
    'ordered',
    'paid',
    'in_transit',
    'received',
    'waiting_for_gradation',
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
    with TickerProviderStateMixin {
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

  TabController? _tabCtrl;

  // Données
  List<Map<String, dynamic>> _groups = const [];

  // Items servant aux KPI (passés à FinanceOverview)
  List<Map<String, dynamic>> _kpiItems = const [];

  // 🔐 Rôle courant & permissions
  OrgRole _role = OrgRole.viewer; // par défaut prudent
  bool _roleLoaded = false; // tant que false, on affiche un loader
  RolePermissions get _perm => kRoleMatrix[_role]!;

  bool get _isOwner => _role == OrgRole.owner;

  // ✅ Total investi exact pour l’onglet Finalized (calculé côté serveur via RPC)
  num? _finalizedInvestOverride;

  // ======== Mode édition de groupe ========
  bool _groupMode = false;
  final Set<String> _selectedKeys = <String>{};
  String? _groupNewStatus;
  final TextEditingController _groupCommentCtrl = TextEditingController();
  bool _applyingGroup = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    _searchCtrl.dispose();
    _groupCommentCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadRole();
    _recreateTabController(); // crée le TabController en fonction du rôle
    await _refresh();
  }

  /// Liste des Tabs selon rôle
  List<Tab> _tabs() => <Tab>[
        const Tab(
            icon: Iconify(Mdi.package_variant,
                color: Color.fromARGB(255, 2, 35, 61)),
            text: 'Inventaire'),
        if (_isOwner)
          const Tab(
              icon: Iconify(Mdi.trending_up,
                  color: Color.fromARGB(255, 2, 35, 61)),
              text: 'Top Sold'),
        if (_isOwner)
          const Tab(
              icon: Iconify(Mdi.safe, color: Color.fromARGB(255, 2, 35, 61)),
              text: 'The Vault'),
        const Tab(
            icon: Iconify(Mdi.check_circle,
                color: Color.fromARGB(255, 2, 35, 61)),
            text: 'Finalized'),
      ];

  /// Pages correspondantes
  List<Widget> _tabViews() => <Widget>[
        _buildInventoryBody(),
        if (_isOwner)
          TopSoldPage(
            orgId: widget.orgId,
            onOpenDetails: (payload) {
              _openDetails({
                'org_id': widget.orgId,
                ...payload,
              });
            },
          ),
        if (_isOwner) vaultPage(orgId: widget.orgId), // ← on passe l’orgId
        _buildInventoryBody(forceStatus: 'finalized'),
      ];

  /// (Re)crée le TabController de façon sûre
  void _recreateTabController() {
    final newLen = _tabs().length;
    final prevIndex = _tabCtrl?.index ?? 0;

    // Dispose AVANT de créer le nouveau (évite 2 tickers actifs en même temps)
    _tabCtrl?.dispose();
    _tabCtrl = TabController(
      length: newLen,
      vsync: this,
      initialIndex: prevIndex.clamp(0, newLen - 1),
    );

    // Forcer rebuild après assignation
    setState(() {});
  }

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      Map<String, dynamic>? row;
      try {
        row = await _sb
            .from('organization_member')
            .select('role')
            .eq('org_id', widget.orgId)
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {
        // RLS/erreur — on tombe sur fallback owner si created_by == uid
      }

      String? roleStr = (row?['role'] as String?);

      if (roleStr == null) {
        try {
          final org = await _sb
              .from('organization')
              .select('created_by')
              .eq('id', widget.orgId)
              .maybeSingle();
          final createdBy = org?['created_by'] as String?;
          if (createdBy != null && createdBy == uid) {
            roleStr = 'owner';
          }
        } catch (_) {}
      }

      final parsed = OrgRole.values.firstWhere(
        (r) => r.name == (roleStr ?? 'viewer').toLowerCase(),
        orElse: () => OrgRole.viewer,
      );

      if (mounted) {
        setState(() {
          _role = parsed;
          _roleLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _roleLoaded = true);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// ======== BOUTON Login/Logout ========
  Future<void> _onTapAuthButton() async {
    final session = _sb.auth.currentSession;
    if (session != null) {
      try {
        await _sb.auth.signOut();
        if (!mounted) return;
        _snack('Logout successful.');
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
      } on AuthException catch (e) {
        _snack('Logout error: ${e.message}');
      } catch (e) {
        _snack('Logout error: $e');
      }
    } else {
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
    }
  }

  DateTime? _purchaseDateStart() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _groups = await _fetchGroupedFromView();
      _kpiItems = await _fetchItemsForKpis();

      // 🔢 récupère le total investi exact pour l’onglet Finalized
      _finalizedInvestOverride = await _fetchFinalizedInvestAggregate();
    } catch (e) {
      _snack('Loading error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rafraîchit _groups / _kpiItems / _finalizedInvestOverride
  /// sans toucher au flag _loading (pas de gros spinner global).
  Future<void> _refreshSilent() async {
    try {
      final newGroups = await _fetchGroupedFromView();
      final newKpiItems = await _fetchItemsForKpis();
      final newFinalizedInvest = await _fetchFinalizedInvestAggregate();

      if (!mounted) return;
      setState(() {
        _groups = newGroups;
        _kpiItems = newKpiItems;
        _finalizedInvestOverride = newFinalizedInvest;
      });
    } catch (_) {
      // best-effort : en cas d'erreur on garde l'optimistic update local
    }
  }

  /// RPC côté serveur : total investi pour FINALIZED, avec filtres alignés à l’UI
  Future<num> _fetchFinalizedInvestAggregate() async {
    try {
      final after = _purchaseDateStart();
      final String? dateFrom = after?.toIso8601String().split('T').first;

      int? gameId;
      if ((_gameFilter ?? '').isNotEmpty) {
        final row = await _sb
            .from('games')
            .select('id,label')
            .eq('label', _gameFilter!)
            .maybeSingle();
        gameId = (row?['id'] as int?);
      }

      final res = await _sb.rpc('app_sum_invested_finalized', params: {
        'p_org_id': widget.orgId,
        'p_type': _typeFilter, // 'single' | 'sealed'
        'p_game_id': gameId, // null si pas de filtre jeu
        'p_date_from': dateFrom, // null si "All time"
      });

      if (res == null) return 0;
      if (res is num) return res;
      return num.tryParse(res.toString()) ?? 0;
    } catch (_) {
      return 0; // fallback silencieux
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGroupedFromView() async {
    final baseCols = <String>[
      'product_id',
      'game_id',
      'type',
      'language',
      'product_name',
      'game_code',
      'game_label',
      'purchase_date',
      'currency',
      'supplier_name',
      'buyer_company',
      'notes',
      'grade_id',
      'grading_note',
      'sale_date',
      'sale_price',
      'tracking',
      'photo_url',
      'document_url',
      'estimated_price',
      'sum_estimated_price',
      'item_location',
      'channel_id',
      'payment_type',
      'buyer_infos',
      'qty_total',
      'qty_ordered',
      'qty_paid',
      'qty_in_transit',
      'qty_received',
      'qty_waiting_for_gradation',
      'qty_sent_to_grader',
      'qty_at_grader',
      'qty_graded',
      'qty_listed',
      'qty_awaiting_payment',
      'qty_sold',
      'qty_shipped',
      'qty_finalized',
      'qty_collection',
      'realized_revenue',
      'sum_shipping_fees',
      'sum_commission_fees',
      'sum_grading_fees',
      'org_id',
      'group_sig', // 👈 important : on récupère group_sig depuis la vue
    ];

    final costCols = <String>[
      'total_cost',
      'total_cost_with_fees',
      'unit_cost',
      'unit_fees',
    ];

    final cols = [
      ...baseCols,
      if (_perm.canSeeUnitCosts) ...costCols,
    ].join(', ');

    var query = _sb
        .from('v_items_by_status_masked')
        .select(cols)
        .eq('type', _typeFilter)
        .eq('org_id', widget.orgId);

    final after = _purchaseDateStart();
    if (after != null) {
      final afterStr = after.toIso8601String().split('T').first;
      query = query.gte('purchase_date', afterStr);
    }

    final List<dynamic> raw =
        await query.order('purchase_date', ascending: false).limit(500);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final rawQ = _searchCtrl.text.trim().toLowerCase();
    if (rawQ.isNotEmpty) {
      final tokens =
          rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      bool rowMatches(Map<String, dynamic> r) {
        final fields = [
          (r['product_name'] ?? '').toString(),
          (r['language'] ?? '').toString(),
          (r['game_label'] ?? '').toString(),
          (r['supplier_name'] ?? '').toString(),
          (r['buyer_company'] ?? '').toString(),
          (r['tracking'] ?? '').toString(),
        ].map((s) => s.toLowerCase()).toList();

        return tokens.every((t) => fields.any((f) => f.contains(t)));
      }

      rows = rows.where(rowMatches).toList();
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _fetchItemsForKpis() async {
    List<String> statuses;
    if ((_statusFilter ?? '').isNotEmpty) {
      final f = _statusFilter!;
      final grouped = kGroupToStatuses[f];
      if (grouped != null) {
        statuses = grouped.where((s) => s != 'vault').toList();
      } else {
        statuses = [f];
      }
    } else {
      statuses = kStatusOrder.where((s) => s != 'vault').toList();
    }

    final canSeeCosts = _perm.canSeeUnitCosts;
    final cols = [
      if (canSeeCosts) 'unit_cost',
      if (canSeeCosts) 'unit_fees',
      if (canSeeCosts) 'shipping_fees',
      if (canSeeCosts) 'commission_fees',
      if (canSeeCosts) 'grading_fees',
      'estimated_price',
      if (_perm.canSeeRevenue) 'sale_price',
      'game_id',
      'org_id',
      'type',
      'status',
      'purchase_date',
    ].join(', ');

    var q = _sb
        .from('item_masked')
        .select(cols)
        .eq('org_id', widget.orgId)
        .eq('type', _typeFilter)
        .inFilter('status', statuses);

    final after = _purchaseDateStart();
    if (after != null) {
      final d = after.toIso8601String().split('T').first;
      q = q.gte('purchase_date', d);
    }

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

  List<Map<String, dynamic>> _explodeLines({String? overrideFilter}) {
    final out = <Map<String, dynamic>>[];
    for (final r in _groups) {
      for (final s in kStatusOrder) {
        if (s == 'vault') continue;
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) {
          out.add({...r, 'status': s, 'qty_status': q});
        }
      }
    }

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

    return out.where((e) => e['status'] != 'finalized').toList();
  }

  // 🔑 clé stable “ligne” pour la sélection groupée (alignée avec nos requêtes)
  String _lineKey(Map<String, dynamic> r) {
    String pick(String k) =>
        (r[k] == null || (r[k] is String && r[k].toString().trim().isEmpty))
            ? '_'
            : r[k].toString();
    final parts = <String>[
      pick('org_id'),
      pick('group_sig'), // 👈 on inclut group_sig pour être bien unique
      pick('product_id'),
      pick('game_id'),
      pick('type'),
      pick('language'),
      pick('channel_id'),
      pick('purchase_date'),
      pick('supplier_name'),
      pick('buyer_company'),
      pick('item_location'),
      pick('tracking'),
      pick('currency'),
      pick('status'), // important
    ];
    return parts.join('|');
  }

  Widget _buildInventoryBody({String? forceStatus}) {
    // Items bruts pour KPI (filtrés si forceStatus != null)
    final effectiveKpiItems = (forceStatus == null)
        ? _kpiItems
        : _kpiItems
            .where((e) => (e['status']?.toString() ?? '') == forceStatus)
            .toList();

    // Lignes (groupes explosés par statut)
    final lines = _explodeLines(overrideFilter: forceStatus);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // -- Contexte d'affichage de l'overview
    final bool isFinalizedView = (forceStatus == 'finalized');
    final bool showFinanceOverview =
        isFinalizedView || _perm.canSeeFinanceOverview;

    // Statuts disponibles pour l'édition groupée
    final List<String> allStatuses =
        kStatusOrder.where((s) => s != 'vault').toList();

    // ======== Application de l'édition de groupe (corrigée: plus de "mixed") ========
    Future<void> applyGroupStatusToSelection() async {
      if (_groupNewStatus == null || _groupNewStatus!.isEmpty) {
        _snack('Pick a status to apply.');
        return;
      }
      if (_selectedKeys.isEmpty) {
        _snack('Select at least one line.');
        return;
      }

      final String newStatus = _groupNewStatus!;

      setState(() => _applyingGroup = true);
      try {
        // Lignes sélectionnées visibles
        final selectedLines = lines
            .where((r) => _selectedKeys.contains(_lineKey(r)))
            .toList(growable: false);

        // Regroupement des item_ids par ancien status
        final Map<String, List<int>> idsByOldStatus = {};
        final List<int> allIds = [];

        for (final line in selectedLines) {
          final oldStatus = (line['status'] ?? '').toString();
          if (oldStatus.isEmpty) continue;

          final ids = await _collectItemIdsForLine(line);
          if (ids.isEmpty) continue;

          allIds.addAll(ids);
          idsByOldStatus.putIfAbsent(oldStatus, () => <int>[]).addAll(ids);
        }

        if (allIds.isEmpty) {
          _snack('No items found for selected lines.');
          return;
        }

        final idsCsv = '(${allIds.join(",")})';

        // ⚙️ MAJ statut en masse
        await _sb
            .from('item')
            .update({'status': newStatus}).filter('id', 'in', idsCsv);

        // 📝 LOG : une entrée par ancien status (plus de "mixed")
        final comment = _groupCommentCtrl.text.trim();
        final String reason =
            comment.isEmpty ? 'group_status' : 'group_status: $comment';

        for (final entry in idsByOldStatus.entries) {
          final String oldStatus = entry.key;
          final List<int> itemIds = entry.value;
          if (itemIds.isEmpty) continue;

          await _logBatchEdit(
            orgId: widget.orgId,
            itemIds: itemIds,
            changes: {
              'status': {
                'old': oldStatus, // ✅ vrai ancien statut
                'new': newStatus,
              },
            },
            reason: reason,
          );
        }

        // ✅ optimistic patch local des groupes
        setState(() {
          for (final line in selectedLines) {
            final gi = _findGroupIndexForLine(line);
            if (gi != null) {
              final g = Map<String, dynamic>.from(_groups[gi]);
              final oldS = (line['status'] ?? '').toString();
              final newS = newStatus;
              final qty = (line['qty_status'] as int?) ?? 0;

              final oldKey = 'qty_$oldS';
              final newKey = 'qty_$newS';

              g[oldKey] = ((g[oldKey] as int? ?? 0) - qty).clamp(0, 1 << 31);
              g[newKey] = (g[newKey] as int? ?? 0) + qty;

              _groups[gi] = g;
            }
          }

          _groupMode = false;
          _selectedKeys.clear();
          _groupNewStatus = null;
          _groupCommentCtrl.clear();
        });

        _snack('Status updated on ${allIds.length} item(s).');
      } on PostgrestException catch (e) {
        _snack('Supabase error: ${e.message}');
      } catch (e) {
        _snack('Error: $e');
      } finally {
        if (mounted) setState(() => _applyingGroup = false);
      }
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
            if (showFinanceOverview)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FinanceOverview(
                  items: effectiveKpiItems,
                  currency: lines.isNotEmpty
                      ? (lines.first['currency']?.toString() ?? 'USD')
                      : 'USD',

                  // 👇 Mode Finalized + override investi (total sécurisé côté serveur)
                  finalizedMode: isFinalizedView,
                  overrideInvested:
                      isFinalizedView ? _finalizedInvestOverride : null,

                  // 👇 Libellés adaptés
                  titleInvested:
                      isFinalizedView ? 'Invested' : 'Invested (view)',
                  titleEstimated:
                      isFinalizedView ? 'Actual margin' : 'Potential revenue',
                  titleSold: 'Actual revenue',

                  // 👇 Sous-titres explicites
                  subtitleInvested: isFinalizedView
                      ? 'Σ costs (finalized)'
                      : 'Σ costs (unsold)',
                  subtitleEstimated: isFinalizedView
                      ? 'Actual revenue - Invested'
                      : 'Σ estimated_price (unsold)',
                  subtitleSold: isFinalizedView
                      ? 'Σ sale_price (finalized)'
                      : 'Σ sale_price (sold)',
                ),
              ),
            if (showFinanceOverview) const SizedBox(height: 12),
            StatusBreakdownPanel(
              expanded: _breakdownExpanded,
              onToggle: (v) => setState(() => _breakdownExpanded = v),
              groupRows:
                  _groups.map((r) => {...r, 'qty_collection': 0}).toList(),
              currentFilter: forceStatus ?? _statusFilter,
              onTapStatus: (s) {
                if (s == 'vault') return;

                if (forceStatus != null) {
                  if (s != forceStatus) {
                    setState(() => _statusFilter = s);
                    _tabCtrl?.index = 0;
                    _refresh();
                  }
                  return;
                }

                setState(() => _statusFilter = (_statusFilter == s ? null : s));
                _refresh();
              },
            ),
            const SizedBox(height: 12),
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

          // ======== Barre "Edit group" + panneau d'action ========
          if (!_loading && _groups.isNotEmpty && _perm.canEditItems)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // 👇 compteur de lignes remis ici
                      Text(
                        'Lines (${lines.length})',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      OutlinedButton.icon(
                        icon: Icon(
                          _groupMode ? Icons.group_off : Icons.group,
                        ),
                        label:
                            Text(_groupMode ? 'Exit group edit' : 'Edit group'),
                        onPressed: () {
                          setState(() {
                            _groupMode = !_groupMode;
                            if (!_groupMode) {
                              _selectedKeys.clear();
                              _groupNewStatus = null;
                              _groupCommentCtrl.clear();
                            }
                          });
                        },
                      ),
                      if (_groupMode)
                        Text(
                          '${_selectedKeys.length} selected',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      if (_groupMode && _selectedKeys.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              setState(() => _selectedKeys.clear()),
                          child: const Text('Clear selection'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _groupMode
                        ? Card(
                            key: const ValueKey('group-panel'),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 260,
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _groupNewStatus,
                                          items: allStatuses.map((s) {
                                            final c = statusColor(context, s);
                                            return DropdownMenuItem<String>(
                                              value: s,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                        horizontal: 6),
                                                decoration: BoxDecoration(
                                                  color: c.withOpacity(0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color:
                                                          c.withOpacity(0.7)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        color: c,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      s.toUpperCase(),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: c,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (v) => setState(
                                              () => _groupNewStatus = v),
                                          decoration: const InputDecoration(
                                            labelText: 'New status',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 360,
                                        child: TextField(
                                          controller: _groupCommentCtrl,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Status comment (optional)',
                                            hintText:
                                                'Reason, tracking, batch ref, etc.',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: (_groupNewStatus != null &&
                                                _selectedKeys.isNotEmpty &&
                                                !_applyingGroup)
                                            ? applyGroupStatusToSelection
                                            : null,
                                        icon: _applyingGroup
                                            ? const SizedBox(
                                                height: 16,
                                                width: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(Icons.done_all),
                                        label: Text(
                                            'Apply to ${_selectedKeys.length} line(s)'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Only the status is modified. A log entry is saved for all affected items.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ======== Tableau ========
          InventoryTableByStatus(
            lines: lines,
            onOpen: _openDetails,
            onEdit: _perm.canEditItems ? _openEdit : null,
            onDelete: _perm.canDeleteLines ? _deleteLine : null,
            showDelete: _perm.canDeleteLines,
            showUnitCosts: _perm.canSeeUnitCosts,
            showRevenue: _perm.canSeeRevenue,
            onInlineUpdate: _applyInlineUpdate, // 👈 important

            // ⭐️ Group-edit wiring
            groupMode: _groupMode && !isFinalizedView,
            selection: _selectedKeys,
            lineKey: _lineKey,
            onToggleSelect: (line, selected) {
              final k = _lineKey(line);
              setState(() {
                if (selected) {
                  _selectedKeys.add(k);
                } else {
                  _selectedKeys.remove(k);
                }
              });
            },
            onToggleSelectAll: (selectAll) {
              setState(() {
                if (selectAll) {
                  _selectedKeys.addAll(lines.map(_lineKey));
                } else {
                  _selectedKeys.clear();
                }
              });
            },
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // 👉 Version simple & robuste : utilise directement group_sig + status
  void _openDetails(Map<String, dynamic> line) async {
    final String orgId = widget.orgId;
    final String status = (line['status'] ?? '').toString();
    final String? groupSig = line['group_sig']?.toString();

    if (groupSig == null || groupSig.isEmpty) {
      _snack('Missing group signature for this line.');
      return;
    }

    final payload = {
      'org_id': orgId,
      ...line,
      'group_sig': groupSig,
    };

    // Optionnel : on essaie de choper un item d’ancrage pour cette ligne
    try {
      final anchor = await _sb
          .from('item')
          .select('id')
          .eq('org_id', orgId)
          .eq('group_sig', groupSig)
          .eq('status', status)
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();

      if (anchor != null && anchor['id'] != null) {
        payload['id'] = anchor['id'];
      }
    } catch (_) {
      // soft fail, on laisse GroupDetails se débrouiller avec group_sig
    }

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
      _snack("Unable to edit: missing data.");
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
            title: const Text('Delete this line?'),
            content: Text(
              'Product: $name\nStatus: $status\n\n'
              'This action will permanently delete all items and movements '
              'associated with THIS line (strictly) and only those.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<List<int>> _collectItemIdsForLine(Map<String, dynamic> line) async {
    final String? groupSig = line['group_sig']?.toString();
    final String status = (line['status'] ?? '').toString();

    // 1️⃣ Tentative "idéal": group_sig + status
    if (groupSig != null && groupSig.isNotEmpty && status.isNotEmpty) {
      final raw = await _sb
          .from('item')
          .select('id')
          .eq('org_id', widget.orgId)
          .eq('group_sig', groupSig)
          .eq('status', status)
          .order('id', ascending: true)
          .limit(20000);

      final ids = raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);

      if (ids.isNotEmpty) {
        // ✅ Cas normal: on a trouvé les items avec le group_sig courant
        return ids;
      }

      // ⚠️ Si on arrive ici : soit le group_sig a changé après l'update status,
      // soit la vue a recombiné les lignes. On va retomber sur le fallback
      // "legacy" plus large pour ne pas obliger à refresh la page.
    }

    // 2️⃣ Fallback : ancienne logique (sans dépendre de group_sig)
    dynamic norm(dynamic v) {
      if (v == null) return null;
      if (v is String && v.trim().isEmpty) return null;
      return v;
    }

    String? dateStr(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v.toIso8601String().split('T').first;
      if (v is String) return v;
      return v.toString();
    }

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
      var q = _sb.from('item').select('id').eq('org_id', widget.orgId);

      for (final k in keys) {
        if (!line.containsKey(k)) continue;
        var v = line[k];

        v = norm(v);
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

      // IMPORTANT : on utilise le statut "courant" de la ligne
      q = q.eq('status', status);

      final List<dynamic> raw =
          await q.order('id', ascending: true).limit(20000);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
    }

    var ids = await runQuery(primaryKeys);
    if (ids.isNotEmpty) return ids;

    const strongKeys = <String>{
      'product_id',
      'status',
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
        _snack('No items found for this line.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';
      await _sb
          .from('movement')
          .delete()
          .eq('org_id', widget.orgId)
          .filter('item_id', 'in', idsCsv);
      await _sb
          .from('item')
          .delete()
          .eq('org_id', widget.orgId)
          .filter('id', 'in', idsCsv);

      _snack('Line deleted (${ids.length} item(s) + movements).');
      _refresh();
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  // ====== LOG: inline == edit (old/new) ======
  Future<void> _logBatchEdit({
    required String orgId,
    required List<int> itemIds,
    required Map<String, Map<String, dynamic>> changes, // {field: {old,new}}
    String? reason,
  }) async {
    if (changes.isEmpty) return;
    try {
      await _sb.rpc('app_log_batch_edit', params: {
        'p_org_id': orgId,
        'p_item_ids': itemIds,
        'p_changes': changes,
        'p_reason': reason,
      });
    } catch (_) {
      // best-effort
    }
  }

  // 👇 helper: trouve l'index du groupe correspondant à la "ligne"
  int? _findGroupIndexForLine(Map<String, dynamic> line) {
    // 1️⃣ D’abord : on essaie de matcher par org_id + group_sig (clé logique du groupe)
    final String? lineGroupSig = line['group_sig']?.toString();
    if (lineGroupSig != null && lineGroupSig.isNotEmpty) {
      for (int i = 0; i < _groups.length; i++) {
        final g = _groups[i];
        final gSig = g['group_sig']?.toString() ?? '';
        final gOrg = g['org_id']?.toString() ?? '';
        if (gSig == lineGroupSig && gOrg == widget.orgId) {
          return i;
        }
      }
    }

    // 2️⃣ Fallback "ancienne logique" au cas où (par sécurité)
    bool same(dynamic a, dynamic b) => (a ?? '') == (b ?? '');
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (same(g['org_id'], widget.orgId) &&
          same(g['product_id'], line['product_id']) &&
          same(g['game_id'], line['game_id']) &&
          same(g['type'], line['type']) &&
          same(g['language'], line['language']) &&
          same(g['purchase_date'], line['purchase_date']) &&
          same(g['currency'], line['currency'])) {
        return i;
      }
    }
    return null;
  }

  // ====== Sauvegarde inline + patch local immédiat + log ======
  Future<void> _applyInlineUpdate(
    Map<String, dynamic> line,
    String field,
    dynamic newValue,
  ) async {
    // 1) parse côté client
    dynamic parsed;
    switch (field) {
      case 'status':
        parsed = (newValue ?? '').toString();
        if (parsed.isEmpty) return;
        break;
      case 'estimated_price':
      case 'sale_price':
      case 'unit_cost':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : num.tryParse(t);
        break;
      case 'channel_id':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : int.tryParse(t);
        break;
      case 'sale_date':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t; // YYYY-MM-DD
        break;
      default:
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t;
    }

    // OLD pour le log
    final oldValue =
        field == 'status' ? (line['status'] ?? '').toString() : line[field];

    // 2) écriture serveur
    try {
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('No items found for this line.');
        return;
      }
      final idsCsv = '(${ids.join(",")})';
      await _sb.from('item').update({field: parsed}).filter('id', 'in', idsCsv);

      // 2bis) LOG comme l’edit
      await _logBatchEdit(
        orgId: widget.orgId,
        itemIds: ids,
        changes: {
          field: {
            'old': oldValue,
            'new': parsed,
          }
        },
        reason: 'inline_edit',
      );

      // 3) ✅ optimistic update local
      setState(() {
        final oldStatus = (line['status'] ?? '').toString();
        final qty = (line['qty_status'] as int?) ?? 0;

        line[field] = parsed;

        final gi = _findGroupIndexForLine(line);
        if (gi != null) {
          final g = Map<String, dynamic>.from(_groups[gi]);

          if (field == 'status') {
            final newStatus = parsed.toString();
            final oldKey = 'qty_$oldStatus';
            final newKey = 'qty_$newStatus';

            final oldQty = (g[oldKey] as int? ?? 0);
            final newQty = (g[newKey] as int? ?? 0);

            g[oldKey] = (oldQty - qty).clamp(0, 1 << 31);
            g[newKey] = newQty + qty;

            line['status'] = newStatus;
          } else {
            g[field] = parsed;
          }

          _groups[gi] = g;
        }
      });
      _refreshSilent();

      _snack('Modified (${ids.length} item(s)).');
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tant que le rôle n'est pas chargé OU pas de TabController, on affiche un loader
    if (!_roleLoaded || _tabCtrl == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLoggedIn = _sb.auth.currentSession != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix'),
        // ⬇️  AJOUT
        actions: [
          IconTheme(
            data: const IconThemeData(opacity: 1.0),
            child: Row(children: [
              IconButton(
                tooltip: isLoggedIn ? 'Sign out' : 'Sign in',
                icon: Iconify(isLoggedIn ? Mdi.logout : Mdi.login,
                    color: const Color.fromARGB(255, 2, 35, 61)),
                onPressed: _onTapAuthButton,
              ),
              IconButton(
                tooltip: 'Change organization',
                icon: const Iconify(Mdi.switch_account,
                    color: Color.fromARGB(255, 2, 35, 61)),
                onPressed: () async {
                  await OrgPrefs.clear();
                  if (!mounted) return;
                  final picked = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                        builder: (_) => const OrganizationsPage()),
                  );
                  if (picked != null && mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => MainInventoryPage(orgId: picked)),
                    );
                  }
                },
              ),
            ]),
          ),
        ],

        bottom: TabBar(
          controller: _tabCtrl,
          tabs: _tabs(),
          labelColor: Theme.of(context).colorScheme.onPrimary,
          unselectedLabelColor:
              Theme.of(context).colorScheme.onPrimary.withOpacity(.75),
          indicatorColor: Theme.of(context).colorScheme.onPrimary,
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
        children: _tabViews(),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabCtrl!,
        builder: (context, _) {
          if (_tabCtrl!.index != 0 || !_perm.canCreateStock) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            backgroundColor: kAccentA,
            foregroundColor: Colors.white,
            onPressed: () async {
              final orgId = widget.orgId;
              if (orgId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No organization selected.')),
                );
                return;
              }

              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => NewStockPage(orgId: orgId)),
              );
              if (changed == true) _refresh();
            },
            icon: const Iconify(Mdi.plus, color: Colors.white),
            label: const Text('New stock'),
          );
        },
      ),
    );
  }
}
