// lib/new_stock_page.dart
import 'dart:convert'; // <-- pour jsonDecode
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewStockPage extends StatefulWidget {
  const NewStockPage({super.key, this.existingItem});

  final Map<String, dynamic>? existingItem; // null => création

  @override
  State<NewStockPage> createState() => _NewStockPageState();
}

class _NewStockPageState extends State<NewStockPage> {
  final _supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  // Champs items
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _gameCtrl = TextEditingController(); // enum (obligatoire)
  final _categoryCtrl = TextEditingController(); // enum (default DB: single)
  final _setNameCtrl = TextEditingController();
  final _collectorNumberCtrl = TextEditingController();
  final _rarityCtrl = TextEditingController();
  final _languageCtrl = TextEditingController(text: 'EN');
  final _conditionCtrl = TextEditingController(); // enum (default DB: NM)
  final _finishCtrl = TextEditingController(); // enum (default DB: normal)
  final _barcodeCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _locationCtrl = TextEditingController(text: 'MAIN');
  final _buyPriceCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  // Champs annexes
  final _orgIdCtrl = TextEditingController(); // optionnel si RLS par org
  final _attributesCtrl = TextEditingController(text: '{}'); // JSON
  // Mouvement de stock initial (création uniquement)
  final _initQtyCtrl = TextEditingController(text: '0');
  final _initReasonCtrl = TextEditingController(text: 'manual'); // enum reason

  bool _isSaving = false;

  bool get _isEdit => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    final it = widget.existingItem;
    if (it != null) {
      _nameCtrl.text = (it['name'] ?? '').toString();
      _skuCtrl.text = (it['sku'] ?? '').toString();
      _gameCtrl.text = (it['game'] ?? '').toString();
      _categoryCtrl.text = (it['category'] ?? '').toString();
      _setNameCtrl.text = (it['set_name'] ?? '').toString();
      _collectorNumberCtrl.text = (it['collector_number'] ?? '').toString();
      _rarityCtrl.text = (it['rarity'] ?? '').toString();
      _languageCtrl.text = (it['language'] ?? 'EN').toString();
      _conditionCtrl.text = (it['condition'] ?? '').toString();
      _finishCtrl.text = (it['finish'] ?? '').toString();
      _barcodeCtrl.text = (it['barcode'] ?? '').toString();
      _imageUrlCtrl.text = (it['image_url'] ?? '').toString();
      _locationCtrl.text = (it['location'] ?? 'MAIN').toString();
      _buyPriceCtrl.text = (it['buy_price']?.toString() ?? '');
      _sellPriceCtrl.text = (it['sell_price']?.toString() ?? '');
      _notesCtrl.text = (it['notes'] ?? '').toString();
      _countryCtrl.text = (it['country'] ?? '').toString();
      _orgIdCtrl.text = (it['org_id'] ?? '').toString();
      // attributes -> JSON string
      final attrs = it['attributes'];
      _attributesCtrl.text = (attrs is Map || attrs is List)
          ? jsonEncode(attrs)
          : (attrs ?? '{}').toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _gameCtrl.dispose();
    _categoryCtrl.dispose();
    _setNameCtrl.dispose();
    _collectorNumberCtrl.dispose();
    _rarityCtrl.dispose();
    _languageCtrl.dispose();
    _conditionCtrl.dispose();
    _finishCtrl.dispose();
    _barcodeCtrl.dispose();
    _imageUrlCtrl.dispose();
    _locationCtrl.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _notesCtrl.dispose();
    _countryCtrl.dispose();
    _orgIdCtrl.dispose();
    _attributesCtrl.dispose();
    _initQtyCtrl.dispose();
    _initReasonCtrl.dispose();
    super.dispose();
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Map<String, dynamic> _buildItemPayload() {
    // parse prices (numeric en DB) -> on envoie des num (double) ou null
    double? parseNum(String s) {
      if (s.trim().isEmpty) return null;
      return double.tryParse(s.replaceAll(',', '.'));
    }

    // parse JSON attributes
    dynamic parseJsonLike(String s) {
      try {
        return jsonDecode(s); // <-- utilise dart:convert
      } catch (_) {
        return {}; // fallback propre pour jsonb
      }
    }

    final data = <String, dynamic>{
      if (_orgIdCtrl.text.trim().isNotEmpty) 'org_id': _orgIdCtrl.text.trim(),
      'sku': _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'game': _gameCtrl.text.trim(), // enum (OBLIGATOIRE dans DDL)
      if (_categoryCtrl.text.trim().isNotEmpty)
        'category': _categoryCtrl.text.trim(),
      'set_name':
          _setNameCtrl.text.trim().isEmpty ? null : _setNameCtrl.text.trim(),
      'collector_number': _collectorNumberCtrl.text.trim().isEmpty
          ? null
          : _collectorNumberCtrl.text.trim(),
      'rarity':
          _rarityCtrl.text.trim().isEmpty ? null : _rarityCtrl.text.trim(),
      'language':
          _languageCtrl.text.trim().isEmpty ? 'EN' : _languageCtrl.text.trim(),
      if (_conditionCtrl.text.trim().isNotEmpty)
        'condition': _conditionCtrl.text.trim(),
      if (_finishCtrl.text.trim().isNotEmpty) 'finish': _finishCtrl.text.trim(),
      'barcode':
          _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      'image_url':
          _imageUrlCtrl.text.trim().isEmpty ? null : _imageUrlCtrl.text.trim(),
      'location': _locationCtrl.text.trim().isEmpty
          ? 'MAIN'
          : _locationCtrl.text.trim(),
      'buy_price': parseNum(_buyPriceCtrl.text),
      'sell_price': parseNum(_sellPriceCtrl.text),
      'attributes': parseJsonLike(_attributesCtrl.text.trim().isEmpty
          ? '{}'
          : _attributesCtrl.text.trim()),
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'country':
          _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    return data;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final payload = _buildItemPayload();

      if (_isEdit) {
        final id = widget.existingItem!['id'];
        final updated = await _supabase
            .from('items')
            .update(payload)
            .eq('id', id)
            .select() // <-- pas de générique
            .maybeSingle(); // <-- OK en v2

        if (updated == null) {
          _msg('Aucun enregistrement mis à jour.');
        } else {
          _msg('Article mis à jour.');
        }
        if (mounted) {
          FocusManager.instance.primaryFocus?.unfocus(); // <-- défocus global
          Navigator.pop(context, true);
        }
        return;
      } else {
        final insertedAny = await _supabase
            .from('items')
            .insert(payload)
            .select() // <-- pas de générique
            .single();

        final inserted = Map<String, dynamic>.from(insertedAny as Map);

        // Mouvement de stock initial si ≠ 0
        final initQty = int.tryParse(_initQtyCtrl.text.trim()) ?? 0;
        final reason = _initReasonCtrl.text.trim().isEmpty
            ? 'manual'
            : _initReasonCtrl.text.trim();
        if (initQty != 0) {
          await _supabase.from('stock_moves').insert({
            'item_id': inserted['id'].toString(),
            'qty_change': initQty,
            'reason': reason, // ⚠️ doit exister dans l’enum reason
            if (_orgIdCtrl.text.trim().isNotEmpty)
              'org_id': _orgIdCtrl.text.trim(),
            'note': 'Stock initial via création item',
          });
        }

        _msg('Article créé${initQty != 0 ? ' (+ stock initial)' : ''}.');
        if (mounted) {
          FocusManager.instance.primaryFocus?.unfocus(); // <-- défocus global
        }
        // ignore: use_build_context_synchronously
        Navigator.pop(context, true);
        return;
      }
    } on PostgrestException catch (e) {
      _msg('Erreur Supabase : ${e.message}');
    } catch (e) {
      _msg('Erreur : $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Modifier un article' : 'Nouvel article';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Ligne 1 : Nom + SKU
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom *'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nom requis'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _skuCtrl,
                        decoration: const InputDecoration(labelText: 'SKU'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 2 : Game (enum) + Category (enum)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _gameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Game (enum) *',
                          helperText:
                              'Doit correspondre à ta valeur d’enum en DB',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Game requis'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Category (enum)',
                          helperText: 'Vide = default DB (single)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 3 : Set / Collector / Rarity
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _setNameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Set name'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _collectorNumberCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Collector #'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _rarityCtrl,
                        decoration: const InputDecoration(labelText: 'Rareté'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 4 : Lang / Condition / Finish
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _languageCtrl,
                        decoration: const InputDecoration(labelText: 'Langue'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _conditionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Condition (enum)',
                          helperText: 'Vide = default DB (NM)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _finishCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Finition (enum)',
                          helperText: 'Vide = default DB (normal)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 5 : Codes / Image / Lieu
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _barcodeCtrl,
                        decoration: const InputDecoration(labelText: 'Barcode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _imageUrlCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Image URL'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _locationCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Emplacement'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 6 : Prix d’achat / vente / Pays
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _buyPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Prix d’achat (€)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sellPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Prix de vente (€)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(labelText: 'Pays'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 7 : org_id + attributes JSON
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _orgIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'org_id (optionnel)',
                          helperText: 'Renseigne si RLS par organisation',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _attributesCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'attributes (JSON)',
                          helperText: 'ex: {"graded":false,"alt":"..."}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 16),

                if (!_isEdit)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const Text(
                        'Stock initial (création uniquement)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _initQtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Quantité initiale (peut être 0)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _initReasonCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Reason (enum)',
                                helperText: 'ex: manual / purchase / adjust…',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_isEdit ? 'Enregistrer' : 'Créer l’article'),
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
