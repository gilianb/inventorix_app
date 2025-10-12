import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditListingDialog extends StatefulWidget {
  const EditListingDialog({super.key, required this.itemIds});
  final List<int> itemIds;

  @override
  State<EditListingDialog> createState() => _EditListingDialogState();
}

class _EditListingDialogState extends State<EditListingDialog> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // ====== Données de référence ======
  List<Map<String, dynamic>> _channels = const [];
  List<Map<String, dynamic>> _games = const [];

  // ====== Etats "appliquer ce champ ?" ======
  bool _applyStatus = false;
  bool _applyChannel = false;
  bool _applyLanguage = false;
  bool _applyGame = false;
  bool _applySupplier = false;
  bool _applyBuyer = false;
  bool _applyUnitCost = false;
  bool _applyUnitFees = false;
  bool _applyPurchaseDate = false;
  bool _applySaleDate = false;
  bool _applySalePrice = false;
  bool _applyEstimatedPrice = false;
  bool _applyTracking = false;
  bool _applyNotes = false;
  bool _applyPhoto = false;
  bool _applyDoc = false;
  bool _applyGrade = false;
  bool _applySubmission = false;
  bool _applyInCollection = false;

  // ====== Valeurs UI ======
  // Enums / listes
  static const _itemStatuses = <String>[
    'ordered',
    'paid',
    'in_transit',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'sold',
    'shipped',
    'finalized',
  ];
  static const _langs = ['EN', 'FR', 'JP'];

  String? _status;
  int? _channelId;
  String? _language;
  int? _gameId;

  // Text controllers
  final _supplierCtrl = TextEditingController();
  final _buyerCtrl = TextEditingController();
  final _unitCostCtrl = TextEditingController();
  final _unitFeesCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  final _estimatedPriceCtrl = TextEditingController();
  final _trackingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _submissionCtrl = TextEditingController();

  // Dates
  DateTime? _purchaseDate;
  DateTime? _saleDate;

  // Bool
  bool _inCollection = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _buyerCtrl.dispose();
    _unitCostCtrl.dispose();
    _unitFeesCtrl.dispose();
    _salePriceCtrl.dispose();
    _estimatedPriceCtrl.dispose();
    _trackingCtrl.dispose();
    _notesCtrl.dispose();
    _photoCtrl.dispose();
    _docCtrl.dispose();
    _gradeCtrl.dispose();
    _submissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    try {
      final channels =
          await _sb.from('channel').select('id, label').order('label');
      final games =
          await _sb.from('games').select('id, code, label').order('label');

      setState(() {
        _channels = channels
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
        _games = games
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // silencieux (on peut tout de même éditer les champs non liés)
    }
  }

  // Helpers
  String _dateStr(DateTime? d) =>
      d == null ? '' : d.toIso8601String().split('T').first; // YYYY-MM-DD

  double? _numFrom(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  int? _intFrom(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> setDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setDate(picked);
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_saving) return;

    // Pas besoin de valider si rien n'est coché
    final anyApplied = _applyStatus ||
        _applyChannel ||
        _applyLanguage ||
        _applyGame ||
        _applySupplier ||
        _applyBuyer ||
        _applyUnitCost ||
        _applyUnitFees ||
        _applyPurchaseDate ||
        _applySaleDate ||
        _applySalePrice ||
        _applyEstimatedPrice ||
        _applyTracking ||
        _applyNotes ||
        _applyPhoto ||
        _applyDoc ||
        _applyGrade ||
        _applySubmission ||
        _applyInCollection;

    if (!anyApplied) {
      Navigator.pop(context, false);
      return;
    }

    setState(() => _saving = true);

    try {
      final payload = <String, dynamic>{};

      if (_applyStatus && (_status != null && _status!.isNotEmpty)) {
        payload['status'] = _status; // ENUM item_status (texte)
      }
      if (_applyChannel) payload['channel_id'] = _channelId;
      if (_applyLanguage) payload['language'] = _language;
      if (_applyGame) payload['game_id'] = _gameId;

      if (_applySupplier && _supplierCtrl.text.trim().isNotEmpty) {
        payload['supplier_name'] = _supplierCtrl.text.trim();
      }
      if (_applyBuyer) {
        final v = _buyerCtrl.text.trim();
        payload['buyer_company'] = v.isEmpty ? null : v;
      }

      if (_applyUnitCost) {
        final v = _numFrom(_unitCostCtrl);
        if (v != null) payload['unit_cost'] = v;
      }
      if (_applyUnitFees) {
        final v = _numFrom(_unitFeesCtrl);
        if (v != null) payload['unit_fees'] = v;
      }

      if (_applyPurchaseDate && _purchaseDate != null) {
        payload['purchase_date'] = _dateStr(_purchaseDate);
      }

      if (_applySaleDate) {
        payload['sale_date'] =
            _saleDate == null ? null : _dateStr(_saleDate); // permet d’annuler
      }
      if (_applySalePrice) {
        final v = _numFrom(_salePriceCtrl);
        payload['sale_price'] = v; // peut être null => effacer
      }
      if (_applyEstimatedPrice) {
        final v = _numFrom(_estimatedPriceCtrl);
        payload['estimated_price'] = v;
      }

      if (_applyTracking) {
        final v = _trackingCtrl.text.trim();
        payload['tracking'] = v.isEmpty ? null : v;
      }
      if (_applyNotes) {
        final v = _notesCtrl.text.trim();
        payload['notes'] = v.isEmpty ? null : v;
      }
      if (_applyPhoto) {
        final v = _photoCtrl.text.trim();
        payload['photo_url'] = v.isEmpty ? null : v;
      }
      if (_applyDoc) {
        final v = _docCtrl.text.trim();
        payload['document_url'] = v.isEmpty ? null : v;
      }
      if (_applyGrade) {
        final v = _gradeCtrl.text.trim();
        payload['grade'] = v.isEmpty ? null : v;
      }
      if (_applySubmission) {
        payload['grading_submission_id'] = _intFrom(_submissionCtrl);
      }

      if (_applyInCollection) {
        payload['in_collection'] = _inCollection;
      }

      if (payload.isEmpty) {
        Navigator.pop(context, false);
        return;
      }

      // Batch update
      await _sb.from('item').update(payload).inFilter('id', widget.itemIds);

      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _msg('Supabase: ${e.message}');
    } catch (e) {
      _msg('Erreur: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier listing (multi)'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ===== Ligne 1 : statut / canal =====
                _ApplyRow(
                  label: 'Statut',
                  checked: _applyStatus,
                  onChanged: (v) => setState(() => _applyStatus = v ?? false),
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    items: _itemStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v),
                    decoration: const InputDecoration(hintText: 'Choisir…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Canal',
                  checked: _applyChannel,
                  onChanged: (v) => setState(() => _applyChannel = v ?? false),
                  child: DropdownButtonFormField<int>(
                    value: _channelId,
                    items: _channels
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(c['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _channelId = v),
                    decoration: const InputDecoration(hintText: 'Choisir…'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 2 : langue / jeu =====
                _ApplyRow(
                  label: 'Langue',
                  checked: _applyLanguage,
                  onChanged: (v) => setState(() => _applyLanguage = v ?? false),
                  child: DropdownButtonFormField<String>(
                    value: _language,
                    items: _langs
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(() => _language = v),
                    decoration: const InputDecoration(hintText: 'Choisir…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Jeu',
                  checked: _applyGame,
                  onChanged: (v) => setState(() => _applyGame = v ?? false),
                  child: DropdownButtonFormField<int>(
                    value: _gameId,
                    items: _games
                        .map((g) => DropdownMenuItem<int>(
                              value: g['id'] as int,
                              child: Text(g['label'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _gameId = v),
                    decoration: const InputDecoration(hintText: 'Choisir…'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 3 : acheteur / fournisseur =====
                _ApplyRow(
                  label: 'Fournisseur',
                  checked: _applySupplier,
                  onChanged: (v) => setState(() => _applySupplier = v ?? false),
                  child: TextFormField(
                    controller: _supplierCtrl,
                    decoration: const InputDecoration(hintText: 'Nom…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Société acheteuse',
                  checked: _applyBuyer,
                  onChanged: (v) => setState(() => _applyBuyer = v ?? false),
                  child: TextFormField(
                    controller: _buyerCtrl,
                    decoration: const InputDecoration(hintText: 'Nom…'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 4 : coûts =====
                _ApplyRow(
                  label: 'Coût unitaire',
                  checked: _applyUnitCost,
                  onChanged: (v) => setState(() => _applyUnitCost = v ?? false),
                  child: TextFormField(
                    controller: _unitCostCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'ex: 12.5'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Frais unitaires',
                  checked: _applyUnitFees,
                  onChanged: (v) => setState(() => _applyUnitFees = v ?? false),
                  child: TextFormField(
                    controller: _unitFeesCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'ex: 0.75'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 5 : dates =====
                _ApplyRow(
                  label: 'Date achat',
                  checked: _applyPurchaseDate,
                  onChanged: (v) =>
                      setState(() => _applyPurchaseDate = v ?? false),
                  child: _DateField(
                    date: _purchaseDate,
                    onTap: () => _pickDate(
                      current: _purchaseDate,
                      setDate: (d) => setState(() => _purchaseDate = d),
                    ),
                    placeholder: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Date vente',
                  checked: _applySaleDate,
                  onChanged: (v) => setState(() => _applySaleDate = v ?? false),
                  child: _DateField(
                    date: _saleDate,
                    onTap: () => _pickDate(
                      current: _saleDate,
                      setDate: (d) => setState(() => _saleDate = d),
                    ),
                    placeholder: 'YYYY-MM-DD (laisser vide pour annuler)',
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 6 : prix vente / estimé =====
                _ApplyRow(
                  label: 'Prix vente',
                  checked: _applySalePrice,
                  onChanged: (v) =>
                      setState(() => _applySalePrice = v ?? false),
                  child: TextFormField(
                    controller: _salePriceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(hintText: 'ex: 35.00 (USD)'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Prix estimé',
                  checked: _applyEstimatedPrice,
                  onChanged: (v) =>
                      setState(() => _applyEstimatedPrice = v ?? false),
                  child: TextFormField(
                    controller: _estimatedPriceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(hintText: 'ex: 40.00 (USD)'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 7 : suivi / notes / médias =====
                _ApplyRow(
                  label: 'Tracking',
                  checked: _applyTracking,
                  onChanged: (v) => setState(() => _applyTracking = v ?? false),
                  child: TextFormField(
                    controller: _trackingCtrl,
                    decoration: const InputDecoration(hintText: 'numéro…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Notes',
                  checked: _applyNotes,
                  onChanged: (v) => setState(() => _applyNotes = v ?? false),
                  child: TextFormField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: '…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Photo URL',
                  checked: _applyPhoto,
                  onChanged: (v) => setState(() => _applyPhoto = v ?? false),
                  child: TextFormField(
                    controller: _photoCtrl,
                    decoration: const InputDecoration(hintText: 'https://…'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Document URL',
                  checked: _applyDoc,
                  onChanged: (v) => setState(() => _applyDoc = v ?? false),
                  child: TextFormField(
                    controller: _docCtrl,
                    decoration: const InputDecoration(hintText: 'https://…'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 8 : grade / submission =====
                _ApplyRow(
                  label: 'Grade',
                  checked: _applyGrade,
                  onChanged: (v) => setState(() => _applyGrade = v ?? false),
                  child: TextFormField(
                    controller: _gradeCtrl,
                    decoration: const InputDecoration(hintText: 'ex: PSA 9'),
                  ),
                ),
                const SizedBox(height: 8),
                _ApplyRow(
                  label: 'Submission ID',
                  checked: _applySubmission,
                  onChanged: (v) =>
                      setState(() => _applySubmission = v ?? false),
                  child: TextFormField(
                    controller: _submissionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'ex: 123'),
                  ),
                ),

                const SizedBox(height: 16),
                // ===== Ligne 9 : collection =====
                _ApplyRow(
                  label: 'Dans collection',
                  checked: _applyInCollection,
                  onChanged: (v) =>
                      setState(() => _applyInCollection = v ?? false),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _inCollection,
                    onChanged: (v) => setState(() => _inCollection = v),
                    title: const Text('Marquer comme collection'),
                    subtitle: const Text(
                        'Déclenche aussi un mouvement via trigger si différent'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/* ====================== Petits widgets ====================== */

class _ApplyRow extends StatelessWidget {
  const _ApplyRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    required this.child,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: checked, onChanged: onChanged),
        const SizedBox(width: 6),
        SizedBox(
          width: 130,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onTap,
    required this.placeholder,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final txt =
        date == null ? placeholder : date!.toIso8601String().split('T').first;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(txt),
        ),
      ),
    );
  }
}
