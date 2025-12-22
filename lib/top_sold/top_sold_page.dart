// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../details/widgets/marge.dart'; // MarginChip
import '../inventory/main_inventory_page.dart'
    show kAccentA, kAccentB, kAccentC, kAccentG;
import 'package:inventorix_app/details/details_page.dart'
    hide kAccentA, kAccentC, kAccentB;

// 🔐 RBAC
import 'package:inventorix_app/org/roles.dart';

import 'models/top_sold_models.dart';
import 'widgets/top_sold_filters_bar.dart';
import 'widgets/top_sold_restock_banner.dart';
import 'widgets/top_sold_product_tile.dart';

class TopSoldPage extends StatefulWidget {
  const TopSoldPage({super.key, this.orgId, this.onOpenDetails});

  final String? orgId;
  final void Function(Map<String, dynamic> itemRow)? onOpenDetails;

  @override
  State<TopSoldPage> createState() => _TopSoldPageState();
}

class _TopSoldPageState extends State<TopSoldPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _roleLoaded = false;

  // RBAC
  OrgRole _role = OrgRole.viewer;
  RolePermissions get _perm => kRoleMatrix[_role]!;

  String _typeFilter = 'all'; // all|single|sealed
  String? _gameFilter; // games.label (nullable)
  String _dateFilter = 'all'; // all|month|week

  TopSoldSort _sort = TopSoldSort.marge;
  int _topN = 20;

  final _searchCtrl = TextEditingController();

  List<TopSoldProductVM> _products = [];
  List<TopSoldProductVM> _restockOOS = [];

  static const String _kDefaultAsset = 'assets/images/default_card.png';

  /// Statuts de vente (on garde large côté Dart, aucun risque si un status n'existe pas)
  static const Set<String> _soldLikeStatuses = {
    'sold',
    'awaiting_payment',
    'sold_awaiting_payment',
    'shipped',
    'finalized',
  };

  /// Exclusion “stock”: si un item est dans ces statuts, il ne compte pas comme copie en stock
  static const List<String> _excludeFromStockCandidates = [
    'sold',
    'awaiting_payment',
    'sold_awaiting_payment',
    'shipped',
    'finalized',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadRole();
    await _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------- RBAC ----------
  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      final orgId = widget.orgId;
      if ((orgId ?? '').isEmpty) {
        if (mounted) {
          setState(() {
            _role = OrgRole.owner;
            _roleLoaded = true;
          });
        }
        return;
      }

      Map<String, dynamic>? row;
      try {
        row = await _sb
            .from('organization_member')
            .select('role')
            .eq('org_id', orgId!)
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {}

      String? roleStr = (row?['role'] as String?);

      if (roleStr == null) {
        try {
          final org = await _sb
              .from('organization')
              .select('created_by')
              .eq('id', orgId as Object)
              .maybeSingle();
          final createdBy = org?['created_by'] as String?;
          if (createdBy != null && createdBy == uid) roleStr = 'owner';
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

  // --------- Helpers ----------
  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _safeStr(dynamic v) => (v == null) ? '' : v.toString();

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  DateTime? _saleDateStart() {
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

  String _money(num? n) => n == null ? '—' : n.toDouble().toStringAsFixed(2);

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // YYYY-MM-DD
    return DateTime.tryParse(s);
  }

  /// ✅ Multi-devise sale_price: devise de vente (fallback currency -> USD)
  String _saleCurrency(Map<String, dynamic> r) {
    final sc = (r['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc;
    final c = (r['currency'] ?? '').toString().trim();
    return c.isNotEmpty ? c : 'USD';
  }

  // ---------- Thumbnail ----------
  Widget _cardThumb(String photoUrl) {
    const double h = 100;
    const double w = 72;
    final hasNet = photoUrl.isNotEmpty;

    Widget img;
    if (hasNet) {
      img = Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Image.asset(_kDefaultAsset, fit: BoxFit.cover),
      );
    } else {
      img = Image.asset(_kDefaultAsset, fit: BoxFit.cover);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: w, height: h, child: img),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sold':
      case 'awaiting_payment':
      case 'sold_awaiting_payment':
      case 'shipped':
      case 'finalized':
        return kAccentG;
      default:
        return kAccentA;
    }
  }

  // --------- Ouverture Détails ----------
  Future<void> _openDetails(Map<String, dynamic> line) async {
    final String orgId = ((widget.orgId ?? '').isNotEmpty)
        ? widget.orgId!
        : (line['org_id']?.toString() ?? '');
    final String status = (line['status'] ?? '').toString();
    final String? groupSig = line['group_sig']?.toString();

    if (orgId.isEmpty || status.isEmpty) {
      _snack('Insufficient data to open details.');
      return;
    }

    // ✅ Mode robuste: group_sig + status
    if (groupSig != null && groupSig.isNotEmpty) {
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

        final payload = {
          'org_id': orgId,
          ...line,
          'group_sig': groupSig,
          if (anchor != null && anchor['id'] != null) 'id': anchor['id'],
        };

        if (widget.onOpenDetails != null) {
          widget.onOpenDetails!(payload);
        } else {
          // ignore: use_build_context_synchronously
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  GroupDetailsPage(group: Map<String, dynamic>.from(payload)),
            ),
          );
        }
        return;
      } catch (_) {
        // soft fail -> fallback plus bas
      }
    }

    _snack("Unable to open details (missing group_sig).");
  }

  // --------- Stock check (Top N) ----------
  String? _extractInvalidEnumValue(String msg) {
    // exemple: invalid input value for enum item_status: "awaiting_payment"
    final re = RegExp(r'enum\s+\w+:\s+"([^"]+)"');
    final m = re.firstMatch(msg);
    return m?.group(1);
  }

  Future<bool> _hasAnyInStock({
    required String orgId,
    required int productId,
  }) async {
    // On tente avec une liste large (incluant awaiting_payment etc),
    // et si Postgres se plaint d’une valeur enum invalide, on la retire et on retry.
    final exclude = List<String>.from(_excludeFromStockCandidates);

    Future<bool> runWith(List<String> ex) async {
      final notIn = '(${ex.join(",")})';
      PostgrestTransformBuilder<PostgrestList> q = _sb
          .from('item_masked')
          .select('id')
          .eq('org_id', orgId)
          .eq('product_id', productId)
          .not('status', 'in', notIn)
          .limit(1);

      final List<dynamic> raw = await q;
      return raw.isNotEmpty;
    }

    for (var i = 0; i < exclude.length + 2; i++) {
      try {
        return await runWith(exclude);
      } on PostgrestException catch (e) {
        final msg = e.message;
        if (!msg.toLowerCase().contains('invalid input value for enum')) {
          rethrow;
        }
        final bad = _extractInvalidEnumValue(msg);
        if (bad == null) rethrow;
        exclude.remove(bad);
        if (exclude.isEmpty) {
          // plus rien à exclure => tout compte comme stock
          return true;
        }
      }
    }
    return await runWith(exclude);
  }

  // --------- Fetch principal ----------
  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final canSeeCosts = _perm.canSeeUnitCosts;
      final canSeeRevenue = _perm.canSeeRevenue;

      String buildCols({required bool includeSaleCurrency}) {
        return <String>[
          'id',
          'org_id',
          'group_sig',
          'product_id',
          'type',
          'language',
          'game_id',
          'status',
          'sale_date',
          if (canSeeRevenue) 'sale_price',
          if (canSeeRevenue && includeSaleCurrency) 'sale_currency',
          'currency',
          'marge',
          if (canSeeCosts) 'unit_cost',
          if (canSeeCosts) 'unit_fees',
          if (canSeeCosts) 'shipping_fees',
          if (canSeeCosts) 'commission_fees',
          if (canSeeCosts) 'grading_fees',
          'photo_url',
        ].join(', ');
      }

      Future<List<Map<String, dynamic>>> runQuery(
          {required bool includeSaleCurrency}) async {
        PostgrestFilterBuilder q = _sb
            .from('item_masked')
            .select(buildCols(includeSaleCurrency: includeSaleCurrency));

        if (_typeFilter != 'all') {
          q = q.eq('type', _typeFilter);
        }

        if ((widget.orgId ?? '').isNotEmpty) {
          q = q.eq('org_id', widget.orgId as Object);
        }

        final after = _saleDateStart();
        if (after != null) {
          final afterStr = after.toIso8601String().split('T').first;
          q = q.gte('sale_date', afterStr);
        }

        // tri sur sale_date, mais on prend large et on filtre les status côté Dart
        final List<dynamic> raw =
            await q.order('sale_date', ascending: false).limit(5000);

        return raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      // Query (robuste si sale_currency manque)
      List<Map<String, dynamic>> items;
      try {
        items = await runQuery(includeSaleCurrency: canSeeRevenue);
      } on PostgrestException catch (e) {
        final msg = e.message.toLowerCase();
        final looksLikeMissingSaleCurrency =
            msg.contains('sale_currency') && msg.contains('column');
        if (!looksLikeMissingSaleCurrency) rethrow;
        items = await runQuery(includeSaleCurrency: false);
      }

      // Filtre: uniquement items vendus-like + contraintes revenue si besoin
      items = items.where((r) {
        final s = (r['status'] ?? '').toString();
        final soldLike = _soldLikeStatuses.contains(s);
        final okRevenue = canSeeRevenue ? (r['sale_price'] != null) : true;
        return soldLike && okRevenue;
      }).toList();

      if (items.isEmpty) {
        setState(() {
          _products = [];
          _restockOOS = [];
        });
        return;
      }

      // Lookups product & games (nom/sku/jeu)
      final productIds =
          items.map((r) => r['product_id']).whereType<int>().toSet().toList();
      final gameIds =
          items.map((r) => r['game_id']).whereType<int>().toSet().toList();

      Map<int, Map<String, dynamic>> productById = {};
      Map<int, Map<String, dynamic>> gameById = {};

      if (productIds.isNotEmpty) {
        final List<dynamic> prods = await _sb
            .from('product')
            .select('id, name, sku, language, org_id')
            .filter('id', 'in', '(${productIds.join(",")})');
        productById = {
          for (final p in prods.map((e) => Map<String, dynamic>.from(e as Map)))
            (p['id'] as int): p
        };
      }

      if (gameIds.isNotEmpty) {
        final List<dynamic> games = await _sb
            .from('games')
            .select('id, label, code')
            .filter('id', 'in', '(${gameIds.join(",")})');
        gameById = {
          for (final g in games.map((e) => Map<String, dynamic>.from(e as Map)))
            (g['id'] as int): g
        };
      }

      // Fallback: infos depuis v_items_by_status_masked
      Map<int, Map<String, dynamic>> vInfoByProductId = {};
      if (productIds.isNotEmpty) {
        final String idsCsv = '(${productIds.join(",")})';
        try {
          final List<dynamic> vrows = await _sb
              .from('v_items_by_status_masked')
              .select(
                  'product_id, game_id, product_name, game_label, game_code, language')
              .filter('product_id', 'in', idsCsv)
              .limit(5000);
          for (final e in vrows) {
            final m = Map<String, dynamic>.from(e as Map);
            final pid = (m['product_id'] as num?)?.toInt();
            if (pid != null && !vInfoByProductId.containsKey(pid)) {
              vInfoByProductId[pid] = {
                'product_name': (m['product_name'] ?? '').toString(),
                'language': (m['language'] ?? '').toString(),
                'game_label': (m['game_label'] ?? '').toString(),
                'game_code': (m['game_code'] ?? '').toString(),
              };
            }
          }
        } catch (_) {
          // no-op (view/cols might differ)
        }
      }

      // Search + game filter (local)
      final rawQ = _searchCtrl.text.trim().toLowerCase();
      final tokens = rawQ.isEmpty
          ? const <String>[]
          : rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      bool matchesSearchForItem(Map<String, dynamic> r) {
        if (tokens.isEmpty) return true;
        final pid = r['product_id'] as int?;
        final gid = r['game_id'] as int?;
        final prod = pid != null ? (productById[pid] ?? const {}) : const {};
        final game = gid != null ? (gameById[gid] ?? const {}) : const {};
        final vinfo =
            pid != null ? (vInfoByProductId[pid] ?? const {}) : const {};

        final fields = <String>[
          (prod['name'] ?? vinfo['product_name'] ?? '').toString(),
          (prod['sku'] ?? '').toString(),
          (vinfo['language'] ?? r['language'] ?? '').toString(),
          (game['label'] ?? vinfo['game_label'] ?? '').toString(),
          (game['code'] ?? vinfo['game_code'] ?? '').toString(),
          (r['status'] ?? '').toString(),
        ].map((s) => s.toLowerCase()).toList();

        return tokens.every((t) => fields.any((f) => f.contains(t)));
      }

      bool matchesGameForItem(Map<String, dynamic> r) {
        if ((_gameFilter ?? '').isEmpty) return true;
        final pid = r['product_id'] as int?;
        final gid = r['game_id'] as int?;
        final game = gid != null ? (gameById[gid] ?? const {}) : const {};
        final vinfo =
            pid != null ? (vInfoByProductId[pid] ?? const {}) : const {};
        final label = (game['label'] ?? '').toString();
        final fall = (vinfo['game_label'] ?? '').toString();
        return label == _gameFilter || fall == _gameFilter;
      }

      items = items
          .where((r) => matchesGameForItem(r) && matchesSearchForItem(r))
          .toList();

      if (items.isEmpty) {
        setState(() {
          _products = [];
          _restockOOS = [];
        });
        return;
      }

      // ---------- Build group aggregates (for sheet + anchor) ----------
      final Map<String, _GroupAgg> groupAgg = {};

      for (final r in items) {
        final orgId = _safeStr(r['org_id']);
        final pid = r['product_id'] as int?;
        if (orgId.isEmpty || pid == null) continue;

        final status = _safeStr(r['status']);
        final groupSig = _safeStr(r['group_sig']);

        // group key: org + groupSig + status (si groupSig vide => fallback sur pid+status)
        final key = groupSig.isNotEmpty
            ? '$orgId|$groupSig|$status'
            : '$orgId|pid=$pid|$status';

        final g = groupAgg.putIfAbsent(
          key,
          () => _GroupAgg(
            orgId: orgId,
            productId: pid,
            gameId: r['game_id'] as int?,
            type: _safeStr(r['type']),
            language: _safeStr(r['language']),
            groupSig: groupSig,
            status: status,
            photoUrl: _safeStr(r['photo_url']),
          ),
        );

        g.qty += 1;
        g.margeSum += (_asNum(r['marge']) ?? 0).toDouble();

        final saleDate = _parseDate(r['sale_date']);
        if (saleDate != null) {
          g.lastSaleDate =
              (g.lastSaleDate == null || saleDate.isAfter(g.lastSaleDate!))
                  ? saleDate
                  : g.lastSaleDate;
        }

        if (g.photoUrl.isEmpty && _safeStr(r['photo_url']).isNotEmpty) {
          g.photoUrl = _safeStr(r['photo_url']);
        }

        if (canSeeRevenue) {
          final cur = _saleCurrency(r);
          g.revenueByCur[cur] = (g.revenueByCur[cur] ?? 0) +
              (_asNum(r['sale_price']) ?? 0).toDouble();
        }

        if (canSeeCosts) {
          final cur =
              _safeStr(r['currency']).isEmpty ? 'USD' : _safeStr(r['currency']);
          final cost = ((_asNum(r['unit_cost']) ?? 0) +
                  (_asNum(r['unit_fees']) ?? 0) +
                  (_asNum(r['shipping_fees']) ?? 0) +
                  (_asNum(r['commission_fees']) ?? 0) +
                  (_asNum(r['grading_fees']) ?? 0))
              .toDouble();
          g.costByCur[cur] = (g.costByCur[cur] ?? 0) + cost;
        }
      }

      // Groups per product
      final Map<String, List<TopSoldGroupVM>> groupsByProductKey = {};
      for (final g in groupAgg.values) {
        final avgMarge = g.qty == 0 ? 0 : (g.margeSum / g.qty);
        final vm = TopSoldGroupVM(
          orgId: g.orgId,
          productId: g.productId,
          gameId: g.gameId,
          type: g.type,
          language: g.language,
          groupSig: g.groupSig,
          status: g.status,
          qty: g.qty,
          avgMarge: avgMarge as double,
          revenueByCurrency: Map<String, double>.from(g.revenueByCur),
          costByCurrency: Map<String, double>.from(g.costByCur),
          photoUrl: g.photoUrl,
          lastSaleDate: g.lastSaleDate,
        );

        final pk = '${g.orgId}|${g.productId}';
        groupsByProductKey.putIfAbsent(pk, () => []).add(vm);
      }

      for (final list in groupsByProductKey.values) {
        list.sort((a, b) {
          final da = a.lastSaleDate;
          final db = b.lastSaleDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      }

      // ---------- Build product aggregates ----------
      final Map<String, _ProdAgg> prodAgg = {};

      for (final r in items) {
        final orgId = _safeStr(r['org_id']);
        final pid = r['product_id'] as int?;
        if (orgId.isEmpty || pid == null) continue;

        final key = '$orgId|$pid';
        final a = prodAgg.putIfAbsent(
          key,
          () => _ProdAgg(
            orgId: orgId,
            productId: pid,
            gameId: r['game_id'] as int?,
            type: _safeStr(r['type']),
            language: _safeStr(r['language']),
            photoUrl: _safeStr(r['photo_url']),
          ),
        );

        a.soldQty += 1;
        a.margeSum += (_asNum(r['marge']) ?? 0).toDouble();

        final saleDate = _parseDate(r['sale_date']);
        if (saleDate != null) {
          a.lastSaleDate =
              (a.lastSaleDate == null || saleDate.isAfter(a.lastSaleDate!))
                  ? saleDate
                  : a.lastSaleDate;
        }

        if (a.photoUrl.isEmpty && _safeStr(r['photo_url']).isNotEmpty) {
          a.photoUrl = _safeStr(r['photo_url']);
        }

        if (canSeeRevenue) {
          final cur = _saleCurrency(r);
          a.revenueByCur[cur] = (a.revenueByCur[cur] ?? 0) +
              (_asNum(r['sale_price']) ?? 0).toDouble();
        }

        if (canSeeCosts) {
          final cur =
              _safeStr(r['currency']).isEmpty ? 'USD' : _safeStr(r['currency']);
          final cost = ((_asNum(r['unit_cost']) ?? 0) +
                  (_asNum(r['unit_fees']) ?? 0) +
                  (_asNum(r['shipping_fees']) ?? 0) +
                  (_asNum(r['commission_fees']) ?? 0) +
                  (_asNum(r['grading_fees']) ?? 0))
              .toDouble();
          a.costByCur[cur] = (a.costByCur[cur] ?? 0) + cost;
        }
      }

      // ---------- Resolve names and build product VMs ----------
      final products = <TopSoldProductVM>[];

      for (final a in prodAgg.values) {
        final pid = a.productId;
        final gid = a.gameId;

        final prod = productById[pid] ?? const <String, dynamic>{};
        final game = (gid != null)
            ? (gameById[gid] ?? const <String, dynamic>{})
            : const <String, dynamic>{};
        final vinfo = vInfoByProductId[pid] ?? const <String, dynamic>{};

        final productName = _safeStr(prod['name']).isNotEmpty
            ? _safeStr(prod['name'])
            : _safeStr(vinfo['product_name']);

        final sku = _safeStr(prod['sku']);

        final gameLabel = _safeStr(game['label']).isNotEmpty
            ? _safeStr(game['label'])
            : _safeStr(vinfo['game_label']);

        final gameCode = _safeStr(game['code']).isNotEmpty
            ? _safeStr(game['code'])
            : _safeStr(vinfo['game_code']);

        final avgMarge = a.soldQty == 0 ? 0 : (a.margeSum / a.soldQty);

        final pk = '${a.orgId}|${a.productId}';
        final groups = (groupsByProductKey[pk] ?? const <TopSoldGroupVM>[]);
        final preview = groups.take(12).toList();
        final anchor = groups.isNotEmpty ? groups.first : null;

        products.add(
          TopSoldProductVM(
            orgId: a.orgId,
            productId: a.productId,
            gameId: a.gameId,
            type: a.type,
            language: a.language,
            productName: productName.isNotEmpty ? productName : 'Produit #$pid',
            sku: sku,
            gameLabel: gameLabel,
            gameCode: gameCode,
            photoUrl: a.photoUrl,
            soldQty: a.soldQty,
            avgMarge: avgMarge as double,
            revenueByCurrency: Map<String, double>.from(a.revenueByCur),
            costByCurrency: Map<String, double>.from(a.costByCur),
            lastSaleDate: a.lastSaleDate,
            groupsPreview: preview,
            anchorGroup: anchor,
            inStockTopN: null, // calculé après pour top N
          ),
        );
      }

      // ---------- Sort products ----------
      void sortProducts(List<TopSoldProductVM> list) {
        list.sort((a, b) {
          switch (_sort) {
            case TopSoldSort.marge:
              return (b.avgMarge).compareTo(a.avgMarge);
            case TopSoldSort.qty:
              return b.soldQty.compareTo(a.soldQty);
            case TopSoldSort.revenue:
              double sum(Map<String, double> m) =>
                  m.values.fold(0.0, (p, e) => p + e);
              return sum(b.revenueByCurrency)
                  .compareTo(sum(a.revenueByCurrency));
          }
        });
      }

      sortProducts(products);

      // ---------- Stock check only for Top N ----------
      final top = products.take(_topN).toList();
      final inStockByKey = <String, bool>{};

      // On lance en parallèle (Top N max 50 => ok)
      final futures = top.map((p) async {
        final ok = await _hasAnyInStock(orgId: p.orgId, productId: p.productId);
        inStockByKey['${p.orgId}|${p.productId}'] = ok;
      }).toList();

      await Future.wait(futures);

      final rebuilt = <TopSoldProductVM>[];
      for (final p in products) {
        final key = '${p.orgId}|${p.productId}';
        final bool? inStock =
            inStockByKey.containsKey(key) ? inStockByKey[key] : null;

        rebuilt.add(
          TopSoldProductVM(
            orgId: p.orgId,
            productId: p.productId,
            gameId: p.gameId,
            type: p.type,
            language: p.language,
            productName: p.productName,
            sku: p.sku,
            gameLabel: p.gameLabel,
            gameCode: p.gameCode,
            photoUrl: p.photoUrl,
            soldQty: p.soldQty,
            avgMarge: p.avgMarge,
            revenueByCurrency: p.revenueByCurrency,
            costByCurrency: p.costByCurrency,
            lastSaleDate: p.lastSaleDate,
            groupsPreview: p.groupsPreview,
            anchorGroup: p.anchorGroup,
            inStockTopN: inStock,
          ),
        );
      }

      final oos =
          rebuilt.take(_topN).where((p) => p.inStockTopN == false).toList();

      setState(() {
        _products = rebuilt;
        _restockOOS = oos;
      });
    } catch (e) {
      if (mounted) _snack('Erreur Top Sold : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------- Games ----------
  Future<List<String>> _availableGames() async {
    try {
      final List<dynamic> raw = await _sb
          .from('games')
          .select('label')
          .order('label', ascending: true);
      return raw
          .map((e) => (e as Map)['label'])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  // --------- UI ----------
  void _openProductSheet(TopSoldProductVM p) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.productName,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (p.gameLabel.isNotEmpty) p.gameLabel,
                    if (p.sku.isNotEmpty) p.sku,
                    'Sold: ${p.soldQty}',
                    if (p.isOutOfStockTopN) 'OUT OF STOCK',
                  ].join(' • '),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (p.groupsPreview.isEmpty)
                  const Text('Aucun groupe à afficher.')
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: p.groupsPreview.length,
                      itemBuilder: (c, i) {
                        final g = p.groupsPreview[i];
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                              '${g.status.toUpperCase()} • Qty: ${g.qty}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              g.groupSig.isNotEmpty
                                  ? 'group_sig: ${g.groupSig}'
                                  : '(group_sig vide)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _openDetails(g.toOpenDetailsPayload());
                            },
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      final anchor = p.anchorGroup;
                      if (anchor != null) {
                        _openDetails(anchor.toOpenDetailsPayload());
                      } else {
                        _snack('Aucun groupe anchor pour ouvrir Détails.');
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ouvrir Détails (anchor)'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _marginChip(num? marge) => MarginChip(marge: marge);

  @override
  Widget build(BuildContext context) {
    if (!_roleLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final canSeeRevenue = _perm.canSeeRevenue;
    final canSeeCosts = _perm.canSeeUnitCosts;

    return Column(
      children: [
        TopSoldFiltersBar(
          typeFilter: _typeFilter,
          dateFilter: _dateFilter,
          gameFilter: _gameFilter,
          sort: _sort,
          topN: _topN,
          searchCtrl: _searchCtrl,
          gamesFuture: _availableGames(),
          onTypeChanged: (v) {
            setState(() => _typeFilter = v);
            _fetch();
          },
          onDateChanged: (v) {
            setState(() => _dateFilter = v);
            _fetch();
          },
          onGameChanged: (v) {
            setState(() => _gameFilter = v);
            _fetch();
          },
          onSortChanged: (v) {
            setState(() => _sort = v);
            _fetch();
          },
          onTopNChanged: (v) {
            setState(() => _topN = v);
            _fetch();
          },
          onRefresh: _fetch,
          onSearchSubmitted: (_) => _fetch(),
          onClearSearch: () {
            _searchCtrl.clear();
            _fetch();
          },
          accentA: kAccentA,
          accentB: kAccentB,
        ),

        // ✅ Bandeau “À racheter”
        if (!_loading)
          TopSoldRestockBanner(
            topN: _topN,
            oosItems: _restockOOS,
            onTapItem: _openProductSheet,
            accentA: kAccentA,
            accentG: kAccentG,
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_products.isEmpty
                  ? const Center(child: Text('No sales found.'))
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: _products.length,
                        itemBuilder: (ctx, i) {
                          final p = _products[i];

                          return TopSoldProductTile(
                            p: p,
                            canSeeRevenue: canSeeRevenue,
                            canSeeCosts: canSeeCosts,
                            onTap: () => _openProductSheet(p),
                            cardThumb: _cardThumb,
                            money: _money,
                            statusChipColor: _statusColor,
                            marginChip: _marginChip,
                            accentA: kAccentA,
                            accentB: kAccentB,
                            accentC: kAccentC,
                          );
                        },
                      ),
                    )),
        ),
      ],
    );
  }
}

// ----------------- Internal aggs -----------------
class _GroupAgg {
  _GroupAgg({
    required this.orgId,
    required this.productId,
    required this.gameId,
    required this.type,
    required this.language,
    required this.groupSig,
    required this.status,
    required this.photoUrl,
  });

  final String orgId;
  final int productId;
  final int? gameId;
  final String type;
  final String language;

  final String groupSig;
  final String status;

  int qty = 0;
  double margeSum = 0.0;

  final Map<String, double> revenueByCur = {};
  final Map<String, double> costByCur = {};

  String photoUrl;
  DateTime? lastSaleDate;
}

class _ProdAgg {
  _ProdAgg({
    required this.orgId,
    required this.productId,
    required this.gameId,
    required this.type,
    required this.language,
    required this.photoUrl,
  });

  final String orgId;
  final int productId;
  final int? gameId;
  final String type;
  final String language;

  int soldQty = 0;
  double margeSum = 0.0;

  final Map<String, double> revenueByCur = {};
  final Map<String, double> costByCur = {};

  String photoUrl;
  DateTime? lastSaleDate;
}
