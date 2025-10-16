import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../inventory/widgets/storage_upload_tile.dart';

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

  // Achat
  final _supplierNameCtrl = TextEditingController(); // texte libre
  final _buyerCompanyCtrl = TextEditingController(); // société acheteuse
  DateTime _purchaseDate = DateTime.now();
  final _totalCostCtrl = TextEditingController(); // PRIX TOTAL (USD)
  final _qtyCtrl = TextEditingController(text: '1');
  final _feesCtrl = TextEditingController(text: '0'); // en USD
  final _estimatedPriceCtrl =
      TextEditingController(); // <- OBLIGATOIRE désormais
  String _initStatus = 'paid';

  // Plus d’options (repliable)
  bool _showMore = false;
  final _trackingCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  final _docUrlCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _gradeIdCtrl = TextEditingController();
  final _itemLocationCtrl = TextEditingController();

  // Jeux
  List<Map<String, dynamic>> _games = const [];
  int? _selectedGameId;

  bool _saving = false;

  static const langs = ['EN', 'FR', 'JP'];

  // Statuts cohérents (single / sealed) + 'collection'
  static const singleStatuses = [
    'ordered',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
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
        if (_games.isNotEmpty) {
          _selectedGameId = _games.first['id'] as int;
        }
      });
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase (games) : ${e.message}');
    } catch (e) {
      _snack('Erreur chargement jeux: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // === Dialog d’erreur pour les uploads ===
  void _showUploadError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erreur de téléchargement'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final totalCost = _num(_totalCostCtrl) ?? 0;
    final fees = _num(_feesCtrl) ?? 0;
    final estPrice = _num(_estimatedPriceCtrl); // <- requis

    if (qty <= 0) {
      _snack('Quantité > 0 requise');
      return;
    }
    if (totalCost < 0) {
      _snack('Prix total invalide');
      return;
    }
    if (_supplierNameCtrl.text.trim().isEmpty) {
      _snack('Fournisseur requis');
      return;
    }
    if (_selectedGameId == null) {
      _snack('Choisis un jeu');
      return;
    }
    if (estPrice == null || estPrice < 0) {
      _snack('Prix estimé par unité requis (>= 0)');
      return;
    }

    setState(() => _saving = true);
    try {
      // (variable inutilisée, conservée si tu veux réutiliser plus tard)

      await _sb.rpc('fn_create_product_and_items', params: {
        'p_type': _type,
        'p_name': _nameCtrl.text.trim(),
        'p_language': _lang,
        'p_game_id': _selectedGameId,
        'p_supplier_name': _supplierNameCtrl.text.trim(),
        'p_buyer_company': _buyerCompanyCtrl.text.trim().isEmpty
            ? null
            : _buyerCompanyCtrl.text.trim(),
        'p_purchase_date': _purchaseDate.toIso8601String().substring(0, 10),
        'p_currency': 'USD',
        'p_qty': qty,
        'p_total_cost': totalCost,
        'p_fees': fees,
        'p_init_status': _initStatus, // peut être 'collection'
        'p_channel_id': null, // ou un int
        'p_tracking': _trackingCtrl.text.trim().isNotEmpty
            ? _trackingCtrl.text.trim()
            : null,
        'p_photo_url': _photoUrlCtrl.text.trim().isNotEmpty
            ? _photoUrlCtrl.text.trim()
            : null,
        'p_document_url':
            _docUrlCtrl.text.trim().isNotEmpty ? _docUrlCtrl.text.trim() : null,
        'p_estimated_price': estPrice, // <- toujours envoyé (non null)
        'p_notes':
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        'p_grade_id': _gradeIdCtrl.text.trim().isNotEmpty
            ? _gradeIdCtrl.text.trim()
            : null,
        'p_item_location': _itemLocationCtrl.text.trim().isNotEmpty
            ? _itemLocationCtrl.text.trim()
            : null,
      });

      _snack('Stock créé ($qty items)');
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
                            onChanged: (v) => setState(() {
                              _type = v ?? 'single';
                              final newStatuses = _type == 'single'
                                  ? singleStatuses
                                  : sealedStatuses;
                              if (!newStatuses.contains(_initStatus)) {
                                _initStatus = newStatuses.first;
                              }
                            }),
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
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nom du produit *'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nom requis'
                            : null,
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
                      TextFormField(
                        controller: _supplierNameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Fournisseur * (texte libre)'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Fournisseur requis'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _buyerCompanyCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Société acheteuse (optionnel)'),
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
                            items: statuses
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
                      // === Estimated price (OBLIGATOIRE) ===
                      TextFormField(
                        controller: _estimatedPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Prix de vente estimé par unité (USD) *',
                        ),
                        validator: (v) {
                          final n = double.tryParse(
                              (v ?? '').trim().replaceAll(',', '.'));
                          if (n == null || n < 0) {
                            return 'Prix estimé requis (>= 0)';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Plus d’options
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
                        // (Estimated price retiré d’ici)
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _gradeIdCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Grading ID'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _itemLocationCtrl,
                              decoration: const InputDecoration(
                                  labelText: "Item Location"),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _trackingCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Tracking Number'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox.shrink()),
                        ]),
                        const SizedBox(height: 8),
                        StorageUploadTile(
                          label: 'Photo',
                          bucket: 'item-photos',
                          objectPrefix:
                              'items', // tu peux mettre 'items/${_selectedGameId ?? "gen"}'
                          initialUrl: _photoUrlCtrl.text.isEmpty
                              ? null
                              : _photoUrlCtrl.text,
                          onUrlChanged: (u) => _photoUrlCtrl.text = u ?? '',
                          acceptImagesOnly: true,
                          onError: _showUploadError, // <-- affiche dialog
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
                          onError: _showUploadError, // <-- affiche dialog
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesCtrl,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
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
