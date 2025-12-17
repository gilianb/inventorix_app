// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_upload_tile.dart';

// 🔐 RBAC (conservé mais NON utilisé pour masquer quoi que ce soit)
import 'package:inventorix_app/org/roles.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

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
        final maxW = mq.size.width * 0.95;
        final maxH = mq.size.height * 0.90;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 880, maxHeight: maxH),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: mq.size.height * 0.5,
                  maxWidth: maxW,
                ),
                child: EditItemsDialog(
                  productId: productId,
                  status: status,
                  availableQty: availableQty,
                  initialSample: initialSample,
                ),
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
  //final OrgRole _role = OrgRole.viewer;
  bool _roleLoaded = false;
  //RolePermissions get _perm => kRoleMatrix[_role]!;

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
  final _channelIdCtrl = TextEditingController();
  final _buyerCompanyCtrl = TextEditingController();
  final _supplierNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  final _documentUrlCtrl = TextEditingController();
  final _unitCostCtrl = TextEditingController();

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

  bool _saving = false;

  // Statuts
  static const List<String> kAllStatuses = [
    'ordered',
    'paid',
    'in_transit',
    'received',
    'waiting_for_gradation',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
    'vault',
  ];

  static const langs = ['EN', 'FR', 'JP'];
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
    // 1) Pré-remplissage avec l’échantillon passé (peut être incomplet)
    final s = _sample;
    _newStatus = _coerceString(widget.status, kAllStatuses, kAllStatuses.first);

    _gradeIdCtrl.text = (s['grade_id'] ?? '').toString();
    _gradingNoteCtrl.text = (s['grading_note'] ?? '').toString();
    _gradingFeesCtrl.text = _numToText(s['grading_fees']);
    _estimatedPriceCtrl.text = _numToText(s['estimated_price']);
    _salePriceCtrl.text = _numToText(s['sale_price']);
    _saleDate = _parseDate(s['sale_date']);
    _itemLocationCtrl.text = (s['item_location'] ?? '').toString();
    _trackingCtrl.text = (s['tracking'] ?? '').toString();
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

    // ✅ sale_currency (prioritaire), fallback legacy sur currency
    final preSaleCur =
        (s['sale_currency'] ?? s['currency'] ?? 'USD').toString();
    _saleCurrency = _coerceString(preSaleCur, saleCurrencies, 'USD');

    // 2) Rôle (non bloquant ici)
    await _loadRole();

    // 3) Jeux (pour dropdown)
    await _loadGames();

    // 4) 🔥 HYDRATATION depuis la DB : on complète chaque champ manquant
    await _hydrateFromDb();

    if (mounted) setState(() {});
  }

  Future<void> _loadRole() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      final orgId = (_sample['org_id']?.toString().isNotEmpty ?? false)
          ? _sample['org_id'].toString()
          : null;

      if (uid == null) {
        setState(() => _roleLoaded = true);
        return;
      }

      if (orgId == null) {
        setState(() {
          _roleLoaded = true;
        });
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

      if (mounted) {
        setState(() {
          _roleLoaded = true;
        });
      }
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
    final seen = <String>{...allowed};
    final out = <DropdownMenuItem<String>>[
      for (final s in allowed) DropdownMenuItem(value: s, child: Text(s)),
    ];
    if (extra != null && extra.isNotEmpty && !seen.contains(extra)) {
      out.insert(0, DropdownMenuItem(value: extra, child: Text(extra)));
    }
    return out;
  }

  Future<void> _loadGames() async {
    try {
      final raw =
          await _sb.from('games').select('id, code, label').order('label');
      setState(() {
        final list = raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final sampleGameId = _asInt(_sample['game_id']);
        if (sampleGameId != null && !list.any((g) => g['id'] == sampleGameId)) {
          list.insert(0, {'id': sampleGameId, 'label': 'Game #$sampleGameId'});
        }

        _games = list;

        if (sampleGameId != null) {
          _gameId = sampleGameId;
        } else {
          _gameId ??= _games.isNotEmpty ? _games.first['id'] as int : null;
        }
      });
    } catch (_) {}
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
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

    // Champs qu’on souhaite hydrater depuis 'item'
    // (✅ on ajoute sale_currency ; on garde currency pour fallback legacy)
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
    ];

    List<Map<String, dynamic>> rows = const [];

    try {
      if (groupSig != null && groupSig.isNotEmpty) {
        // Cas le plus fiable : group_sig
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
        // Fallback : filtre par product_id + status + clés fortes présentes
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

    void fillIfEmpty(TextEditingController c, dynamic value,
        {bool intCast = false}) {
      if (c.text.trim().isEmpty && value != null) {
        if (intCast && value is num) {
          c.text = value.toInt().toString();
        } else {
          c.text = value.toString();
        }
      }
    }

    fillIfEmpty(_gradeIdCtrl, firstNonNull('grade_id'));
    fillIfEmpty(_gradingNoteCtrl, firstNonNull('grading_note'));
    fillIfEmpty(_gradingFeesCtrl, firstNonNull('grading_fees'));
    fillIfEmpty(_estimatedPriceCtrl, firstNonNull('estimated_price'));
    fillIfEmpty(_salePriceCtrl, firstNonNull('sale_price'));
    fillIfEmpty(_itemLocationCtrl, firstNonNull('item_location'));
    fillIfEmpty(_trackingCtrl, firstNonNull('tracking'));
    fillIfEmpty(_channelIdCtrl, firstNonNull('channel_id'), intCast: true);
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
      final gid = _asInt(maybeGame);
      if (gid != null) _gameId = gid;
    }

    final maybeSaleDate = firstNonNull('sale_date');
    if (_saleDate == null && maybeSaleDate != null) {
      _saleDate = _parseDate(maybeSaleDate);
    }

    // ✅ sale_currency : priorité ; fallback legacy sur currency
    final maybeSaleCurrency = firstNonNull('sale_currency')?.toString();
    final maybeLegacyCurrency = firstNonNull('currency')?.toString();
    final resolved = (maybeSaleCurrency != null && maybeSaleCurrency.isNotEmpty)
        ? maybeSaleCurrency
        : (maybeLegacyCurrency != null && maybeLegacyCurrency.isNotEmpty
            ? maybeLegacyCurrency
            : _saleCurrency);
    _saleCurrency = _coerceString(resolved, saleCurrencies, _saleCurrency);

    // 🔎 Produit : si product_name vide, essayer depuis 'product'
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

  int? _tryInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  // === Helpers de comparaison "changement" ===
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

  bool _changedInt(String key, String currentText) {
    final oldRaw = _sample[key];
    final old = oldRaw == null ? null : int.tryParse(oldRaw.toString());
    final cur = _tryInt(currentText);
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

  // retourne une map pour item avec uniquement les champs modifiés
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

    void putInt(String key, TextEditingController c) {
      if (_changedInt(key, c.text)) {
        m[key] = _tryInt(c.text);
      }
    }

    // Tous les champs sont libres (plus de RBAC ici)
    putText('grade_id', _gradeIdCtrl);
    putText('grading_note', _gradingNoteCtrl);
    putNum('grading_fees', _gradingFeesCtrl);
    putNum('estimated_price', _estimatedPriceCtrl);
    putText('item_location', _itemLocationCtrl);
    putText('tracking', _trackingCtrl);
    putInt('channel_id', _channelIdCtrl);
    putText('buyer_company', _buyerCompanyCtrl);
    putText('supplier_name', _supplierNameCtrl);
    putText('notes', _notesCtrl);
    putText('photo_url', _photoUrlCtrl);
    putText('document_url', _documentUrlCtrl);
    putNum('unit_cost', _unitCostCtrl);

    // Nouveaux champs item
    if (_changedSimple('type', _newType)) m['type'] = _newType;
    if (_changedSimple('language', _language)) m['language'] = _language;
    if (_changedSimple('game_id', _gameId)) m['game_id'] = _gameId;

    // ✅ sale_currency UNIQUEMENT (ne touche plus "currency")
    final oldSaleCur =
        (_sample['sale_currency'] ?? _sample['currency'] ?? 'USD').toString();
    if (oldSaleCur != _saleCurrency) {
      m['sale_currency'] = _saleCurrency;
    }

    // Frais totaux (répartis plus tard)
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

    // Sale fields
    if (_changedNum('sale_price', _salePriceCtrl.text)) {
      m['sale_price'] = _tryNum(_salePriceCtrl.text);
    }
    if (_changedDate('sale_date', _saleDate)) {
      m['sale_date'] = _saleDate?.toIso8601String().substring(0, 10);
    }

    // Status
    final statusBefore = widget.status;
    final statusAfter = (_newStatus.isNotEmpty ? _newStatus : statusBefore);
    if (statusAfter != statusBefore) {
      m['status'] = statusAfter;
    }

    return m;
  }

  // mise à jour du produit si name/type changent
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

  // ===== Batch diff pour le log (1 événement) =====
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

    // ✅ sale_currency (log)
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

  // ===== FIX group_sig-first =====
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

      // Division des frais totaux en "par unité" (pour l'UPDATE uniquement)
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_roleLoaded) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    Widget numberField(TextEditingController c, String hint,
        {bool decimal = true, bool enabled = true}) {
      return TextField(
        controller: c,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(hintText: hint),
      );
    }

    Widget labelWithField(String label, Widget field) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          field,
        ],
      );
    }

    // ==== Responsive helper (évite overflow) ====
    Widget wrapFields(BoxConstraints cons, List<Widget> children) {
      final w = cons.maxWidth;

      // largeur "cellule" : 1 colonne sur petit écran, 2 sur moyen, 3-4 sur large
      double cellW;
      if (w >= 980) {
        cellW = (w - 12 * 3) / 4;
      } else if (w >= 720) {
        cellW = (w - 12) / 2;
      } else {
        cellW = w;
      }

      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in children) SizedBox(width: cellW, child: c),
        ],
      );
    }

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.edit, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Edit ${widget.availableQty} item(s) — status "${widget.status}"',
              style: Theme.of(context).textTheme.titleMedium,
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

    final general = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          return Column(
            children: [
              // ====== TOP: count + oldest/newest ======
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cons.maxWidth >= 720
                        ? (cons.maxWidth - 12) / 2
                        : cons.maxWidth,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Number of items to edit',
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
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: _countCtrl,
                              onChanged: (t) {
                                final n = int.tryParse(t) ?? _countToEdit;
                                setState(() => _countToEdit =
                                    n.clamp(1, widget.availableQty));
                              },
                              decoration: const InputDecoration(isDense: true),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: cons.maxWidth >= 720
                        ? (cons.maxWidth - 12) / 2
                        : cons.maxWidth,
                    child: SwitchListTile(
                      value: _oldestFirst,
                      onChanged: (v) => setState(() => _oldestFirst = v),
                      title: const Text('Selection: oldest first'),
                      subtitle: const Text('Disable to choose newest first'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ====== PRODUIT / ITEM DE TÊTE ======
              wrapFields(cons, [
                labelWithField(
                  'Product name',
                  TextField(
                    controller: _productNameCtrl,
                    decoration: const InputDecoration(hintText: 'Product name'),
                  ),
                ),
                labelWithField(
                  'Type',
                  DropdownButtonFormField<String>(
                    value: _newType,
                    items: _stringItems(itemTypes, extra: _newType),
                    onChanged: (v) => setState(() => _newType = v ?? 'single'),
                    decoration: const InputDecoration(hintText: 'Type'),
                  ),
                ),
                labelWithField(
                  'Language',
                  DropdownButtonFormField<String>(
                    value: _language,
                    items: _stringItems(langs, extra: _language),
                    onChanged: (v) => setState(() => _language = v ?? 'EN'),
                    decoration: const InputDecoration(hintText: 'Language'),
                  ),
                ),
                labelWithField(
                  'Game',
                  DropdownButtonFormField<int>(
                    value: _gameId,
                    items: _games
                        .map((g) => DropdownMenuItem<int>(
                              value: g['id'] as int,
                              child: Text(g['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _gameId = v),
                    decoration: const InputDecoration(hintText: 'Game'),
                  ),
                ),
                // ✅ sale_currency only
              ]),
              const SizedBox(height: 12),

              // ====== STATUS ======
              labelWithField(
                'Status',
                DropdownButtonFormField<String>(
                  value: (_newStatus.isNotEmpty ? _newStatus : widget.status),
                  items: _stringItems(
                    kAllStatuses,
                    extra: _newStatus.isNotEmpty ? _newStatus : widget.status,
                  ),
                  onChanged: (v) =>
                      setState(() => _newStatus = v ?? widget.status),
                  decoration:
                      const InputDecoration(hintText: 'Choose a status'),
                ),
              ),
              const SizedBox(height: 12),

              // ====== LIGNE 1 ======
              wrapFields(cons, [
                labelWithField(
                  'Grade ID',
                  TextField(
                    controller: _gradeIdCtrl,
                    decoration: const InputDecoration(
                        hintText: 'PSA serial number, etc.'),
                  ),
                ),
                labelWithField(
                  'Grading Note',
                  TextField(
                    controller: _gradingNoteCtrl,
                    decoration:
                        const InputDecoration(hintText: 'e.g.: Excellent'),
                  ),
                ),
                // ✅ USD only
                labelWithField(
                  'Grading Fees (USD)',
                  numberField(_gradingFeesCtrl, 'e.g.: 25.00', decimal: true),
                ),
                labelWithField(
                  'Item Location',
                  TextField(
                    controller: _itemLocationCtrl,
                    decoration:
                        const InputDecoration(hintText: 'e.g.: Paris / Dubai'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 2 ======
              wrapFields(cons, [
                // ✅ USD only
                labelWithField('Unit cost (USD)',
                    numberField(_unitCostCtrl, 'e.g.: 95.00', decimal: true)),
                // ✅ USD only
                labelWithField(
                  'Estimated price per unit (USD)',
                  numberField(_estimatedPriceCtrl, 'e.g.: 125.00',
                      decimal: true),
                ),
                // ✅ sale currency only
                labelWithField(
                  'Sale price ($_saleCurrency)',
                  numberField(_salePriceCtrl, 'e.g.: 145.00', decimal: true),
                ),
                labelWithField(
                  'Sale currency',
                  DropdownButtonFormField<String>(
                    value: _saleCurrency,
                    items: saleCurrencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _saleCurrency = v ?? _saleCurrency),
                    decoration:
                        const InputDecoration(hintText: 'Sale currency'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 3 ======
              wrapFields(cons, [
                labelWithField(
                  'Sale date',
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickSaleDate,
                          child: InputDecorator(
                            decoration:
                                const InputDecoration(hintText: 'YYYY-MM-DD'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
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
                labelWithField(
                  'Tracking',
                  TextField(
                    controller: _trackingCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g.: UPS 1Z... / DHL *****...',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 4 ======
              wrapFields(cons, [
                labelWithField(
                  'Sale location (Channel ID)',
                  TextField(
                    controller: _channelIdCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                    decoration: const InputDecoration(hintText: 'e.g.: 12'),
                  ),
                ),
                labelWithField(
                  'Buyer company',
                  TextField(
                    controller: _buyerCompanyCtrl,
                    decoration:
                        const InputDecoration(hintText: 'Buyer company'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 5 ======
              wrapFields(cons, [
                labelWithField(
                  'Supplier name',
                  TextField(
                    controller: _supplierNameCtrl,
                    decoration: const InputDecoration(hintText: 'Supplier'),
                  ),
                ),
                labelWithField(
                  'Notes',
                  TextField(
                    controller: _notesCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Notes'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 6 (frais & paiements) ======
              wrapFields(cons, [
                // ✅ USD only
                labelWithField(
                  'Shipping fees (USD)',
                  numberField(_shippingFeesCtrl, 'e.g.: 12.50', decimal: true),
                ),
                // ✅ USD only
                labelWithField(
                  'Commission fees (USD)',
                  numberField(_commissionFeesCtrl, 'e.g.: 5.90', decimal: true),
                ),
              ]),
              const SizedBox(height: 12),

              wrapFields(cons, [
                labelWithField(
                  'Payment type',
                  TextField(
                    controller: _paymentTypeCtrl,
                    decoration: const InputDecoration(
                        hintText: 'e.g. PayPal / Bank / ...'),
                  ),
                ),
                labelWithField(
                  'Buyer infos',
                  TextField(
                    controller: _buyerInfosCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        hintText: 'Name / Address / Order ref...'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ====== LIGNE 7 : Fichiers ======
              wrapFields(cons, [
                labelWithField(
                  'Photo',
                  StorageUploadTile(
                    label: 'Upload / View photo',
                    bucket: 'item-photos',
                    objectPrefix: 'items/${widget.productId}',
                    initialUrl:
                        _photoUrlCtrl.text.isEmpty ? null : _photoUrlCtrl.text,
                    onUrlChanged: (u) =>
                        setState(() => _photoUrlCtrl.text = u ?? ''),
                    acceptImagesOnly: true,
                    onError: (err) => _showUploadError(err),
                  ),
                ),
                labelWithField(
                  'Document',
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
                ),
              ]),
            ],
          );
        },
      ),
    );

    final actions = Padding(
      padding: const EdgeInsets.all(16),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const Divider(height: 1),
        const SizedBox(height: 8),
        general,
        const SizedBox(height: 8),
        actions,
      ],
    );
  }

  // ====== popup d'erreur d'upload ======
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
