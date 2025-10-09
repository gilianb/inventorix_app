import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewStockPage extends StatefulWidget {
  const NewStockPage({super.key});

  @override
  State<NewStockPage> createState() => _NewStockPageState();
}

class _NewStockPageState extends State<NewStockPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Product minimal
  String _type = 'single'; // 'single' | 'sealed'
  final _nameCtrl = TextEditingController();
  String _lang = 'EN';

  // Lot
  final _supplierNameCtrl = TextEditingController(); // texte libre
  final _buyerCompanyCtrl = TextEditingController(); // société acheteuse
  DateTime _purchaseDate = DateTime.now();
  final _totalCostCtrl = TextEditingController(); // PRIX TOTAL DU LOT (USD)
  final _qtyCtrl = TextEditingController(text: '1');
  final _feesCtrl = TextEditingController(text: '0'); // en USD
  final _notesCtrl = TextEditingController();
  String _initStatus = 'paid';

  bool _saving = false;

  static const langs = ['EN', 'FR', 'JP'];
  static const singleStatuses = [
    // Achat
    'paid', 'in_transit', 'received',
    // Gradation
    'sent_to_grader', 'at_grader', 'graded',
    // Vente
    'listed', 'sold', 'shipped', 'finalized'
  ];
  static const sealedStatuses = [
    'ordered',
    'paid',
    'received',
    'listed',
    'shipped',
    'finalized',
  ];

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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

    setState(() => _saving = true);
    try {
      final lotId = await _sb.rpc('fn_create_product_and_lot', params: {
        'p_type': _type,
        'p_name': _nameCtrl.text.trim(),
        'p_language': _lang,
        'p_supplier_name': _supplierNameCtrl.text.trim(),
        'p_purchase_date': _purchaseDate.toIso8601String().substring(0, 10),
        'p_total_cost': totalCost,
        'p_qty': qty,
        'p_fees': fees,
        'p_init_status': _initStatus,
        'p_buyer_company': _buyerCompanyCtrl.text.trim().isEmpty
            ? null
            : _buyerCompanyCtrl.text.trim(),
        'p_notes':
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });

      _snack('Lot créé (#$lotId)');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _type == 'single' ? singleStatuses : sealedStatuses;
    final statusValue =
        statuses.contains(_initStatus) ? _initStatus : statuses.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau lot')),
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
                            value: _type,
                            items: const [
                              DropdownMenuItem(
                                  value: 'single', child: Text('Single')),
                              DropdownMenuItem(
                                  value: 'sealed', child: Text('Sealed')),
                            ],
                            onChanged: (v) => setState(() {
                              _type = v ?? 'single';
                              // si le statut courant n’existe pas dans la nouvelle liste, on le remet au 1er
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Lot & Achat (USD)',
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
                                labelText: 'Prix total du lot (USD) *'),
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
                            initialValue:
                                statusValue, // <-- au lieu d'initialValue / ou d'une value potentiellement invalide
                            items: statuses
                                .toSet() // dédoublonne au cas où
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
                        controller: _notesCtrl,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: 'Notes (optionnel)'),
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
                    label: const Text('Créer le lot'),
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
