// ignore_for_file: unused_local_variable, deprecated_member_use
/* Rôle : écran “Détails” (StatefulWidget).
   Charge les items d’un groupe, l’historique, et compose l’UI. */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../inventory/widgets/edit.dart' show EditItemsDialog;

// Widgets existants
import 'widgets/history_list.dart';
import 'widgets/info_extras_card.dart';
import 'widgets/info_banner.dart';

// Widgets factorisés
import 'widgets/details_header.dart';
import 'widgets/media_thumb.dart';
import 'widgets/items_table.dart';

// Service (helpers)
import 'details_service.dart';

// KPI factorisé
import '../../inventory/widgets/finance_overview.dart';

/// Image par défaut locale (asset) si `photo_url` manquante
const String kDefaultAssetPhoto = 'assets/images/default_card.png';

/// Palette locale
const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

/// Colonnes utiles de la vue agrégée
const List<String> kViewCols = [
  'org_id',
  'group_sig',
  'type',
  'status',
  'product_id',
  'product_name',
  'game_id',
  'game_code',
  'game_label',
  'language',
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
  'item_location',
  'channel_id',
  'payment_type',
  'buyer_infos',
  'qty_status',
  'total_cost_with_fees',
  'sum_shipping_fees',
  'sum_commission_fees',
  'sum_grading_fees',
];

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({super.key, required this.group, this.orgId});
  final Map<String, dynamic> group;
  final String? orgId;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _viewRow; // ligne représentative (vue agrégée)
  List<Map<String, dynamic>> _items = []; // items du groupe (table item)
  List<Map<String, dynamic>> _movements = []; // historique movements

  String? _localStatusFilter; // pour l’affichage
  bool _showItemsTable = true;
  bool _showHistory = true;
  bool _dirty = false; // indique si modification effectuée

  Map<String, dynamic> get _initial => widget.group;

  String? get _orgIdFromContext {
    final v = (widget.orgId ?? widget.group['org_id'])?.toString();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  String get _title =>
      (_viewRow?['product_name'] ?? _initial['product_name'] ?? '').toString();

  String get _subtitle {
    final game =
        (_viewRow?['game_label'] ?? _initial['game_label'] ?? '').toString();
    final lang =
        (_viewRow?['language'] ?? _initial['language'] ?? '').toString();
    final type = (_viewRow?['type'] ?? _initial['type'] ?? '').toString();
    return [game, lang, if (type.isNotEmpty) type]
        .where((e) => e.isNotEmpty)
        .join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // 1) Résoudre org/group_sig/status de manière fiable
      String? orgId = _orgIdFromContext;
      String? sig = (widget.group['group_sig']?.toString().isNotEmpty ?? false)
          ? widget.group['group_sig'].toString()
          : null;
      String? clickedStatus = (widget.group['status'] ?? '').toString();
      final int? clickedId = (widget.group['id'] as num?)?.toInt();
      final int? pid = (widget.group['product_id'] as num?)?.toInt();

      if (clickedId != null) {
        // Source de vérité: item
        final probe = await _sb
            .from('item')
            .select('org_id, group_sig, status, product_id')
            .eq('id', clickedId)
            .maybeSingle();
        if (probe != null) {
          orgId = (probe['org_id']?.toString().isNotEmpty ?? false)
              ? probe['org_id'].toString()
              : orgId;
          if (probe['group_sig'] != null &&
              probe['group_sig'].toString().isNotEmpty) {
            sig = probe['group_sig'].toString();
          }
          clickedStatus = (probe['status'] ?? clickedStatus)?.toString();
        }
      }

      // Si pas encore de sig mais on a org + product (+ éventuellement status),
      // on va chercher 1 item pour récupérer la sig (secours).
      if (sig == null && orgId != null && pid != null) {
        var q = _sb
            .from('item')
            .select('group_sig')
            .eq('org_id', orgId)
            .eq('product_id', pid);
        if ((clickedStatus ?? '').isNotEmpty)
          q = q.eq('status', clickedStatus as Object);
        final probe =
            await q.order('id', ascending: false).limit(1).maybeSingle();
        if (probe != null &&
            (probe['group_sig']?.toString().isNotEmpty ?? false)) {
          sig = probe['group_sig'].toString();
        }
      }

      List<Map<String, dynamic>> items = [];

      if (sig != null && orgId != null) {
        // 2) CHEMIN STRICT: par signature de groupe
        const itemCols = [
          'id',
          'org_id',
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
          'estimated_price',
          'item_location',
          'shipping_fees',
          'commission_fees',
          'payment_type',
          'buyer_infos',
          'marge',
          'group_sig',
        ];

        final raw = await _sb
            .from('item')
            .select(itemCols.join(','))
            .eq('org_id', orgId)
            .eq('group_sig', sig)
            .order('id', ascending: true);

        items = List<Map<String, dynamic>>.from(
          (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );

        // Vue agrégée pour l’entête/carte infos
        Map<String, dynamic>? viewRow;
        try {
          final vr = await _sb
              .from('v_item_groups')
              .select(kViewCols.join(','))
              .eq('org_id', orgId)
              .eq('group_sig', sig)
              .limit(1)
              .maybeSingle();
          if (vr != null) viewRow = Map<String, dynamic>.from(vr);
        } catch (_) {}

        // Fallback viewRow si la vue ne renvoie rien
        viewRow ??= {
          if (items.isNotEmpty) ...items.first,
          ..._initial,
          'group_sig': sig,
          'org_id': orgId,
        };

        // Status cohérent (tous les items d’une sig ont le même)
        final detectedStatus = items.isNotEmpty
            ? (items.first['status'] ?? '').toString()
            : (clickedStatus);

        _localStatusFilter = (detectedStatus ?? '').toString();

        final hist = await DetailsService.fetchHistoryForItems(
          _sb,
          items.map((e) => e['id'] as int).toList(),
        );

        setState(() {
          _viewRow = viewRow;
          _items = items;
          _movements = hist;
        });
        return;
      }

      // 3) ULTIME secours: on tente tout le produit (peu probable maintenant)
      if (pid != null) {
        final raw = await _sb
            .from('item')
            .select('*')
            .eq('product_id', pid)
            .order('id', ascending: true);
        items = (raw as List)
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      if (items.isEmpty) {
        setState(() {
          _items = const [];
          _movements = const [];
          _viewRow = _initial;
        });
        return;
      }

      _localStatusFilter = (items.first['status'] ?? '').toString();

      final hist = await DetailsService.fetchHistoryForItems(
        _sb,
        items.map((e) => e['id'] as int).toList(),
      );

      setState(() {
        _viewRow = {..._initial, ...items.first};
        _items = items;
        _movements = hist;
      });
    } catch (e) {
      _snack('Erreur chargement détails : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _onEditGroup() async {
    final curStatus = (_items.isNotEmpty
            ? (_items.first['status'] ?? '').toString()
            : (_localStatusFilter ?? widget.group['status'] ?? ''))
        .toString();

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
        if (_items.isNotEmpty && _items.first['group_sig'] != null)
          'group_sig': _items.first['group_sig'],
      },
    );

    if (changed == true) {
      _dirty = true;
      await _loadAll();
    }
  }

  // Helpers d’affichage
  List<Map<String, dynamic>> _filteredItems() {
    final f = (_localStatusFilter ?? '').toString();
    if (f.isEmpty) return _items;
    return _items.where((e) => (e['status'] ?? '') == f).toList();
  }

  @override
  Widget build(BuildContext context) {
    final status = (_localStatusFilter ??
            (_items.isNotEmpty
                ? (_items.first['status']?.toString())
                : widget.group['status']?.toString()) ??
            '')
        .toString();

    final visibleItems = _filteredItems();

    // marge moyenne pour le header
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

    final photoUrl =
        (_viewRow?['photo_url'] ?? widget.group['photo_url'])?.toString();
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final displayImageUrl = hasPhoto ? photoUrl : kDefaultAssetPhoto;

    final info = {
      ...?_viewRow,
      if (_items.isNotEmpty) ..._items.first,
    };
    final uDoc = (info['document_url'] ?? '').toString();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _dirty);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _dirty),
          ),
          actions: [
            IconButton(
              tooltip: 'Modifier N items',
              icon: const Icon(Icons.edit),
              onPressed: visibleItems.isEmpty ? null : _onEditGroup,
            ),
          ],
          flexibleSpace: const _AppbarGradient(),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    DetailsHeader(
                      title: _title,
                      subtitle: _subtitle,
                      status: status,
                      qty: qtyStatus,
                      margin: headerMargin,
                      historyEvents: _movements,
                      historyTitle: 'Journal des sauvegardes',
                      historyCount: _movements.length,
                    ),

                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (ctx, cons) {
                        final wide = cons.maxWidth >= 760;

                        final finance = FinanceOverview(
                          items: visibleItems,
                          currency: currency,
                          titleInvested: 'Investi (vue)',
                          titleEstimated: 'Valeur estimée',
                          titleSold: 'Revenu réel',
                          subtitleInvested: 'Σ coûts (items non vendus)',
                          subtitleEstimated: 'Σ estimated_price (non vendus)',
                          subtitleSold: 'Σ sale_price (vendus)',
                        );

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 320,
                                child: Column(
                                  children: [
                                    MediaThumb(
                                      imageUrl: displayImageUrl,
                                      isAsset: !hasPhoto,
                                      aspectRatio: 0.72,
                                      onOpen: hasPhoto
                                          ? () async {
                                              final uri =
                                                  Uri.tryParse(photoUrl);
                                              if (uri != null) {
                                                await launchUrl(uri,
                                                    mode: LaunchMode
                                                        .externalApplication);
                                              }
                                            }
                                          : null,
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
                              Expanded(
                                child: Column(
                                  children: [
                                    finance,
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
                          return Column(
                            children: [
                              MediaThumb(
                                imageUrl: displayImageUrl,
                                isAsset: !hasPhoto,
                                aspectRatio: 0.72,
                                onOpen: hasPhoto
                                    ? () async {
                                        final uri = Uri.tryParse(photoUrl);
                                        if (uri != null) {
                                          await launchUrl(uri,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      }
                                    : null,
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
                              finance,
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

                    // Items
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
                      ItemsTable(items: visibleItems, currency: currency),

                    const SizedBox(height: 16),

                    // Historique
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

class _AppbarGradient extends StatelessWidget {
  const _AppbarGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [kAccentA, kAccentB],
        ),
      ),
    );
  }
}
