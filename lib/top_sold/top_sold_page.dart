// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../details/widgets/marge.dart'; // MarginChip
import '../inventory/main_inventory_page.dart'
    show kAccentA, kAccentB, kAccentC, kAccentG;
import 'package:inventorix_app/details/details_page.dart'
    hide
        kAccentA,
        kAccentC,
        kAccentB; // ⬅️ pour ouverture locale si pas de callback

class TopSoldPage extends StatefulWidget {
  const TopSoldPage({super.key, this.orgId, this.onOpenDetails});

  /// Filtre d’organisation (UUID). Si null/empty => pas de filtre org côté requêtes.
  final String? orgId;

  /// Callback pour ouvrir la page Détails depuis l’onglet Top Sold
  final void Function(Map<String, dynamic> itemRow)? onOpenDetails;

  @override
  State<TopSoldPage> createState() => _TopSoldPageState();
}

class _TopSoldPageState extends State<TopSoldPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String _typeFilter = 'all'; // 'all' | 'single' | 'sealed'
  String? _gameFilter; // games.label (nullable)
  List<Map<String, dynamic>> _rows = [];

  final _searchCtrl = TextEditingController();

  /// Filtre de période sur purchase_date
  /// 'all' | 'month' (30j) | 'week' (7j)
  String _dateFilter = 'all';

  static const String _kDefaultAsset = 'assets/images/default_card.png';

  static const List<String> _wantedStatuses = [
    'sold',
    'shipped',
    'finalized',
    'collection'
  ];

  /// ⚠️ Clé de regroupement STRICTE — identique à MainInventory
  static const Set<String> _strictLineKeys = {
    'product_id',
    'game_id',
    'type',
    'language',
    'channel_id',
    'purchase_date',
    'currency',
    'supplier_name',
    'buyer_company',
    'notes',
    'grade_id',
    'grading_note',
    'grading_fees',
    'sale_date',
    'sale_price',
    'tracking',
    'photo_url',
    'document_url',
    'estimated_price',
    'item_location',
    'unit_cost',
    'unit_fees',
    // statut géré séparément
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------- Helpers ----------
  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _safeStr(dynamic v) => (v == null) ? '' : v.toString();

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

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // --------- Fetch principal ----------
  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // 1) Base query
      PostgrestFilterBuilder q = _sb.from('item').select('''
            id, product_id, type, language, game_id,
            status, sale_date, sale_price, currency, marge,
            unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
            photo_url, buyer_company, supplier_name, purchase_date,
            channel_id, notes, grade_id, grading_note, document_url,
            estimated_price, item_location, org_id
          ''');

      if (_typeFilter != 'all') {
        q = q.eq('type', _typeFilter);
      }

      // 🔐 filtre org si fourni
      if ((widget.orgId ?? '').isNotEmpty) {
        q = q.eq('org_id', widget.orgId as Object);
      }

      // Filtre période sur purchase_date
      final after = _purchaseDateStart();
      if (after != null) {
        final afterStr = after.toIso8601String().split('T').first; // YYYY-MM-DD
        q = q.gte('purchase_date', afterStr);
      }

      final List<dynamic> raw =
          await q.order('sale_date', ascending: false).limit(5000);
      var items = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) Filtre statuts: ventes/collection effectives
      items = items.where((r) {
        final s = (r['status'] ?? '').toString();
        final hasSale = r['sale_price'] != null; // clé: vente existante
        return _wantedStatuses.contains(s) && hasSale;
      }).toList();

      // 3) Lookups product & games (pour nom/sku/jeu)
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

      // 3.bis) Fallback: noms depuis la vue v_items_by_status
      Map<int, Map<String, dynamic>> vInfoByProductId = {};
      if (productIds.isNotEmpty) {
        final String idsCsv = '(${productIds.join(",")})';
        final List<dynamic> vrows = await _sb
            .from('v_items_by_status')
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
      }

      // 4) Filtre jeu + recherche locale (multi-mots AND, sur Enter)
      final rawQ = _searchCtrl.text.trim().toLowerCase();
      final tokens = rawQ.isEmpty
          ? const <String>[]
          : rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      bool matchesSearch(Map<String, dynamic> r) {
        if (tokens.isEmpty) return true;

        final pid = r['product_id'] as int?;
        final gid = r['game_id'] as int?;

        final product = pid != null ? (productById[pid] ?? const {}) : const {};
        final game = gid != null ? (gameById[gid] ?? const {}) : const {};
        final vinfo =
            pid != null ? (vInfoByProductId[pid] ?? const {}) : const {};

        final fields = <String>[
          (product['name'] ?? vinfo['product_name'] ?? '').toString(),
          (product['sku'] ?? '').toString(),
          (vinfo['language'] ?? r['language'] ?? '').toString(),
          (game['label'] ?? vinfo['game_label'] ?? '').toString(),
          (game['code'] ?? vinfo['game_code'] ?? '').toString(),
          (r['supplier_name'] ?? '').toString(),
          (r['buyer_company'] ?? '').toString(),
          (r['tracking'] ?? '').toString(),
        ].map((s) => s.toLowerCase()).toList();

        // Chaque token doit apparaître dans AU MOINS un champ
        return tokens.every((t) => fields.any((f) => f.contains(t)));
      }

      bool matchesGame(Map<String, dynamic> r) {
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

      if ((_gameFilter ?? '').isNotEmpty || tokens.isNotEmpty) {
        items = items.where((r) => matchesGame(r) && matchesSearch(r)).toList();
      }

      // 5) REGROUPEMENT STRICT + statut
      Map<String, Map<String, dynamic>> groups = {};

      String keyOf(Map<String, dynamic> r) {
        final buf = StringBuffer();
        for (final k in _strictLineKeys) {
          final v = r.containsKey(k) ? r[k] : null;
          buf.write('$k=');
          if (v == null) {
            buf.write('∅|');
          } else {
            buf.write('${v.toString()}|');
          }
        }
        buf.write('status=${(r['status'] ?? '').toString()}|');
        return buf.toString();
      }

      for (final r in items) {
        final key = keyOf(r);
        final g = groups.putIfAbsent(key, () {
          final base = <String, dynamic>{};
          for (final k in _strictLineKeys) {
            base[k] = r[k];
          }
          base['status'] = r['status'];
          base['product_id'] = r['product_id'];
          base['game_id'] = r['game_id'];
          base['type'] = r['type'];
          base['language'] = r['language'];
          base['_count'] = 0;
          base['_sum_marge'] = 0.0;
          base['_sum_sale'] = 0.0;
          base['_sum_ucost'] = 0.0;
          base['_sum_ufees'] = 0.0;
          base['_sum_ship'] = 0.0;
          base['_sum_comm'] = 0.0;
          base['_sum_grad'] = 0.0;
          base['_any_photo'] = (r['photo_url'] ?? '').toString();
          base['currency'] = r['currency'];
          base['org_id'] = r['org_id'];
          return base;
        });

        g['_count'] = (g['_count'] as int) + 1;
        g['_sum_marge'] = (g['_sum_marge'] as num).toDouble() +
            (_asNum(r['marge']) ?? 0).toDouble();
        g['_sum_sale'] =
            (g['_sum_sale'] as num).toDouble() + (_asNum(r['sale_price']) ?? 0);
        g['_sum_ucost'] =
            (g['_sum_ucost'] as num).toDouble() + (_asNum(r['unit_cost']) ?? 0);
        g['_sum_ufees'] =
            (g['_sum_ufees'] as num).toDouble() + (_asNum(r['unit_fees']) ?? 0);
        g['_sum_ship'] = (g['_sum_ship'] as num).toDouble() +
            (_asNum(r['shipping_fees']) ?? 0);
        g['_sum_comm'] = (g['_sum_comm'] as num).toDouble() +
            (_asNum(r['commission_fees']) ?? 0);
        g['_sum_grad'] = (g['_sum_grad'] as num).toDouble() +
            (_asNum(r['grading_fees']) ?? 0);

        final curPhoto = (g['_any_photo'] ?? '').toString();
        if (curPhoto.isEmpty) {
          final cand = (r['photo_url'] ?? '').toString();
          if (cand.isNotEmpty) g['_any_photo'] = cand;
        }
      }

      // 6) Lignes d’affichage (moyennes par groupe)
      final rows = <Map<String, dynamic>>[];
      for (final g in groups.values) {
        final cnt = (g['_count'] as int);
        num avg(num sum) => cnt == 0 ? 0 : sum / cnt;

        final pid = g['product_id'] as int?;
        final gid = g['game_id'] as int?;

        final product = pid != null ? (productById[pid] ?? const {}) : const {};
        final game = gid != null ? (gameById[gid] ?? const {}) : const {};
        final vinfo =
            pid != null ? (vInfoByProductId[pid] ?? const {}) : const {};

        rows.add({
          for (final k in _strictLineKeys) k: g[k],
          'status': g['status'],
          'product_id': pid,
          'game_id': gid,
          'type': g['type'],
          'language': g['language'],
          'org_id': g['org_id'],

          // Affichage + Détails
          'product_name':
              (product['name'] ?? vinfo['product_name'] ?? '').toString(),
          'language_display': (product['language'] ??
                  vinfo['language'] ??
                  (g['language'] ?? ''))
              .toString(),
          'game_label': (game['label'] ?? vinfo['game_label'] ?? '').toString(),
          'game_code': (game['code'] ?? vinfo['game_code'] ?? '').toString(),

          'product': product,
          'game': game,
          'photo_url': (g['_any_photo'] ?? '').toString(),
          'currency': g['currency'] ?? 'USD',

          'marge': avg((g['_sum_marge'] as num)),
          'sale_price': avg((g['_sum_sale'] as num)),
          'unit_cost': avg((g['_sum_ucost'] as num)),
          'unit_fees': avg((g['_sum_ufees'] as num)),
          'shipping_fees': avg((g['_sum_ship'] as num)),
          'commission_fees': avg((g['_sum_comm'] as num)),
          'grading_fees': avg((g['_sum_grad'] as num)),
          'qty': cnt,
        });
      }

      // 7) Tri final marge desc
      rows.sort((a, b) {
        final ma = a['marge'] as num?;
        final mb = b['marge'] as num?;
        if (ma == null && mb == null) return 0;
        if (ma == null) return 1;
        if (mb == null) return -1;
        return mb.compareTo(ma);
      });

      _rows = rows;
    } catch (e) {
      if (mounted) {
        _snack('Erreur Top Sold : $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------- Ouverture Détails (robuste, comme MainInventory) ----------
// --------- Ouverture Détails (robuste, sans updated_at) ----------
  Future<void> _openDetails(Map<String, dynamic> line) async {
    final String? orgId = ((widget.orgId ?? '').isNotEmpty)
        ? widget.orgId
        : (line['org_id']?.toString());
    final status = (line['status'] ?? '').toString();
    final type = (line['type'] ?? '').toString();
    final language = (line['language'] ?? '').toString();
    final int? productId = line['product_id'] as int?;
    final int? gameId = line['game_id'] as int?;

    if (orgId == null ||
        productId == null ||
        gameId == null ||
        status.isEmpty) {
      _snack('Données insuffisantes pour ouvrir les détails.');
      return;
    }

    Map<String, dynamic>? rep;

    // ⬇️ même logique que sur MainInventory, mais on ne touche plus updated_at
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
      // 🔁 on choisit l’ID le plus récent — pas de dépendance à updated_at
      return await q.order('id', ascending: false).limit(1).maybeSingle();
    }

    try {
      // PASS 1 — clés fortes
      rep = await _probe([
        ['status', 'eq', status],
        ['type', 'eq', type],
        ['language', 'eq', language],
        ['product_id', 'eq', productId],
        ['game_id', 'eq', gameId],
      ]);

      // PASS 2
      rep ??= await _probe([
        ['status', 'eq', status],
        ['product_id', 'eq', productId],
        ['game_id', 'eq', gameId],
      ]);

      // PASS 3 — ultime secours
      rep ??= await _probe([
        ['status', 'eq', status],
        ['product_id', 'eq', productId],
      ]);

      if (rep == null || rep['id'] == null) {
        _snack("Impossible d'identifier le groupe d'items pour cette ligne.");
        return;
      }
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

    if (widget.onOpenDetails != null) {
      widget.onOpenDetails!(payload);
    } else {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              GroupDetailsPage(group: Map<String, dynamic>.from(payload)),
        ),
      );
    }
  }

  String _money(num? n) => n == null ? '—' : n.toDouble().toStringAsFixed(2);

  /// Vignette format "carte" (≈100×72) avec fallback asset si pas d'image.
  Widget _cardThumb(String photoUrl) {
    const double h = 100;
    const double w = 72; // ~ h * 0.72
    final hasNet = photoUrl.isNotEmpty;

    Widget img;
    if (hasNet) {
      img = Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          _kDefaultAsset,
          fit: BoxFit.cover,
        ),
      );
    } else {
      img = Image.asset(
        _kDefaultAsset,
        fit: BoxFit.cover,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: w,
        height: h,
        child: img,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // === Barre filtres ===
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Card(
            elevation: 1,
            shadowColor: kAccentA.withOpacity(.18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Type (avec "Tous")
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Tous')),
                        ButtonSegment(value: 'single', label: Text('Single')),
                        ButtonSegment(value: 'sealed', label: Text('Sealed')),
                      ],
                      selected: {_typeFilter},
                      onSelectionChanged: (s) {
                        setState(() => _typeFilter = s.first);
                        _fetch();
                      },
                    ),

                    // Période (purchase_date)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All time')),
                        ButtonSegment(
                            value: 'month', label: Text('Last month')),
                        ButtonSegment(value: 'week', label: Text('Last week')),
                      ],
                      selected: {_dateFilter},
                      onSelectionChanged: (s) {
                        setState(() => _dateFilter = s.first);
                        _fetch();
                      },
                    ),

                    // Jeu (table games)
                    FutureBuilder<List<String>>(
                      future: _availableGames(),
                      builder: (ctx, snap) {
                        final games = (snap.data ?? const []);
                        final safeValue =
                            (_gameFilter != null && games.contains(_gameFilter))
                                ? _gameFilter
                                : null; // évite valeur hors-liste
                        return DropdownButton<String?>(
                          value: safeValue,
                          hint: const Text('Filtrer par jeu'),
                          items: <DropdownMenuItem<String?>>[
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('Tous les jeux')),
                            ...games.map(
                              (g) => DropdownMenuItem<String?>(
                                value: g,
                                child: Text(g),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _gameFilter = v);
                            _fetch();
                          },
                        );
                      },
                    ),

                    // Search (multi-mots, Enter pour lancer)
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Rechercher (multi-mots : nom/sku/jeu...)',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _fetch(); // relance à vide
                                  },
                                ),
                        ),
                        onSubmitted: (_) => _fetch(), // ⬅️ Enter
                      ),
                    ),

                    FilledButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualiser'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // === Liste Top Sold ===
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_rows.isEmpty
                  ? const Center(
                      child: Text('Aucune vente/collection trouvée.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: _rows.length,
                      itemBuilder: (ctx, i) {
                        final Map<String, dynamic> r =
                            Map<String, dynamic>.from(_rows[i]);
                        final Map<String, dynamic> product =
                            Map<String, dynamic>.from(r['product'] ?? const {});
                        final Map<String, dynamic> game =
                            Map<String, dynamic>.from(r['game'] ?? const {});

                        final String title =
                            _safeStr(r['product_name']).isNotEmpty
                                ? _safeStr(r['product_name'])
                                : (_safeStr(product['name']).isNotEmpty
                                    ? _safeStr(product['name'])
                                    : 'Produit #${_safeStr(r['product_id'])}');

                        final String gameLbl =
                            _safeStr(r['game_label']).isNotEmpty
                                ? _safeStr(r['game_label'])
                                : _safeStr(game['label']);
                        final String sku = _safeStr(product['sku']);
                        final String subtitle = [gameLbl, sku]
                            .where((e) => e.isNotEmpty)
                            .join(' • ');

                        final String photoUrl = _safeStr(r['photo_url']);
                        final String status = _safeStr(r['status']);
                        final String currency = _safeStr(r['currency']).isEmpty
                            ? 'USD'
                            : _safeStr(r['currency']);

                        final num? marge = _asNum(r['marge']);
                        final num unitCost = (_asNum(r['unit_cost']) ?? 0) +
                            (_asNum(r['unit_fees']) ?? 0) +
                            (_asNum(r['shipping_fees']) ?? 0) +
                            (_asNum(r['commission_fees']) ?? 0) +
                            (_asNum(r['grading_fees']) ?? 0);
                        final num? salePrice = _asNum(r['sale_price']);

                        return Card(
                          elevation: 0.8,
                          shadowColor: kAccentA.withOpacity(.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openDetails(r), // ✅ robuste
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _cardThumb(photoUrl),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: (Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800)) ??
                                              const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: (Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant)) ??
                                                const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black54),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Chip(
                                              label: Text(
                                                status.isEmpty
                                                    ? '—'
                                                    : status.toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              ),
                                              backgroundColor:
                                                  _statusColor(status),
                                            ),
                                            MarginChip(marge: marge),
                                            Chip(
                                              avatar: const Icon(Icons.sell,
                                                  size: 16,
                                                  color: Colors.white),
                                              label: Text(
                                                (salePrice == null)
                                                    ? '—'
                                                    : '${_money(salePrice)} $currency',
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              ),
                                              backgroundColor: kAccentB,
                                            ),
                                            Chip(
                                              avatar: const Icon(Icons.savings,
                                                  size: 16,
                                                  color: Colors.white),
                                              label: Text(
                                                '${_money(unitCost)} $currency',
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              ),
                                              backgroundColor: kAccentC,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sold':
      case 'shipped':
      case 'finalized':
        return kAccentG;
      default:
        return kAccentA; // collection & autres
    }
  }

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
}
