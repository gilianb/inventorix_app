import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_upload_tile.dart';

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

  // combien d'items modifier dans ce groupe
  late int _countToEdit;

  // appliquer sur les items les plus anciens (id ASC) ou récents (id DESC)
  bool _oldestFirst = true;

  // ======= CONTRÔLEURS ======= (plus de cases à cocher)
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

  // Nouveaux contrôleurs
  String _newType = 'single'; // 'single' | 'sealed'
  final _productNameCtrl = TextEditingController();
  String _language = 'EN';
  int? _gameId; // via dropdown
  final _shippingFeesCtrl = TextEditingController();
  final _commissionFeesCtrl = TextEditingController();
  final _paymentTypeCtrl = TextEditingController();
  final _buyerInfosCtrl = TextEditingController();

  // Jeux pour dropdown
  List<Map<String, dynamic>> _games = const [];

  bool _saving = false;

  // Statuts
  static const List<String> kAllStatuses = [
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
    'collection',
  ];

  static const langs = ['EN', 'FR', 'JP'];
  static const itemTypes = ['single', 'sealed'];

  Map<String, dynamic> get _sample => (widget.initialSample ?? const {});

  // Helpers de coercition (assure une valeur valide dans les dropdowns)
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

  @override
  void initState() {
    super.initState();
    _countToEdit = widget.availableQty.clamp(1, 999999);
    final s = _sample;

    // Coercition pour éviter des valeurs hors liste
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

    _loadGames();
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

        // Si le game_id du sample n'existe plus en DB, on l'injecte comme placeholder
        final sampleGameId = _asInt(_sample['game_id']);
        if (sampleGameId != null && !list.any((g) => g['id'] == sampleGameId)) {
          list.insert(0, {
            'id': sampleGameId,
            'label': 'Game #$sampleGameId',
          });
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

  @override
  void dispose() {
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

    // Text -> NULL si vide (si différent)
    void putText(String key, TextEditingController c) {
      if (_changedText(key, c.text)) {
        m[key] = c.text.trim().isEmpty ? null : c.text.trim();
      }
    }

    // Num -> peut être NULL (effacé)
    void putNum(String key, TextEditingController c) {
      if (_changedNum(key, c.text)) {
        m[key] = _tryNum(c.text);
      }
    }

    // Int -> peut être NULL
    void putInt(String key, TextEditingController c) {
      if (_changedInt(key, c.text)) {
        m[key] = _tryInt(c.text);
      }
    }

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
    putNum('unit_cost', _unitCostCtrl); // 👈 ajout

    // Nouveaux champs item
    if (_changedSimple('type', _newType)) m['type'] = _newType;
    if (_changedSimple('language', _language)) m['language'] = _language;
    if (_changedSimple('game_id', _gameId)) m['game_id'] = _gameId;
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

  Future<void> _apply() async {
    final baseUpdates = _buildItemUpdates();
    final productUpdates = _buildProductUpdates();

    if (baseUpdates.isEmpty && productUpdates.isEmpty) {
      _snack('Aucun changement détecté.');
      return;
    }

    setState(() => _saving = true);
    try {
      final sample = Map<String, dynamic>.from(_sample)
        ..putIfAbsent('product_id', () => widget.productId);

      // === 1) IDs strictement du même groupe (NULL = NULL) ===
      PostgrestFilterBuilder idsQ = _sb.from('item').select('id');

      const keys = <String>{
        'product_id',
        'game_id',
        'type',
        'language',
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
        'item_location',
        'channel_id',
        'unit_cost', // 👈 ajout
      };

      for (final k in keys) {
        if (!sample.containsKey(k)) continue;
        final v = sample[k];
        if (v == null) {
          idsQ = idsQ.filter(k, 'is', null);
        } else {
          idsQ = idsQ.eq(k, v);
        }
      }

      idsQ = idsQ.eq('status', widget.status);

      final idsRaw =
          await idsQ.order('id', ascending: _oldestFirst).limit(_countToEdit);
      final ids = idsRaw.map((e) => (e as Map)['id']).whereType<int>().toList();

      if (ids.isEmpty) {
        _snack("Aucun item trouvé à mettre à jour pour CETTE ligne.");
        return;
      }

      // === 2) Apply updates UNIQUEMENT aux IDs ===
      final idsCsv = '(${ids.join(",")})';
      if (baseUpdates.isNotEmpty) {
        await _sb.from('item').update(baseUpdates).filter('id', 'in', idsCsv);
      }

      if (productUpdates.isNotEmpty) {
        await _sb
            .from('product')
            .update(productUpdates)
            .eq('id', widget.productId);
      }

      if (mounted) {
        _snack('Mise à jour effectuée (${ids.length} item(s)).');
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
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

    Widget numberField(TextEditingController c, String hint,
        {bool decimal = true}) {
      return TextField(
        controller: c,
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

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.edit, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modifier ${widget.availableQty} item(s) — statut "${widget.status}"',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
            tooltip: 'Fermer',
          ),
        ],
      ),
    );

    final countController =
        TextEditingController(text: _countToEdit.toString());

    final general = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Nombre d’items à modifier',
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
                        onChanged: (v) => setState(
                          () => _countToEdit =
                              v.round().clamp(1, widget.availableQty),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: countController,
                        onChanged: (t) {
                          final n = int.tryParse(t) ?? _countToEdit;
                          setState(() =>
                              _countToEdit = n.clamp(1, widget.availableQty));
                        },
                        decoration: const InputDecoration(isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile(
                value: _oldestFirst,
                onChanged: (v) => setState(() => _oldestFirst = v),
                title: const Text('Sélection : plus anciens d’abord'),
                subtitle: const Text('Désactive pour choisir les plus récents'),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== PRODUIT / ITEM DE TÊTE ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Product name',
                TextField(
                  controller: _productNameCtrl,
                  decoration: const InputDecoration(hintText: 'Nom du produit'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Type',
                DropdownButtonFormField<String>(
                  value: _newType,
                  items: _stringItems(itemTypes, extra: _newType),
                  onChanged: (v) => setState(() => _newType = v ?? 'single'),
                  decoration: const InputDecoration(hintText: 'Type'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: labelWithField(
                'Language',
                DropdownButtonFormField<String>(
                  value: _language,
                  items: _stringItems(langs, extra: _language),
                  onChanged: (v) => setState(() => _language = v ?? 'EN'),
                  decoration: const InputDecoration(hintText: 'Langue'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Jeu',
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
            ),
          ]),
          const SizedBox(height: 8),

          // ====== STATUS ======
          labelWithField(
            'Status',
            DropdownButtonFormField<String>(
              value: (_newStatus.isNotEmpty ? _newStatus : widget.status),
              items: _stringItems(kAllStatuses,
                  extra: _newStatus.isNotEmpty ? _newStatus : widget.status),
              onChanged: (v) => setState(() => _newStatus = v ?? widget.status),
              decoration: const InputDecoration(hintText: 'Choisir un statut'),
            ),
          ),
          const SizedBox(height: 8),

          // ====== LIGNE 1 ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Grade ID',
                TextField(
                  controller: _gradeIdCtrl,
                  decoration: const InputDecoration(
                      hintText: 'PSA serial number, etc.'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Grading Note',
                TextField(
                  controller: _gradingNoteCtrl,
                  decoration: const InputDecoration(hintText: 'ex: Excellent'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Grading Fees (USD)',
                numberField(_gradingFeesCtrl, 'ex: 25.00', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Item Location',
                TextField(
                  controller: _itemLocationCtrl,
                  decoration:
                      const InputDecoration(hintText: 'ex: Paris / Dubai'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 2 ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Unit cost (USD)',
                numberField(_unitCostCtrl, 'ex: 95.00', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Estimated price per unit (USD)',
                numberField(_estimatedPriceCtrl, 'ex: 125.00', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Sale price',
                numberField(_salePriceCtrl, 'ex: 145.00', decimal: true),
              ),
            ),
          ]),

          // ====== LIGNE 3 ======
          Row(children: [
            Expanded(
              child: labelWithField(
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
                      tooltip: 'Effacer la date',
                      onPressed: () => setState(() => _saleDate = null),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Tracking',
                TextField(
                  controller: _trackingCtrl,
                  decoration: const InputDecoration(
                      hintText: 'ex: UPS 1Z... / DHL *****...'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 4 ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Endroit de vente (Channel ID)',
                numberField(_channelIdCtrl, 'ex: 12', decimal: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Buyer company',
                TextField(
                  controller: _buyerCompanyCtrl,
                  decoration:
                      const InputDecoration(hintText: 'Société acheteuse'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 5 ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Supplier name',
                TextField(
                  controller: _supplierNameCtrl,
                  decoration: const InputDecoration(hintText: 'Fournisseur'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Notes',
                TextField(
                  controller: _notesCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Notes'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 6 (frais & paiements) ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Shipping fees (USD)',
                numberField(_shippingFeesCtrl, 'ex: 12.50', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Commission fees (USD)',
                numberField(_commissionFeesCtrl, 'ex: 5.90', decimal: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: labelWithField(
                'Payment type',
                TextField(
                  controller: _paymentTypeCtrl,
                  decoration: const InputDecoration(
                      hintText: 'e.g. PayPal / Bank / ...'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Buyer infos',
                TextField(
                  controller: _buyerInfosCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Nom / Adresse / Réf. commande...'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 7 : Fichiers ======
          Row(children: [
            Expanded(
              child: labelWithField(
                'Photo',
                StorageUploadTile(
                  label: 'Uploader / Voir photo',
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: labelWithField(
                'Document',
                StorageUploadTile(
                  label: 'Uploader / Ouvrir document',
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
            ),
          ]),
        ],
      ),
    );

    final actions = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving ? null : _apply,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Appliquer'),
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
        title: const Text('Nom de fichier invalide'),
        content: Text(
          'Le nom du fichier ne doit pas contenir d’espaces ni de caractères spéciaux.\n\n'
          'Détail : $message',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }
}
