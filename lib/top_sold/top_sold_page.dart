// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../details/widgets/marge.dart'; // MarginChip
import '../inventory/main_inventory_page.dart'
    show kAccentA, kAccentB, kAccentC, kAccentG;

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

  /// NEW: filtre de période sur purchase_date
  /// 'all' | 'month' (30j) | 'week' (7j)
  String _dateFilter = 'all';

  static const String _kDefaultAsset = 'assets/images/default_card.png';

  static const List<String> _wantedStatuses = [
    'sold',
    'shipped',
    'finalized',
    'collection'
  ];

  /// ⚠️ Clé de regroupement STRICTE — IDENTIQUE à MainInventoryPage._collectItemIdsForLine
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
    // le statut est filtré/attaché séparément juste en-dessous
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  // --------- Helpers anti-null ----------
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
  // --------------------------------------

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // 1) Base query (on sélectionne aussi purchase_date pour filtrer côté base)
      dynamic q = _sb.from('item').select('''
            id, product_id, type, language, game_id,
            status, sale_date, sale_price, currency, marge,
            unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees,
            photo_url, buyer_company, supplier_name, purchase_date,
            channel_id, notes, grade_id, grading_note, document_url,
            estimated_price, item_location, org_id
          ''');

      if (_typeFilter != 'all') {
        q = q.filter('type', 'eq', _typeFilter);
      }

      // Filtre période sur purchase_date (côté base)
      final after = _purchaseDateStart();
      if (after != null) {
        final afterStr = after.toIso8601String().split('T').first; // YYYY-MM-DD
        q = q.gte('purchase_date', afterStr);
      }

      q = q.order('sale_date', ascending: false).limit(5000);

      final List<dynamic> raw = await q;
      var items = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) Filtre statuts côté client
      items = items.where((r) {
        final s = (r['status'] ?? '').toString();
        final hasSale = r['sale_price'] != null; // <- clé: vente existante
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
        var pq = _sb
            .from('product')
            .select('id, name, sku, language, org_id')
            .filter('id', 'in', '(${productIds.join(",")})');

        // (ne filtre pas org ici si RLS empêche la lecture; on gère fallback vue)
        final List<dynamic> prods = await pq;
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

      // 3.bis) Fallback: noms depuis la vue v_items_by_status (insensible aux RLS de product)
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

      // 4) Filtre jeu + recherche locale (product.name / product.sku)
      final qtxt = _searchCtrl.text.trim().toLowerCase();
      if ((_gameFilter ?? '').isNotEmpty || qtxt.isNotEmpty) {
        items = items.where((r) {
          final p = productById[r['product_id'] as int?] ?? const {};
          final g = gameById[r['game_id'] as int?] ?? const {};

          // fallback vue pour game_label
          final gameLabelFallback =
              (vInfoByProductId[r['product_id'] as int?]?['game_label'] ?? '')
                  .toString();

          final gameOk = (_gameFilter ?? '').isEmpty ||
              (g['label'] ?? '') == _gameFilter ||
              gameLabelFallback == _gameFilter;
          if (!gameOk) return false;

          if (qtxt.isEmpty) return true;
          final name = (p['name'] ?? '').toString().toLowerCase();
          final sku = (p['sku'] ?? '').toString().toLowerCase();
          final nameFallback =
              (vInfoByProductId[r['product_id'] as int?]?['product_name'] ?? '')
                  .toString()
                  .toLowerCase();
          return name.contains(qtxt) ||
              sku.contains(qtxt) ||
              nameFallback.contains(qtxt);
        }).toList();
      }

      // 5) REGROUPEMENT STRICT (mêmes clés que l'inventaire) + statut
      Map<String, Map<String, dynamic>> groups = {}; // key -> aggregate map

      String keyOf(Map<String, dynamic> r) {
        final buf = StringBuffer();
        for (final k in _strictLineKeys) {
          final v = r.containsKey(k) ? r[k] : null;
          buf.write('$k=');
          if (v == null) {
            buf.write('∅|');
          } else {
            // normalisation simple
            buf.write('${v.toString()}|');
          }
        }
        // statut fait partie de la ligne
        buf.write('status=${(r['status'] ?? '').toString()}|');
        return buf.toString();
      }

      for (final r in items) {
        final key = keyOf(r);
        final g = groups.putIfAbsent(key, () {
          // base du groupe = copier toutes les clés strictes + statut
          final base = <String, dynamic>{};
          for (final k in _strictLineKeys) {
            base[k] = r[k];
          }
          base['status'] = r['status'];
          base['product_id'] = r['product_id'];
          base['game_id'] = r['game_id'];
          base['_count'] = 0;
          base['_sum_marge'] = 0.0;
          base['_sum_sale'] = 0.0;
          base['_sum_ucost'] = 0.0;
          base['_sum_ufees'] = 0.0;
          base['_sum_ship'] = 0.0;
          base['_sum_comm'] = 0.0;
          base['_sum_grad'] = 0.0;
          // pour l'affichage: on garde aussi une photo non vide si possible
          base['_any_photo'] = (r['photo_url'] ?? '').toString();
          // garder la monnaie
          base['currency'] = r['currency'];
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

      // 6) Construction des lignes d’affichage (moyennes par groupe)
      final rows = <Map<String, dynamic>>[];
      for (final g in groups.values) {
        final cnt = (g['_count'] as int);
        num avg(num sum) => cnt == 0 ? 0 : sum / cnt;

        final pid = g['product_id'] as int?;
        final gid = g['game_id'] as int?;

        final product = productById[pid] ?? const {};
        final game = gameById[gid] ?? const {};
        final vinfo =
            (pid != null) ? (vInfoByProductId[pid] ?? const {}) : const {};

        rows.add({
          for (final k in _strictLineKeys) k: g[k],
          'status': g['status'],

          'product_id': pid,
          'game_id': gid,

          // 👇 champs plats utilisés par la page Détails + affichage
          'product_name':
              (product['name'] ?? vinfo['product_name'] ?? '').toString(),
          'language': (product['language'] ??
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

      // 7) Tri final marge desc (NULL en bas)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur Top Sold : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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

                    // NEW: période de création (purchase_date)
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

                    // Jeu (table games) — TOUT en nullable
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

                    // Search (product.name / product.sku)
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Rechercher (nom/sku)',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onSubmitted: (_) => _fetch(),
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
                        // ======= Lecture ultra-safe de la ligne =======
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

                        // ======= Tuile =======
                        return Card(
                          elevation: 0.8,
                          shadowColor: kAccentA.withOpacity(.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              // ✅ MET CE BLOC À LA PLACE (même logique que MainInventory) :
                              widget.onOpenDetails?.call({
                                'product_id': r['product_id'],
                                'status': status,
                                'currency': r['currency'],
                                'unit_cost': r['unit_cost'],
                                'sale_price': r['sale_price'],
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // VIGNETTE FORMAT "CARTE"
                                  _cardThumb(photoUrl),
                                  const SizedBox(width: 12),

                                  // infos
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
