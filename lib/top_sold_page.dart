// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'details/widgets/marge.dart'; // MarginChip
import 'inventory/main_inventory_page.dart'
    show kAccentA, kAccentB, kAccentC, kAccentG;

class TopSoldPage extends StatefulWidget {
  const TopSoldPage({super.key, this.onOpenDetails});

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

  static const List<String> _wantedStatuses = [
    'sold',
    'shipped',
    'finalized',
    'collection'
  ];

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
            photo_url, buyer_company, supplier_name, purchase_date
          ''');

      if (_typeFilter != 'all') {
        q = q.filter('type', 'eq', _typeFilter);
      }

      // NEW: filtre période sur purchase_date (côté base)
      final after = _purchaseDateStart();
      if (after != null) {
        final afterStr = after.toIso8601String().split('T').first; // YYYY-MM-DD
        q = q.gte('purchase_date', afterStr);
      }

      q = q.order('sale_date', ascending: false).limit(2000);

      final List<dynamic> raw = await q;
      var rows = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) Filtre statuts côté client
      rows = rows.where((r) {
        final s = (r['status'] ?? '').toString();
        return _wantedStatuses.contains(s);
      }).toList();

      // 3) Lookups product & games
      final productIds =
          rows.map((r) => r['product_id']).whereType<int>().toSet().toList();
      final gameIds =
          rows.map((r) => r['game_id']).whereType<int>().toSet().toList();

      Map<int, Map<String, dynamic>> productById = {};
      Map<int, Map<String, dynamic>> gameById = {};

      if (productIds.isNotEmpty) {
        final List<dynamic> prods = await _sb
            .from('product')
            .select('id, name, sku, language')
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

      // 4) Filtre jeu + recherche locale (product.name / product.sku)
      final qtxt = _searchCtrl.text.trim().toLowerCase();
      if ((_gameFilter ?? '').isNotEmpty || qtxt.isNotEmpty) {
        rows = rows.where((r) {
          final p = productById[r['product_id'] as int?] ?? const {};
          final g = gameById[r['game_id'] as int?] ?? const {};

          final gameOk =
              (_gameFilter ?? '').isEmpty || (g['label'] ?? '') == _gameFilter;
          if (!gameOk) return false;

          if (qtxt.isEmpty) return true;
          final name = (p['name'] ?? '').toString().toLowerCase();
          final sku = (p['sku'] ?? '').toString().toLowerCase();
          return name.contains(qtxt) || sku.contains(qtxt);
        }).toList();
      }

      // 5) Tri final marge desc (NULL en bas)
      rows.sort((a, b) {
        final ma = a['marge'] as num?;
        final mb = b['marge'] as num?;
        if (ma == null && mb == null) return 0;
        if (ma == null) return 1;
        if (mb == null) return -1;
        return mb.compareTo(ma);
      });

      // 6) Fusion pour rendu (anti-NPE clé manquante)
      _rows = rows
          .map((r) => {
                ...r,
                'product': productById[r['product_id'] as int?] ?? const {},
                'game': gameById[r['game_id'] as int?] ?? const {},
              })
          .toList();
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

                        final String title = _safeStr(product['name']).isEmpty
                            ? 'Produit #${_safeStr(r['product_id'])}'
                            : _safeStr(product['name']);

                        final String gameLbl = _safeStr(game['label']);
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

                        // ======= Tuile tolérante =======
                        return Card(
                          elevation: 0.8,
                          shadowColor: kAccentA.withOpacity(.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => widget.onOpenDetails?.call(r),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // thumb robuste
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 140,
                                      height: 94,
                                      child: Image.network(
                                        (photoUrl.isEmpty
                                            ? 'https://placehold.co/600x400?text=No+Photo'
                                            : photoUrl),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) {
                                          return Container(
                                            color: Colors.black12,
                                            alignment: Alignment.center,
                                            child:
                                                const Icon(Icons.broken_image),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
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
