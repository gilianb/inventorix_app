// ignore_for_file: unused_local_variable, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../inventory/widgets/edit.dart' show EditItemsDialog;

import 'widgets/history_list.dart';
import 'widgets/finance_summary.dart';
import 'widgets/info_extras_card.dart';
import 'widgets/info_banner.dart';
import 'widgets/marge.dart'; // ⬅️ nouveau

/// Clé d'image par défaut si `photo_url` est vide ou invalide
const String kDefaultPhoto = 'https://placehold.co/600x400?text=No+Photo';

/// Petite palette d’accents (juste visuel, pas de logique)
const kAccentA = Color(0xFF6C5CE7); // indigo/violet
const kAccentB = Color(0xFF00D1B2); // teal/menthe
const kAccentC = Color(0xFFFFB545); // amber doux

/// Colonnes disponibles dans la vue v_items_by_status (strict)
/// ⚠️ NE PAS mettre grading_note / grading_fees ici car la vue ne les expose pas
const List<String> kViewCols = [
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
  'qty_in_transit',
  'qty_paid',
  'qty_received',
  'qty_sent_to_grader',
  'qty_at_grader',
  'qty_graded',
  'qty_listed',
  'qty_awaiting_payment',
  'qty_sold',
  'qty_shipped',
  'qty_finalized',
  'qty_collection',
  'total_cost',
  'total_cost_with_fees',
  'realized_revenue',
  // agrégats pour Investi(vue) enrichi :
  'sum_shipping_fees',
  'sum_commission_fees',
  'sum_grading_fees',
];

/// ⚠️ CLE DE REGROUPEMENT STRICTE — IDENTIQUE A MainInventoryPage._collectItemIdsForLine
const Set<String> kStrictLineKeys = {
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
};

/// Sous-ensemble “volatils” que l’on peut ignorer en fallback si strict=vide
const Set<String> kVolatileKeys = {
  'notes',
  'sale_date',
  'sale_price',
  'tracking',
  'photo_url',
  'document_url',
  'estimated_price',
};

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({super.key, required this.group});
  final Map<String, dynamic> group;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _viewRow; // ligne exacte depuis v_items_by_status
  List<Map<String, dynamic>> _items = []; // items du groupe strict
  List<Map<String, dynamic>> _movements = []; // historique movement

  // Filtre local par statut (timeline / chips)
  String? _localStatusFilter;

  // Toggles d’affichage
  bool _showItemsTable = true;
  bool _showHistory = true;

  // indique si un edit a modifié quelque chose
  bool _dirty = false;

  // Helpers
  Map<String, dynamic> get _initial => widget.group;

  String get _title =>
      (_viewRow?['product_name'] ?? _initial['product_name'] ?? '').toString();

  String get _subtitle {
    final game =
        (_viewRow?['game_label'] ?? _initial['game_label'] ?? '').toString();
    final lang =
        (_viewRow?['language'] ?? _initial['language'] ?? '').toString();
    final type = (_viewRow?['type'] ?? _initial['type'] ?? '').toString();
    final s = [game, lang, if (type.isNotEmpty) type]
        .where((e) => e.isNotEmpty)
        .join(' • ');
    return s;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // === 1) Items STRICTS : mêmes clés que MainInventory + statut cliqué ===
      final strictItems = await _fetchItemsByLineKey(
        widget.group,
        ignoreKeys: const {},
      );

      List<Map<String, dynamic>> items = strictItems;

      // === 2) Fallback doux si strict vide : on ignore seulement les clés volatiles ===
      if (items.isEmpty) {
        items = await _fetchItemsByLineKey(
          widget.group,
          ignoreKeys: kVolatileKeys,
        );
      }

      // === 3) Si encore vide, on arrête proprement (pas d’infos fantômes) ===
      if (items.isEmpty) {
        setState(() {
          _viewRow = null;
          _items = const [];
          _movements = const [];
        });
        return;
      }

      // Statut actif (utilise celui cliqué si fourni)
      final detectedStatus =
          (widget.group['status'] ?? items.first['status'] ?? '').toString();
      if ((_localStatusFilter ?? '').isEmpty ||
          _localStatusFilter != detectedStatus) {
        _localStatusFilter = detectedStatus;
      }

      // === 4) Récupère la ligne de vue EXACTE qu’on a cliquée ===
      final viewRow = await _fetchViewRow(widget.group) ?? widget.group;

      // === 5) Mouvements des items trouvés ===
      final mvts =
          await _fetchMovementsFor(items.map((e) => e['id'] as int).toList());

      setState(() {
        _viewRow = viewRow;
        _items = items;
        _movements = mvts;
      });
    } catch (e) {
      _snack('Erreur chargement détails : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<Map<String, dynamic>?> _fetchViewRow(
      Map<String, dynamic> group) async {
    var builder = _sb.from('v_items_by_status').select(kViewCols.join(','));
    // on n’applique que les clés que la vue connaît
    for (final key in kViewCols) {
      if (group.containsKey(key) && group[key] != null) {
        builder = builder.eq(key, group[key]);
      }
    }
    final res = await builder.limit(1);
    final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    return list.isNotEmpty ? list.first : null;
  }

  /// Construit une requête items basée sur la même clé de regroupement que MainInventory,
  /// + le statut cliqué. Si [ignoreKeys] contient des clés, elles ne seront pas utilisées.
  Future<List<Map<String, dynamic>>> _fetchItemsByLineKey(
    Map<String, dynamic> source, {
    required Set<String> ignoreKeys,
  }) async {
    const itemCols = [
      'id',
      'product_id',
      'game_id',
      'type',
      'language',
      'status',
      'channel_id',
      'purchase_date',
      'currency',
      'supplier_name',
      'buyer_company',
      'unit_cost',
      'unit_fees',
      'notes',
      'grade_id',
      'grading_note',
      'grading_fees',
      'sale_date',
      'sale_price',
      'tracking',
      'photo_url',
      'document_url',
      'created_at',
      'estimated_price',
      'item_location',
      'shipping_fees',
      'commission_fees',
      'payment_type',
      'buyer_infos',
      'marge',
    ];

    var q = _sb.from('item').select(itemCols.join(','));

    for (final k in kStrictLineKeys) {
      if (ignoreKeys.contains(k)) continue;
      if (!source.containsKey(k)) continue;
      final v = source[k];
      if (v == null) {
        q = q.filter(k, 'is', null);
      } else {
        q = q.filter(k, 'eq', v);
      }
    }

    // Statut = ligne cliquée (source de vérité)
    final clickedStatus = (source['status'] ?? '').toString();
    if (clickedStatus.isNotEmpty) {
      q = q.eq('status', clickedStatus);
    } else if ((_localStatusFilter ?? '').isNotEmpty) {
      q = q.eq('status', _localStatusFilter as Object);
    }

    final raw = await q.order('id', ascending: true).limit(20000);
    return List<Map<String, dynamic>>.from(
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMovementsFor(
      List<int> itemIds) async {
    if (itemIds.isEmpty) return [];
    final idsIn = '(${itemIds.join(",")})';
    final raw = await _sb
        .from('movement')
        .select(
          'id, ts, mtype, from_status, to_status, channel_id, qty, unit_price, currency, fees, grader, grade, tracking, note, item_id',
        )
        .filter('item_id', 'in', idsIn)
        .order('ts', ascending: false)
        .limit(20000);

    final list = List<Map<String, dynamic>>.from(
        (raw as List).map((e) => Map<String, dynamic>.from(e as Map)));
    return list;
  }

  Future<void> _onEditGroup() async {
    final curStatus =
        (_localStatusFilter ?? widget.group['status'] ?? '').toString();

    // quantité affichée = nombre d’items filtrés localement
    final qty = _items.where((e) => (e['status'] ?? '') == curStatus).length;

    final productId =
        (_viewRow?['product_id'] ?? widget.group['product_id']) as int?;

    if (productId == null || curStatus.isEmpty || qty <= 0) {
      _snack('Impossible d’éditer ce groupe.');
      return;
    }

    final changed = await EditItemsDialog.show(
      context,
      productId: productId,
      status: curStatus,
      availableQty: qty,
      initialSample: {
        ...?_viewRow,
        if (_items.isNotEmpty) ..._items.first,
      },
    );

    if (changed == true) {
      _dirty = true;
      await _loadAll(); // refresh local
    }
  }

  // ===== Helpers KPIs =====

  List<Map<String, dynamic>> _filteredItems() {
    final f = (_localStatusFilter ?? '').toString();
    if (f.isEmpty) return _items;
    return _items.where((e) => (e['status'] ?? '') == f).toList();
  }

  num _sumNum(Iterable<dynamic> it) {
    num s = 0;
    for (final v in it) {
      final n = (v is num) ? v : num.tryParse(v?.toString() ?? '');
      if (n != null) s += n;
    }
    return s;
  }

  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _saleGroupKey(Map<String, dynamic> r) {
    // Clé “vente/commande” : modifie/élargis si nécessaire
    final sd = (r['sale_date'] ?? '').toString();
    final buyer = (r['buyer_company'] ?? '').toString();
    final trk = (r['tracking'] ?? '').toString();
    final ch = (r['channel_id'] ?? '').toString();
    // Si tout est vide -> on retournera '' (=pas de regroupement)
    return [sd, buyer, trk, ch].join('|').trim();
  }

  /// Somme Investi basée sur les ITEMS VISIBLES, en ne comptant les
  /// frais “par commande” (shipping/commission/grading) qu’une seule fois par commande.
  num _investedFromItems(List<Map<String, dynamic>> items) {
    num base = 0;
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final r in items) {
      base += (_asNum(r['unit_cost']) ?? 0) + (_asNum(r['unit_fees']) ?? 0);
      final key = _saleGroupKey(r);
      (groups[key] ??= <Map<String, dynamic>>[]).add(r);
    }

    num groupFees = 0;
    groups.forEach((key, list) {
      // Pas de clés -> on considère que les frais sont bien "par item"
      if (key.isEmpty) {
        for (final r in list) {
          groupFees += (_asNum(r['shipping_fees']) ?? 0) +
              (_asNum(r['commission_fees']) ?? 0) +
              (_asNum(r['grading_fees']) ?? 0);
        }
      } else {
        // Heuristique "une seule fois par commande"
        // on prend le MAX (et pas la somme) sur le groupe
        num maxShip = 0, maxComm = 0, maxGrad = 0;
        for (final r in list) {
          final s = _asNum(r['shipping_fees']) ?? 0;
          final c = _asNum(r['commission_fees']) ?? 0;
          final g = _asNum(r['grading_fees']) ?? 0;
          if (s > maxShip) maxShip = s;
          if (c > maxComm) maxComm = c;
          if (g > maxGrad) maxGrad = g;
        }
        groupFees += maxShip + maxComm + maxGrad;
      }
    });

    return base + groupFees;
  }

  bool _isRealized(String s) =>
      s == 'sold' || s == 'shipped' || s == 'finalized';

  @override
  Widget build(BuildContext context) {
    final status = (_localStatusFilter ??
            (_items.isNotEmpty
                ? (_items.first['status']?.toString())
                : widget.group['status']?.toString()) ??
            '')
        .toString();

    final visibleItems = _filteredItems();
    // marge moyenne (sur les items visibles qui ont une marge calculée)
    final soldMargins = visibleItems
        .map((e) => e['marge'] as num?)
        .where((m) => m != null)
        .cast<num>()
        .toList();

    final num? headerMargin = soldMargins.isEmpty
        ? null
        : (soldMargins.reduce((a, b) => a + b) / soldMargins.length);

    final qtyStatus = visibleItems.length;
    final currency = (_viewRow?['currency'] ??
            (_items.isNotEmpty ? _items.first['currency']?.toString() : null) ??
            widget.group['currency'] ??
            'USD')
        .toString();

    final qtyTotal = (_viewRow?['qty_total'] as num?) ?? qtyStatus;
    final totalWithFees = (_viewRow?['total_cost_with_fees'] as num?) ?? 0;
    final sumShipping = (_viewRow?['sum_shipping_fees'] as num?) ?? 0;
    final sumCommission = (_viewRow?['sum_commission_fees'] as num?) ?? 0;
    final sumGrading = (_viewRow?['sum_grading_fees'] as num?) ?? 0;

    final investedForView = _investedFromItems(visibleItems);

    // Σ estimated_price en traitant null comme 0
    final potential =
        _sumNum(visibleItems.map((e) => (e['estimated_price'] as num?) ?? 0));
    final realized = _sumNum(visibleItems.where((e) {
      final s = (e['status'] ?? '').toString();
      return _isRealized(s);
    }).map((e) => (e['sale_price'] as num?) ?? 0));

    final photoUrl =
        (_viewRow?['photo_url'] ?? widget.group['photo_url'])?.toString();
    final imageUrl =
        (photoUrl == null || photoUrl.isEmpty) ? kDefaultPhoto : photoUrl;

    // ===== THEME LOCAL (cosmétique) =====
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      // renvoie le flag au parent quand on quitte
      onWillPop: () async {
        Navigator.pop(context, _dirty);
        return false; // on consomme le pop
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _dirty),
          ),
          title: Text(
            _title.isEmpty ? 'Détails' : _title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'Modifier N items',
              icon: const Icon(Icons.edit),
              onPressed: visibleItems.isEmpty ? null : _onEditGroup,
            ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1, -1),
                end: Alignment(1, 1),
                colors: [
                  kAccentA, // plus punchy
                  kAccentB,
                ],
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    // HEADER
                    _Header(
                      title: _title,
                      subtitle: _subtitle,
                      status: status,
                      qty: qtyStatus,
                      onStatusSelected: (s) =>
                          setState(() => _localStatusFilter = s),
                      activeStatus: _localStatusFilter,
                      margin: headerMargin,
                    ),
                    const SizedBox(height: 12),

                    // === Photo (petite) à gauche + Overview à droite ===
                    LayoutBuilder(
                      builder: (ctx, cons) {
                        final wide = cons.maxWidth >= 760;

                        final info = {
                          ...?_viewRow,
                          if (_items.isNotEmpty) ..._items.first,
                        };
                        final uDoc = (info['document_url'] ?? '').toString();

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Colonne gauche : vignette + document banner
                              SizedBox(
                                width: 260,
                                child: Column(
                                  children: [
                                    _MediaThumb(
                                      imageUrl: imageUrl,
                                      onOpen: () async {
                                        if (imageUrl.isEmpty) return;
                                        final uri = Uri.tryParse(imageUrl);
                                        if (uri != null) {
                                          await launchUrl(uri,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    if (uDoc.isNotEmpty)
                                      InfoBanner(
                                        icon: Icons.description,
                                        message:
                                            'Document disponible — appuyez pour ouvrir',
                                        onTap: () async {
                                          final uri = Uri.tryParse(uDoc);
                                          if (uri != null) {
                                            await launchUrl(uri,
                                                mode: LaunchMode
                                                    .externalApplication);
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Colonne droite : Finance + Infos détaillées
                              Expanded(
                                child: Column(
                                  children: [
                                    FinanceSummary(
                                      currency: currency,
                                      investedForView: investedForView,
                                      potentialRevenue: potential,
                                      realizedRevenue: realized,
                                    ),
                                    const SizedBox(height: 12),
                                    InfoExtrasCard(
                                      data: info,
                                      currencyFallback: currency,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Empilé (mobile)
                          return Column(
                            children: [
                              _MediaThumb(
                                imageUrl: imageUrl,
                                onOpen: () async {
                                  if (imageUrl.isEmpty) return;
                                  final uri = Uri.tryParse(imageUrl);
                                  if (uri != null) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              if (uDoc.isNotEmpty)
                                InfoBanner(
                                  icon: Icons.description,
                                  message:
                                      'Document disponible — appuyez pour ouvrir',
                                  onTap: () async {
                                    final uri = Uri.tryParse(uDoc);
                                    if (uri != null) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                              const SizedBox(height: 12),
                              FinanceSummary(
                                currency: currency,
                                investedForView: investedForView,
                                potentialRevenue: potential,
                                realizedRevenue: realized,
                              ),
                              const SizedBox(height: 12),
                              InfoExtrasCard(
                                data: info,
                                currencyFallback: currency,
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // ====== TABLE / LISTE ITEMS avec toggle ======
                    Row(
                      children: [
                        Text('Items',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: _showItemsTable ? 'Masquer' : 'Afficher',
                          icon: Icon(_showItemsTable
                              ? Icons.expand_less
                              : Icons.expand_more),
                          onPressed: () => setState(
                              () => _showItemsTable = !_showItemsTable),
                        ),
                      ],
                    ),
                    if (_showItemsTable)
                      _ItemsTable(
                        items: visibleItems,
                        currency: currency,
                      ),
                    const SizedBox(height: 16),

                    // ====== HISTORIQUE avec toggle ======
                    Row(
                      children: [
                        Text('Historique complet',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        IconButton(
                          tooltip: _showHistory ? 'Masquer' : 'Afficher',
                          icon: Icon(_showHistory
                              ? Icons.expand_less
                              : Icons.expand_more),
                          onPressed: () =>
                              setState(() => _showHistory = !_showHistory),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_showHistory) HistoryList(movements: _movements),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Header avec un soupçon de couleur
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.qty,
    required this.onStatusSelected,
    required this.activeStatus,
    this.margin,
  });

  final String title;
  final String subtitle;
  final String status;
  final int qty;
  final ValueChanged<String?> onStatusSelected;
  final String? activeStatus;
  final num? margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0.8,
      color: cs.surface,
      shadowColor: kAccentA.withOpacity(.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-1, 0),
            end: Alignment(1, 0),
            colors: [kAccentA, kAccentB],
          ).scale(0.08), // subtil
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: kAccentA,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.inventory_2, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? 'Détails' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(status.toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                        backgroundColor: kAccentB,
                      ),
                      Chip(
                        avatar: const Icon(Icons.format_list_numbered,
                            size: 16, color: Colors.white),
                        label: Text('Qté : $qty',
                            style: const TextStyle(color: Colors.white)),
                        backgroundColor: kAccentC,
                      ),
                      Tooltip(
                        message:
                            margin == null ? 'Not sold yet' : 'Marge moyenne',
                        child: MarginChip(marge: margin),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vignette média avec overlay coloré discret
class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.imageUrl, this.onOpen});
  final String imageUrl;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0.8,
      shadowColor: kAccentA.withOpacity(.12),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 3 / 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  imageUrl.isEmpty ? kDefaultPhoto : imageUrl,
                  fit: BoxFit.cover,
                ),
                // voile léger pour la lisibilité
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        kAccentA.withOpacity(.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                if (onOpen != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: kAccentB.withOpacity(.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.open_in_new,
                              size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Ouvrir',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tableau des items avec zébrage + accents
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items, required this.currency});
  final List<Map<String, dynamic>> items;
  final String currency;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();
  String _m(num? n) => n == null ? '—' : n.toDouble().toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Text('Aucun item dans ce groupe.',
          style: Theme.of(context).textTheme.bodyMedium);
    }

    return Card(
      elevation: 0.6,
      color: cs.surface,
      shadowColor: kAccentA.withOpacity(.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 42,
            dataRowMinHeight: 44,
            columnSpacing: 20,
            headingRowColor:
                MaterialStateProperty.all(kAccentA.withOpacity(.08)),
            headingTextStyle: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            dividerThickness: .6,
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Grade ID')),
              DataColumn(label: Text('Grade note')),
              DataColumn(label: Text('Grading fees')),
              DataColumn(label: Text('Est.')),
              DataColumn(label: Text('Sale')),
              DataColumn(label: Text('Marge')), // ⬅️ nouveau
              DataColumn(label: Text('Tracking')),
              DataColumn(label: Text('Buyer')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Photo')),
              DataColumn(label: Text('Doc')),
            ],
            rows: List<DataRow>.generate(items.length, (i) {
              final r = items[i];
              final est = (r['estimated_price'] as num?);
              final sale = (r['sale_price'] as num?);
              final marge = (r['marge'] as num?);

              final s = (r['status'] ?? '').toString();
              final photo = (r['photo_url'] ?? '').toString();
              final doc = (r['document_url'] ?? '').toString();
              final bg = (i % 2 == 0) ? cs.surface : cs.surfaceContainerHighest;
              return DataRow(
                color: MaterialStateProperty.all(bg.withOpacity(.50)),
                cells: [
                  DataCell(Text('${r['id']}')),
                  DataCell(Chip(
                    label: Text(s.toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                    backgroundColor: _statusColor(s),
                  )),
                  DataCell(Text(_txt(r['grade_id']))),
                  DataCell(Text(_txt(r['grading_note']))),
                  DataCell(Text(_txt(r['grading_fees']))),
                  DataCell(Text(est == null ? '—' : '${_m(est)} $currency')),
                  DataCell(Text(sale == null ? '—' : '${_m(sale)} $currency')),
                  DataCell(MarginChip(marge: marge)), // ⬅️ nouveau
                  DataCell(Text(_txt(r['tracking']))),
                  DataCell(Text(_txt(r['buyer_company']))),
                  DataCell(Text(_txt(r['supplier_name']))),
                  DataCell(_MiniLinkIcon(url: photo, icon: Icons.photo)),
                  DataCell(_MiniLinkIcon(url: doc, icon: Icons.description)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Couleur de chip par statut (visuel uniquement)
  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'received':
        return kAccentB;
      case 'listed':
        return kAccentA;
      case 'sold':
      case 'shipped':
      case 'finalized':
        return const Color(0xFF22C55E); // green
      case 'in_transit':
        return const Color(0xFF3B82F6); // blue
      case 'at_grader':
      case 'graded':
        return const Color(0xFFa855f7); // purple
      default:
        return kAccentC; // amber
    }
  }
}

class _MiniLinkIcon extends StatelessWidget {
  const _MiniLinkIcon({required this.url, required this.icon});
  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const Text('—');
    return IconButton(
      tooltip: 'Ouvrir',
      icon: Icon(icon, color: kAccentA),
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
