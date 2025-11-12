// lib/collection_page.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../inventory/widgets/table_by_status.dart';
import '../../../inventory/widgets/edit.dart';
import '../../../inventory/widgets/search_and_filters.dart';
import 'package:inventorix_app/details/details_page.dart';
import 'package:inventorix_app/new_stock/new_stock_page.dart';

// ✅ KPI factorisé (Investi / Estimé / Vendu)
import '../../../inventory/widgets/finance_overview.dart';
import '../org/roles.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

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
  OrgRole _role = OrgRole.viewer; // mutable
  bool _roleLoaded = false; // on attend le chargement
  RolePermissions get _perm => kRoleMatrix[_role]!;

  // Données pour le tableau (groupes)
  List<Map<String, dynamic>> _groups = const [];

  // Données brutes items pour le KPI factorisé
  List<Map<String, dynamic>> _kpiItems = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadRole();
    await _refresh();
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
      _groups = await _fetchGroupsFromView();
      _kpiItems = await _fetchCollectionItemsForKpis();
    } catch (e) {
      _snack('Erreur chargement collection : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      final oid = (widget.orgId ?? '').toString();
      if (oid.isEmpty) {
        // Sans orgId on ne peut pas résoudre le rôle ; on reste viewer.
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
      } catch (_) {
        // best effort
      }

      String? roleStr = (row?['role'] as String?);

      if (roleStr == null) {
        // fallback : si l’utilisateur est le créateur de l’org, rôle owner
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

  /// Lit la vue stricte v_item_groups (1 ligne = 1 group_sig) en ne gardant que status='collection'
  /// + hydratation game_label/game_code depuis la table games
  Future<List<Map<String, dynamic>>> _fetchGroupsFromView() async {
    const cols = '''
      group_sig, org_id, type, status,
      product_id, product_name, game_id, language,
      purchase_date, currency,
      supplier_name, buyer_company, notes,
      grade_id, grading_note, sale_date, sale_price, tracking, photo_url, document_url,
      estimated_price, item_location, channel_id, payment_type, buyer_infos,
      unit_cost, unit_fees,
      qty_status, total_cost_with_fees,
      sum_shipping_fees, sum_commission_fees, sum_grading_fees
    ''';

    var q = _sb
        .from('v_item_groups')
        .select(cols)
        .eq('type', _typeFilter)
        .eq('status', 'collection');

    if ((widget.orgId ?? '').isNotEmpty) {
      q = q.eq('org_id', widget.orgId as Object);
    }

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
        'status': 'collection', // sécurité
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

    // ===== Filtre jeu local (par label) =====
    if ((_gameFilter ?? '').isNotEmpty) {
      rows = rows.where((r) => (r['game_label'] ?? '') == _gameFilter).toList();
    }

    return rows;
  }

  /// Items bruts de la collection (pour KPI FinanceOverview)
  Future<List<Map<String, dynamic>>> _fetchCollectionItemsForKpis() async {
    var sel = _sb.from('item').select('''
          id, org_id, game_id, type, status, sale_price,
          unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
          estimated_price, currency
        ''').eq('status', 'collection').eq('type', _typeFilter);

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
      initialSample: line, // ← contient group_sig
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
    final String? groupSig = (line['group_sig']?.toString().isNotEmpty ?? false)
        ? line['group_sig'].toString()
        : null;

    final Object? orgId =
        ((widget.orgId ?? '').isNotEmpty) ? widget.orgId as Object : null;

    if (groupSig != null) {
      var q = _sb
          .from('item')
          .select('id')
          .eq('group_sig', groupSig)
          .eq('status', (line['status'] ?? '').toString());
      if (orgId != null) q = q.eq('org_id', orgId);
      final List<dynamic> raw =
          await q.order('id', ascending: true).limit(20000);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
    }

    // --- Fallback par clés ---
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

      q = q.eq('status', (line['status'] ?? '').toString());

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
    ids = await runQuery(strongKeys);
    return ids;
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
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

  // ====== LOG inline (old/new) comme Edit ======
  Future<void> _logBatchEdit({
    required String orgId,
    required List<int> itemIds,
    required Map<String, Map<String, dynamic>> changes, // {field:{old,new}}
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
      // best effort
    }
  }

  // 👉 helper: trouve l'index de groupe pour patch local
  int? _findGroupIndex(Map<String, dynamic> line) {
    // priorité group_sig si présent
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
    // parse côté client
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
        _snack('Aucun item trouvé pour cette ligne.');
        return;
      }

      final idsCsv = '(${ids.join(",")})';
      await _sb.from('item').update({field: parsed}).filter('id', 'in', idsCsv);

      // Log identique à Edit
      await _logBatchEdit(
        orgId: (line['org_id'] ?? widget.orgId ?? '').toString(),
        itemIds: ids,
        changes: {
          field: {'old': oldValue, 'new': parsed}
        },
        reason: 'inline_edit_collection',
      );

      // ✅ Patch local optimiste (groupes + KPI)
      setState(() {
        // Patch KPI items (si chargés)
        if (_kpiItems.isNotEmpty) {
          final byId = {for (final it in _kpiItems) it['id']: it};
          for (final id in ids) {
            final it = byId[id];
            if (it != null) {
              it[field] = parsed;
              if (field == 'status') it['status'] = parsed;
            }
          }
          // Si statut ≠ collection, retirer ces items de la base KPI locale
          if (field == 'status' && parsed != 'collection') {
            _kpiItems.removeWhere((it) => ids.contains(it['id']));
          }
        }

        // Patch ligne de tableau (1 row = 1 group_sig)
        final gi = _findGroupIndex(line);
        if (gi != null) {
          if (field == 'status' && parsed != 'collection') {
            // La ligne sort de la vue → suppression immédiate
            _groups = List.of(_groups)..removeAt(gi);
          } else {
            final g = Map<String, dynamic>.from(_groups[gi]);
            g[field] = parsed;
            _groups[gi] = g;
            line[field] = parsed;
          }
        }
      });

      _snack('Modifié (${ids.length} item(s)).');
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
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
                            ),
                            const SizedBox(height: 8),
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

                if (_perm.canSeeFinanceOverview)
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

                InventoryTableByStatus(
                  lines: lines,
                  onOpen: _openDetails,
                  onEdit: _openEdit,
                  onDelete: _deleteLine,
                  onInlineUpdate: _applyInlineUpdate, // 👈 inline + log + patch
                ),

                const SizedBox(height: 48),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text(' Collection'),
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
        icon: const Iconify(Mdi.plus, color: Colors.white),
        label: const Text('Nouveau stock'),
      ),
    );
  }
}
