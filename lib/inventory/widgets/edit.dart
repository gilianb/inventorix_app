import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_upload_tile.dart';

/// Dialog d'édition en masse d'UN groupe strict (la ligne cliquée)
/// - N'édite QUE les items correspondant exactement à la ligne (toutes clés identiques, NULL = NULL) + le statut courant
/// - Permet de choisir la quantité à modifier (1..availableQty)
/// - Permet de cocher les champs à mettre à jour et saisir les valeurs
/// - Applique les modifs aux N items sélectionnés (par défaut: plus anciens id)
class EditItemsDialog extends StatefulWidget {
  const EditItemsDialog({
    super.key,
    required this.productId,
    required this.status,
    required this.availableQty,
    required this.initialSample, // la "ligne" cliquée (contient les clés du groupe)
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

  // ======= FLAGS d'inclusion =======
  bool incStatus = false;
  bool incGradeId = false;
  bool incGradingNote = false;
  bool incGradingFees = false;
  bool incEstimatedPrice = false;
  bool incSalePrice = false;
  bool incSaleDate = false;
  bool incItemLocation = false;
  bool incTracking = false;
  bool incChannelId = false;
  bool incBuyerCompany = false;
  bool incSupplierName = false;
  bool incNotes = false;
  bool incPhotoUrl = false;
  bool incDocumentUrl = false;

  // Nouveaux champs
  bool incType = false;
  bool incProductName = false;
  bool incLanguage = false;
  bool incGameId = false;
  bool incShippingFees = false;
  bool incCommissionFees = false;
  bool incPaymentType = false;
  bool incBuyerInfos = false;

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

  // Ajout du statut awaiting_payment
  static const List<String> kAllStatuses = [
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'awaiting_payment', // ⬅︎ ajouté
    'sold',
    'shipped',
    'finalized',
    'collection',
  ];

  static const Set<String> kSalePhase = {'sold', 'shipped', 'finalized'};

  static const langs = ['EN', 'FR', 'JP'];
  static const itemTypes = ['single', 'sealed'];

  @override
  void initState() {
    super.initState();
    _countToEdit = widget.availableQty.clamp(1, 999999);
    // Pré-remplissage à partir de l'échantillon (la ligne cliquée)
    final s = widget.initialSample ?? const {};
    _newStatus = widget.status;

    _gradeIdCtrl.text = (s['grade_id'] ?? '').toString();
    _gradingNoteCtrl.text = (s['grading_note'] ?? '').toString();
    _gradingFeesCtrl.text = _numToText(s['grading_fees']);
    // robustesse: si la vue renvoie null on met vide
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

    // Nouveaux champs
    _newType = (s['type'] ?? 'single').toString().isEmpty
        ? 'single'
        : (s['type'] ?? 'single').toString();
    _productNameCtrl.text = (s['product_name'] ?? '').toString();
    _language = (s['language'] ?? 'EN').toString().isEmpty
        ? 'EN'
        : (s['language'] ?? 'EN').toString();
    _gameId = _asInt(s['game_id']);
    _shippingFeesCtrl.text = _numToText(s['shipping_fees']); // si exposé
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
        _games = raw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // si pas de game défini, on prend le premier
        _gameId ??= _games.isNotEmpty ? _games.first['id'] as int : null;
      });
    } catch (_) {
      // silencieux
    }
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

    _productNameCtrl.dispose();
    _shippingFeesCtrl.dispose();
    _commissionFeesCtrl.dispose();
    _paymentTypeCtrl.dispose();
    _buyerInfosCtrl.dispose();
    super.dispose();
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

  Future<void> _apply() async {
    // === 1) Construire l'update de façon SÛRE et ciblée ===
    final baseUpdates = <String, dynamic>{};
    if (incGradeId) {
      baseUpdates['grade_id'] =
          _gradeIdCtrl.text.trim().isEmpty ? null : _gradeIdCtrl.text.trim();
    }

    if (incGradingNote) {
      baseUpdates['grading_note'] = _gradingNoteCtrl.text.trim().isEmpty
          ? null
          : _gradingNoteCtrl.text.trim();
    }
    if (incGradingFees) {
      baseUpdates['grading_fees'] = _tryNum(_gradingFeesCtrl.text);
    }
    if (incEstimatedPrice) {
      baseUpdates['estimated_price'] = _tryNum(_estimatedPriceCtrl.text);
    }
    if (incItemLocation) {
      baseUpdates['item_location'] = _itemLocationCtrl.text.trim().isEmpty
          ? null
          : _itemLocationCtrl.text.trim();
    }
    if (incTracking) {
      baseUpdates['tracking'] =
          _trackingCtrl.text.trim().isEmpty ? null : _trackingCtrl.text.trim();
    }
    if (incChannelId) baseUpdates['channel_id'] = _tryInt(_channelIdCtrl.text);
    if (incBuyerCompany) {
      baseUpdates['buyer_company'] = _buyerCompanyCtrl.text.trim().isEmpty
          ? null
          : _buyerCompanyCtrl.text.trim();
    }
    if (incSupplierName) {
      baseUpdates['supplier_name'] = _supplierNameCtrl.text.trim().isEmpty
          ? null
          : _supplierNameCtrl.text.trim();
    }
    if (incNotes) {
      baseUpdates['notes'] =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    }
    if (incPhotoUrl) {
      baseUpdates['photo_url'] =
          _photoUrlCtrl.text.trim().isEmpty ? null : _photoUrlCtrl.text.trim();
    }
    if (incDocumentUrl) {
      baseUpdates['document_url'] = _documentUrlCtrl.text.trim().isEmpty
          ? null
          : _documentUrlCtrl.text.trim();
    }

    // Nouveaux champs (items)
    if (incType) baseUpdates['type'] = _newType;
    if (incLanguage) baseUpdates['language'] = _language;
    if (incGameId) baseUpdates['game_id'] = _gameId;
    if (incShippingFees) {
      baseUpdates['shipping_fees'] = _tryNum(_shippingFeesCtrl.text);
    }
    if (incCommissionFees) {
      baseUpdates['commission_fees'] = _tryNum(_commissionFeesCtrl.text);
    }
    if (incPaymentType) {
      baseUpdates['payment_type'] = _paymentTypeCtrl.text.trim().isEmpty
          ? null
          : _paymentTypeCtrl.text.trim();
    }
    if (incBuyerInfos) {
      baseUpdates['buyer_infos'] = _buyerInfosCtrl.text.trim().isEmpty
          ? null
          : _buyerInfosCtrl.text.trim();
    }

    // Champs de vente (appliqués UNIQUEMENT sur les IDs ciblés)
    final saleUpdates = <String, dynamic>{};
    if (incSalePrice) saleUpdates['sale_price'] = _tryNum(_salePriceCtrl.text);
    if (incSaleDate) {
      saleUpdates['sale_date'] = _saleDate?.toIso8601String().substring(0, 10);
    }

    // Changement de statut
    String? newStatus;
    if (incStatus) newStatus = _newStatus;

    // Mise à jour du produit (name/type)
    final productUpdates = <String, dynamic>{};
    if (incProductName) {
      final n = _productNameCtrl.text.trim();
      productUpdates['name'] = n.isEmpty ? null : n;
    }
    if (incType) {
      // aligner product.type sur item.type
      productUpdates['type'] = _newType;
    }

    if (baseUpdates.isEmpty &&
        saleUpdates.isEmpty &&
        newStatus == null &&
        productUpdates.isEmpty) {
      _snack('Sélectionne au moins un champ à modifier.');
      return;
    }

    setState(() => _saving = true);
    try {
      final sample = (widget.initialSample ?? {})
        ..putIfAbsent('product_id', () => widget.productId);

      // === 2) Sélectionner exactement N IDs, strictement ===
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
        // 'unit_cost', 'unit_fees' si tu veux rendre encore plus strict
        // NB: on n'utilise pas shipping/commission/payment/buyer_infos pour filtrer
        // car ces champs peuvent être nouvellement ajoutés et souvent NULL.
      };

      for (final k in keys) {
        if (!sample.containsKey(k)) continue;
        final v = sample[k];
        if (v == null) {
          idsQ = idsQ.filter(k, 'is', null); // NULL = NULL strict
        } else {
          idsQ = idsQ.eq(k, v);
        }
      }

      // Statut EXACT de la ligne cliquée
      idsQ = idsQ.eq('status', widget.status);

      // Tri + Limit APRÈS les filtres
      final idsRaw =
          await idsQ.order('id', ascending: _oldestFirst).limit(_countToEdit);
      final ids = idsRaw.map((e) => (e as Map)['id']).whereType<int>().toList();

      if (ids.isEmpty) {
        _snack("Aucun item trouvé à mettre à jour pour CETTE ligne.");
        return;
      }

      // === 3) Construire l'update final et l'appliquer UNIQUEMENT aux IDs ===
      final updatePayload = <String, dynamic>{};
      updatePayload.addAll(baseUpdates);

      if (newStatus != null) {
        updatePayload['status'] = newStatus;
      }

      final goingToSale = newStatus != null && kSalePhase.contains(newStatus);
      if (saleUpdates.isNotEmpty && (goingToSale || !incStatus)) {
        updatePayload.addAll(saleUpdates);
      }

      // Application STRICTE aux IDs choisis (sans .in_(), on passe un IN string)
      final idsCsv = '(${ids.join(",")})';
      await _sb.from('item').update(updatePayload).filter('id', 'in', idsCsv);

      // Mise à jour Product (si demandé)
      if (productUpdates.isNotEmpty) {
        await _sb
            .from('product')
            .update(productUpdates)
            .eq('id', widget.productId);
      }

      if (mounted) {
        _snack(
            'Mise à jour effectuée (${ids.length} item(s)) sur la ligne sélectionnée.');
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

  // ====== popup d'erreur d'upload (nom de fichier invalide, etc.) ======
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget checkRow({
      required bool value,
      required ValueChanged<bool?> onChanged,
      required String label,
      required Widget field,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: onChanged),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                field,
              ],
            ),
          ),
        ],
      );
    }

    Widget numberField(TextEditingController c, String hint,
        {bool decimal = true}) {
      return TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(hintText: hint),
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

          // ====== CHAMPS PRODUIT / ITEM DE TÊTE ======
          Row(children: [
            Expanded(
              child: checkRow(
                value: incProductName,
                onChanged: (v) => setState(() => incProductName = v ?? false),
                label: 'Product name',
                field: TextField(
                  controller: _productNameCtrl,
                  decoration: const InputDecoration(hintText: 'Nom du produit'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incType,
                onChanged: (v) => setState(() => incType = v ?? false),
                label: 'Type',
                field: DropdownButtonFormField<String>(
                  initialValue: _newType,
                  items: itemTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _newType = v ?? 'single'),
                  decoration: const InputDecoration(hintText: 'Type'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: checkRow(
                value: incLanguage,
                onChanged: (v) => setState(() => incLanguage = v ?? false),
                label: 'Language',
                field: DropdownButtonFormField<String>(
                  initialValue: _language,
                  items: langs
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setState(() => _language = v ?? 'EN'),
                  decoration: const InputDecoration(hintText: 'Langue'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incGameId,
                onChanged: (v) => setState(() => incGameId = v ?? false),
                label: 'Jeu',
                field: DropdownButtonFormField<int>(
                  initialValue: _gameId,
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
          checkRow(
            value: incStatus,
            onChanged: (v) => setState(() => incStatus = v ?? false),
            label: 'Status',
            field: DropdownButtonFormField<String>(
              initialValue:
                  (_newStatus.isNotEmpty ? _newStatus : widget.status),
              items: kAllStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _newStatus = v ?? widget.status),
              decoration: const InputDecoration(hintText: 'Choisir un statut'),
            ),
          ),
          const SizedBox(height: 8),

          // ====== LIGNE 1 ======
          Row(children: [
            Expanded(
              child: checkRow(
                value: incGradeId,
                onChanged: (v) => setState(() => incGradeId = v ?? false),
                label: 'Grade ID',
                field: TextField(
                  controller: _gradeIdCtrl,
                  decoration: const InputDecoration(
                      hintText: 'PSA serial number, etc.'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incGradingNote,
                onChanged: (v) => setState(() => incGradingNote = v ?? false),
                label: "Grading Note",
                field: TextField(
                  controller: _gradingNoteCtrl,
                  decoration: const InputDecoration(hintText: 'ex: Excellent'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incGradingFees,
                onChanged: (v) => setState(() => incGradingFees = v ?? false),
                label: 'Grading Fees (USD)',
                field:
                    numberField(_gradingFeesCtrl, 'ex: 25.00', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incItemLocation,
                onChanged: (v) => setState(() => incItemLocation = v ?? false),
                label: "Item Location",
                field: TextField(
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
              child: checkRow(
                value: incEstimatedPrice,
                onChanged: (v) =>
                    setState(() => incEstimatedPrice = v ?? false),
                label: 'Estimated price per unit (USD)',
                field: numberField(_estimatedPriceCtrl, 'ex: 125.00',
                    decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incSalePrice,
                onChanged: (v) => setState(() => incSalePrice = v ?? false),
                label: 'Sale price',
                field: numberField(_salePriceCtrl, 'ex: 145.00', decimal: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ====== LIGNE 3 ======
          Row(children: [
            Expanded(
              child: checkRow(
                value: incSaleDate,
                onChanged: (v) => setState(() => incSaleDate = v ?? false),
                label: 'Sale date',
                field: InkWell(
                  onTap: _pickSaleDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(hintText: 'YYYY-MM-DD'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_saleDate == null
                          ? '—'
                          : _saleDate!.toIso8601String().substring(0, 10)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incTracking,
                onChanged: (v) => setState(() => incTracking = v ?? false),
                label: 'Tracking',
                field: TextField(
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
              child: checkRow(
                value: incChannelId,
                onChanged: (v) => setState(() => incChannelId = v ?? false),
                label: 'Endroit de vente (Channel ID)',
                field: numberField(_channelIdCtrl, 'ex: 12', decimal: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incBuyerCompany,
                onChanged: (v) => setState(() => incBuyerCompany = v ?? false),
                label: 'Buyer company',
                field: TextField(
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
              child: checkRow(
                value: incSupplierName,
                onChanged: (v) => setState(() => incSupplierName = v ?? false),
                label: 'Supplier name',
                field: TextField(
                  controller: _supplierNameCtrl,
                  decoration: const InputDecoration(hintText: 'Fournisseur'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incNotes,
                onChanged: (v) => setState(() => incNotes = v ?? false),
                label: 'Notes',
                field: TextField(
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
              child: checkRow(
                value: incShippingFees,
                onChanged: (v) => setState(() => incShippingFees = v ?? false),
                label: 'Shipping fees (USD)',
                field:
                    numberField(_shippingFeesCtrl, 'ex: 12.50', decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incCommissionFees,
                onChanged: (v) =>
                    setState(() => incCommissionFees = v ?? false),
                label: 'Commission fees (USD)',
                field:
                    numberField(_commissionFeesCtrl, 'ex: 5.90', decimal: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: checkRow(
                value: incPaymentType,
                onChanged: (v) => setState(() => incPaymentType = v ?? false),
                label: 'Payment type',
                field: TextField(
                  controller: _paymentTypeCtrl,
                  decoration: const InputDecoration(
                      hintText: 'e.g. PayPal / Bank / ...'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: checkRow(
                value: incBuyerInfos,
                onChanged: (v) => setState(() => incBuyerInfos = v ?? false),
                label: 'Buyer infos',
                field: TextField(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                          value: incPhotoUrl,
                          onChanged: (v) =>
                              setState(() => incPhotoUrl = v ?? false)),
                      const SizedBox(width: 6),
                      Text('Photo',
                          style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                  StorageUploadTile(
                    label: 'Uploader / Voir photo',
                    bucket: 'item-photos',
                    objectPrefix: 'items/${widget.productId}',
                    initialUrl:
                        _photoUrlCtrl.text.isEmpty ? null : _photoUrlCtrl.text,
                    onUrlChanged: (u) => _photoUrlCtrl.text = u ?? '',
                    acceptImagesOnly: true,
                    onError: (err) => _showUploadError(err),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                          value: incDocumentUrl,
                          onChanged: (v) =>
                              setState(() => incDocumentUrl = v ?? false)),
                      const SizedBox(width: 6),
                      Text('Document',
                          style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                  StorageUploadTile(
                    label: 'Uploader / Ouvrir document',
                    bucket: 'item-docs',
                    objectPrefix: 'items/${widget.productId}',
                    initialUrl: _documentUrlCtrl.text.isEmpty
                        ? null
                        : _documentUrlCtrl.text,
                    onUrlChanged: (u) => _documentUrlCtrl.text = u ?? '',
                    acceptDocsOnly: true,
                    onError: (err) => _showUploadError(err),
                  ),
                ],
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
}
