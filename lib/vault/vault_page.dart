// lib/vault/vault_page.dart
// ignore_for_file: deprecated_member_use

import 'dart:convert'; // ✅ FX JSON
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http; // ✅ FX HTTP

import 'package:inventorix_app/inventory/widgets/table_by_status.dart';
import 'package:inventorix_app/edit/edit_page.dart';
import 'package:inventorix_app/inventory/widgets/search_and_filters.dart';
import 'package:inventorix_app/inventory/widgets/finance_overview.dart';

import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/new_stock/new_stock_page.dart';

import 'package:inventorix_app/org/roles.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

// ignore: camel_case_types
class vaultPage extends StatefulWidget {
  const vaultPage({super.key, this.orgId}); // ← orgId optionnel
  final String? orgId;

  @override
  State<vaultPage> createState() => _vaultPageState();
}

// ignore: camel_case_types
class _vaultPageState extends State<vaultPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;

  // Filtres/UI (alignés avec la page principale)
  final _searchCtrl = TextEditingController();
  String? _gameFilter; // valeur = game_label
  String? _languageFilter; // filtre langue
  String _typeFilter = 'single'; // 'single' | 'sealed'
  String _priceBand = 'any'; // 'any' | 'p1' | 'p2' | 'p3' | 'p4'

  OrgRole _role = OrgRole.viewer; // mutable
  bool _roleLoaded = false; // on attend le chargement
  RolePermissions get _perm => kRoleMatrix[_role]!;

  // Données pour le tableau (groupes)
  List<Map<String, dynamic>> _groups = const [];

  // Données brutes items pour le KPI factorisé
  List<Map<String, dynamic>> _kpiItems = const [];

  // ✅ FX cache (base USD)
  static const Duration _fxTtl = Duration(hours: 12);
  Future<Map<String, double>>? _fxFuture;
  Map<String, double>? _fxRates;
  DateTime? _fxLoadedAt;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadRole();
    _ensureFxLoaded(force: true);
    await _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ====================== FX (USD) ======================

  bool _fxIsStale() {
    final t = _fxLoadedAt;
    if (t == null) return true;
    return DateTime.now().difference(t) > _fxTtl;
  }

  void _ensureFxLoaded({bool force = false}) {
    if (!_perm.canSeeFinanceOverview) return;

    if (force || _fxRates == null || _fxIsStale()) {
      _fxFuture = _loadFxRatesUsdBase().then((rates) {
        _fxRates = rates;
        _fxLoadedAt = DateTime.now();
        return rates;
      });
    }
  }

  /// Charge les taux FX en base USD.
  /// Format: rates["EUR"] = 0.92 => 1 USD = 0.92 EUR
  Future<Map<String, double>> _loadFxRatesUsdBase() async {
    try {
      final uri = Uri.parse('https://api.frankfurter.app/latest?from=USD');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const {'USD': 1.0};
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rates = (json['rates'] as Map<String, dynamic>?);

      final out = <String, double>{'USD': 1.0};
      if (rates != null) {
        for (final e in rates.entries) {
          final k = e.key.toUpperCase();
          final v = e.value;
          final d = (v is num) ? v.toDouble() : double.tryParse(v.toString());
          if (d != null && d > 0) out[k] = d;
        }
      }
      return out;
    } catch (_) {
      return const {'USD': 1.0};
    }
  }

  /// Convertit amount (dans ccy) -> USD, en utilisant un mapping "1 USD = rate[ccy] ccy"
  double _toUsd(num amount, String? ccy, Map<String, double> usdBaseRates) {
    final cur = (ccy ?? '').trim().toUpperCase();
    final a = amount.toDouble();

    if (cur.isEmpty || cur == 'USD') return a;

    final perUsd = usdBaseRates[cur];
    if (perUsd == null || perUsd == 0) return a;

    // cur -> USD
    return a / perUsd;
  }

  List<Map<String, dynamic>> _convertItemsToUsd(
    List<Map<String, dynamic>> items,
    Map<String, double> usdBaseRates,
  ) {
    double? conv(dynamic v, String? ccy) {
      if (v == null) return null;
      final n = (v is num) ? v : num.tryParse(v.toString());
      if (n == null) return null;
      return _toUsd(n, ccy, usdBaseRates);
    }

    return items.map((it) {
      final currency = (it['currency'] ?? '').toString().trim();
      final saleCurrency =
          (it['sale_currency'] ?? it['currency'] ?? '').toString().trim();

      return {
        ...it,
        'unit_cost': conv(it['unit_cost'], currency),
        'unit_fees': conv(it['unit_fees'], currency),
        'shipping_fees': conv(it['shipping_fees'], currency),
        'commission_fees': conv(it['commission_fees'], currency),
        'grading_fees': conv(it['grading_fees'], currency),
        'estimated_price': conv(it['estimated_price'], currency),
        'sale_price': conv(it['sale_price'], saleCurrency),
        'currency': 'USD',
        'sale_currency': 'USD',
      };
    }).toList(growable: false);
  }

  // ====================== Filters ======================

  /// Limites min/max pour la tranche de prix (estimated_price)
  /// 'any' | 'p1' | 'p2' | 'p3' | 'p4'
  Map<String, double?> _priceBounds() {
    double? minPrice;
    double? maxPrice;

    switch (_priceBand) {
      case 'p1': // < 50
        maxPrice = 50;
        break;
      case 'p2': // 50 - 200
        minPrice = 50;
        maxPrice = 200;
        break;
      case 'p3': // 200 - 1000
        minPrice = 200;
        maxPrice = 1000;
        break;
      case 'p4': // > 1000
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
    try {
      _groups = await _fetchGroupsFromView();
      _kpiItems = await _fetchvaultItemsForKpis();
      _ensureFxLoaded(); // ✅ refresh FX si stale
    } catch (e) {
      _snack('Error loading vault: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rafraîchit _groups et _kpiItems en arrière-plan (pas de gros loader global).
  Future<void> _refreshSilent() async {
    try {
      final newGroups = await _fetchGroupsFromView();
      final newKpiItems = await _fetchvaultItemsForKpis();

      if (!mounted) return;
      setState(() {
        _groups = newGroups;
        _kpiItems = newKpiItems;
      });
      _ensureFxLoaded();
    } catch (_) {
      // best effort
    }
  }

  // ====================== RBAC ======================

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      final oid = (widget.orgId ?? '').toString();
      if (oid.isEmpty) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      Map<String, dynamic>? row;
      try {
        row = await _sb
            .from('organization_member')
            .select('role')
            .eq('org_id', oid)
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {}

      String? roleStr = (row?['role'] as String?);

      if (roleStr == null) {
        try {
          final org = await _sb
              .from('organization')
              .select('created_by')
              .eq('id', oid)
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

  // ====================== DATA: Groups (table) ======================

  /// Lit la vue v_item_groups (1 ligne = 1 group_sig) en ne gardant que status='vault'
  /// + hydratation game_label/game_code depuis la table games
  /// + enrichissement "market" pour le mode Vault.
  Future<List<Map<String, dynamic>>> _fetchGroupsFromView() async {
    // NOTE: on inclut qty_status, etc. + group_sig.
    const cols = '''
      group_sig, org_id, type, status,
      product_id, product_name, game_id, language,
      purchase_date, currency,
      supplier_name, buyer_company, notes,
      grade_id, grading_note, sale_date, sale_price, sale_currency, tracking, photo_url, document_url,
      estimated_price, item_location, channel_id, payment_type, buyer_infos,
      unit_cost, unit_fees,
      qty_status, total_cost_with_fees,
      sum_shipping_fees, sum_commission_fees, sum_grading_fees
    ''';

    var q = _sb
        .from('v_item_groups')
        .select(cols)
        .eq('type', _typeFilter)
        .eq('status', 'vault');

    if ((widget.orgId ?? '').isNotEmpty) {
      q = q.eq('org_id', widget.orgId as Object);
    }

    // Filtre jeu (via game_id) si sélectionné
    if ((_gameFilter ?? '').isNotEmpty) {
      final gid = await _resolveGameIdByLabel(_gameFilter!);
      if (gid != null) {
        q = q.eq('game_id', gid);
      } else {
        return const [];
      }
    }

    // Filtre langue
    if ((_languageFilter ?? '').isNotEmpty) {
      q = q.eq('language', _languageFilter as Object);
    }

    // Filtre tranche de prix sur estimated_price
    final bounds = _priceBounds();
    final minPrice = bounds['min'];
    final maxPrice = bounds['max'];
    if (minPrice != null) q = q.gte('estimated_price', minPrice);
    if (maxPrice != null) q = q.lte('estimated_price', maxPrice);

    final List<dynamic> raw =
        await q.order('purchase_date', ascending: false).limit(1000);

    var rows = raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // ===== Hydrate game_label / game_code =====
    final gameIds = rows
        .map((r) => r['game_id'])
        .where((v) => v != null)
        .toSet()
        .cast<int>()
        .toList();

    Map<int, Map<String, dynamic>> gamesById = {};
    if (gameIds.isNotEmpty) {
      final gs = await _sb
          .from('games')
          .select('id, code, label')
          .inFilter('id', gameIds);
      final list = gs
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final g in list) {
        gamesById[g['id'] as int] = g;
      }
    }

    rows = rows.map((r) {
      final gid = r['game_id'] as int?;
      final g = gid != null ? gamesById[gid] : null;
      return {
        ...r,
        'game_label': g?['label'] ?? '',
        'game_code': g?['code'] ?? '',
        'status': 'vault', // sécurité
      };
    }).toList();

    // ===== Filtre texte local (multi-mots en AND) =====
    final rawQ = _searchCtrl.text.trim().toLowerCase();
    if (rawQ.isNotEmpty) {
      final tokens =
          rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      bool rowMatches(Map<String, dynamic> r) {
        final fields = <String>[
          (r['product_name'] ?? '').toString(),
          (r['language'] ?? '').toString(),
          (r['game_label'] ?? '').toString(),
          (r['game_code'] ?? '').toString(),
          (r['supplier_name'] ?? '').toString(),
          (r['buyer_company'] ?? '').toString(),
          (r['tracking'] ?? '').toString(),
        ].map((s) => s.toLowerCase()).toList();

        return tokens.every((t) => fields.any((f) => f.contains(t)));
      }

      rows = rows.where(rowMatches).toList();
    }

    // ===== Enrichissement "market" =====
    rows = await _enrichWithMarket(rows);

    return rows;
  }

  /// Récupère les prix de marché de `product` + calcule un Δ% depuis `price_history` (raw / psa10)
  Future<List<Map<String, dynamic>>> _enrichWithMarket(
      List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return rows;

    final productIds = rows
        .map((r) => r['product_id'])
        .whereType<int>()
        .toSet()
        .toList(growable: false);

    final List<dynamic> prodRaw = await _sb
        .from('product')
        .select('id, price_raw, price_graded')
        .inFilter('id', productIds);

    final Map<int, Map<String, dynamic>> productById = {
      for (final p in prodRaw)
        (p['id'] as int): Map<String, dynamic>.from(p as Map)
    };

    final List<dynamic> histRaw = await _sb
        .from('price_history')
        .select('product_id, grade, grade_detail, price, fetched_at')
        .inFilter('product_id', productIds)
        .or('grade.eq.raw,and(grade.eq.psa,grade_detail.eq.10)')
        .order('fetched_at', ascending: false)
        .limit(20000);

    final Map<int, Map<String, List<Map<String, dynamic>>>> histByProd = {};
    for (final h in histRaw) {
      final m = Map<String, dynamic>.from(h as Map);
      final int pid = m['product_id'] as int;
      final String grade = (m['grade'] ?? '').toString();
      final String gdetail = (m['grade_detail'] ?? '').toString();
      final String bucket = (grade == 'psa' && gdetail == '10')
          ? 'psa10'
          : (grade == 'raw' ? 'raw' : '');
      if (bucket.isEmpty) continue;

      histByProd.putIfAbsent(pid, () => {'raw': [], 'psa10': []});
      final list = histByProd[pid]![bucket]!;
      if (list.length < 2) list.add(m);
    }

    num? pct(num? last, num? prev) {
      if (last == null || prev == null || prev == 0) return null;
      return ((last - prev) / prev) * 100.0;
    }

    num? lastOf(List<Map<String, dynamic>> xs) =>
        (xs.isNotEmpty ? (xs[0]['price'] as num?) : null);
    num? prevOf(List<Map<String, dynamic>> xs) =>
        (xs.length >= 2 ? (xs[1]['price'] as num?) : null);

    return rows.map((r) {
      final pid = r['product_id'] as int?;
      final graded = (r['grading_note'] ?? '').toString().trim().isNotEmpty;

      final p = (pid != null) ? productById[pid] : null;
      final rawPrice = (p?['price_raw'] as num?);
      final psa10Price = (p?['price_graded'] as num?);

      final marketPrice = graded ? psa10Price : rawPrice;
      final kind = graded ? 'PSA10' : 'Raw';

      num? marketDelta;
      if (pid != null) {
        final buckets = histByProd[pid];
        if (buckets != null) {
          final xs = graded ? buckets['psa10']! : buckets['raw']!;
          marketDelta = pct(lastOf(xs), prevOf(xs));
        }
      }

      return {
        ...r,
        'market_price': marketPrice,
        'market_kind': kind,
        'market_change_pct': marketDelta,
      };
    }).toList(growable: false);
  }

  // ====================== DATA: KPI items ======================

  /// Items bruts de la vault (pour KPI FinanceOverview)
  /// ✅ RBAC: lecture sur item_masked + colonnes conditionnelles
  Future<List<Map<String, dynamic>>> _fetchvaultItemsForKpis() async {
    final canSeeCosts = _perm.canSeeUnitCosts;
    final canSeeRevenue = _perm.canSeeRevenue;

    final cols = <String>[
      'id',
      'org_id',
      'game_id',
      'type',
      'status',
      'currency',
      'language',
      'estimated_price',
      if (canSeeRevenue) 'sale_price',
      if (canSeeRevenue) 'sale_currency',
      if (canSeeCosts) 'unit_cost',
      if (canSeeCosts) 'unit_fees',
      if (canSeeCosts) 'shipping_fees',
      if (canSeeCosts) 'commission_fees',
      if (canSeeCosts) 'grading_fees',
    ].join(', ');

    var sel = _sb
        .from('item_masked')
        .select(cols)
        .eq('status', 'vault')
        .eq('type', _typeFilter);

    if ((widget.orgId ?? '').isNotEmpty) {
      sel = sel.eq('org_id', widget.orgId as Object);
    }

    if ((_gameFilter ?? '').isNotEmpty) {
      final gid = await _resolveGameIdByLabel(_gameFilter!);
      if (gid != null) {
        sel = sel.eq('game_id', gid);
      } else {
        return const [];
      }
    }

    if ((_languageFilter ?? '').isNotEmpty) {
      sel = sel.eq('language', _languageFilter as Object);
    }

    final bounds = _priceBounds();
    final minPrice = bounds['min'];
    final maxPrice = bounds['max'];
    if (minPrice != null) sel = sel.gte('estimated_price', minPrice);
    if (maxPrice != null) sel = sel.lte('estimated_price', maxPrice);

    final List<dynamic> rows = await sel.limit(50000);
    return rows
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

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

    if (changed == true) _refresh();
  }

  void _openEdit(Map<String, dynamic> line) async {
    final productId = line['product_id'] as int?;
    final status = (line['status'] ?? '').toString();
    final qty = (line['qty_status'] as int?) ?? 0;

    if (productId == null || status.isEmpty || qty <= 0) {
      _snack('Cannot edit: missing data.');
      return;
    }

    final changed = await EditItemsDialog.show(
      context,
      productId: productId,
      status: status,
      availableQty: qty,
      initialSample: line, // ← contient group_sig
    );

    if (changed == true) _refresh();
  }

  // ======= SUPPRESSION D'UNE LIGNE (vault) =======
  Future<bool> _confirmDeleteDialog(Map<String, dynamic> line) async {
    final name = (line['product_name'] ?? '').toString();
    final status = (line['status'] ?? '').toString();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this vault line?'),
            content: Text(
              'Product: $name\nStatus: $status\n\n'
              'This action will permanently delete all items and movements '
              'that belong STRICTLY to this line.',
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

  /// Récupère les IDs d'items appartenant STRICTEMENT à la "ligne"
  Future<List<int>> _collectItemIdsForLine(Map<String, dynamic> line) async {
    final String? groupSig = (line['group_sig']?.toString().isNotEmpty ?? false)
        ? line['group_sig'].toString()
        : null;

    final Object? orgId =
        ((widget.orgId ?? '').isNotEmpty) ? widget.orgId as Object : null;

    final String status = (line['status'] ?? '').toString();

    // 1️⃣ Tentative idéale : group_sig + status
    if (groupSig != null) {
      var q = _sb
          .from('item')
          .select('id')
          .eq('group_sig', groupSig)
          .eq('status', status);
      if (orgId != null) q = q.eq('org_id', orgId);

      final List<dynamic> raw =
          await q.order('id', ascending: true).limit(20000);
      final ids = raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);

      if (ids.isNotEmpty) return ids;
    }

    // 2️⃣ Fallback par clés
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
      'sale_currency',
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
      if (orgId != null) q = q.eq('org_id', orgId);

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
    return await runQuery(strongKeys);
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
    final ok = await _confirmDeleteDialog(line);
    if (!ok) return;

    try {
      final ids = await _collectItemIdsForLine(line);
      if (ids.isEmpty) {
        _snack('No items found for this vault line.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';

      final moveDel =
          _sb.from('movement').delete().filter('item_id', 'in', idsCsv);
      final itemDel = _sb.from('item').delete().filter('id', 'in', idsCsv);

      if ((widget.orgId ?? '').isNotEmpty) {
        moveDel.eq('org_id', widget.orgId as Object);
        itemDel.eq('org_id', widget.orgId as Object);
      }

      await moveDel;
      await itemDel;

      _snack('Line deleted (${ids.length} item(s) + movements).');
      _refresh();
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  // ====== LOG inline (old/new) ======
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

  // 👉 helper: trouve l'index de groupe pour patch local
  int? _findGroupIndex(Map<String, dynamic> line) {
    final sig = (line['group_sig'] ?? '').toString();
    if (sig.isNotEmpty) {
      final i =
          _groups.indexWhere((g) => (g['group_sig']?.toString() ?? '') == sig);
      if (i >= 0) return i;
    }
    bool same(dynamic a, dynamic b) => (a ?? '') == (b ?? '');
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (same(g['org_id'], line['org_id']) &&
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

  // ====== Édition inline + log + patch local ======
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
      case 'sale_currency':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t;
        break;
      case 'channel_id':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : int.tryParse(t);
        break;
      case 'sale_date':
        final t = (newValue ?? '').toString().trim();
        parsed = t.isEmpty ? null : t;
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
        orgId: (line['org_id'] ?? widget.orgId ?? '').toString(),
        itemIds: ids,
        changes: {
          field: {'old': oldValue, 'new': parsed}
        },
        reason: 'inline_edit_vault',
      );

      setState(() {
        // Patch KPI items
        if (_kpiItems.isNotEmpty) {
          final byId = {for (final it in _kpiItems) it['id']: it};
          for (final id in ids) {
            final it = byId[id];
            if (it != null) {
              it[field] = parsed;
              if (field == 'status') it['status'] = parsed;
            }
          }
          if (field == 'status' && parsed != 'vault') {
            _kpiItems.removeWhere((it) => ids.contains(it['id']));
          }
        }

        // Patch tableau
        final gi = _findGroupIndex(line);
        if (gi != null) {
          if (field == 'status' && parsed != 'vault') {
            _groups = List.of(_groups)..removeAt(gi);
          } else {
            final g = Map<String, dynamic>.from(_groups[gi]);
            g[field] = parsed;
            _groups[gi] = g;
            line[field] = parsed;
          }
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

  // 🔑 clé stable (au cas où)
  String _lineKey(Map<String, dynamic> r) {
    final sig = (r['group_sig'] ?? '').toString();
    if (sig.isNotEmpty) return sig;

    String pick(String k) =>
        (r[k] == null || (r[k] is String && r[k].toString().trim().isEmpty))
            ? '_'
            : r[k].toString();

    return [
      pick('org_id'),
      pick('product_id'),
      pick('game_id'),
      pick('type'),
      pick('language'),
      pick('purchase_date'),
      pick('currency'),
      'vault',
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final lines = _groups; // 1 ligne = 1 group_sig

    final gamesForFilter = _groups
        .map((r) => (r['game_label'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final languagesForFilter = _groups
        .map((r) => (r['language'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final body = (_loading || !_roleLoaded)
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
                            SearchAndGameFilter(
                              searchCtrl: _searchCtrl,
                              games: gamesForFilter,
                              selectedGame: _gameFilter,
                              onGameChanged: (v) {
                                setState(() => _gameFilter = v);
                                _refresh();
                              },
                              onSearch: _refresh,
                              languages: languagesForFilter,
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
                            ),
                            const SizedBox(height: 8),
                            TypeTabs(
                              typeFilter: _typeFilter,
                              onTypeChanged: (t) {
                                setState(() => _typeFilter = t);
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

                if (_perm.canSeeFinanceOverview)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FutureBuilder<Map<String, double>>(
                      future: _fxFuture ??= _loadFxRatesUsdBase().then((r) {
                        _fxRates = r;
                        _fxLoadedAt = DateTime.now();
                        return r;
                      }),
                      builder: (ctx, snap) {
                        final rates = snap.data ?? _fxRates;

                        final itemsForKpi = (rates == null)
                            ? _kpiItems
                            : _convertItemsToUsd(_kpiItems, rates);

                        final showCurrency = (rates == null)
                            ? (lines.isNotEmpty
                                ? (lines.first['currency']?.toString() ?? 'USD')
                                : 'USD')
                            : 'USD';

                        return FinanceOverview(
                          items: itemsForKpi,
                          currency: showCurrency,
                          titleInvested: (rates == null)
                              ? 'Invested (vault)'
                              : 'Invested (USD)',
                          titleEstimated: (rates == null)
                              ? 'Estimated value'
                              : 'Estimated value (USD)',
                          titleSold: (rates == null)
                              ? 'Total sold'
                              : 'Total sold (USD)',
                          subtitleInvested: 'Σ costs (unsold items)',
                          subtitleEstimated: 'Σ estimated_price (unsold items)',
                          subtitleSold: 'Σ sale_price (sold items)',
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'The vault — Items (${lines.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),

                InventoryTableByStatus(
                  mode: InventoryTableMode.vault,
                  lines: lines,
                  onOpen: _openDetails,
                  onEdit: _perm.canEditItems ? _openEdit : null,
                  onDelete: _perm.canDeleteLines ? _deleteLine : null,
                  showDelete: _perm.canDeleteLines,
                  showUnitCosts: _perm.canSeeUnitCosts,
                  showRevenue: false,
                  showEstimated: false,
                  onInlineUpdate: _applyInlineUpdate,

                  // pas de group-edit dans la vault
                  groupMode: false,
                  selection: const <String>{},
                  lineKey: _lineKey,
                  onToggleSelect: (_, __) {},
                  onToggleSelectAll: (_) {},
                ),

                const SizedBox(height: 48),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('The vault'),
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
      floatingActionButton: (!_roleLoaded || !_perm.canCreateStock)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: kAccentA,
              foregroundColor: Colors.white,
              onPressed: () async {
                final orgId = widget.orgId;
                if (orgId == null || orgId.isEmpty) {
                  _snack('No organization selected.');
                  return;
                }
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => NewStockPage(orgId: orgId)),
                );
                if (changed == true) _refresh();
              },
              icon: const Iconify(Mdi.plus, color: Colors.white),
              label: const Text('New stock'),
            ),
    );
  }
}
