// ignore_for_file: use_build_context_synchronously
/*
Orchestrateur de la page. Contient l’état (controllers,
 validations, _save()), le chargement des jeux, et assemble les 
sous-widgets (sections) + bouton “Créer le stock”.*/

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../inventory/widgets/storage_upload_tile.dart';
import 'widgets/product_section.dart';
import 'widgets/searchbar.dart'; // ← ton picker existant

import 'new_stock_service.dart';
import 'widgets/purchase_section.dart';
import 'widgets/options_section.dart';
import 'widgets/date_field.dart';
import 'widgets/lookup_autocomplete_field.dart';

class NewStockPage extends StatefulWidget {
  const NewStockPage({super.key, required this.orgId});
  final String orgId; // ← AJOUT : org_id courant

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

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadGames() async {
    try {
      final list = await NewStockService.loadGames(_sb);
      setState(() {
        _games = list;
        if (_games.isNotEmpty) _selectedGameId = _games.first['id'] as int;
      });
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase (games) : ${e.message}');
    } catch (e) {
      _snack('Erreur chargement jeux: $e');
    }
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
        // Cas A : carte sélectionnée dans le catalogue
        await NewStockService.saveWithExternalCard(
          sb: _sb,
          orgId: widget.orgId,
          bp: _selectedCatalogCard!,
          selectedGameId: _selectedGameId!,
          type: _type,
          lang: _lang,
          initStatus: _initStatus,
          purchaseDate: _purchaseDate,
          currency: 'USD',
          supplierName: _supplierNameCtrl.text.trim().isEmpty
              ? null
              : _supplierNameCtrl.text.trim(),
          buyerCompany: _buyerCompanyCtrl.text.trim().isEmpty
              ? null
              : _buyerCompanyCtrl.text.trim(),
          qty: qty,
          totalCost: totalCost,
          fees: _num(_feesCtrl) ?? 0,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          gradeId: _gradeIdCtrl.text.trim().isEmpty
              ? null
              : _gradeIdCtrl.text.trim(),
          gradingNote: _gradingNoteCtrl.text.trim().isEmpty
              ? null
              : _gradingNoteCtrl.text.trim(),
          salePrice: _salePriceCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _salePriceCtrl.text.trim().replaceAll(',', '.')),
          tracking: _trackingCtrl.text.trim().isEmpty
              ? null
              : _trackingCtrl.text.trim(),
          photoUrl: _photoUrlCtrl.text.trim().isEmpty
              ? null
              : _photoUrlCtrl.text.trim(),
          documentUrl:
              _docUrlCtrl.text.trim().isEmpty ? null : _docUrlCtrl.text.trim(),
          estimatedPrice: estPrice,
          itemLocation: _itemLocationCtrl.text.trim().isEmpty
              ? null
              : _itemLocationCtrl.text.trim(),
          shippingFees: _shippingFeesCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _shippingFeesCtrl.text.trim().replaceAll(',', '.')),
          commissionFees: _commissionFeesCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _commissionFeesCtrl.text.trim().replaceAll(',', '.')),
          paymentType: _paymentTypeCtrl.text.trim().isEmpty
              ? null
              : _paymentTypeCtrl.text.trim(),
          buyerInfos: _buyerInfosCtrl.text.trim().isEmpty
              ? null
              : _buyerInfosCtrl.text.trim(),
          gradingFees: _num(_gradingFeesCtrl),
        );
      } else if (_nameCtrl.text.trim().isNotEmpty) {
        // Cas B : saisie libre (pas de blueprint sélectionné)
        await NewStockService.saveFallbackRpc(
          sb: _sb,
          orgId: widget.orgId,
          type: _type,
          name: _nameCtrl.text.trim(),
          lang: _lang,
          selectedGameId: _selectedGameId!,
          supplierName: _supplierNameCtrl.text.trim(),
          buyerCompany: _buyerCompanyCtrl.text.trim(),
          purchaseDate: _purchaseDate,
          qty: qty,
          totalCost: totalCost,
          fees: _num(_feesCtrl) ?? 0,
          initStatus: _initStatus,
          tracking: _trackingCtrl.text.trim(),
          photoUrl: _photoUrlCtrl.text.trim(),
          documentUrl: _docUrlCtrl.text.trim(),
          estimatedPrice: estPrice,
          notes: _notesCtrl.text.trim(),
          gradeId: _gradeIdCtrl.text.trim(),
          gradingNote: _gradingNoteCtrl.text.trim(),
          gradingFees: _num(_gradingFeesCtrl),
          itemLocation: _itemLocationCtrl.text.trim(),
          shippingFees: _shippingFeesCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _shippingFeesCtrl.text.trim().replaceAll(',', '.')),
          commissionFees: _commissionFeesCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _commissionFeesCtrl.text.trim().replaceAll(',', '.')),
          paymentType: _paymentTypeCtrl.text.trim(),
          buyerInfos: _buyerInfosCtrl.text.trim(),
          salePrice: _salePriceCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(
                  _salePriceCtrl.text.trim().replaceAll(',', '.')),
        );
      } else {
        // Cas C : ni blueprint ni nom → on informe l’utilisateur
        _snack(
            'Renseigne un nom de produit ou sélectionne une fiche du catalogue.');
        setState(() => _saving = false);
        return;
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
                // ——— Produit ———
                ProductSection(
                  type: _type,
                  lang: _lang,
                  langs: langs,
                  games: _games,
                  selectedGameId: _selectedGameId,
                  catalogPicker: CatalogPicker(
                    labelText: 'Nom du produit *',
                    selectedGameId: _selectedGameId,
                    onTextChanged: (text) {
                      _nameCtrl.text = text;
                      final t = text.trim();
                      if (_selectedCatalogDisplay != null &&
                          t == _selectedCatalogDisplay) {
                        return;
                      }
                      setState(() {
                        _selectedCatalogCard = null;
                        _selectedBlueprintId = null;
                        _selectedCatalogDisplay = null;
                      });
                    },
                    onSelected: (card) {
                      setState(() {
                        _selectedCatalogCard = card;
                        _selectedBlueprintId = (card['id'] as num?)?.toInt();
                        final full = (card['display_text'] as String?) ??
                            NewStockService.buildFullDisplay(card);
                        _selectedCatalogDisplay = full;
                        _nameCtrl.text = full;
                        final img = (card['image_url'] as String?) ?? '';
                        if (img.isNotEmpty) _photoUrlCtrl.text = img;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('Sélectionné: ${card['name'] ?? 'Item'}')),
                      );
                    },
                  ),
                  onTypeChanged: (v) {
                    setState(() {
                      _type = v ?? 'single';
                      final newStatuses =
                          _type == 'single' ? singleStatuses : sealedStatuses;
                      if (!newStatuses.contains(_initStatus)) {
                        _initStatus = newStatuses.first;
                      }
                    });
                  },
                  onLangChanged: (v) => setState(() => _lang = v ?? 'EN'),
                  onGameChanged: (v) => setState(() => _selectedGameId = v),
                ),
                const SizedBox(height: 12),

                // ——— Achat ———
                PurchaseSection(
                  supplierField: LookupAutocompleteField(
                    tableName: 'fournisseur',
                    label: 'Fournisseur (optionnel)',
                    controller: _supplierNameCtrl,
                    addDialogTitle: 'Nouveau fournisseur',
                  ),
                  buyerField: LookupAutocompleteField(
                    tableName: 'society',
                    label: 'Société acheteuse (optionnel)',
                    controller: _buyerCompanyCtrl,
                    addDialogTitle: 'Nouvelle société',
                  ),
                  totalCostCtrl: _totalCostCtrl,
                  qtyCtrl: _qtyCtrl,
                  dateField: DateField(
                    label: "Date d'achat",
                    date: _purchaseDate,
                    onTap: _pickDate,
                  ),
                  statusValue: statusValue,
                  statuses: statuses,
                  onStatusChanged: (v) =>
                      setState(() => _initStatus = v ?? statusValue),
                  feesCtrl: _feesCtrl,
                  estimatedPriceCtrl: _estimatedPriceCtrl,
                ),
                const SizedBox(height: 12),

                // ——— Toggle options ———
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
                  OptionsSection(
                    gradeIdCtrl: _gradeIdCtrl,
                    gradingNoteCtrl: _gradingNoteCtrl,
                    gradingFeesCtrl: _gradingFeesCtrl,
                    itemLocationField: LookupAutocompleteField(
                      tableName: 'item_location',
                      label: 'Item Location',
                      controller: _itemLocationCtrl,
                      addDialogTitle: 'Nouvel emplacement',
                    ),
                    trackingCtrl: _trackingCtrl,
                    photoTile: StorageUploadTile(
                      label: 'Photo',
                      bucket: 'item-photos',
                      objectPrefix: 'items',
                      initialUrl: _photoUrlCtrl.text.isEmpty
                          ? null
                          : _photoUrlCtrl.text,
                      onUrlChanged: (u) => _photoUrlCtrl.text = u ?? '',
                      acceptImagesOnly: true,
                      onError: (m) => _showUploadError(m),
                    ),
                    docTile: StorageUploadTile(
                      label: 'Document',
                      bucket: 'item-docs',
                      objectPrefix: 'items',
                      initialUrl:
                          _docUrlCtrl.text.isEmpty ? null : _docUrlCtrl.text,
                      onUrlChanged: (u) => _docUrlCtrl.text = u ?? '',
                      acceptDocsOnly: true,
                      onError: (m) => _showUploadError(m),
                    ),
                    notesCtrl: _notesCtrl,
                    shippingFeesCtrl: _shippingFeesCtrl,
                    commissionFeesCtrl: _commissionFeesCtrl,
                    salePriceCtrl: _salePriceCtrl,
                    paymentTypeCtrl: _paymentTypeCtrl,
                    buyerInfosCtrl: _buyerInfosCtrl,
                  ),

                const SizedBox(height: 20),

                // ——— Save button ———
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
}
