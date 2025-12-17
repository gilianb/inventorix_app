// lib/details/details_page.dart
// ignore_for_file: unused_local_variable, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../inventory/widgets/edit.dart' show EditItemsDialog;

import 'widgets/info_extras_card.dart';

import 'widgets/details_header.dart';
import 'widgets/media_thumb.dart';
import 'widgets/items_table.dart';
import 'widgets/price_trends.dart';
import 'widgets/qr_line_button.dart'; // <-- QR widget
import 'widgets/price_history_chart.dart'; // <-- graph historique

import 'widgets/details_overview_panel.dart';
import 'widgets/details_section_header.dart';
import 'widgets/details_status_filter_bar.dart';

import 'details_service.dart';
import '../../inventory/widgets/finance_overview.dart';
import '../inventory/utils/fx_to_usd.dart';
import '../public/public_item_page.dart'; // <-- Aperçu public (NOUVEAU)

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

// invoicing
import 'package:inventorix_app/invoicing/invoice_actions.dart';
import 'package:inventorix_app/invoicing/ui/invoice_create_dialog.dart';
import 'package:inventorix_app/invoicing/ui/attach_purchase_invoice_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const String kDefaultAssetPhoto = 'assets/images/default_card.png';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

// Base URL publique (racine du site web — /i/<token> sera ajouté)
const String kPublicQrBaseUrl = 'https://inventorix-web.vercel.app';

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
  bool _roleLoaded = false;
  bool _isOwner = false;

  Map<String, dynamic>? _viewRow;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _movements = [];

  /// Toutes les invoices liées aux items visibles (sale + purchase)
  List<Map<String, dynamic>> _relatedInvoices = [];

  String? _localStatusFilter;
  bool _showItemsTable = false;
  bool _dirty = false;

  Map<String, dynamic>? _productExtras; // { blueprint_id, tcg_player_id }
  int _trendsReloadTick = 0;

  // ==== Realtime ====
  RealtimeChannel? _rtChannel;
  Timer? _softReloadDebounce;
  String? _subOrgId;
  String? _subGroupSig;

  // ==== OVERRIDES collants (après edit) ====
  String? _ovOrgId;
  String? _ovGroupSig;
  String? _ovStatus;
  int? _ovAnchorItemId;

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
    unawaited(_loadRole());
    _loadAll();
  }

  @override
  void dispose() {
    try {
      _rtChannel?.unsubscribe();
    } catch (_) {}
    _softReloadDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      final orgId = _orgIdFromContext;
      if (uid == null || orgId == null) {
        setState(() {
          _roleLoaded = true;
          _isOwner = false;
        });
        return;
      }

      Map<String, dynamic>? mem;
      try {
        mem = await _sb
            .from('organization_member')
            .select('role')
            .eq('org_id', orgId)
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {}

      var isOwner = (mem?['role']?.toString().toLowerCase() == 'owner');

      if (!isOwner) {
        try {
          final org = await _sb
              .from('organization')
              .select('created_by')
              .eq('id', orgId)
              .maybeSingle();
          if ((org?['created_by'] as String?) == uid) isOwner = true;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isOwner = isOwner;
          _roleLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _roleLoaded = true;
          _isOwner = false;
        });
      }
    }
  }

  // ---------- Realtime helpers ----------

  void _scheduleSoftReload() {
    _softReloadDebounce?.cancel();
    _softReloadDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _loadAll();
    });
  }

  void _subscribeToGroup({required String orgId, required String groupSig}) {
    if (_subOrgId == orgId && _subGroupSig == groupSig && _rtChannel != null) {
      return; // déjà abonné au bon couple
    }

    try {
      _rtChannel?.unsubscribe();
    } catch (_) {}
    _rtChannel = null;

    final ch = _sb.channel('grp:$orgId:$groupSig');

    // Pas de filter param (compat SDK). On filtre dans le callback.
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'item',
      callback: (payload) {
        final newRec = Map<String, dynamic>.from(payload.newRecord);
        final oldRec = Map<String, dynamic>.from(payload.oldRecord);

        bool match(Map<String, dynamic> r) =>
            (r['org_id']?.toString() == orgId) &&
            (r['group_sig']?.toString() == groupSig);

        if (match(newRec) || match(oldRec)) {
          _scheduleSoftReload();
        }
      },
    );

    ch.subscribe();

    _rtChannel = ch;
    _subOrgId = orgId;
    _subGroupSig = groupSig;
  }

  // ---------- Helpers de sélection de status ----------

  String _resolveStatusFilter(
    List<Map<String, dynamic>> items, {
    String? previous,
    String? preferred,
  }) {
    final statuses = items
        .map((e) => (e['status'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    if (preferred != null && statuses.contains(preferred)) return preferred;
    if (previous != null && statuses.contains(previous)) return previous;

    const order = [
      'finalized',
      'shipped',
      'sold',
      'awaiting_payment',
      'listed',
      'graded',
      'at_grader',
      'sent_to_grader',
      'waiting_for_gradation',
      'received',
      'in_transit',
      'paid',
      'ordered',
    ];
    for (final s in order) {
      if (statuses.contains(s)) return s;
    }
    return statuses.isNotEmpty ? statuses.first : '';
  }

  String? _statusOfItem(List<Map<String, dynamic>> items, int id) {
    final r = items.cast<Map<String, dynamic>?>().firstWhere(
          (e) => ((e?['id'] as num?)?.toInt() == id),
          orElse: () => null,
        );
    final s = (r?['status'] ?? '').toString();
    return s.isNotEmpty ? s : null;
  }

  // ---------- Helpers marge dérivée (fallback) ----------

  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _normCur(dynamic v, {String fallback = ''}) {
    final s = (v ?? fallback).toString().trim().toUpperCase();
    return s;
  }

  /// ✅ IMPORTANT (PATCH FX)
  /// - Si la DB a calculé `marge`, on la prend (source of truth).
  /// - Si `marge` est null ET que purchase currency != sale currency,
  ///   on NE calcule PAS côté Flutter (sinon résultat faux sans conversion FX).
  /// - On garde un fallback Flutter uniquement quand les devises sont identiques
  ///   (utile pour anciens rows / cas simples).
  num? _derivedMarginPct(Map<String, dynamic> r) {
    final num? m = _asNum(r['marge']);
    if (m != null) return m;

    final status = (r['status'] ?? '').toString().toLowerCase();
    if (!['sold', 'shipped', 'finalized'].contains(status)) return null;

    final num? sale = _asNum(r['sale_price']);
    if (sale == null || sale == 0) return null;

    final purchaseCur = _normCur(r['currency']);
    final saleCur = _normCur(
      r['sale_currency'] ?? r['sale_price_currency'] ?? r['sale_currency_code'],
      fallback: purchaseCur,
    );

    // 🔒 Si devises différentes -> marge doit venir de la DB (avec FX), sinon null.
    if (purchaseCur.isNotEmpty &&
        saleCur.isNotEmpty &&
        purchaseCur != saleCur) {
      return null;
    }

    final num cost =
        (_asNum(r['unit_cost']) ?? 0) + (_asNum(r['unit_fees']) ?? 0);
    final num fees = (_asNum(r['shipping_fees']) ?? 0) +
        (_asNum(r['commission_fees']) ?? 0) +
        (_asNum(r['grading_fees']) ?? 0);
    final num invested = cost + fees;

    if (invested <= 0) return null;

    return ((sale - invested) / invested) * 100;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // 🔑 utilise d'abord les OVERRIDES collants si présents
      String? orgId = _ovOrgId ?? _orgIdFromContext;
      String? sig = _ovGroupSig ??
          ((widget.group['group_sig']?.toString().isNotEmpty ?? false)
              ? widget.group['group_sig'].toString()
              : null);
      String? clickedStatus =
          _ovStatus ?? (widget.group['status'] ?? '').toString();
      final int? clickedId =
          _ovAnchorItemId ?? (widget.group['id'] as num?)?.toInt();
      final int? pidFromWidget = (widget.group['product_id'] as num?)?.toInt();

      int? pidEff = pidFromWidget;

      if (clickedId != null) {
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
          final pidProbe = (probe['product_id'] as num?)?.toInt();
          if (pidProbe != null) pidEff = pidProbe;
        }
      }

      if (sig == null && orgId != null && pidEff != null) {
        var q = _sb
            .from('item')
            .select('group_sig')
            .eq('org_id', orgId)
            .eq('product_id', pidEff);
        if ((clickedStatus ?? '').isNotEmpty) {
          q = q.eq('status', clickedStatus as Object);
        }
        final probe =
            await q.order('id', ascending: false).limit(1).maybeSingle();
        if (probe != null &&
            (probe['group_sig']?.toString().isNotEmpty ?? false)) {
          sig = probe['group_sig'].toString();
        }
      }

      List<Map<String, dynamic>> items = [];
      List<Map<String, dynamic>> relatedInvoices = [];

      if (sig != null && orgId != null) {
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
          'sale_currency', // ✅ devise liée à sale_price
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
          'public_token', // <-- IMPORTANT pour QR stable
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

        viewRow ??= {
          if (items.isNotEmpty) ...items.first,
          ..._initial,
          'group_sig': sig,
          'org_id': orgId,
        };

        pidEff = (viewRow['product_id'] as num?)?.toInt() ??
            pidEff ??
            (items.isNotEmpty
                ? (items.first['product_id'] as num?)?.toInt()
                : null);

        final hist = await DetailsService.fetchHistoryForItems(
          _sb,
          items.map((e) => e['id'] as int).toList(),
        );

        _productExtras = await _fetchProductExtras(pidEff);

        // Invoices liées (sale + purchase) pour les items
        relatedInvoices = await _fetchRelatedInvoices(orgId, items);

        // (Re)subscribe au couple (orgId,sig)
        _subscribeToGroup(orgId: orgId, groupSig: sig);

        // Statut pertinent
        final previous = _localStatusFilter;
        final focusStatus =
            (clickedId != null) ? _statusOfItem(items, clickedId) : null;
        final preferred = (focusStatus ?? clickedStatus)?.toString();
        _localStatusFilter = _resolveStatusFilter(
          items,
          previous: previous,
          preferred: preferred,
        );

        // 🔒 Met à jour les overrides “collants”
        _ovOrgId = orgId;
        _ovGroupSig = sig;
        _ovStatus = _localStatusFilter;
        _ovAnchorItemId = (items.isNotEmpty)
            ? (items.first['id'] as num?)?.toInt()
            : _ovAnchorItemId;

        setState(() {
          _viewRow = viewRow;
          _items = items;
          _movements = hist;
          _relatedInvoices = relatedInvoices;
          _trendsReloadTick++;
        });
        return;
      }

      if (pidEff != null) {
        final raw = await _sb
            .from('item')
            .select('*')
            .eq('product_id', pidEff)
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
          _productExtras = null;
          _relatedInvoices = const [];
          _trendsReloadTick++;
        });
        return;
      }

      // Même logique de filtre ici aussi
      final previous = _localStatusFilter;
      final focusStatus =
          (clickedId != null) ? _statusOfItem(items, clickedId) : null;
      final preferred = (focusStatus ?? clickedStatus)?.toString();
      _localStatusFilter = _resolveStatusFilter(
        items,
        previous: previous,
        preferred: preferred,
      );

      final hist = await DetailsService.fetchHistoryForItems(
        _sb,
        items.map((e) => e['id'] as int).toList(),
      );

      final pid = pidEff ?? (items.first['product_id'] as num?)?.toInt();
      _productExtras = await _fetchProductExtras(pid);

      // Invoices liées dans ce cas (on déduit org depuis le 1er item)
      final effOrgId = orgId ?? items.first['org_id']?.toString();
      if (effOrgId != null) {
        relatedInvoices = await _fetchRelatedInvoices(effOrgId, items);
      }

      // 🔒 Coller aussi ici
      _ovOrgId = items.first['org_id']?.toString();
      _ovGroupSig = items.first['group_sig']?.toString();
      _ovStatus = _localStatusFilter;
      _ovAnchorItemId = (items.first['id'] as num?)?.toInt();

      setState(() {
        _viewRow = {..._initial, ...items.first};
        _items = items;
        _movements = hist;
        _relatedInvoices = relatedInvoices;
        _trendsReloadTick++;
      });
    } catch (e) {
      _snack('Error loading details: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchProductExtras(int? productId) async {
    if (productId == null) return null;
    try {
      final p = await _sb
          .from('product')
          .select('blueprint_id, tcg_player_id')
          .eq('id', productId)
          .maybeSingle();

      if (p != null) {
        return {
          'blueprint_id': (p['blueprint_id'] as num?)?.toInt(),
          'tcg_player_id': p['tcg_player_id']?.toString(),
        };
      }
    } catch (_) {}
    return null;
  }

  /// Charge toutes les invoices (sale + purchase) liées aux items donnés.
  ///
  /// - Purchase: via invoice.related_item_id
  /// - Sales (single & multi-items): via invoice_line.item_id
  Future<List<Map<String, dynamic>>> _fetchRelatedInvoices(
    String orgId,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return [];
    final itemIds =
        items.map((e) => (e['id'] as num?)?.toInt()).whereType<int>().toList();
    if (itemIds.isEmpty) return [];

    final List<Map<String, dynamic>> result = [];

    // 1) Invoices liées directement à un item (PURCHASE + anciennes SALES 1-item)
    final directRows = await _sb
        .from('invoice')
        .select(
          'id, invoice_type, status, invoice_number, document_url, related_item_id',
        )
        .eq('org_id', orgId)
        .inFilter('related_item_id', itemIds);

    for (final r in (directRows as List)) {
      result.add(Map<String, dynamic>.from(r as Map));
    }

    // 2) Invoices liées via invoice_line (SALES multi-items ou même single)
    final lineRows = await _sb
        .from('invoice_line')
        .select(
          'item_id, invoice:invoice(id, invoice_type, status, invoice_number, document_url, related_item_id)',
        )
        .inFilter('item_id', itemIds);

    final Map<int, Map<String, dynamic>> byInvoiceId = {
      for (final r in result)
        if (r['id'] != null) (r['id'] as int): r,
    };

    for (final r in (lineRows as List)) {
      final map = Map<String, dynamic>.from(r as Map);
      final inv = map['invoice'] as Map<String, dynamic>?;
      if (inv == null) continue;

      final int invId = (inv['id'] as num).toInt();
      if (byInvoiceId.containsKey(invId)) {
        continue; // déjà ajouté depuis les directRows
      }

      final merged = <String, dynamic>{
        ...inv,
        'related_item_id': inv['related_item_id'],
        'line_item_id': map['item_id'],
      };
      byInvoiceId[invId] = merged;
    }

    return byInvoiceId.values.toList();
  }

  Map<String, dynamic>? _firstInvoiceOfType(String type) {
    for (final inv in _relatedInvoices) {
      final t = (inv['invoice_type'] ?? '').toString();
      final doc = (inv['document_url'] ?? '').toString();
      if (t == type && doc.isNotEmpty) return inv;
    }
    return null;
  }

  Future<void> _openInvoiceDocument(String documentUrl) async {
    if (documentUrl.startsWith('http://') ||
        documentUrl.startsWith('https://')) {
      final uri = Uri.tryParse(documentUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    final fullPath = documentUrl;
    final pathInBucket = fullPath.replaceFirst('invoices/', '');

    try {
      if (kIsWeb) {
        final signedUrl = await _sb.storage
            .from('invoices')
            .createSignedUrl(pathInBucket, 60);

        final uri = Uri.tryParse(signedUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _snack('Invalid PDF URL');
        }
      } else {
        final bytes = await _sb.storage.from('invoices').download(pathInBucket);
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (e) {
      _snack('Error opening document: $e');
    }
  }

  Widget _buildInvoiceDocButtons(String uDocFallback) {
    final saleInv = _firstInvoiceOfType('sale');
    final purchaseInv = _firstInvoiceOfType('purchase');

    final saleDoc = (saleInv?['document_url'] ?? '').toString();
    final purchaseDoc = (purchaseInv?['document_url'] ?? '').toString();

    final hasSale = saleDoc.isNotEmpty;
    final hasPurchase = purchaseDoc.isNotEmpty;
    final hasFallback = !hasSale && !hasPurchase && uDocFallback.isNotEmpty;

    if (!hasSale && !hasPurchase && !hasFallback) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (hasSale)
          _InvoiceDocButton(
            label: 'Sales invoice',
            icon: Icons.receipt_long,
            onPressed: () => _openInvoiceDocument(saleDoc),
          ),
        if (hasPurchase)
          _InvoiceDocButton(
            label: 'Purchase invoice',
            icon: Icons.shopping_bag_outlined,
            onPressed: () => _openInvoiceDocument(purchaseDoc),
          ),
        if (!hasSale && !hasPurchase && hasFallback)
          _InvoiceDocButton(
            label: 'Main document',
            icon: Icons.description,
            onPressed: () => _openInvoiceDocument(uDocFallback),
          ),
      ],
    );
  }

  Map<String, dynamic> _maskUnitInMap(Map<String, dynamic> m) {
    if (_isOwner) return m;
    final c = Map<String, dynamic>.from(m);
    for (final k in const [
      'marge',
    ]) {
      if (c.containsKey(k)) c[k] = null;
    }
    return c;
  }

  List<Map<String, dynamic>> _maskUnitInList(List<Map<String, dynamic>> list) {
    if (_isOwner) return list;
    return list.map(_maskUnitInMap).toList(growable: false);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _onEditGroup() async {
    final anchorId =
        (_items.isNotEmpty ? (_items.first['id'] as num?)?.toInt() : null);

    final curStatus = (_localStatusFilter ??
            (_items.isNotEmpty
                ? (_items.first['status'] ?? '').toString()
                : (widget.group['status'] ?? '').toString()))
        .toString();

    final qty = _items.where((e) => (e['status'] ?? '') == curStatus).length;
    final productId =
        (_viewRow?['product_id'] ?? widget.group['product_id']) as int?;

    if (productId == null || curStatus.isEmpty || qty <= 0) {
      _snack('Unable to edit this group.');
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

      if (anchorId != null) {
        try {
          final p = await _sb
              .from('item')
              .select('org_id, group_sig, status, product_id')
              .eq('id', anchorId)
              .maybeSingle();

          if (p != null) {
            _ovOrgId = p['org_id']?.toString();
            _ovGroupSig = p['group_sig']?.toString();
            _ovStatus = (p['status'] ?? '').toString();
            _ovAnchorItemId = anchorId;
          }
        } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 160));
      await _loadAll();
    }
  }

  List<Map<String, dynamic>> _filteredItems() {
    final f = (_localStatusFilter ?? '').toString();
    if (f.isEmpty) return _items;
    return _items.where((e) => (e['status'] ?? '') == f).toList();
  }

  Map<String, int> _statusCounts(List<Map<String, dynamic>> items) {
    final m = <String, int>{};
    for (final it in items) {
      final s = (it['status'] ?? '').toString();
      if (s.isEmpty) continue;
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }

  // ----- Helpers QR par token -----

  String? _firstVisiblePublicToken() {
    final it = _filteredItems();
    if (it.isNotEmpty) {
      final t = (it.first['public_token'] ?? '').toString();
      if (t.isNotEmpty) return t;
    }
    if (_items.isNotEmpty) {
      final t = (_items.first['public_token'] ?? '').toString();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  String _buildItemPublicUrl(String token) {
    final base = kPublicQrBaseUrl.endsWith('/')
        ? kPublicQrBaseUrl.substring(0, kPublicQrBaseUrl.length - 1)
        : kPublicQrBaseUrl;
    return '$base/i/$token';
  }

  String _buildItemAppDeepLink(String token) => 'inventorix://i/$token';

  // ===================== INVOICING ACTIONS =====================

  Future<void> _onCreateInvoiceForGroup() async {
    final orgId = _orgIdFromContext;
    if (orgId == null) {
      _snack('Missing organization id.');
      return;
    }

    if (_items.isEmpty) {
      _snack('No items available for this group.');
      return;
    }

    // Helper: sale currency (lié uniquement à sale_price)
    String saleCurrencyOf(Map<String, dynamic> it) {
      final raw = (it['sale_currency'] ??
              it['sale_price_currency'] ??
              it['sale_currency_code'])
          ?.toString()
          .trim();
      if (raw != null && raw.isNotEmpty) return raw;

      // fallback “historique”: si pas de sale_currency, on garde l’ancienne devise item
      final cur =
          (it['currency'] ?? _viewRow?['currency'] ?? 'USD').toString().trim();
      return cur.isEmpty ? 'USD' : cur;
    }

    // 1) On prend d’abord les items filtrés par status (vue actuelle)
    List<Map<String, dynamic>> candidates = _filteredItems();
    if (candidates.isEmpty) {
      candidates = List<Map<String, dynamic>>.from(_items);
    }

    // 2) On ne garde que ceux qui ont un sale_price (donc vendus)
    candidates = candidates
        .where((e) => e['sale_price'] != null)
        .toList(growable: false);

    if (candidates.isEmpty) {
      _snack('No sold items (with sale_price) in this group.');
      return;
    }

    // ✅ MULTI-DEVISE (lié à sale_price) :
    // Une facture ne doit PAS mélanger plusieurs devises de vente.
    final preferredSaleCurrency = saleCurrencyOf(candidates.first);

    final saleCurrencySet = candidates.map((e) => saleCurrencyOf(e)).toSet();

    if (saleCurrencySet.length > 1) {
      final before = candidates.length;
      candidates = candidates
          .where((e) => saleCurrencyOf(e) == preferredSaleCurrency)
          .toList(growable: false);

      final skipped = before - candidates.length;
      if (skipped > 0) {
        _snack(
          'Multiple sale currencies detected. Invoicing only $preferredSaleCurrency ($skipped item(s) skipped).',
        );
      }
    }

    if (candidates.isEmpty) {
      _snack('No sold items to invoice in $preferredSaleCurrency.');
      return;
    }

    // On utilisera tous ces ids pour la facture
    final itemIds = candidates
        .map((e) => (e['id'] as num?)?.toInt())
        .whereType<int>()
        .toList(growable: false);

    if (itemIds.isEmpty) {
      _snack('No valid items to invoice.');
      return;
    }

    final firstItem = candidates.first;

    // ✅ devise facture = devise de vente
    final currency = saleCurrencyOf(firstItem);

    final rawBuyerCompany =
        (firstItem['buyer_company'] ?? '').toString().trim();

    String? orgName;
    try {
      final orgRow = await _sb
          .from('organization')
          .select('name')
          .eq('id', orgId)
          .maybeSingle();
      orgName = orgRow?['name']?.toString().trim();
    } catch (_) {}

    final sellerNameDefault =
        rawBuyerCompany.isNotEmpty ? rawBuyerCompany : orgName;

    final buyerInfos = (firstItem['buyer_infos'] ?? '').toString().trim();
    final buyerNameDefault = buyerInfos.isNotEmpty ? buyerInfos : 'Customer';

    final formResult = await InvoiceCreateDialog.show(
      context,
      currency: currency,
      // sellerName: sellerNameDefault,
      sellerName: 'cardshouker',
      buyerName: buyerNameDefault,
    );

    if (formResult == null) {
      return;
    }

    try {
      final actions = InvoiceActions(_sb);

      final invoice = await actions.createBillForItemsAndGeneratePdf(
        orgId: orgId,
        itemIds: itemIds,
        currency: currency, // ✅ sale currency
        taxRate: formResult.taxRate,
        dueDate: null,
        // Seller
        sellerName: formResult.sellerName,
        sellerAddress: formResult.sellerAddress,
        sellerCountry: formResult.sellerCountry,
        sellerVatNumber: formResult.sellerVatNumber,
        sellerTaxRegistration: null,
        sellerRegistrationNumber: null,
        // Buyer
        buyerName: formResult.buyerName,
        buyerAddress: formResult.buyerAddress,
        buyerCountry: formResult.buyerCountry,
        buyerVatNumber: null,
        buyerTaxRegistration: null,
        buyerEmail: formResult.buyerEmail,
        buyerPhone: null,
        // Other
        paymentTerms: formResult.paymentTerms,
        notes: formResult.notes,
      );

      _snack('Invoice ${invoice.invoiceNumber} created.');
      await _loadAll();
    } catch (e) {
      _snack('Error while creating invoice: $e');
    }
  }

  Future<void> _onAttachPurchaseInvoice() async {
    final orgId = _orgIdFromContext;
    if (orgId == null) {
      _snack('Missing organization id.');
      return;
    }

    if (_items.isEmpty) {
      _snack('No items available for this group.');
      return;
    }

    final firstItem = _items.first;
    final int? itemId = (firstItem['id'] as num?)?.toInt();

    if (itemId == null) {
      _snack('Invalid item id.');
      return;
    }

    // ✅ purchase invoice reste basé sur la devise "item/coûts"
    final currency =
        (firstItem['currency'] ?? _viewRow?['currency'] ?? 'USD').toString();

    final defaultSupplier =
        (firstItem['supplier_name'] ?? _viewRow?['supplier_name'])?.toString();

    final formResult = await AttachPurchaseInvoiceDialog.show(
      context,
      currency: currency,
      supplierName: defaultSupplier,
    );

    if (formResult == null) {
      return;
    }

    try {
      final actions = InvoiceActions(_sb);

      await actions.attachPurchaseInvoiceForItem(
        orgId: orgId,
        itemId: itemId,
        currency: currency,
        supplierName: formResult.supplierName,
        externalInvoiceNumber: formResult.invoiceNumber,
        fileBytes: formResult.fileBytes,
        fileName: formResult.fileName,
        notes: formResult.notes,
      );

      _snack(
          'Purchase invoice ${formResult.invoiceNumber} attached to this item.');
      await _loadAll();
    } catch (e) {
      _snack('Error while attaching purchase invoice: $e');
    }
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    if (_loading || !_roleLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final status = (_ovStatus ??
            _localStatusFilter ??
            (_items.isNotEmpty
                ? (_items.first['status']?.toString())
                : widget.group['status']?.toString()) ??
            '')
        .toString();

    List<Map<String, dynamic>> sourceItems = _filteredItems();
    if (sourceItems.isEmpty && _items.isNotEmpty) {
      final fallback =
          _resolveStatusFilter(_items, previous: _localStatusFilter);
      sourceItems =
          _items.where((e) => (e['status'] ?? '') == fallback).toList();
    }

    final visibleItems = _maskUnitInList(sourceItems);

    final soldMargins = visibleItems
        .map(_derivedMarginPct)
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

    final infoRaw = {
      ...?_viewRow,
      if (_items.isNotEmpty) ..._items.first,
    };
    final info = _maskUnitInMap(infoRaw);
    final uDoc = (info['document_url'] ?? '').toString();

    final int? blueprintId = ((_viewRow?['blueprint_id']) as num?)?.toInt() ??
        (_productExtras?['blueprint_id'] as int?) ??
        (widget.group['blueprint_id'] as int?);
    final String? tcgPlayerId = (_viewRow?['tcg_player_id']?.toString()) ??
        (_productExtras?['tcg_player_id'] as String?) ??
        (widget.group['tcg_player_id']?.toString());

    final publicToken = _firstVisiblePublicToken();
    final String? publicUrl =
        (publicToken != null) ? _buildItemPublicUrl(publicToken) : null;
    final String? appLink =
        (publicToken != null) ? _buildItemAppDeepLink(publicToken) : null;

    final bool isSingle =
        ((_viewRow?['type'] ?? widget.group['type'] ?? 'single')
                .toString()
                .toLowerCase() ==
            'single');

    final finance = _isOwner
        ? FinanceOverview(
            items: sourceItems,
            currency: currency,
            baseCurrency: 'USD',
            fxToUsd: kFxToUsd,
            titleInvested: 'Invested (view)',
            titleEstimated: 'Estimated value',
            titleSold: 'Actual revenue',
            subtitleInvested: 'Σ costs (unsold items)',
            subtitleEstimated: 'Σ estimated_price (unsold)',
            subtitleSold: 'Σ sale_price (sold)',
          )
        : const SizedBox.shrink();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _dirty);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.pop(context, _dirty)),
          title: Text(
            _title.isEmpty ? 'Details' : _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_isOwner)
              IconButton(
                tooltip: 'Attach purchase invoice',
                icon: const Icon(Icons.upload_file),
                onPressed: _items.isEmpty ? null : _onAttachPurchaseInvoice,
              ),
            if (_isOwner)
              IconButton(
                tooltip: 'Create sales invoice',
                icon: const Icon(Icons.receipt_long),
                onPressed: _items.isEmpty ? null : _onCreateInvoiceForGroup,
              ),
            IconButton(
              tooltip: 'Edit items',
              icon: const Iconify(Mdi.pencil),
              onPressed: visibleItems.isEmpty ? null : _onEditGroup,
            ),
          ],
          flexibleSpace: const _AppbarGradient(),
        ),
        body: RefreshIndicator(
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
                historyTitle: 'Save history',
                historyCount: _movements.length,
                showMargins: _isOwner,
              ),
              DetailsStatusFilterBar(
                counts: _statusCounts(_items),
                selected: status,
                total: _items.length,
                onSelected: (s) {
                  setState(() {
                    _localStatusFilter = s;
                    _ovStatus = s;
                  });
                },
              ),
              const SizedBox(height: 12),
              DetailsOverviewPanel(
                mediaThumb: MediaThumb(
                  imageUrl: displayImageUrl,
                  isAsset: !hasPhoto,
                  aspectRatio: 0.72,
                  onOpen: hasPhoto
                      ? () async {
                          final uri = Uri.tryParse(photoUrl);
                          if (uri != null) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      : null,
                ),
                invoiceButtons: _buildInvoiceDocButtons(uDoc),
                qrRow: Align(
                  alignment: Alignment.centerLeft,
                  child: QrLineButton.inline(
                    publicUrl: publicUrl,
                    appLink: appLink,
                    onCopy: (link) async {
                      await Clipboard.setData(ClipboardData(text: link));
                      _snack('Link copied');
                    },
                  ),
                ),
                publicPreviewButton: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: (publicToken == null)
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PublicItemPage(
                                  token: publicToken,
                                ),
                              ),
                            );
                          },
                    child: const Text('Public preview'),
                  ),
                ),
                showFinance: _isOwner,
                finance: finance,
                infoCard: InfoExtrasCard(
                  data: info,
                  currencyFallback: currency,
                  showMargins: _isOwner,
                ),
              ),
              const SizedBox(height: 16),
              DetailsSectionHeader(
                title: 'Items',
                subtitle: 'Showing $qtyStatus / ${_items.length} item(s)',
                icon: Icons.inventory_2_outlined,
                trailing: IconButton(
                  tooltip: _showItemsTable ? 'Hide' : 'Show',
                  icon: Iconify(
                    _showItemsTable ? Mdi.chevron_up : Mdi.chevron_down,
                  ),
                  onPressed: () =>
                      setState(() => _showItemsTable = !_showItemsTable),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SizeTransition(sizeFactor: anim, child: child),
                  );
                },
                child: _showItemsTable
                    ? ItemsTable(
                        key: const ValueKey('items_table'),
                        items: visibleItems,
                        currency: currency,
                        showMargins: _isOwner,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('items_table_hidden'),
                      ),
              ),
              const SizedBox(height: 16),
              DetailsSectionHeader(
                title: 'Price trends',
                icon: Icons.trending_up,
                tooltip:
                    'Collectr (Edge) + CardTrader — Graph based on price_history (1 point/day).',
              ),
              const SizedBox(height: 8),
              PriceTrendsCard(
                key: ValueKey(
                  'trends_${(_viewRow?['product_id'] ?? widget.group['product_id'])}_$_trendsReloadTick',
                ),
                productId: (_viewRow?['product_id'] ??
                    widget.group['product_id']) as int?,
                productType: (_viewRow?['type'] ?? widget.group['type'] ?? '')
                    .toString(),
                currency: currency,
                photoUrl: (_viewRow?['photo_url'] ?? widget.group['photo_url'])
                    ?.toString(),
                blueprintId: ((_viewRow?['blueprint_id']) as num?)?.toInt() ??
                    (_productExtras?['blueprint_id'] as int?) ??
                    (widget.group['blueprint_id'] as int?),
                tcgPlayerId: (_viewRow?['tcg_player_id']?.toString()) ??
                    (_productExtras?['tcg_player_id'] as String?) ??
                    (widget.group['tcg_player_id']?.toString()),
                reloadTick: _trendsReloadTick,
              ),
              const SizedBox(height: 12),
              PriceHistoryTabs(
                productId: (_viewRow?['product_id'] ??
                    widget.group['product_id']) as int?,
                isSingle: isSingle,
                currency: currency,
              ),
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

class _InvoiceDocButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _InvoiceDocButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
