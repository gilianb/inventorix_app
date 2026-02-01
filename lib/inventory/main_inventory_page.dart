// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ PDF export
import 'package:file_saver/file_saver.dart';
import 'package:printing/printing.dart';
import '../../inventory/utils/inventory_pdf_export.dart';

import '../../inventory/widgets/status_breakdown_panel.dart';
import '../../inventory/widgets/table_by_status.dart';
import '../../inventory/utils/status_utils.dart';
import '../edit/edit_page.dart';
import '../../inventory/widgets/finance_overview.dart';

// ✅ Grouped products view (C)
import '../../inventory/widgets/products_grouped_view.dart';

// ✅ FX constants (sale_price multi-devise -> USD)
import '../../inventory/utils/fx_to_usd.dart';

// ✅ UI-only “short main file”
import '../../inventory/models/inventory_view_mode.dart';
import '../../inventory/widgets/inventory_controls_card.dart';
import '../../inventory/widgets/inventory_list_meta_bar.dart';
import '../../inventory/widgets/inventory_group_edit_panel.dart';

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

// invoice
import 'package:inventorix_app/invoicing/ui/invoice_management_page.dart';

import 'widgets/search_and_filters.dart';

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
  String? _languageFilter; // filtre langue
  String _priceBand = 'any'; // 'any' | 'p1' | 'p2' | 'p3' | 'p4'

  bool _loading = true;
  bool _breakdownExpanded = false;
  String _typeFilter = 'single'; // 'single' | 'sealed'
  String? _statusFilter; // filtre de la liste

  /// Sur quelle date on base le filtre :
  /// 'purchase' (purchase_date) ou 'sale' (sale_date)
  String _dateBase = 'purchase';

  /// Période à appliquer : 'all' | 'month' (30j) | 'week' (7j)
  String _dateRange = 'all';

  TabController? _tabCtrl;

  // Données
  List<Map<String, dynamic>> _groups = const [];

  // Items servant aux KPI (passés à FinanceOverview)
  List<Map<String, dynamic>> _kpiItems = const [];

  // 🔐 Rôle courant & permissions
  OrgRole _role = OrgRole.viewer; // par défaut prudent
  bool _roleLoaded = false;
  RolePermissions get _perm => kRoleMatrix[_role]!;
  bool get _isOwner => _role == OrgRole.owner;

  // ✅ Total investi exact pour l’onglet Finalized (calculé côté serveur via RPC)
  num? _finalizedInvestOverride;

  // ======== Mode édition de groupe ========
  bool _groupMode = false;
  final Set<String> _selectedKeys = <String>{};
  String? _groupNewStatus;

  // ✅ NEW: group grading controls
  List<Map<String, dynamic>> _gradingServices = const [];
  int? _groupGradingServiceId; // null = ne pas modifier
  DateTime? _groupAtGraderDate; // appliqué quand newStatus == 'at_grader'

  final TextEditingController _groupCommentCtrl = TextEditingController();
  bool _applyingGroup = false;

  // ======== A + C (pagination + grouped view) ========
  static const int _kChunk = 50;
  InventoryListViewMode _viewMode = InventoryListViewMode.products;

  final Map<String, int> _visibleLineLimitByView = {};
  final Map<String, int> _visibleProductLimitByView = {};
  final Map<String, String?> _expandedProductKeyByView = {};

  final ScrollController _invScrollCtrl = ScrollController();
  final ScrollController _finalizedScrollCtrl = ScrollController();
  DateTime? _lastAutoLoadMoreAt;

  // ✅ PDF exporting state
  bool _exportingPdf = false;

  String _viewKey(String? forceStatus) => forceStatus ?? '__main__';

  void _ensureViewState(String? forceStatus) {
    final k = _viewKey(forceStatus);
    _visibleLineLimitByView.putIfAbsent(k, () => _kChunk);
    _visibleProductLimitByView.putIfAbsent(k, () => _kChunk);
    _expandedProductKeyByView.putIfAbsent(k, () => null);
  }

  void _resetViewState(String? forceStatus) {
    final k = _viewKey(forceStatus);
    _visibleLineLimitByView[k] = _kChunk;
    _visibleProductLimitByView[k] = _kChunk;
    _expandedProductKeyByView[k] = null;
  }

  void _handleScrollNearBottom(String? forceStatus) {
    final ctrl =
        (forceStatus == 'finalized') ? _finalizedScrollCtrl : _invScrollCtrl;

    if (!ctrl.hasClients) return;
    final pos = ctrl.position;
    if (!pos.hasContentDimensions) return;

    // Trigger when within 400px of bottom
    if (pos.pixels < pos.maxScrollExtent - 400) return;

    // Throttle (avoid spamming setState)
    final now = DateTime.now();
    final last = _lastAutoLoadMoreAt;
    if (last != null && now.difference(last).inMilliseconds < 350) return;
    _lastAutoLoadMoreAt = now;

    final k = _viewKey(forceStatus);
    setState(() {
      if (_viewMode == InventoryListViewMode.lines) {
        _visibleLineLimitByView[k] =
            (_visibleLineLimitByView[k] ?? _kChunk) + _kChunk;
      } else {
        _visibleProductLimitByView[k] =
            (_visibleProductLimitByView[k] ?? _kChunk) + _kChunk;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _invScrollCtrl.addListener(() => _handleScrollNearBottom(null));
    _finalizedScrollCtrl
        .addListener(() => _handleScrollNearBottom('finalized'));
    _init();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    _searchCtrl.dispose();
    _groupCommentCtrl.dispose();
    _invScrollCtrl.dispose();
    _finalizedScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadRole();
    _recreateTabController();
    await _refresh();
  }

  /// Liste des Tabs selon rôle
  List<Tab> _tabs() => <Tab>[
        const Tab(
          icon: Iconify(
            Mdi.package_variant,
            color: Color.fromARGB(255, 2, 35, 61),
          ),
          text: 'Inventaire',
        ),
        if (_isOwner)
          const Tab(
            icon: Iconify(
              Mdi.trending_up,
              color: Color.fromARGB(255, 2, 35, 61),
            ),
            text: 'Top Sold',
          ),
        if (_isOwner)
          const Tab(
            icon: Iconify(
              Mdi.safe,
              color: Color.fromARGB(255, 2, 35, 61),
            ),
            text: 'The Vault',
          ),
        const Tab(
          icon: Iconify(
            Mdi.check_circle,
            color: Color.fromARGB(255, 2, 35, 61),
          ),
          text: 'Finalized',
        ),
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
        if (_isOwner) vaultPage(orgId: widget.orgId),
        _buildInventoryBody(forceStatus: 'finalized'),
      ];

  /// (Re)crée le TabController de façon sûre
  void _recreateTabController() {
    final newLen = _tabs().length;
    final prevIndex = _tabCtrl?.index ?? 0;

    _tabCtrl?.dispose();
    _tabCtrl = TabController(
      length: newLen,
      vsync: this,
      initialIndex: prevIndex.clamp(0, newLen - 1),
    );

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
      } catch (_) {}

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

  Future<void> _loadGradingServices() async {
    try {
      final raw = await _sb
          .from('grading_service')
          .select(
              'id, code, label, expected_days, default_fee, sort_order, active')
          .eq('org_id', widget.orgId)
          .eq('active', true)
          .order('sort_order', ascending: true, nullsFirst: false)
          .order('label', ascending: true);

      final list = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _gradingServices = list;
        // Si l'id sélectionné n'existe plus -> reset
        if (_groupGradingServiceId != null &&
            !_gradingServices.any((s) => s['id'] == _groupGradingServiceId)) {
          _groupGradingServiceId = null;
        }
      });
    } catch (_) {
      // ignore
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

  DateTime? _dateRangeStart() {
    final now = DateTime.now();
    switch (_dateRange) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  Map<String, double?> _priceBounds() {
    double? minPrice;
    double? maxPrice;

    switch (_priceBand) {
      case 'p1':
        maxPrice = 50;
        break;
      case 'p2':
        minPrice = 50;
        maxPrice = 200;
        break;
      case 'p3':
        minPrice = 200;
        maxPrice = 1000;
        break;
      case 'p4':
        minPrice = 1000;
        break;
      case 'any':
      default:
        break;
    }

    return {'min': minPrice, 'max': maxPrice};
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    _resetViewState(null);
    _resetViewState('finalized');

    try {
      await _loadGradingServices();
      _groups = await _fetchGroupedFromView();
      _kpiItems = await _fetchItemsForKpis();
      _finalizedInvestOverride = await _fetchFinalizedInvestAggregate();
    } catch (e) {
      _snack('Loading error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSilent() async {
    try {
      await _loadGradingServices();
      final newGroups = await _fetchGroupedFromView();
      final newKpiItems = await _fetchItemsForKpis();
      final newFinalizedInvest = await _fetchFinalizedInvestAggregate();

      if (!mounted) return;
      setState(() {
        _groups = newGroups;
        _kpiItems = newKpiItems;
        _finalizedInvestOverride = newFinalizedInvest;
      });
    } catch (_) {}
  }

  Future<num> _fetchFinalizedInvestAggregate() async {
    try {
      final after = _dateRangeStart();
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
        'p_type': _typeFilter,
        'p_game_id': gameId,
        'p_date_from': dateFrom,
      });

      if (res == null) return 0;
      if (res is num) return res;
      return num.tryParse(res.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ✅ UPDATED: allow type override (for PDF export)
  Future<List<Map<String, dynamic>>> _fetchGroupedFromView(
      {String? typeOverride}) async {
    final type = typeOverride ?? _typeFilter;

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
      'sale_currency', // ✅ MULTI-DEVISE
      'tracking',
      'photo_url',
      'document_url',
      'estimated_price',
      'sum_estimated_price',
      'item_location',
      'channel_id',
      'payment_type',
      'buyer_infos',

      // ✅ NEW: grading service + dates (from view)
      'grading_service_id',
      'sent_to_grader_date',
      'at_grader_date',

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
      'group_sig',
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
        .eq('type', type)
        .eq('org_id', widget.orgId);

    final after = _dateRangeStart();
    late final String orderColumn;

    if (_dateBase == 'purchase') {
      if (after != null) {
        final afterStr = after.toIso8601String().split('T').first;
        query = query.gte('purchase_date', afterStr);
      }
      orderColumn = 'purchase_date';
    } else {
      query = query.not('sale_date', 'is', null);
      if (after != null) {
        final afterStr = after.toIso8601String().split('T').first;
        query = query.gte('sale_date', afterStr);
      }
      orderColumn = 'sale_date';
    }

    if ((_gameFilter ?? '').isNotEmpty) {
      final row = await _sb
          .from('games')
          .select('id,label')
          .eq('label', _gameFilter!)
          .maybeSingle();
      final gid = (row?['id'] as int?);
      if (gid != null) query = query.eq('game_id', gid);
    }

    if ((_languageFilter ?? '').isNotEmpty) {
      query = query.eq('language', _languageFilter as Object);
    }

    final bounds = _priceBounds();
    final minPrice = bounds['min'];
    final maxPrice = bounds['max'];
    if (minPrice != null) query = query.gte('estimated_price', minPrice);
    if (maxPrice != null) query = query.lte('estimated_price', maxPrice);

    final List<dynamic> raw =
        await query.order(orderColumn, ascending: false).limit(5000);

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
          (r['buyer_infos'] ?? '').toString(),
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
      statuses = (grouped ?? <String>[f]).where((s) => s != 'vault').toList();
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
      if (_perm.canSeeRevenue) 'sale_currency', // ✅ MULTI-DEVISE
      'game_id',
      'org_id',
      'type',
      'status',
      'purchase_date',
      'language',
      'sale_date',
    ].join(', ');

    var q = _sb
        .from('item_masked')
        .select(cols)
        .eq('org_id', widget.orgId)
        .eq('type', _typeFilter)
        .inFilter('status', statuses);

    final after = _dateRangeStart();
    if (_dateBase == 'purchase') {
      if (after != null) {
        final d = after.toIso8601String().split('T').first;
        q = q.gte('purchase_date', d);
      }
    } else {
      q = q.not('sale_date', 'is', null);
      if (after != null) {
        final d = after.toIso8601String().split('T').first;
        q = q.gte('sale_date', d);
      }
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

    if ((_languageFilter ?? '').isNotEmpty) {
      q = q.eq('language', _languageFilter as Object);
    }

    final bounds = _priceBounds();
    final minPrice = bounds['min'];
    final maxPrice = bounds['max'];
    if (minPrice != null) q = q.gte('estimated_price', minPrice);
    if (maxPrice != null) q = q.lte('estimated_price', maxPrice);

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
        if (q > 0) out.add({...r, 'status': s, 'qty_status': q});
      }
    }

    final effectiveFilter = (overrideFilter ?? _statusFilter)?.toString() ?? '';
    if (effectiveFilter.isNotEmpty) {
      final grouped = kGroupToStatuses[effectiveFilter];
      if (grouped != null) {
        return out
            .where((e) => grouped.contains(e['status'] as String))
            .toList();
      }
      return out.where((e) => e['status'] == effectiveFilter).toList();
    }

    return out.where((e) => e['status'] != 'finalized').toList();
  }

  // ✅ explode lines from arbitrary groups (used for PDF export)
  List<Map<String, dynamic>> _explodeLinesFromGroups(
    List<Map<String, dynamic>> groups, {
    String? overrideFilter,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final r in groups) {
      for (final s in kStatusOrder) {
        if (s == 'vault') continue;
        final q = (r['qty_$s'] as int?) ?? 0;
        if (q > 0) out.add({...r, 'status': s, 'qty_status': q});
      }
    }

    final effectiveFilter = (overrideFilter ?? _statusFilter)?.toString() ?? '';
    if (effectiveFilter.isNotEmpty) {
      final grouped = kGroupToStatuses[effectiveFilter];
      if (grouped != null) {
        return out
            .where((e) => grouped.contains(e['status'] as String))
            .toList();
      }
      return out.where((e) => e['status'] == effectiveFilter).toList();
    }

    // same default as UI: exclude finalized by default
    return out.where((e) => e['status'] != 'finalized').toList();
  }

  String _lineKey(Map<String, dynamic> r) {
    String pick(String k) =>
        (r[k] == null || (r[k] is String && r[k].toString().trim().isEmpty))
            ? '_'
            : r[k].toString();
    final parts = <String>[
      pick('org_id'),
      pick('group_sig'),
      pick('product_id'),
      pick('game_id'),
      pick('type'),
      pick('language'),
      pick('channel_id'),
      pick('purchase_date'),
      pick('supplier_name'),
      pick('buyer_company'),
      pick('item_location'),
      pick('buyer_infos'),
      pick('currency'),
      pick('status'),

      // ✅ NEW: make lines distinct by grading service (important for group edit)
      pick('grading_service_id'),
    ];
    return parts.join('|');
  }

  // ✅ PDF filename stamp
  String _pdfStamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}${two(dt.minute)}';
  }

  Future<void> _savePdfDirectly({
    required Uint8List bytes,
    required String baseName, // without ".pdf"
  }) async {
    // Objectif:
    // - Web: download direct
    // - Mobile/Desktop: save file (ou save-as si nécessaire), sans écran d'impression
    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
        return;
      }

      // Sur mobile/desktop: essaye d'abord "Save As" (choix du dossier, plus “download-like”)
      try {
        await FileSaver.instance.saveAs(
          name: baseName,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
        return;
      } catch (_) {
        // fallback: saveFile
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
        return;
      }
    } catch (_) {
      // Dernier recours: share (permet "Enregistrer dans Fichiers" / "Save to Files")
      await Printing.sharePdf(bytes: bytes, filename: '$baseName.pdf');
    }
  }

  // ✅ Export PDF: Singles + Sealed (name + qty)
  Future<void> _exportInventoryPdf() async {
    if (_exportingPdf) return;

    setState(() => _exportingPdf = true);

    try {
      final now = DateTime.now();

      // 1) Fetch both types using current filters (game/lang/date/price/search)
      final singleGroups = await _fetchGroupedFromView(typeOverride: 'single');
      final sealedGroups = await _fetchGroupedFromView(typeOverride: 'sealed');

      // 2) Explode all statuses (ignore statusFilter => export everything)
      final singleLines =
          _explodeLinesFromGroups(singleGroups, overrideFilter: '');
      final sealedLines =
          _explodeLinesFromGroups(sealedGroups, overrideFilter: '');

      // 3) Same grouping as product grouped view
      final singleProducts = buildProductSummaries(
        lines: singleLines,
        canSeeUnitCosts: false,
        showEstimated: false,
      );
      final sealedProducts = buildProductSummaries(
        lines: sealedLines,
        canSeeUnitCosts: false,
        showEstimated: false,
      );

      // 4) Build PDF bytes
      final bytes = await buildInventoryExportPdfBytes(
        orgId: widget.orgId,
        generatedAt: now,
        singles: singleProducts,
        sealed: sealedProducts,
      );

      final baseName = 'inventorix_inventory_${_pdfStamp(now)}';

      // 5) Save/Download directly (no print dialog)
      await _savePdfDirectly(bytes: bytes, baseName: baseName);

      _snack('PDF exported: $baseName.pdf');
    } catch (e) {
      _snack('PDF export error: $e');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Widget _buildInventoryBody({String? forceStatus}) {
    final effectiveKpiItems = (forceStatus == null)
        ? _kpiItems
        : _kpiItems
            .where((e) => (e['status']?.toString() ?? '') == forceStatus)
            .toList();

    if (_loading) return const Center(child: CircularProgressIndicator());

    _ensureViewState(forceStatus);

    final bool isFinalizedView = (forceStatus == 'finalized');
    final bool showFinanceOverview =
        isFinalizedView || _perm.canSeeFinanceOverview;

    final allLines = _explodeLines(overrideFilter: forceStatus);

    final k = _viewKey(forceStatus);
    final visibleLineLimit = _visibleLineLimitByView[k] ?? _kChunk;
    final visibleProductLimit = _visibleProductLimitByView[k] ?? _kChunk;

    final visibleLines =
        allLines.take(visibleLineLimit).toList(growable: false);

    final allProducts = buildProductSummaries(
      lines: allLines,
      canSeeUnitCosts: _perm.canSeeUnitCosts,
      showEstimated: showFinanceOverview,
    );
    final visibleProducts =
        allProducts.take(visibleProductLimit).toList(growable: false);

    final List<String> allStatuses =
        kStatusOrder.where((s) => s != 'vault').toList();

    String? dateToStr(DateTime? d) => d?.toIso8601String().split('T').first;

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
        final selectedLines = allLines
            .where((r) => _selectedKeys.contains(_lineKey(r)))
            .toList(growable: false);

        final List<int> allIds = [];
        final List<_LogEntry> logEntries = [];

        for (final line in selectedLines) {
          final oldStatus = (line['status'] ?? '').toString();
          if (oldStatus.isEmpty) continue;

          final ids = await _collectItemIdsForLine(line);
          if (ids.isEmpty) continue;

          allIds.addAll(ids);

          final changes = <String, Map<String, dynamic>>{
            'status': {'old': oldStatus, 'new': newStatus},
          };

          // ✅ log grading changes if applicable
          if ((newStatus == 'sent_to_grader' || newStatus == 'at_grader') &&
              _groupGradingServiceId != null) {
            changes['grading_service_id'] = {
              'old': line['grading_service_id'],
              'new': _groupGradingServiceId,
            };
          }
          if (newStatus == 'at_grader' && _groupAtGraderDate != null) {
            changes['at_grader_date'] = {
              'old': line['at_grader_date'],
              'new': dateToStr(_groupAtGraderDate),
            };
          }

          logEntries.add(_LogEntry(
            itemIds: ids,
            changes: changes,
          ));
        }

        if (allIds.isEmpty) {
          _snack('No items found for selected lines.');
          return;
        }

        final idsCsv = '(${allIds.join(",")})';

        // ✅ Build bulk update
        final updates = <String, dynamic>{
          'status': newStatus,
        };

        // Apply grading service + date only when relevant
        if (newStatus == 'sent_to_grader' || newStatus == 'at_grader') {
          if (_groupGradingServiceId != null) {
            updates['grading_service_id'] = _groupGradingServiceId;
          }
        }
        if (newStatus == 'at_grader' && _groupAtGraderDate != null) {
          updates['at_grader_date'] = dateToStr(_groupAtGraderDate);
        }

        await _sb.from('item').update(updates).filter('id', 'in', idsCsv);

        final comment = _groupCommentCtrl.text.trim();
        final String reason =
            comment.isEmpty ? 'group_status' : 'group_status: $comment';

        for (final e in logEntries) {
          await _logBatchEdit(
            orgId: widget.orgId,
            itemIds: e.itemIds,
            changes: e.changes,
            reason: reason,
          );
        }

        setState(() {
          for (final line in selectedLines) {
            final gi = _findGroupIndexForLine(line);
            if (gi != null) {
              final g = Map<String, dynamic>.from(_groups[gi]);
              final oldS = (line['status'] ?? '').toString();
              final qty = (line['qty_status'] as int?) ?? 0;

              final oldKey = 'qty_$oldS';
              final newKey = 'qty_$newStatus';

              g[oldKey] = ((g[oldKey] as int? ?? 0) - qty).clamp(0, 1 << 31);
              g[newKey] = (g[newKey] as int? ?? 0) + qty;

              // Keep group-level display fields in sync (best-effort)
              if (updates.containsKey('grading_service_id')) {
                g['grading_service_id'] = updates['grading_service_id'];
              }
              if (updates.containsKey('at_grader_date')) {
                g['at_grader_date'] = updates['at_grader_date'];
              }

              _groups[gi] = g;
            }
          }

          _groupMode = false;
          _selectedKeys.clear();
          _groupNewStatus = null;
          _groupCommentCtrl.clear();

          // ✅ reset grading controls after apply (optional but clean UX)
          _groupGradingServiceId = null;
          _groupAtGraderDate = null;
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
        controller: isFinalizedView ? _finalizedScrollCtrl : _invScrollCtrl,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: InventoryControlsCard(
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
              languages: _groups
                  .map((r) => (r['language'] ?? '') as String)
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort(),
              selectedLanguage: _languageFilter,
              onLanguageChanged: (v) {
                setState(() => _languageFilter = v);
                _refresh();
              },
              priceBand: _priceBand,
              onPriceBandChanged: (band) {
                setState(() => _priceBand = band);
                _refresh();
              },
              typeFilter: _typeFilter,
              onTypeChanged: (t) {
                setState(() => _typeFilter = t);
                _refresh();
              },
              dateBase: _dateBase,
              onDateBaseChanged: (v) {
                setState(() => _dateBase = v);
                _refresh();
              },
              dateRange: _dateRange,
              onDateRangeChanged: (v) {
                setState(() => _dateRange = v);
                _refresh();
              },
              viewMode: _viewMode,
              onViewModeChanged: (newMode) {
                setState(() {
                  _viewMode = newMode;

                  _resetViewState(forceStatus);

                  if (_viewMode != InventoryListViewMode.lines) {
                    _groupMode = false;
                    _selectedKeys.clear();
                    _groupNewStatus = null;
                    _groupCommentCtrl.clear();

                    _groupGradingServiceId = null;
                    _groupAtGraderDate = null;
                  }
                });
              },
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
                  currency: allLines.isNotEmpty
                      ? (allLines.first['currency']?.toString() ?? 'USD')
                      : 'USD',
                  baseCurrency: 'USD',
                  fxToUsd: kFxToUsd,
                  finalizedMode: isFinalizedView,
                  overrideInvested:
                      isFinalizedView ? _finalizedInvestOverride : null,
                  titleInvested:
                      isFinalizedView ? 'Invested' : 'Invested (view)',
                  titleEstimated:
                      isFinalizedView ? 'Actual margin' : 'Potential revenue',
                  titleSold: 'Actual revenue',
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
                linesCount: allLines.length,
                onClear: () {
                  setState(() => _statusFilter = null);
                  _refresh();
                },
              ),
            if (forceStatus == null) const SizedBox(height: 12),
          ],
          InventoryListMetaBar(
            viewMode: _viewMode,
            visibleLines: visibleLines.length,
            totalLines: allLines.length,
            visibleProducts: visibleProducts.length,
            totalProducts: allProducts.length,
          ),
          const SizedBox(height: 8),
          InventoryGroupEditPanel(
            enabled: !isFinalizedView &&
                _viewMode == InventoryListViewMode.lines &&
                !_loading &&
                _groups.isNotEmpty &&
                _perm.canEditItems,
            totalLines: allLines.length,
            groupMode: _groupMode && !isFinalizedView,
            selectedCount: _selectedKeys.length,
            onToggleGroupMode: () {
              setState(() {
                _groupMode = !_groupMode;
                if (!_groupMode) {
                  _selectedKeys.clear();
                  _groupNewStatus = null;
                  _groupCommentCtrl.clear();

                  _groupGradingServiceId = null;
                  _groupAtGraderDate = null;
                }
              });
            },
            onClearSelection: () => setState(() => _selectedKeys.clear()),
            statuses: allStatuses,
            newStatus: _groupNewStatus,
            onNewStatusChanged: (v) => setState(() => _groupNewStatus = v),
            gradingServices: _gradingServices,
            selectedGradingServiceId: _groupGradingServiceId,
            onGradingServiceChanged: (id) =>
                setState(() => _groupGradingServiceId = id),
            atGraderDate: _groupAtGraderDate,
            onPickAtGraderDate: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _groupAtGraderDate ?? now,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              if (!mounted) return;
              setState(() => _groupAtGraderDate = picked);
            },
            onClearAtGraderDate: () =>
                setState(() => _groupAtGraderDate = null),
            commentCtrl: _groupCommentCtrl,
            applying: _applyingGroup,
            onApply: applyGroupStatusToSelection,
          ),
          const SizedBox(height: 8),
          if (_viewMode == InventoryListViewMode.lines)
            InventoryTableByStatus(
              lines: visibleLines,
              onOpen: _openDetails,
              onEdit: _perm.canEditItems ? _openEdit : null,
              onDelete: _perm.canDeleteLines ? _deleteLine : null,
              showDelete: _perm.canDeleteLines,
              showUnitCosts: _perm.canSeeUnitCosts,
              showRevenue: _perm.canSeeRevenue,
              showEstimated: showFinanceOverview,
              onInlineUpdate: _applyInlineUpdate,
              groupMode: _groupMode && !isFinalizedView,
              selection: _selectedKeys,
              lineKey: _lineKey,
              onToggleSelect: (line, selected) {
                final kk = _lineKey(line);
                setState(() {
                  if (selected) {
                    _selectedKeys.add(kk);
                  } else {
                    _selectedKeys.remove(kk);
                  }
                });
              },
              onToggleSelectAll: (selectAll) {
                setState(() {
                  if (selectAll) {
                    _selectedKeys.addAll(visibleLines.map(_lineKey));
                  } else {
                    _selectedKeys.clear();
                  }
                });
              },
            )
          else
            InventoryProductsGroupedList(
              summaries: visibleProducts,
              allLines: allLines,
              expandedKey: _expandedProductKeyByView[_viewKey(forceStatus)],
              onExpandedChanged: (newKey) {
                setState(() {
                  _expandedProductKeyByView[_viewKey(forceStatus)] = newKey;
                });
              },
              lineKey: _lineKey,
              onOpen: _openDetails,
              onEdit: _perm.canEditItems ? _openEdit : null,
              onDelete: _perm.canDeleteLines ? _deleteLine : null,
              showDelete: _perm.canDeleteLines,
              showUnitCosts: _perm.canSeeUnitCosts,
              showRevenue: _perm.canSeeRevenue,
              showEstimated: showFinanceOverview,
              onInlineUpdate: _applyInlineUpdate,
            ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  void _openDetails(Map<String, dynamic> line) async {
    final String orgId = widget.orgId;
    final String status = (line['status'] ?? '').toString();
    final String? groupSig = line['group_sig']?.toString();
    final int? gradingServiceId = line['grading_service_id'] as int?;

    if (groupSig == null || groupSig.isEmpty) {
      _snack('Missing group signature for this line.');
      return;
    }

    final payload = {
      'org_id': orgId,
      ...line,
      'group_sig': groupSig,
    };

    try {
      var q = _sb
          .from('item')
          .select('id')
          .eq('org_id', orgId)
          .eq('group_sig', groupSig)
          .eq('status', status);

      if (gradingServiceId != null) {
        q = q.eq('grading_service_id', gradingServiceId);
      }

      final anchor =
          await q.order('id', ascending: true).limit(1).maybeSingle();

      if (anchor != null && anchor['id'] != null) payload['id'] = anchor['id'];
    } catch (_) {}

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            GroupDetailsPage(group: Map<String, dynamic>.from(payload)),
      ),
    );
    if (changed == true) _refresh();
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
    if (changed == true) _refresh();
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
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
    final int? gradingServiceId = line['grading_service_id'] as int?;

    if (groupSig != null && groupSig.isNotEmpty && status.isNotEmpty) {
      var q = _sb
          .from('item')
          .select('id')
          .eq('org_id', widget.orgId)
          .eq('group_sig', groupSig)
          .eq('status', status);

      // ✅ NEW: keep line specificity if UI splits by grading service
      if (gradingServiceId != null) {
        q = q.eq('grading_service_id', gradingServiceId);
      }

      final raw = await q.order('id', ascending: true).limit(20000);

      final ids = raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);

      if (ids.isNotEmpty) return ids;
    }

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
      'sale_currency', // ✅ MULTI-DEVISE
      'tracking',
      'estimated_price',
      'item_location',
      'unit_cost',
      'unit_fees',
      'shipping_fees',
      'commission_fees',
      'payment_type',
      'buyer_infos',

      // ✅ NEW: keep specificity if line is split by service
      'grading_service_id',
    };

    Future<List<int>> runQuery(Set<String> keys) async {
      var q = _sb.from('item').select('id').eq('org_id', widget.orgId);

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
      'buyer_infos',
      'grading_service_id',
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

  Future<void> _logBatchEdit({
    required String orgId,
    required List<int> itemIds,
    required Map<String, Map<String, dynamic>> changes,
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
    } catch (_) {}
  }

  int? _findGroupIndexForLine(Map<String, dynamic> line) {
    final String? lineGroupSig = line['group_sig']?.toString();
    final int? lineGsId = line['grading_service_id'] as int?;

    if (lineGroupSig != null && lineGroupSig.isNotEmpty) {
      for (int i = 0; i < _groups.length; i++) {
        final g = _groups[i];
        final gSig = g['group_sig']?.toString() ?? '';
        final gOrg = g['org_id']?.toString() ?? '';
        final gGsId = g['grading_service_id'] as int?;
        if (gSig == lineGroupSig &&
            gOrg == widget.orgId &&
            (gGsId == lineGsId)) {
          return i;
        }
      }
    }

    bool same(dynamic a, dynamic b) => (a ?? '') == (b ?? '');
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (same(g['org_id'], widget.orgId) &&
          same(g['product_id'], line['product_id']) &&
          same(g['game_id'], line['game_id']) &&
          same(g['type'], line['type']) &&
          same(g['language'], line['language']) &&
          same(g['purchase_date'], line['purchase_date']) &&
          same(g['currency'], line['currency']) &&
          same(g['grading_service_id'], line['grading_service_id'])) {
        return i;
      }
    }
    return null;
  }

  Future<void> _applyInlineUpdate(
    Map<String, dynamic> line,
    String field,
    dynamic newValue,
  ) async {
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

      case 'sale_currency': // ✅ MULTI-DEVISE
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t;
        break;

      case 'channel_id':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : int.tryParse(t);
        break;

      case 'sale_date':
      case 'sent_to_grader_date':
      case 'at_grader_date':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t; // YYYY-MM-DD
        break;

      case 'grading_service_id':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : int.tryParse(t);
        break;

      default:
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t;
    }

    final oldValue =
        field == 'status' ? (line['status'] ?? '').toString() : line[field];

    try {
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('No items found for this line.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';
      await _sb.from('item').update({field: parsed}).filter('id', 'in', idsCsv);

      await _logBatchEdit(
        orgId: widget.orgId,
        itemIds: ids,
        changes: {
          field: {'old': oldValue, 'new': parsed}
        },
        reason: 'inline_edit',
      );

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
    if (!_roleLoaded || _tabCtrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isLoggedIn = _sb.auth.currentSession != null;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventorix'),
          actions: [
            IconTheme(
              data: const IconThemeData(opacity: 1.0),
              child: Row(
                children: [
                  // ✅ Export PDF button (download/save directly)
                  IconButton(
                    tooltip: _exportingPdf ? 'Exporting PDF...' : 'Export PDF',
                    icon: _exportingPdf
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.picture_as_pdf_outlined,
                            color: Color.fromARGB(255, 2, 35, 61),
                          ),
                    onPressed: _exportingPdf ? null : _exportInventoryPdf,
                  ),
                  IconButton(
                    tooltip: 'Invoices',
                    icon: const Iconify(
                      Mdi.file_document_outline,
                      color: Color.fromARGB(255, 2, 35, 61),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              InvoiceManagementPage(orgId: widget.orgId),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: isLoggedIn ? 'Sign out' : 'Sign in',
                    icon: Iconify(
                      isLoggedIn ? Mdi.logout : Mdi.login,
                      color: const Color.fromARGB(255, 2, 35, 61),
                    ),
                    onPressed: _onTapAuthButton,
                  ),
                  IconButton(
                    tooltip: 'Change organization',
                    icon: const Iconify(
                      Mdi.switch_account,
                      color: Color.fromARGB(255, 2, 35, 61),
                    ),
                    onPressed: () async {
                      await OrgPrefs.clear();
                      if (!mounted) return;
                      final picked = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const OrganizationsPage(),
                        ),
                      );
                      if (picked != null && mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => MainInventoryPage(orgId: picked),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
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
      ),
    );
  }
}

class _LogEntry {
  const _LogEntry({required this.itemIds, required this.changes});
  final List<int> itemIds;
  final Map<String, Map<String, dynamic>> changes;
}
