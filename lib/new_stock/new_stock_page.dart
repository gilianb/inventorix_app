import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../inventory/widgets/storage_upload_tile.dart';
import 'widgets/product_section.dart';
import 'widgets/searchbar.dart';

import 'new_stock_service.dart';
import 'widgets/purchase_section.dart';
import 'widgets/options_section.dart';
import 'widgets/date_field.dart';
import 'widgets/lookup_autocomplete_field.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

class NewStockPage extends StatefulWidget {
  const NewStockPage({super.key, required this.orgId});
  final String orgId; // ← org_id courant

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

  // ✅ Devise (prix par devise)
  String _currency = 'USD';
  static const currencies = ['USD', 'EUR', 'GBP', 'JPY', 'ILS', 'CHF', 'CAD'];

  // ✅ NEW: devise de vente (sale_currency) indépendante de currency (legacy)
  // Par défaut on la synchronise sur _currency.
  final _saleCurrencyCtrl = TextEditingController(text: 'USD');

  // Sélection catalogue (externe)
  Map<String, dynamic>? _selectedCatalogCard; // blueprint complet
  int? _selectedBlueprintId; // blueprints.id (externe)
  String? _selectedCatalogDisplay; // libellé complet affiché

  // Achat
  final _supplierNameCtrl = TextEditingController(); // optionnel
  final _buyerCompanyCtrl = TextEditingController(); // optionnel
  DateTime _purchaseDate = DateTime.now();
  final _totalCostCtrl =
      TextEditingController(); // total (dans la devise choisie)
  final _qtyCtrl = TextEditingController(text: '1');
  final _feesCtrl =
      TextEditingController(text: '0'); // total (dans la devise choisie)
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
    'vault',
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
    'vault',
  ];

  @override
  void initState() {
    super.initState();
    _saleCurrencyCtrl.text = _currency; // sync par défaut
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
    _saleCurrencyCtrl.dispose();
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
      _snack('Supabase error (games): ${e.message}');
    } catch (e) {
      _snack('Error loading games: $e');
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

  String? _saleCurrencyValueOrNull() {
    final t = _saleCurrencyCtrl.text.trim().toUpperCase();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final totalCost = _num(_totalCostCtrl) ?? 0;
    final estPrice = _num(_estimatedPriceCtrl);

    if (qty <= 0) {
      _snack('Quantity > 0 required');
      return;
    }
    if (totalCost < 0) {
      _snack('Invalid total price');
      return;
    }
    if (_selectedGameId == null) {
      _snack('Choose a game');
      return;
    }

    // Frais saisis (TOTaux) → convertis en frais par unité
    final double? shippingTotal = _num(_shippingFeesCtrl);
    final double? commissionTotal = _num(_commissionFeesCtrl);
    final double? shippingPerUnit =
        (shippingTotal != null) ? (shippingTotal / qty) : null;
    final double? commissionPerUnit =
        (commissionTotal != null) ? (commissionTotal / qty) : null;

    final mustHaveEstimated =
        _initStatus == 'listed' || _initStatus == 'awaiting_payment';
    if (mustHaveEstimated && (estPrice == null || estPrice < 0)) {
      _snack('Estimated price required (>= 0) for a sale status');
      return;
    }

    final salePrice = _salePriceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_salePriceCtrl.text.trim().replaceAll(',', '.'));

    // ✅ NEW: sale_currency (si vide -> null, fallback legacy côté affichage/compute)
    final saleCurrency = _saleCurrencyValueOrNull();

    setState(() => _saving = true);
    try {
      if (_selectedBlueprintId != null && _selectedCatalogCard != null) {
        await NewStockService.saveWithExternalCard(
          sb: _sb,
          orgId: widget.orgId,
          bp: _selectedCatalogCard!,
          selectedGameId: _selectedGameId!,
          type: _type,
          lang: _lang,
          initStatus: _initStatus,
          purchaseDate: _purchaseDate,
          currency: _currency,
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
          salePrice: salePrice,
          saleCurrency: saleCurrency,
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
          shippingFees: shippingPerUnit,
          commissionFees: commissionPerUnit,
          paymentType: _paymentTypeCtrl.text.trim().isEmpty
              ? null
              : _paymentTypeCtrl.text.trim(),
          buyerInfos: _buyerInfosCtrl.text.trim().isEmpty
              ? null
              : _buyerInfosCtrl.text.trim(),
          gradingFees: _num(_gradingFeesCtrl),
        );
      } else if (_nameCtrl.text.trim().isNotEmpty) {
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
          currency: _currency,
          tracking: _trackingCtrl.text.trim(),
          photoUrl: _photoUrlCtrl.text.trim(),
          documentUrl: _docUrlCtrl.text.trim(),
          estimatedPrice: estPrice,
          notes: _notesCtrl.text.trim(),
          gradeId: _gradeIdCtrl.text.trim(),
          gradingNote: _gradingNoteCtrl.text.trim(),
          gradingFees: _num(_gradingFeesCtrl),
          itemLocation: _itemLocationCtrl.text.trim(),
          shippingFees: shippingPerUnit,
          commissionFees: commissionPerUnit,
          paymentType: _paymentTypeCtrl.text.trim(),
          buyerInfos: _buyerInfosCtrl.text.trim(),
          salePrice: salePrice,
          saleCurrency: saleCurrency,
        );
      } else {
        _snack('Enter a product name or select a catalog entry.');
        setState(() => _saving = false);
        return;
      }

      _snack('Stock created (${_qtyCtrl.text} items)');
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
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
      appBar: AppBar(title: const Text('New stock')),
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
                    labelText: 'Product name *',
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
                                Text('Selected: ${card['name'] ?? 'Item'}')),
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

                // ✅ Devise (prix par devise) - UI simple
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  items: currencies
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    final newCur = (v ?? 'USD').toUpperCase();
                    final prevCur = _currency.toUpperCase();
                    setState(() => _currency = newCur);

                    // ✅ Si l’utilisateur n’a pas “décorrélé” la devise de vente,
                    // on suit la devise legacy.
                    final saleCurNow =
                        _saleCurrencyCtrl.text.trim().toUpperCase();
                    final shouldSync =
                        saleCurNow.isEmpty || saleCurNow == prevCur;
                    if (shouldSync) _saleCurrencyCtrl.text = newCur;
                  },
                  decoration: const InputDecoration(labelText: 'Currency *'),
                ),
                const SizedBox(height: 12),

                // ——— Achat ———
                PurchaseSection(
                  currency: _currency, // ✅ NEW
                  supplierField: LookupAutocompleteField(
                    tableName: 'fournisseur',
                    label: 'Supplier (optional)',
                    controller: _supplierNameCtrl,
                    addDialogTitle: 'New supplier',
                    orgId: widget.orgId, // ✅ NEW
                  ),
                  buyerField: LookupAutocompleteField(
                    tableName: 'society',
                    label: 'Buyer company (optional)',
                    controller: _buyerCompanyCtrl,
                    addDialogTitle: 'New buyer company',
                    orgId: widget.orgId, // ✅ NEW
                  ),
                  totalCostCtrl: _totalCostCtrl,
                  qtyCtrl: _qtyCtrl,
                  dateField: DateField(
                    label: "Purchase date",
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
                        Iconify(_showMore ? Mdi.expand_less : Mdi.expand_more),
                    label: const Text('More options'),
                  ),
                ),

                if (_showMore)
                  OptionsSection(
                    currency: _currency,
                    gradeIdCtrl: _gradeIdCtrl,
                    gradingNoteCtrl: _gradingNoteCtrl,
                    gradingFeesCtrl: _gradingFeesCtrl,
                    itemLocationField: LookupAutocompleteField(
                      tableName: 'item_location',
                      label: 'Item Location',
                      controller: _itemLocationCtrl,
                      addDialogTitle: 'New location',
                      // ❗ item_location est global (pas d'org_id) => ne pas passer orgId
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
                    saleCurrencyCtrl: _saleCurrencyCtrl,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Iconify(Mdi.content_save),
                    label: const Text('Create stock'),
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
        title: const Text('Upload error'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}
