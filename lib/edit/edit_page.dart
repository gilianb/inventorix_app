//edit/edit_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../inventory/widgets/storage_upload_tile.dart';

// 🔐 RBAC (conservé mais NON utilisé pour masquer quoi que ce soit)
import 'package:inventorix_app/org/roles.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

// UI widgets
import 'widgets/edit_form_widgets.dart';

// ✅ Status colors + canonical order
import '../inventory/utils/status_utils.dart';

class EditItemsDialog extends StatefulWidget {
  const EditItemsDialog({
    super.key,
    required this.productId,
    required this.status,
    required this.availableQty,
    required this.initialSample,
  });

  final int productId;
  final String status;
  final int availableQty;
  final Map<String, dynamic>? initialSample;

  static Future<bool?> show(
    BuildContext context, {
    required int productId,
    required String status,
    required int availableQty,
    Map<String, dynamic>? initialSample,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);

        // ✅ largeur adaptée écran (max 880) + hauteur max 90%
        final dialogW = (mq.size.width * 0.96).clamp(320.0, 880.0);
        final maxH = mq.size.height * 0.90;

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogW, maxHeight: maxH),
            child: SizedBox(
              width: dialogW,
              // ✅ IMPORTANT : PAS de scroll ici -> le widget gère le scroll
              child: EditItemsDialog(
                productId: productId,
                status: status,
                availableQty: availableQty,
                initialSample: initialSample,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<EditItemsDialog> createState() => _EditItemsDialogState();
}

class _EditItemsDialogState extends State<EditItemsDialog> {
  final _sb = Supabase.instance.client;

  // RBAC (non bloquant ici)
  bool _roleLoaded = false;

  // combien d'items modifier dans ce groupe
  late int _countToEdit;
  late final TextEditingController _countCtrl;

  // appliquer sur les items les plus anciens (id ASC) ou récents (id DESC)
  bool _oldestFirst = true;

  // ======= CONTRÔLEURS =======
  String _newStatus = '';
  final _gradeIdCtrl = TextEditingController();
  final _gradingNoteCtrl = TextEditingController();
  final _gradingFeesCtrl = TextEditingController();
  final _estimatedPriceCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  DateTime? _saleDate;
  final _itemLocationCtrl = TextEditingController();
  final _trackingCtrl = TextEditingController();
  final _channelIdCtrl = TextEditingController(); // gardé pour compat / debug
  final _buyerCompanyCtrl = TextEditingController();
  final _supplierNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  final _documentUrlCtrl = TextEditingController();
  final _unitCostCtrl = TextEditingController();

  // ✅ NEW grading service + dates
  List<Map<String, dynamic>> _gradingServices = const [];
  int? _gradingServiceId; // item.grading_service_id
  DateTime? _sentToGraderDate; // item.sent_to_grader_date
  DateTime? _atGraderDate; // item.at_grader_date

  // Nouveaux contrôleurs (tête produit / item)
  String _newType = 'single'; // 'single' | 'sealed'
  final _productNameCtrl = TextEditingController();
  String _language = 'EN';
  int? _gameId; // via dropdown
  final _shippingFeesCtrl = TextEditingController();
  final _commissionFeesCtrl = TextEditingController();
  final _paymentTypeCtrl = TextEditingController();
  final _buyerInfosCtrl = TextEditingController();

  // ✅ Devise UNIQUEMENT pour sale_price
  String _saleCurrency = 'USD';
  static const saleCurrencies = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'ILS',
    'CHF',
    'CAD',
    'AED',
  ];

  // Jeux pour dropdown
  List<Map<String, dynamic>> _games = const [];

  // Channels pour dropdown
  List<Map<String, dynamic>> _channels = const [];
  int? _selectedChannelId; // null = aucun channel

  bool _saving = false;

  static const langs = ['EN', 'FR', 'JP', 'CN', 'DE', 'ES', 'IT'];
  static const itemTypes = ['single', 'sealed'];

  Map<String, dynamic> get _sample => (widget.initialSample ?? const {});

  @override
  void initState() {
    super.initState();
    _countToEdit = widget.availableQty.clamp(1, 999999);
    _countCtrl = TextEditingController(text: _countToEdit.toString());
    _init();
  }

  Future<void> _init() async {
    final s = _sample;
    _newStatus = _coerceString(widget.status, kStatusOrder, kStatusOrder.first);

    _gradeIdCtrl.text = (s['grade_id'] ?? '').toString();
    _gradingNoteCtrl.text = (s['grading_note'] ?? '').toString();
    _gradingFeesCtrl.text = _numToText(s['grading_fees']);
    _estimatedPriceCtrl.text = _numToText(s['estimated_price']);
    _salePriceCtrl.text = _numToText(s['sale_price']);
    _saleDate = _parseDate(s['sale_date']);
    _itemLocationCtrl.text = (s['item_location'] ?? '').toString();
    _trackingCtrl.text = (s['tracking'] ?? '').toString();

    final sampleChannelId = _asInt(s['channel_id']);
    _selectedChannelId = sampleChannelId;
    _channelIdCtrl.text = _numToIntText(s['channel_id']);

    _buyerCompanyCtrl.text = (s['buyer_company'] ?? '').toString();
    _supplierNameCtrl.text = (s['supplier_name'] ?? '').toString();
    _notesCtrl.text = (s['notes'] ?? '').toString();
    _photoUrlCtrl.text = (s['photo_url'] ?? '').toString();
    _documentUrlCtrl.text = (s['document_url'] ?? '').toString();
    _unitCostCtrl.text = _numToText(s['unit_cost']);

    _newType =
        _coerceString((s['type'] ?? 'single').toString(), itemTypes, 'single');
    _productNameCtrl.text = (s['product_name'] ?? '').toString();
    _language = _coerceString((s['language'] ?? 'EN').toString(), langs, 'EN');
    _gameId = _asInt(s['game_id']);
    _shippingFeesCtrl.text = _numToText(s['shipping_fees']);
    _commissionFeesCtrl.text = _numToText(s['commission_fees']);
    _paymentTypeCtrl.text = (s['payment_type'] ?? '').toString();
    _buyerInfosCtrl.text = (s['buyer_infos'] ?? '').toString();

    // ✅ NEW fields from sample
    _gradingServiceId = _asInt(s['grading_service_id']);
    _sentToGraderDate = _parseDate(s['sent_to_grader_date']);
    _atGraderDate = _parseDate(s['at_grader_date']);

    final preSaleCur =
        (s['sale_currency'] ?? s['currency'] ?? 'USD').toString();
    _saleCurrency = _coerceString(preSaleCur, saleCurrencies, 'USD');

    await _loadRole();
    await _loadGames();
    await _loadChannels();
    await _loadGradingServices();
    await _hydrateFromDb();

    if (mounted) setState(() {});
  }

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      final orgId = (_sample['org_id']?.toString().isNotEmpty ?? false)
          ? _sample['org_id'].toString()
          : null;

      if (uid == null || orgId == null) {
        if (mounted) setState(() => _roleLoaded = true);
        return;
      }

      Map<String, dynamic>? row;
      try {
        row = await _sb
            .from('organization_member')
            .select('role')
            .eq('org_id', orgId)
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {}

      String? roleStr = (row?['role'] as String?);

      if (roleStr == null) {
        try {
          final org = await _sb
              .from('organization')
              .select('created_by')
              .eq('id', orgId)
              .maybeSingle();
          final createdBy = org?['created_by'] as String?;
          if (createdBy != null && createdBy == uid) {
            roleStr = 'owner';
          }
        } catch (_) {}
      }

      OrgRole.values.firstWhere(
        (r) => r.name == (roleStr ?? 'viewer').toLowerCase(),
        orElse: () => OrgRole.viewer,
      );

      if (mounted) setState(() => _roleLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _roleLoaded = true);
    }
  }

  // ======= utils =======
  String _coerceString(String? value, List<String> allowed, String fallback) {
    final v = (value ?? '').trim();
    return allowed.contains(v) ? v : fallback;
  }

  List<DropdownMenuItem<String>> _stringItems(List<String> allowed,
      {String? extra}) {
    final seen = <String>{};
    final out = <DropdownMenuItem<String>>[];

    for (final s in allowed) {
      if (seen.add(s)) {
        out.add(DropdownMenuItem(value: s, child: Text(s)));
      }
    }

    if (extra != null && extra.isNotEmpty && seen.add(extra)) {
      out.insert(0, DropdownMenuItem(value: extra, child: Text(extra)));
    }

    return out;
  }

  List<String> _statusListWithExtra({required String current}) {
    final list = <String>[...kStatusOrder];
    if (current.trim().isNotEmpty && !list.contains(current)) {
      list.insert(0, current);
    }
    return list;
  }

  String _prettyStatus(String s) => s.replaceAll('_', ' ');

  Widget _statusRow(BuildContext context, String s) {
    final c = statusColor(context, s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(_prettyStatus(s), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _numToText(dynamic v) => v == null ? '' : v.toString();
  String _numToIntText(dynamic v) =>
      v == null ? '' : (v is num ? v.toInt().toString() : v.toString());

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      final s = v.toString();
      return DateTime.tryParse(s.length > 10 ? s : '${s}T00:00:00');
    } catch (_) {
      return null;
    }
  }

  // ✅ Business days helpers (lun–ven)
  bool _isBusinessDay(DateTime d) =>
      d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;

  DateTime _addBusinessDays(DateTime start, int businessDays) {
    var d = DateTime(start.year, start.month, start.day);
    var added = 0;
    while (added < businessDays) {
      d = d.add(const Duration(days: 1));
      if (_isBusinessDay(d)) added++;
    }
    return d;
  }

  int _businessDaysBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    if (s.isAtSameMomentAs(e)) return 0;

    if (e.isAfter(s)) {
      var count = 0;
      var d = s;
      while (d.isBefore(e)) {
        d = d.add(const Duration(days: 1));
        if (_isBusinessDay(d)) count++;
      }
      return count;
    } else {
      return -_businessDaysBetween(e, s);
    }
  }

  // ✅ Dedup helper by int id while preserving order
  List<Map<String, dynamic>> _dedupRowsByIntId(
    List<Map<String, dynamic>> rows, {
    String idKey = 'id',
  }) {
    final seen = <int>{};
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = _asInt(r[idKey]);
      if (id == null) continue;
      if (seen.add(id)) out.add(r);
    }
    return out;
  }

  Future<void> _loadGames() async {
    try {
      final raw = await _sb
          .from('games')
          .select('id, code, label, sort_order')
          .order('sort_order', ascending: true, nullsFirst: false)
          .order('label', ascending: true);

      final list = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final sampleGameId = _asInt(_sample['game_id']);
      if (sampleGameId != null &&
          !list.any((g) => _asInt(g['id']) == sampleGameId)) {
        list.insert(0, {'id': sampleGameId, 'label': 'Game #$sampleGameId'});
      }

      final dedup = _dedupRowsByIntId(list);

      if (!mounted) return;
      setState(() {
        _games = dedup;

        // ✅ sanitize selected value (avoid Dropdown crash)
        final ids = _games.map((g) => _asInt(g['id'])).whereType<int>().toSet();
        if (_gameId != null && !ids.contains(_gameId)) {
          _gameId = ids.isNotEmpty ? ids.first : null;
        } else {
          _gameId ??= ids.isNotEmpty ? ids.first : null;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadChannels() async {
    try {
      final raw = await _sb
          .from('channel')
          .select('id, code, label')
          .order('label', ascending: true);

      final list = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final sampleChannelId = _asInt(_sample['channel_id']);
      if (sampleChannelId != null &&
          !list.any((c) => _asInt(c['id']) == sampleChannelId)) {
        list.insert(0, {
          'id': sampleChannelId,
          'code': '—',
          'label': 'Channel #$sampleChannelId',
        });
      }

      final dedup = _dedupRowsByIntId(list);

      if (!mounted) return;
      setState(() {
        _channels = dedup;

        // ✅ sanitize selected value (avoid Dropdown crash)
        final ids =
            _channels.map((c) => _asInt(c['id'])).whereType<int>().toSet();
        if (_selectedChannelId != null && !ids.contains(_selectedChannelId)) {
          _selectedChannelId = null;
        }
        _channelIdCtrl.text = _selectedChannelId?.toString() ?? '';
      });
    } catch (_) {
      // ignore
    }
  }

  // ✅ NEW: grading service list (org-scoped, active)
  Future<void> _loadGradingServices() async {
    try {
      final orgId = (_sample['org_id']?.toString().isNotEmpty ?? false)
          ? _sample['org_id'].toString()
          : null;
      if (orgId == null) return;

      final raw = await _sb
          .from('grading_service')
          .select(
              'id, code, label, expected_days, default_fee, sort_order, active')
          .eq('org_id', orgId)
          .eq('active', true)
          .order('sort_order', ascending: true, nullsFirst: false)
          .order('label', ascending: true);

      final list = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final sampleGsId = _asInt(_sample['grading_service_id']);
      if (sampleGsId != null &&
          !list.any((x) => _asInt(x['id']) == sampleGsId)) {
        list.insert(0, {
          'id': sampleGsId,
          'code': '—',
          'label': 'Service #$sampleGsId',
          'expected_days': 30,
          'default_fee': 0,
        });
      }

      final dedup = _dedupRowsByIntId(list);

      if (!mounted) return;
      setState(() {
        _gradingServices = dedup;

        // ✅ sanitize selected value (avoid Dropdown crash)
        final ids = _gradingServices
            .map((s) => _asInt(s['id']))
            .whereType<int>()
            .toSet();
        if (_gradingServiceId != null && !ids.contains(_gradingServiceId)) {
          _gradingServiceId = null;
        } else {
          _gradingServiceId ??= (sampleGsId != null && ids.contains(sampleGsId))
              ? sampleGsId
              : null;
        }
      });
    } catch (_) {
      // ignore
    }
  }

  // ========= HYDRATATION DB =========
  Future<void> _hydrateFromDb() async {
    final sample = _sample;
    final orgId = (sample['org_id']?.toString().isNotEmpty ?? false)
        ? sample['org_id']
        : null;
    final String? groupSig =
        (sample['group_sig']?.toString().isNotEmpty ?? false)
            ? sample['group_sig'].toString()
            : null;

    const itemCols = <String>[
      'grade_id',
      'grading_note',
      'grading_fees',
      'estimated_price',
      'sale_price',
      'sale_currency',
      'currency',
      'sale_date',
      'item_location',
      'tracking',
      'channel_id',
      'buyer_company',
      'supplier_name',
      'notes',
      'photo_url',
      'document_url',
      'unit_cost',
      'shipping_fees',
      'commission_fees',
      'payment_type',
      'buyer_infos',
      'type',
      'language',
      'game_id',
      'grading_service_id',
      'sent_to_grader_date',
      'at_grader_date',
    ];

    List<Map<String, dynamic>> rows = const [];

    try {
      if (groupSig != null && groupSig.isNotEmpty) {
        var q = _sb
            .from('item')
            .select(itemCols.join(', '))
            .eq('group_sig', groupSig)
            .eq('status', widget.status);
        if (orgId != null) q = q.eq('org_id', orgId);
        final List<dynamic> raw =
            await q.order('id', ascending: false).limit(50);
        rows = raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        const strongKeys = <String>{
          'game_id',
          'type',
          'language',
          'channel_id',
          'purchase_date',
          'supplier_name',
          'buyer_company',
          'item_location',
          'tracking',
        };

        var q = _sb
            .from('item')
            .select(itemCols.join(', '))
            .eq('product_id', widget.productId)
            .eq('status', widget.status);
        if (orgId != null) q = q.eq('org_id', orgId);

        for (final k in strongKeys) {
          if (sample.containsKey(k) &&
              (sample[k] != null) &&
              sample[k].toString().isNotEmpty) {
            var v = sample[k];
            if (k == 'purchase_date') {
              final d = v is DateTime
                  ? v.toIso8601String().substring(0, 10)
                  : v.toString().substring(0, 10);
              q = q.eq(k, d);
            } else {
              q = q.eq(k, v);
            }
          }
        }

        final List<dynamic> raw =
            await q.order('id', ascending: false).limit(50);
        rows = raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {
      rows = const [];
    }

    dynamic firstNonNull(String key) {
      for (final r in rows) {
        final v = r[key];
        if (v != null && v.toString().isNotEmpty) return v;
      }
      return null;
    }

    void fillIfEmpty(TextEditingController c, dynamic value) {
      if (c.text.trim().isEmpty && value != null) {
        c.text = value.toString();
      }
    }

    fillIfEmpty(_gradeIdCtrl, firstNonNull('grade_id'));
    fillIfEmpty(_gradingNoteCtrl, firstNonNull('grading_note'));
    fillIfEmpty(_gradingFeesCtrl, firstNonNull('grading_fees'));
    fillIfEmpty(_estimatedPriceCtrl, firstNonNull('estimated_price'));
    fillIfEmpty(_salePriceCtrl, firstNonNull('sale_price'));
    fillIfEmpty(_itemLocationCtrl, firstNonNull('item_location'));
    fillIfEmpty(_trackingCtrl, firstNonNull('tracking'));

    final dbChannel = firstNonNull('channel_id');
    if (_selectedChannelId == null && dbChannel != null) {
      _selectedChannelId = _asInt(dbChannel);
      _channelIdCtrl.text = _selectedChannelId?.toString() ?? '';
    }

    fillIfEmpty(_buyerCompanyCtrl, firstNonNull('buyer_company'));
    fillIfEmpty(_supplierNameCtrl, firstNonNull('supplier_name'));
    fillIfEmpty(_notesCtrl, firstNonNull('notes'));
    fillIfEmpty(_photoUrlCtrl, firstNonNull('photo_url'));
    fillIfEmpty(_documentUrlCtrl, firstNonNull('document_url'));
    fillIfEmpty(_unitCostCtrl, firstNonNull('unit_cost'));
    fillIfEmpty(_shippingFeesCtrl, firstNonNull('shipping_fees'));
    fillIfEmpty(_commissionFeesCtrl, firstNonNull('commission_fees'));
    fillIfEmpty(_paymentTypeCtrl, firstNonNull('payment_type'));
    fillIfEmpty(_buyerInfosCtrl, firstNonNull('buyer_infos'));

    final maybeType = firstNonNull('type')?.toString();
    if (maybeType != null && maybeType.isNotEmpty) {
      _newType = _coerceString(maybeType, itemTypes, _newType);
    }

    final maybeLang = firstNonNull('language')?.toString();
    if (maybeLang != null && maybeLang.isNotEmpty) {
      _language = _coerceString(maybeLang, langs, _language);
    }

    final maybeGame = firstNonNull('game_id');
    if (maybeGame != null) {
      _gameId = _asInt(maybeGame);
    }

    final maybeSaleDate = firstNonNull('sale_date');
    if (_saleDate == null && maybeSaleDate != null) {
      _saleDate = _parseDate(maybeSaleDate);
    }

    final maybeSaleCurrency = firstNonNull('sale_currency')?.toString();
    final maybeLegacyCurrency = firstNonNull('currency')?.toString();
    final resolved = (maybeSaleCurrency != null && maybeSaleCurrency.isNotEmpty)
        ? maybeSaleCurrency
        : (maybeLegacyCurrency != null && maybeLegacyCurrency.isNotEmpty
            ? maybeLegacyCurrency
            : _saleCurrency);
    _saleCurrency = _coerceString(resolved, saleCurrencies, _saleCurrency);

    final maybeGs = firstNonNull('grading_service_id');
    if (_gradingServiceId == null && maybeGs != null) {
      _gradingServiceId = _asInt(maybeGs);
    }
    final maybeSent = firstNonNull('sent_to_grader_date');
    if (_sentToGraderDate == null && maybeSent != null) {
      _sentToGraderDate = _parseDate(maybeSent);
    }
    final maybeAt = firstNonNull('at_grader_date');
    if (_atGraderDate == null && maybeAt != null) {
      _atGraderDate = _parseDate(maybeAt);
    }

    if (_productNameCtrl.text.trim().isEmpty) {
      try {
        final prod = await _sb
            .from('product')
            .select('name, type')
            .eq('id', widget.productId)
            .maybeSingle();
        final pName = (prod?['name']?.toString() ?? '');
        if (pName.isNotEmpty) _productNameCtrl.text = pName;
        final pType = (prod?['type']?.toString() ?? '');
        if (pType.isNotEmpty) {
          _newType = _coerceString(pType, itemTypes, _newType);
        }
      } catch (_) {}
    }

    // ✅ final sanitize to avoid dropdown crash even if orgId missing etc.
    if (mounted) {
      setState(() {
        final gsIds = _gradingServices
            .map((x) => _asInt(x['id']))
            .whereType<int>()
            .toSet();
        if (_gradingServiceId != null && !gsIds.contains(_gradingServiceId)) {
          _gradingServiceId = null;
        }

        final chIds =
            _channels.map((x) => _asInt(x['id'])).whereType<int>().toSet();
        if (_selectedChannelId != null && !chIds.contains(_selectedChannelId)) {
          _selectedChannelId = null;
          _channelIdCtrl.text = '';
        }

        final gIds =
            _games.map((x) => _asInt(x['id'])).whereType<int>().toSet();
        if (_gameId != null && !gIds.contains(_gameId)) {
          _gameId = gIds.isNotEmpty ? gIds.first : null;
        }
      });
    }
  }

  @override
  void dispose() {
    _countCtrl.dispose();

    _gradeIdCtrl.dispose();
    _gradingNoteCtrl.dispose();
    _gradingFeesCtrl.dispose();
    _estimatedPriceCtrl.dispose();
    _salePriceCtrl.dispose();
    _itemLocationCtrl.dispose();
    _trackingCtrl.dispose();
    _channelIdCtrl.dispose();
    _buyerCompanyCtrl.dispose();
    _supplierNameCtrl.dispose();
    _notesCtrl.dispose();
    _photoUrlCtrl.dispose();
    _documentUrlCtrl.dispose();
    _unitCostCtrl.dispose();

    _productNameCtrl.dispose();
    _shippingFeesCtrl.dispose();
    _commissionFeesCtrl.dispose();
    _paymentTypeCtrl.dispose();
    _buyerInfosCtrl.dispose();
    super.dispose();
  }

  num? _tryNum(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  bool _changedText(String key, String current) {
    final old = (_sample[key]?.toString() ?? '');
    return (old.trim() != current.trim());
  }

  bool _changedNum(String key, String currentText) {
    final oldRaw = _sample[key];
    final old = oldRaw == null ? null : num.tryParse(oldRaw.toString());
    final cur = _tryNum(currentText);
    return old != cur;
  }

  bool _changedDate(String key, DateTime? cur) {
    final oldRaw = _sample[key];
    DateTime? old;
    if (oldRaw != null) {
      final s = oldRaw.toString();
      old = DateTime.tryParse(s.length > 10 ? s : '${s}T00:00:00');
    }
    String? d(DateTime? x) => x?.toIso8601String().substring(0, 10);
    return d(old) != d(cur);
  }

  bool _changedSimple(String key, Object? current) {
    final old = _sample[key];
    return old?.toString() != current?.toString();
  }

  Map<String, dynamic> _buildItemUpdates() {
    final m = <String, dynamic>{};

    void putText(String key, TextEditingController c) {
      if (_changedText(key, c.text)) {
        m[key] = c.text.trim().isEmpty ? null : c.text.trim();
      }
    }

    void putNum(String key, TextEditingController c) {
      if (_changedNum(key, c.text)) {
        m[key] = _tryNum(c.text);
      }
    }

    putText('grade_id', _gradeIdCtrl);
    putText('grading_note', _gradingNoteCtrl);
    putNum('grading_fees', _gradingFeesCtrl);
    putNum('estimated_price', _estimatedPriceCtrl);
    putText('item_location', _itemLocationCtrl);
    putText('tracking', _trackingCtrl);

    final oldGs = _asInt(_sample['grading_service_id']);
    if (oldGs != _gradingServiceId) {
      m['grading_service_id'] = _gradingServiceId;
    }
    if (_changedDate('sent_to_grader_date', _sentToGraderDate)) {
      m['sent_to_grader_date'] =
          _sentToGraderDate?.toIso8601String().substring(0, 10);
    }
    if (_changedDate('at_grader_date', _atGraderDate)) {
      m['at_grader_date'] = _atGraderDate?.toIso8601String().substring(0, 10);
    }

    final oldChannelId = _asInt(_sample['channel_id']);
    if (oldChannelId != _selectedChannelId) {
      m['channel_id'] = _selectedChannelId;
    }

    putText('buyer_company', _buyerCompanyCtrl);
    putText('supplier_name', _supplierNameCtrl);
    putText('notes', _notesCtrl);
    putText('photo_url', _photoUrlCtrl);
    putText('document_url', _documentUrlCtrl);
    putNum('unit_cost', _unitCostCtrl);

    if (_changedSimple('type', _newType)) m['type'] = _newType;
    if (_changedSimple('language', _language)) m['language'] = _language;
    if (_changedSimple('game_id', _gameId)) m['game_id'] = _gameId;

    final oldSaleCur =
        (_sample['sale_currency'] ?? _sample['currency'] ?? 'USD').toString();
    if (oldSaleCur != _saleCurrency) {
      m['sale_currency'] = _saleCurrency;
    }

    if (_changedNum('shipping_fees', _shippingFeesCtrl.text)) {
      m['shipping_fees'] = _tryNum(_shippingFeesCtrl.text);
    }
    if (_changedNum('commission_fees', _commissionFeesCtrl.text)) {
      m['commission_fees'] = _tryNum(_commissionFeesCtrl.text);
    }

    if (_changedText('payment_type', _paymentTypeCtrl.text)) {
      m['payment_type'] = _paymentTypeCtrl.text.trim().isEmpty
          ? null
          : _paymentTypeCtrl.text.trim();
    }
    if (_changedText('buyer_infos', _buyerInfosCtrl.text)) {
      m['buyer_infos'] = _buyerInfosCtrl.text.trim().isEmpty
          ? null
          : _buyerInfosCtrl.text.trim();
    }

    if (_changedNum('sale_price', _salePriceCtrl.text)) {
      m['sale_price'] = _tryNum(_salePriceCtrl.text);
    }
    if (_changedDate('sale_date', _saleDate)) {
      m['sale_date'] = _saleDate?.toIso8601String().substring(0, 10);
    }

    final statusBefore = widget.status;
    final statusAfter = (_newStatus.isNotEmpty ? _newStatus : statusBefore);
    if (statusAfter != statusBefore) {
      m['status'] = statusAfter;
    }

    return m;
  }

  Map<String, dynamic> _buildProductUpdates() {
    final m = <String, dynamic>{};
    final oldName = (_sample['product_name'] ?? '').toString();
    final newName = _productNameCtrl.text.trim();
    if (oldName != newName) {
      m['name'] = newName.isEmpty ? null : newName;
    }
    final oldType = (_sample['type'] ?? '').toString();
    if (oldType != _newType) {
      m['type'] = _newType;
    }
    return m;
  }

  Map<String, dynamic> _buildBatchChanges(
    Map<String, dynamic> baseUpdates,
    Map<String, dynamic> productUpdates,
  ) {
    final changes = <String, dynamic>{};

    baseUpdates.forEach((code, newV) {
      final oldV = _sample[code];
      if ((oldV?.toString() ?? '') != (newV?.toString() ?? '')) {
        changes[code] = {'old': oldV, 'new': newV};
      }
    });

    if (productUpdates.containsKey('name')) {
      changes['product_name'] = {
        'old': _sample['product_name'],
        'new': productUpdates['name'],
      };
    }
    if (productUpdates.containsKey('type')) {
      changes['type'] = {'old': _sample['type'], 'new': productUpdates['type']};
    }

    if (_changedSimple('language', _language)) {
      changes['language'] = {'old': _sample['language'], 'new': _language};
    }
    if (_changedSimple('game_id', _gameId)) {
      changes['game_id'] = {'old': _sample['game_id'], 'new': _gameId};
    }

    final oldSaleCur =
        (_sample['sale_currency'] ?? _sample['currency'] ?? 'USD').toString();
    if (oldSaleCur != _saleCurrency) {
      changes['sale_currency'] = {'old': oldSaleCur, 'new': _saleCurrency};
    }

    return changes;
  }

  Future<void> _logBatchEditRPC({
    required String orgId,
    required List<int> itemIds,
    required Map<String, dynamic> baseUpdates,
    required Map<String, dynamic> productUpdates,
  }) async {
    final changes = _buildBatchChanges(baseUpdates, productUpdates);
    if (changes.isEmpty) return;

    await _sb.rpc('app_log_batch_edit', params: {
      'p_org_id': orgId,
      'p_item_ids': itemIds,
      'p_changes': changes,
      'p_reason': null,
    });
  }

  Future<List<int>> _collectIdsForEdit({
    required Map<String, dynamic> sample,
    required String status,
    required int limitCount,
    required bool oldestFirst,
  }) async {
    final orgId = (sample['org_id']?.toString().isNotEmpty ?? false)
        ? sample['org_id']
        : null;
    final String? groupSig =
        (sample['group_sig']?.toString().isNotEmpty ?? false)
            ? sample['group_sig'].toString()
            : null;

    if (groupSig != null) {
      var q = _sb
          .from('item')
          .select('id')
          .eq('group_sig', groupSig)
          .eq('status', status);
      if (orgId != null) q = q.eq('org_id', orgId);
      final List<dynamic> raw =
          await q.order('id', ascending: oldestFirst).limit(limitCount);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
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

    Future<List<int>> runQuery(Set<String> keys) async {
      var q = _sb.from('item').select('id');

      if (orgId != null) q = q.eq('org_id', orgId);
      q = q.eq('product_id', widget.productId);

      for (final k in keys) {
        if (!sample.containsKey(k)) continue;
        var v = norm(sample[k]);
        if (v == null) {
          q = q.filter(k, 'is', null);
        } else if (k == 'purchase_date' || k == 'sale_date') {
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
          await q.order('id', ascending: oldestFirst).limit(limitCount);
      return raw
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList(growable: false);
    }

    const primaryKeys = <String>{
      'game_id',
      'type',
      'language',
      'channel_id',
      'purchase_date',
      'supplier_name',
      'buyer_company',
      'item_location',
      'tracking',
    };

    const strongKeys = <String>{
      'game_id',
      'type',
      'language',
      'channel_id',
      'purchase_date',
      'supplier_name',
      'buyer_company',
    };

    var ids = await runQuery(primaryKeys);
    if (ids.isNotEmpty) return ids;

    ids = await runQuery(strongKeys);
    return ids;
  }

  Future<void> _apply() async {
    final baseUpdates = _buildItemUpdates();
    final productUpdates = _buildProductUpdates();

    if (baseUpdates.isEmpty && productUpdates.isEmpty) {
      _snack('No changes detected.');
      return;
    }

    setState(() => _saving = true);
    try {
      final sample = Map<String, dynamic>.from(_sample)
        ..putIfAbsent('product_id', () => widget.productId);

      final String? orgId = (sample['org_id']?.toString().isNotEmpty ?? false)
          ? sample['org_id'].toString()
          : null;

      final ids = await _collectIdsForEdit(
        sample: sample,
        status: widget.status,
        limitCount: _countToEdit,
        oldestFirst: _oldestFirst,
      );

      if (ids.isEmpty) {
        _snack('No items found to update for this row.');
        return;
      }

      final updates = Map<String, dynamic>.from(baseUpdates);
      final n = ids.length;
      if (n > 0) {
        if (updates.containsKey('shipping_fees')) {
          final v = updates['shipping_fees'];
          if (v is num) updates['shipping_fees'] = v / n;
        }
        if (updates.containsKey('commission_fees')) {
          final v = updates['commission_fees'];
          if (v is num) updates['commission_fees'] = v / n;
        }
      }

      final idsCsv = '(${ids.join(",")})';
      if (updates.isNotEmpty) {
        await _sb.from('item').update(updates).filter('id', 'in', idsCsv);
      }
      if (productUpdates.isNotEmpty) {
        await _sb
            .from('product')
            .update(productUpdates)
            .eq('id', widget.productId);
      }

      if (orgId != null) {
        await _logBatchEditRPC(
          orgId: orgId,
          itemIds: ids,
          baseUpdates: baseUpdates,
          productUpdates: productUpdates,
        );
      }

      if (mounted) {
        _snack('Update applied (${ids.length} item(s)).');
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickSaleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      initialDate: _saleDate ?? now,
    );
    if (picked != null) setState(() => _saleDate = picked);
  }

  Future<void> _pickSentToGraderDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      initialDate: _sentToGraderDate ?? now,
    );
    if (picked != null) setState(() => _sentToGraderDate = picked);
  }

  Future<void> _pickAtGraderDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      initialDate: _atGraderDate ?? now,
    );
    if (picked != null) setState(() => _atGraderDate = picked);
  }

  Map<String, dynamic>? _selectedGsRow() {
    if (_gradingServiceId == null) return null;
    for (final r in _gradingServices) {
      if (_asInt(r['id']) == _gradingServiceId) return r;
    }
    return null;
  }

  int? _selectedExpectedDays() {
    final r = _selectedGsRow();
    if (r == null) return null;
    final v = r['expected_days'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  num? _selectedDefaultFee() {
    final r = _selectedGsRow();
    if (r == null) return null;
    final v = r['default_fee'];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_roleLoaded) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final decoratedTheme = theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(0.35),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline.withOpacity(0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
        ),
      ),
    );

    Widget text(
      TextEditingController c, {
      required String hint,
      int? minLines,
      int? maxLines,
      TextInputType? keyboardType,
    }) {
      return TextField(
        controller: c,
        minLines: minLines,
        maxLines: maxLines ?? 1,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
      );
    }

    Widget num(TextEditingController c,
        {required String hint, bool decimal = true}) {
      return TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(hintText: hint),
      );
    }

    final header = Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.25),
        border: Border(bottom: BorderSide(color: cs.outline.withOpacity(0.12))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withOpacity(0.12)),
            ),
            child: Icon(Icons.edit, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit items',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    EditInfoChip(
                      icon: Icons.inventory_2_outlined,
                      label: '${widget.availableQty} item(s)',
                    ),
                    EditInfoChip(
                      icon: Icons.flag_outlined,
                      label: 'Status: ${widget.status}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, false),
            icon: const Iconify(Mdi.close),
            tooltip: 'Close',
          ),
        ],
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final currentStatus =
              (_newStatus.isNotEmpty ? _newStatus : widget.status);
          final statusList = _statusListWithExtra(current: currentStatus);

          final bool isSingle = _newType == 'single';

          // ✅ sanitize dropdown values at build time (last line of defense)
          final dedupGames = _dedupRowsByIntId(_games);
          final gameIds =
              dedupGames.map((g) => _asInt(g['id'])).whereType<int>().toSet();
          final int? safeGameId = (_gameId != null && gameIds.contains(_gameId))
              ? _gameId
              : (gameIds.isNotEmpty ? gameIds.first : null);

          final dedupChannels = _dedupRowsByIntId(_channels);
          final channelIds = dedupChannels
              .map((c) => _asInt(c['id']))
              .whereType<int>()
              .toSet();
          final int? safeChannelId = (_selectedChannelId != null &&
                  channelIds.contains(_selectedChannelId))
              ? _selectedChannelId
              : null;

          final dedupGs = _dedupRowsByIntId(_gradingServices);
          final gsIds =
              dedupGs.map((s) => _asInt(s['id'])).whereType<int>().toSet();
          final int? safeGsId =
              (_gradingServiceId != null && gsIds.contains(_gradingServiceId))
                  ? _gradingServiceId
                  : null;

          final int? expectedDays = _selectedExpectedDays();
          final DateTime? baseAt = _atGraderDate;

          DateTime? expectedBack;
          int? businessDaysLeft;
          if (isSingle &&
              baseAt != null &&
              expectedDays != null &&
              expectedDays > 0) {
            expectedBack = _addBusinessDays(baseAt, expectedDays);
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            businessDaysLeft = _businessDaysBetween(today, expectedBack);
          }

          return Column(
            children: [
              EditSectionCard(
                title: 'Batch selection',
                subtitle:
                    'Choose how many items will be updated and how they are picked.',
                icon: Icons.tune,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Number of items to edit',
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: cs.outline.withOpacity(0.18)),
                          color: cs.surfaceVariant.withOpacity(0.18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Slider(
                                min: 1,
                                max: widget.availableQty.toDouble(),
                                divisions: widget.availableQty - 1 <= 0
                                    ? 1
                                    : widget.availableQty - 1,
                                value: _countToEdit.toDouble(),
                                label: '$_countToEdit',
                                onChanged: (v) => setState(() {
                                  _countToEdit =
                                      v.round().clamp(1, widget.availableQty);
                                  _countCtrl.text = _countToEdit.toString();
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _countCtrl,
                                onChanged: (t) {
                                  final n = int.tryParse(t) ?? _countToEdit;
                                  setState(() => _countToEdit =
                                      n.clamp(1, widget.availableQty));
                                },
                                decoration: const InputDecoration(
                                    isDense: true, hintText: 'Qty'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: _oldestFirst,
                      onChanged: (v) => setState(() => _oldestFirst = v),
                      title: const Text('Oldest first'),
                      subtitle: const Text('Disable to choose newest first'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Product & item info',
                icon: Icons.inventory_2_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Product name',
                      child: text(_productNameCtrl, hint: 'Product name'),
                    ),
                    LabeledField(
                      label: 'Type',
                      child: DropdownButtonFormField<String>(
                        value: _newType,
                        items: _stringItems(itemTypes, extra: _newType),
                        onChanged: (v) =>
                            setState(() => _newType = v ?? 'single'),
                        decoration: const InputDecoration(hintText: 'Type'),
                      ),
                    ),
                    LabeledField(
                      label: 'Language',
                      child: DropdownButtonFormField<String>(
                        value: _language,
                        items: _stringItems(langs, extra: _language),
                        onChanged: (v) => setState(() => _language = v ?? 'EN'),
                        decoration: const InputDecoration(hintText: 'Language'),
                      ),
                    ),
                    LabeledField(
                      label: 'Game',
                      child: DropdownButtonFormField<int?>(
                        value: safeGameId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— None —'),
                          ),
                          ...dedupGames.map((g) {
                            final id = _asInt(g['id']);
                            final label = (g['label'] ?? 'Game').toString();
                            if (id == null) {
                              return const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('—'),
                              );
                            }
                            return DropdownMenuItem<int?>(
                              value: id,
                              child:
                                  Text(label, overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: (v) => setState(() => _gameId = v),
                        decoration: const InputDecoration(hintText: 'Game'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Workflow',
                icon: Icons.flag_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Status',
                      child: SizedBox(
                        height: 48,
                        child: DropdownButtonFormField<String>(
                          value: currentStatus,
                          isDense: true,
                          isExpanded: true,
                          items: statusList
                              .map((s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: _statusRow(context, s),
                                  ))
                              .toList(),
                          selectedItemBuilder: (ctx2) => statusList
                              .map((s) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: _statusRow(ctx2, s),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _newStatus = v ?? widget.status),
                          decoration: const InputDecoration(
                              hintText: 'Choose a status'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Grading & location',
                icon: Icons.verified_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    if (isSingle)
                      LabeledField(
                        label: 'Grading service',
                        child: DropdownButtonFormField<int?>(
                          value: safeGsId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('— None —'),
                            ),
                            ...dedupGs.map((gs) {
                              final id = _asInt(gs['id']);
                              if (id == null) return null;
                              final label = (gs['label'] ?? '').toString();
                              final code = (gs['code'] ?? '').toString();
                              final days = gs['expected_days'];
                              final fee = gs['default_fee'];
                              final meta = [
                                if (code.isNotEmpty) code,
                                if (days != null) '${days}d',
                                if (fee != null) '\$${fee.toString()}',
                              ].join(' • ');
                              return DropdownMenuItem<int?>(
                                value: id,
                                child: Text(
                                  meta.isEmpty ? label : '$label ($meta)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).whereType<DropdownMenuItem<int?>>(),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _gradingServiceId = v;

                              if (_gradingFeesCtrl.text.trim().isEmpty &&
                                  v != null) {
                                final df = _selectedDefaultFee();
                                if (df != null) {
                                  _gradingFeesCtrl.text = df.toString();
                                }
                              }
                            });
                          },
                          decoration: const InputDecoration(
                              hintText: 'Choose a service'),
                        ),
                      ),
                    LabeledField(
                      label: 'Grade ID',
                      child:
                          text(_gradeIdCtrl, hint: 'PSA serial number, etc.'),
                    ),
                    LabeledField(
                      label: 'Grading Note',
                      child: text(_gradingNoteCtrl, hint: 'e.g.: Excellent'),
                    ),
                    LabeledField(
                      label: 'Grading Fees (USD)',
                      child: num(_gradingFeesCtrl,
                          hint: 'e.g.: 25.00', decimal: true),
                    ),
                    LabeledField(
                      label: 'Item Location',
                      child:
                          text(_itemLocationCtrl, hint: 'e.g.: Paris / Dubai'),
                    ),

                    if (isSingle)
                      LabeledField(
                        label: 'Sent to grader date',
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickSentToGraderDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                      hintText: 'YYYY-MM-DD'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Text(_fmtDate(_sentToGraderDate)),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Clear date',
                              onPressed: () =>
                                  setState(() => _sentToGraderDate = null),
                              icon: const Iconify(Mdi.close),
                            ),
                          ],
                        ),
                      ),
                    if (isSingle)
                      LabeledField(
                        label: 'At grader date',
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickAtGraderDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                      hintText: 'YYYY-MM-DD'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Text(_fmtDate(_atGraderDate)),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Clear date',
                              onPressed: () =>
                                  setState(() => _atGraderDate = null),
                              icon: const Iconify(Mdi.close),
                            ),
                          ],
                        ),
                      ),

                    // ✅ ETA display (business days)
                    if (isSingle)
                      LabeledField(
                        label: 'Estimated grading time',
                        child: InputDecorator(
                          decoration: const InputDecoration(hintText: '—'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  expectedBack == null
                                      ? 'Set "At grader date" + service to get ETA.'
                                      : 'Expected back: ${_fmtDate(expectedBack)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                if (expectedBack != null &&
                                    businessDaysLeft != null)
                                  Text(
                                    businessDaysLeft < 0
                                        ? 'Overdue: ${-businessDaysLeft} business day(s)'
                                        : 'Remaining: $businessDaysLeft business day(s)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: businessDaysLeft < 0
                                          ? Colors.redAccent
                                          : (businessDaysLeft <= 5
                                              ? Colors.orange
                                              : Colors.green),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Pricing',
                icon: Icons.payments_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Unit cost (USD)',
                      child: num(_unitCostCtrl,
                          hint: 'e.g.: 95.00', decimal: true),
                    ),
                    LabeledField(
                      label: 'Estimated price per unit (USD)',
                      child: num(_estimatedPriceCtrl,
                          hint: 'e.g.: 125.00', decimal: true),
                    ),
                    LabeledField(
                      label: 'Sale price ($_saleCurrency)',
                      child: num(_salePriceCtrl,
                          hint: 'e.g.: 145.00', decimal: true),
                    ),
                    LabeledField(
                      label: 'Sale currency',
                      child: DropdownButtonFormField<String>(
                        value: _saleCurrency,
                        items: saleCurrencies
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _saleCurrency = v ?? _saleCurrency),
                        decoration:
                            const InputDecoration(hintText: 'Sale currency'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Sale & shipping',
                icon: Icons.local_shipping_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Sale date',
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickSaleDate,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                    hintText: 'YYYY-MM-DD'),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    _saleDate == null
                                        ? '—'
                                        : _saleDate!
                                            .toIso8601String()
                                            .substring(0, 10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Clear date',
                            onPressed: () => setState(() => _saleDate = null),
                            icon: const Iconify(Mdi.close),
                          ),
                        ],
                      ),
                    ),
                    LabeledField(
                      label: 'Tracking',
                      child: text(_trackingCtrl,
                          hint: 'e.g.: UPS 1Z... / DHL *****...'),
                    ),
                    LabeledField(
                      label: 'Sale channel',
                      child: DropdownButtonFormField<int?>(
                        value: safeChannelId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— None —'),
                          ),
                          ...dedupChannels.map((c) {
                            final id = _asInt(c['id']);
                            if (id == null) return null;
                            final code = (c['code'] ?? '').toString();
                            final label = (c['label'] ?? '').toString();
                            final txt =
                                code.isNotEmpty ? '$label ($code)' : label;
                            return DropdownMenuItem<int?>(
                              value: id,
                              child: Text(txt, overflow: TextOverflow.ellipsis),
                            );
                          }).whereType<DropdownMenuItem<int?>>(),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedChannelId = v;
                          _channelIdCtrl.text = v?.toString() ?? '';
                        }),
                        decoration:
                            const InputDecoration(hintText: 'Choose a channel'),
                      ),
                    ),
                    LabeledField(
                      label: 'Buyer company',
                      child: text(_buyerCompanyCtrl, hint: 'Buyer company'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Parties & notes',
                icon: Icons.groups_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Supplier name',
                      child: text(_supplierNameCtrl, hint: 'Supplier'),
                    ),
                    LabeledField(
                      label: 'Notes',
                      child: text(_notesCtrl,
                          hint: 'Notes', minLines: 1, maxLines: 3),
                    ),
                    LabeledField(
                      label: 'Payment type',
                      child: text(_paymentTypeCtrl,
                          hint: 'e.g. PayPal / Bank / ...'),
                    ),
                    LabeledField(
                      label: 'Buyer infos',
                      child: text(
                        _buyerInfosCtrl,
                        hint: 'Name / Address / Order ref...',
                        minLines: 1,
                        maxLines: 3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Fees',
                subtitle:
                    'Totals are split across edited items when applying the update.',
                icon: Icons.percent_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    LabeledField(
                      label: 'Shipping fees (USD)',
                      child: num(_shippingFeesCtrl,
                          hint: 'e.g.: 12.50', decimal: true),
                    ),
                    LabeledField(
                      label: 'Commission fees (USD)',
                      child: num(_commissionFeesCtrl,
                          hint: 'e.g.: 5.90', decimal: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              EditSectionCard(
                title: 'Files',
                icon: Icons.attach_file_outlined,
                child: ResponsiveWrapFields(
                  maxWidth: cons.maxWidth,
                  children: [
                    StorageUploadTile(
                      label: 'Upload / View photo',
                      bucket: 'item-photos',
                      objectPrefix: 'items/${widget.productId}',
                      initialUrl: _photoUrlCtrl.text.isEmpty
                          ? null
                          : _photoUrlCtrl.text,
                      onUrlChanged: (u) =>
                          setState(() => _photoUrlCtrl.text = u ?? ''),
                      acceptImagesOnly: true,
                      onError: (err) => _showUploadError(err),
                    ),
                    StorageUploadTile(
                      label: 'Upload / Open document',
                      bucket: 'item-docs',
                      objectPrefix: 'items/${widget.productId}',
                      initialUrl: _documentUrlCtrl.text.isEmpty
                          ? null
                          : _documentUrlCtrl.text,
                      onUrlChanged: (u) =>
                          setState(() => _documentUrlCtrl.text = u ?? ''),
                      acceptDocsOnly: true,
                      onError: (err) => _showUploadError(err),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final actions = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.12))),
        color: cs.surface,
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving ? null : _apply,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Iconify(Mdi.content_save),
            label: const Text('Apply'),
          ),
        ],
      ),
    );

    return Theme(
      data: decoratedTheme,
      child: LayoutBuilder(
        builder: (ctx, cons) {
          return SizedBox(
            width: cons.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: content,
                  ),
                ),
                actions,
              ],
            ),
          );
        },
      ),
    );
  }

  void _showUploadError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invalid filename'),
        content: Text(
          'File name must not contain spaces or special characters.\n\n'
          'Details: $message',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
