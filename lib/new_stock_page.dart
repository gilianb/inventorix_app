// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../inventory/widgets/storage_upload_tile.dart';
import 'searchbar.dart'; // <— garde ton chemin actuel

class NewStockPage extends StatefulWidget {
  const NewStockPage({super.key});

  @override
  State<NewStockPage> createState() => _NewStockPageState();
}

class _NewStockPageState extends State<NewStockPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Produit minimal
  String _type = 'single'; // 'single' | 'sealed'
  final _nameCtrl = TextEditingController();
  String _lang = 'EN';

  // Sélection catalogue (externe)
  Map<String, dynamic>? _selectedCatalogCard; // blueprint complet
  int? _selectedBlueprintId; // blueprints.id (externe)
  String? _selectedCatalogDisplay; // libellé complet affiché

  // Achat
  final _supplierNameCtrl = TextEditingController(); // optionnel
  final _buyerCompanyCtrl = TextEditingController(); // optionnel
  DateTime _purchaseDate = DateTime.now();
  final _totalCostCtrl = TextEditingController(); // USD (total)
  final _qtyCtrl = TextEditingController(text: '1');
  final _feesCtrl = TextEditingController(text: '0'); // USD
  final _estimatedPriceCtrl = TextEditingController(); // optionnel
  String _initStatus = 'paid';

  // Plus d’options
  bool _showMore = false;
  final _trackingCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  final _docUrlCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _gradeIdCtrl = TextEditingController();
  final _gradingNoteCtrl = TextEditingController();
  final _gradingFeesCtrl = TextEditingController();
  final _itemLocationCtrl = TextEditingController();

  // Vente/frais
  final _shippingFeesCtrl = TextEditingController();
  final _commissionFeesCtrl = TextEditingController();
  final _paymentTypeCtrl = TextEditingController();
  final _buyerInfosCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();

  // Jeux
  List<Map<String, dynamic>> _games = const [];
  int? _selectedGameId;

  bool _saving = false;

  static const langs = ['EN', 'FR', 'JP'];

  static const singleStatuses = [
    'ordered',
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
  static const sealedStatuses = [
    'ordered',
    'paid',
    'received',
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
    'collection',
  ];

  @override
  void initState() {
    super.initState();
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
        if (_games.isNotEmpty) _selectedGameId = _games.first['id'] as int;
      });
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase (games) : ${e.message}');
    } catch (e) {
      _snack('Erreur chargement jeux: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showUploadError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erreur de téléchargement'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  double? _num(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  String _composeProductNameFromBlueprint(Map<String, dynamic> bp) {
    final name = (bp['name'] as String?)?.trim() ?? '';

    final parts = <String>[];
    final exName = (bp['expansion_name'] as String?)?.trim() ?? '';
    final exCode = (bp['expansion_code'] as String?)?.trim() ?? '';
    final number = (bp['collector_number'] as String?)?.trim() ?? '';
    final rarity = (bp['rarity_text'] as String?)?.trim() ?? '';
    final version = (bp['version'] as String?)?.trim() ?? '';

    // ex: "Dark Magician — Legend of Blue Eyes (LOB) — No. 005 — Ver. Ultra Rare — v1"
    if (exName.isNotEmpty && exCode.isNotEmpty) {
      parts.add('$exName ($exCode)');
    } else if (exName.isNotEmpty) {
      parts.add(exName);
    } else if (exCode.isNotEmpty) {
      parts.add(exCode);
    }
    if (number.isNotEmpty) parts.add('No. $number');
    if (rarity.isNotEmpty) parts.add('Ver. $rarity');
    if (version.isNotEmpty) parts.add('v$version');

    if (parts.isEmpty) return name;
    if (name.isEmpty) return parts.join(' — ');
    return '$name — ${parts.join(' — ')}';
  }

  Future<int> _ensureProductFromBlueprint({
    required Map<String, dynamic> bp,
    required int gameId,
    required String type,
    required String language,
  }) async {
    final blueprintId = (bp['id'] as num).toInt();

    final existing = await _sb
        .from('product')
        .select('id')
        .eq('blueprint_id', blueprintId)
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      return (existing['id'] as num).toInt();
    }

    final String? photo =
        (bp['image_url'] as String?)?.trim().isNotEmpty == true
            ? (bp['image_url'] as String)
            : (_photoUrlCtrl.text.trim().isNotEmpty
                ? _photoUrlCtrl.text.trim()
                : null);

    final insert = {
      'type': type,
      'name': _composeProductNameFromBlueprint(bp),
      'language': language,
      'game_id': gameId,
      'blueprint_id': blueprintId,
      'version': bp['version'],
      'collector_number': bp['collector_number'],
      'expansion_code': bp['expansion_code'],
      'expansion_name': bp['expansion_name'],
      'rarity_text': bp['rarity_text'],
      'scryfall_id': bp['scryfall_id'],
      'tcg_player_id': bp['tcg_player_id'],
      'card_market_ids': bp['card_market_ids'],
      'image_storage': bp['image_storage'],
      'photo_url': photo,
      'fixed_properties': bp['fixed_properties'],
      'editable_properties': bp['editable_properties'],
      'data': bp['data'],
    };

    final inserted =
        await _sb.from('product').insert(insert).select('id').single();
    return (inserted['id'] as num).toInt();
  }

  Future<void> _saveWithExternalCard(Map<String, dynamic> bp) async {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final totalCost = _num(_totalCostCtrl) ?? 0;
    final fees = _num(_feesCtrl) ?? 0;
    final estPrice = _num(_estimatedPriceCtrl);
    final gradingFees = _num(_gradingFeesCtrl);
    final perUnitCost = qty > 0 ? (totalCost / qty) : 0;
    final perUnitFees = qty > 0 ? (fees / qty) : 0;

    final String? photo = (bp['image_url'] as String?)?.isNotEmpty == true
        ? bp['image_url']
        : null;

    final productId = await _ensureProductFromBlueprint(
      bp: bp,
      gameId: _selectedGameId!,
      type: _type,
      language: _lang,
    );

    final items = List.generate(qty, (_) {
      return {
        'product_id': productId,
        'game_id': _selectedGameId,
        'type': _type,
        'language': _lang,
        'status': _initStatus,
        'purchase_date': _purchaseDate.toIso8601String().substring(0, 10),
        'currency': 'USD',
        'supplier_name': _supplierNameCtrl.text.trim().isEmpty
            ? null
            : _supplierNameCtrl.text.trim(),
        'buyer_company': _buyerCompanyCtrl.text.trim().isEmpty
            ? null
            : _buyerCompanyCtrl.text.trim(),
        'unit_cost': perUnitCost,
        'unit_fees': perUnitFees,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'grade_id':
            _gradeIdCtrl.text.trim().isEmpty ? null : _gradeIdCtrl.text.trim(),
        'grading_note': _gradingNoteCtrl.text.trim().isEmpty
            ? null
            : _gradingNoteCtrl.text.trim(),
        'sale_date': null,
        'sale_price': _salePriceCtrl.text.trim().isEmpty
            ? null
            : double.tryParse(_salePriceCtrl.text.trim().replaceAll(',', '.')),
        'tracking': _trackingCtrl.text.trim().isEmpty
            ? null
            : _trackingCtrl.text.trim(),
        'photo_url': (_photoUrlCtrl.text.trim().isNotEmpty)
            ? _photoUrlCtrl.text.trim()
            : (photo),
        'document_url':
            _docUrlCtrl.text.trim().isEmpty ? null : _docUrlCtrl.text.trim(),
        'estimated_price': estPrice,
        'item_location': _itemLocationCtrl.text.trim().isEmpty
            ? null
            : _itemLocationCtrl.text.trim(),
        'shipping_fees': (_shippingFeesCtrl.text.trim().isEmpty)
            ? null
            : double.tryParse(
                _shippingFeesCtrl.text.trim().replaceAll(',', '.')),
        'commission_fees': (_commissionFeesCtrl.text.trim().isEmpty)
            ? null
            : double.tryParse(
                _commissionFeesCtrl.text.trim().replaceAll(',', '.')),
        'payment_type': _paymentTypeCtrl.text.trim().isEmpty
            ? null
            : _paymentTypeCtrl.text.trim(),
        'buyer_infos': _buyerInfosCtrl.text.trim().isEmpty
            ? null
            : _buyerInfosCtrl.text.trim(),
        'grading_fees': gradingFees,
      };
    });

    await _sb.from('item').insert(items);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final totalCost = _num(_totalCostCtrl) ?? 0;
    final estPrice = _num(_estimatedPriceCtrl);

    if (qty <= 0) {
      _snack('Quantité > 0 requise');
      return;
    }
    if (totalCost < 0) {
      _snack('Prix total invalide');
      return;
    }
    if (_selectedGameId == null) {
      _snack('Choisis un jeu');
      return;
    }

    final mustHaveEstimated =
        _initStatus == 'listed' || _initStatus == 'awaiting_payment';
    if (mustHaveEstimated && (estPrice == null || estPrice < 0)) {
      _snack('Prix estimé requis (>= 0) pour un statut de vente');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_selectedBlueprintId != null && _selectedCatalogCard != null) {
        await _saveWithExternalCard(_selectedCatalogCard!);
      } else if (_nameCtrl.text.trim().isNotEmpty) {
        // texte tapé sans sélection effective
        _snack('Sélectionne une fiche du catalogue dans la liste.');
        setState(() => _saving = false);
        return;
      } else {
        // Fallback RPC si tu veux créer un produit libre (rare)
        final fees = _num(_feesCtrl) ?? 0;
        final gradingFees = _num(_gradingFeesCtrl);
        await _sb.rpc('fn_create_product_and_items', params: {
          'p_type': _type,
          'p_name': _nameCtrl.text.trim(),
          'p_language': _lang,
          'p_game_id': _selectedGameId,
          'p_supplier_name': _supplierNameCtrl.text.trim().isNotEmpty
              ? _supplierNameCtrl.text.trim()
              : null,
          'p_buyer_company': _buyerCompanyCtrl.text.trim().isNotEmpty
              ? _buyerCompanyCtrl.text.trim()
              : null,
          'p_purchase_date': _purchaseDate.toIso8601String().substring(0, 10),
          'p_currency': 'USD',
          'p_qty': qty,
          'p_total_cost': totalCost,
          'p_fees': fees,
          'p_init_status': _initStatus,
          'p_channel_id': null,
          'p_tracking': _trackingCtrl.text.trim().isNotEmpty
              ? _trackingCtrl.text.trim()
              : null,
          'p_photo_url': _photoUrlCtrl.text.trim().isNotEmpty
              ? _photoUrlCtrl.text.trim()
              : null,
          'p_document_url': _docUrlCtrl.text.trim().isNotEmpty
              ? _docUrlCtrl.text.trim()
              : null,
          'p_estimated_price': estPrice,
          'p_notes':
              _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
          'p_grade_id': _gradeIdCtrl.text.trim().isNotEmpty
              ? _gradeIdCtrl.text.trim()
              : null,
          'p_grading_note': _gradingNoteCtrl.text.trim().isNotEmpty
              ? _gradingNoteCtrl.text.trim()
              : null,
          'p_grading_fees': gradingFees,
          'p_item_location': _itemLocationCtrl.text.trim().isNotEmpty
              ? _itemLocationCtrl.text.trim()
              : null,
          'p_shipping_fees': (_shippingFeesCtrl.text.trim().isEmpty)
              ? null
              : double.tryParse(
                  _shippingFeesCtrl.text.trim().replaceAll(',', '.')),
          'p_commission_fees': (_commissionFeesCtrl.text.trim().isEmpty)
              ? null
              : double.tryParse(
                  _commissionFeesCtrl.text.trim().replaceAll(',', '.')),
          'p_payment_type': _paymentTypeCtrl.text.trim().isEmpty
              ? null
              : _paymentTypeCtrl.text.trim(),
          'p_buyer_infos':
              _buyerInfosCtrl.text.trim().isEmpty ? null : _buyerInfosCtrl.text,
          'p_sale_price': _salePriceCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _salePriceCtrl.text.trim().replaceAll(',', '.')),
        });
      }

      _snack('Stock créé (${_qtyCtrl.text} items)');
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supplierNameCtrl.dispose();
    _buyerCompanyCtrl.dispose();
    _totalCostCtrl.dispose();
    _qtyCtrl.dispose();
    _feesCtrl.dispose();
    _notesCtrl.dispose();
    _trackingCtrl.dispose();
    _photoUrlCtrl.dispose();
    _docUrlCtrl.dispose();
    _estimatedPriceCtrl.dispose();
    _gradeIdCtrl.dispose();
    _itemLocationCtrl.dispose();
    _shippingFeesCtrl.dispose();
    _commissionFeesCtrl.dispose();
    _paymentTypeCtrl.dispose();
    _salePriceCtrl.dispose();
    _buyerInfosCtrl.dispose();
    _gradingNoteCtrl.dispose();
    _gradingFeesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _type == 'single' ? singleStatuses : sealedStatuses;
    final statusValue =
        statuses.contains(_initStatus) ? _initStatus : statuses.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau stock')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _Section(
                  title: 'Produit',
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _type,
                            items: const [
                              DropdownMenuItem(
                                  value: 'single', child: Text('Single')),
                              DropdownMenuItem(
                                  value: 'sealed', child: Text('Sealed')),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _type = v ?? 'single';
                                final newStatuses = _type == 'single'
                                    ? singleStatuses
                                    : sealedStatuses;
                                if (!newStatuses.contains(_initStatus)) {
                                  _initStatus = newStatuses.first;
                                }
                              });
                            },
                            decoration:
                                const InputDecoration(labelText: 'Type *'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _lang,
                            items: langs
                                .map((l) =>
                                    DropdownMenuItem(value: l, child: Text(l)))
                                .toList(),
                            onChanged: (v) => setState(() => _lang = v ?? 'EN'),
                            decoration:
                                const InputDecoration(labelText: 'Langue *'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),

                      // ========= Barre de recherche catalogue =========
                      CatalogPicker(
                        labelText: 'Nom du produit *',
                        selectedGameId: _selectedGameId,
                        onTextChanged: (text) {
                          // On synchronise le texte pour le fallback (rare)
                          _nameCtrl.text = text;

                          // IMPORTANT : ne pas annuler la sélection si l'utilisateur
                          // ne fait que voir le libellé programmatique (libellé complet)
                          final t = text.trim();
                          if (_selectedCatalogDisplay != null &&
                              t == _selectedCatalogDisplay) {
                            return; // c'est la mise à jour due à la sélection → on ne clear pas
                          }

                          // L'utilisateur modifie le texte → on invalide la sélection
                          setState(() {
                            _selectedCatalogCard = null;
                            _selectedBlueprintId = null;
                            _selectedCatalogDisplay = null;
                          });
                        },
                        onSelected: (card) {
                          setState(() {
                            _selectedCatalogCard = card;
                            _selectedBlueprintId =
                                (card['id'] as num?)?.toInt();

                            // Libellé complet (pré-calculé par le picker)
                            final full = (card['display_text'] as String?) ??
                                buildFullDisplay(card);
                            _selectedCatalogDisplay = full;
                            _nameCtrl.text = full;

                            // Photo par défaut depuis le blueprint
                            final img = (card['image_url'] as String?) ?? '';
                            if (img.isNotEmpty) _photoUrlCtrl.text = img;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Sélectionné: ${card['name'] ?? 'Item'}')),
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      DropdownButtonFormField<int>(
                        initialValue: _selectedGameId,
                        items: _games
                            .map((g) => DropdownMenuItem<int>(
                                  value: g['id'] as int,
                                  child: Text(g['label'] as String),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGameId = v),
                        validator: (v) => v == null ? 'Choisir un jeu' : null,
                        decoration: const InputDecoration(labelText: 'Jeu *'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Achat (USD)',
                  child: Column(
                    children: [
                      LookupAutocompleteField(
                        tableName: 'fournisseur',
                        label: 'Fournisseur (optionnel)',
                        controller: _supplierNameCtrl,
                        addDialogTitle: 'Nouveau fournisseur',
                      ),
                      const SizedBox(height: 8),
                      LookupAutocompleteField(
                        tableName: 'society',
                        label: 'Société acheteuse (optionnel)',
                        controller: _buyerCompanyCtrl,
                        addDialogTitle: 'Nouvelle société',
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _totalCostCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Prix total (USD) *'),
                            validator: (v) => (double.tryParse(
                                            (v ?? '').replaceAll(',', '.')) ??
                                        -1) >=
                                    0
                                ? null
                                : 'Montant invalide',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Quantité *'),
                            validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0
                                ? null
                                : 'Qté > 0',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: _DateField(
                            label: "Date d'achat",
                            date: _purchaseDate,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: statusValue,
                            items: (_type == 'single'
                                    ? singleStatuses
                                    : sealedStatuses)
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _initStatus = v ?? statusValue),
                            decoration: const InputDecoration(
                                labelText: 'Statut initial'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _feesCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Frais (USD) — optionnel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: 'Devise'),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('USD'),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _estimatedPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Prix de vente estimé par unité (USD)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showMore = !_showMore),
                    icon:
                        Icon(_showMore ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Plus d’options'),
                  ),
                ),
                if (_showMore)
                  _Section(
                    title: 'Options (facultatif)',
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(
                              child: TextFormField(
                                  controller: _gradeIdCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Grading ID'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                                  controller: _gradingNoteCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Grading Note'))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _gradingFeesCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Grading Fees (USD) — par unité'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LookupAutocompleteField(
                              tableName: 'item_location',
                              label: 'Item Location',
                              controller: _itemLocationCtrl,
                              addDialogTitle: 'Nouvel emplacement',
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: TextFormField(
                                  controller: _trackingCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Tracking Number'))),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox.shrink()),
                        ]),
                        const SizedBox(height: 8),
                        StorageUploadTile(
                          label: 'Photo',
                          bucket: 'item-photos',
                          objectPrefix: 'items',
                          initialUrl: _photoUrlCtrl.text.isEmpty
                              ? null
                              : _photoUrlCtrl.text,
                          onUrlChanged: (u) => _photoUrlCtrl.text = u ?? '',
                          acceptImagesOnly: true,
                          onError: _showUploadError,
                        ),
                        const SizedBox(height: 8),
                        StorageUploadTile(
                          label: 'Document',
                          bucket: 'item-docs',
                          objectPrefix: 'items',
                          initialUrl: _docUrlCtrl.text.isEmpty
                              ? null
                              : _docUrlCtrl.text,
                          onUrlChanged: (u) => _docUrlCtrl.text = u ?? '',
                          acceptDocsOnly: true,
                          onError: _showUploadError,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                            controller: _notesCtrl,
                            minLines: 2,
                            maxLines: 5,
                            decoration:
                                const InputDecoration(labelText: 'Notes')),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _shippingFeesCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Frais d\'expédition (USD)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _commissionFeesCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Frais de commission (USD)'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _salePriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Prix de vente (optionnel)'),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: TextFormField(
                                  controller: _paymentTypeCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Type de paiement'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                                  controller: _buyerInfosCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Infos acheteur'))),
                        ]),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Créer le stock'),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final txt = date.toIso8601String().split('T').first;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Date', border: OutlineInputBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('$label: $txt'),
        ),
      ),
    );
  }
}

/// ===== Lookup simple (inchangé)
class LookupAutocompleteField extends StatefulWidget {
  const LookupAutocompleteField({
    super.key,
    required this.tableName,
    required this.label,
    required this.controller,
    this.addDialogTitle,
    this.requiredField = false,
    this.whereActiveOnly = true,
    this.maxOptions = 10,
    this.autoAddOnEnter = true,
  });

  final String tableName;
  final String label;
  final TextEditingController controller;
  final String? addDialogTitle;
  final bool requiredField;
  final bool whereActiveOnly;
  final int maxOptions;
  final bool autoAddOnEnter;

  @override
  State<LookupAutocompleteField> createState() =>
      _LookupAutocompleteFieldState();
}

class _LookupAutocompleteFieldState extends State<LookupAutocompleteField> {
  final _sb = Supabase.instance.client;

  final FocusNode _focusNode = FocusNode();
  List<String> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final base = _sb.from(widget.tableName).select('name');
      List<dynamic> data;
      if (widget.whereActiveOnly) {
        try {
          data = await base.eq('active', true).order('name');
        } on PostgrestException {
          data = await base.order('name');
        }
      } else {
        data = await base.order('name');
      }
      _all = data
          .map<String>((e) => (e as Map)['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      _all = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasAnyMatch(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return _all.isNotEmpty;
    return _all.any((n) => n.toLowerCase().contains(s));
  }

  bool _hasExact(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return false;
    return _all.any((n) => n.toLowerCase() == s);
  }

  Future<void> _addValue(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;

    if (_all.any((x) => x.toLowerCase() == n.toLowerCase())) {
      widget.controller.text = n;
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Déjà présent: "$n"')));
      }
      return;
    }

    try {
      final inserted = await _sb
          .from(widget.tableName)
          .insert({'name': n})
          .select('id, name')
          .single();
      if ((inserted['id'] != null)) {
        await _load();
        widget.controller.text = n;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ajouté: "${inserted['name']}"')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Insertion non confirmée.')));
        }
      }
    } on PostgrestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur INSERT: ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur inconnue: $e')));
      }
    }
  }

  Future<void> _submitOrAdd(String currentText) async {
    final t = currentText.trim();
    if (t.isEmpty) return;

    final anyMatch = _hasAnyMatch(t);
    final exact = _hasExact(t);

    if (exact) {
      widget.controller.text = t;
      return;
    }

    if (widget.autoAddOnEnter && !anyMatch) {
      await _addValue(t);
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.requiredField ? '${widget.label} *' : widget.label;

    if (_loading) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return _all.take(widget.maxOptions);
        return _all
            .where((n) => n.toLowerCase().contains(q))
            .take(widget.maxOptions);
      },
      displayStringForOption: (opt) => opt,
      optionsViewBuilder: (context, onSelected, options) {
        final input = widget.controller.text.trim();
        final canAdd = input.isNotEmpty && !_hasExact(input);
        final merged = [...options, if (canAdd) '___ADD___$input'];

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: merged.length,
                itemBuilder: (ctx, i) {
                  final v = merged[i];
                  final isAdd = v.startsWith('___ADD___');
                  final text = isAdd ? v.substring(9) : v;
                  return ListTile(
                    dense: true,
                    title: isAdd
                        ? Text('➕ Ajouter "$text"',
                            overflow: TextOverflow.ellipsis)
                        : Text(text, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      if (isAdd) {
                        await _addValue(text);
                        _focusNode.unfocus();
                      } else {
                        onSelected(text);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label),
          onFieldSubmitted: (val) async {
            await _submitOrAdd(val);
            onFieldSubmitted();
          },
          validator: (v) {
            if (!widget.requiredField) return null;
            if (v == null || v.trim().isEmpty) return 'Champ requis';
            return null;
          },
        );
      },
      onSelected: (val) => widget.controller.text = val,
    );
  }
}
