import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/invoice_folder.dart';

class AttachExternalInvoiceResult {
  final String supplierName; // ex: Etisalat / Prestataire
  final String invoiceNumber; // ref externe
  final DateTime issueDate;
  final double totalAmount; // total TTC (on mettra taxe=0)
  final String currency;

  final int? folderId; // dossier existant choisi
  final String? newFolderName; // si l’utilisateur veut en créer un

  final String? notes;

  final Uint8List fileBytes;
  final String fileName;

  AttachExternalInvoiceResult({
    required this.supplierName,
    required this.invoiceNumber,
    required this.issueDate,
    required this.totalAmount,
    required this.currency,
    required this.fileBytes,
    required this.fileName,
    this.folderId,
    this.newFolderName,
    this.notes,
  });
}

class AttachExternalInvoiceDialog extends StatefulWidget {
  final String currency;
  final List<InvoiceFolder> folders;

  const AttachExternalInvoiceDialog({
    super.key,
    required this.currency,
    required this.folders,
  });

  static Future<AttachExternalInvoiceResult?> show(
    BuildContext context, {
    required String currency,
    required List<InvoiceFolder> folders,
  }) {
    return showDialog<AttachExternalInvoiceResult>(
      context: context,
      builder: (_) => AttachExternalInvoiceDialog(
        currency: currency,
        folders: folders,
      ),
    );
  }

  @override
  State<AttachExternalInvoiceDialog> createState() =>
      _AttachExternalInvoiceDialogState();
}

class _AttachExternalInvoiceDialogState
    extends State<AttachExternalInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();

  final _supplierCtrl = TextEditingController();
  final _invoiceNumberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _newFolderCtrl = TextEditingController();

  DateTime _issueDate = DateTime.now();

  Uint8List? _fileBytes;
  String? _fileName;
  String? _fileError;
  bool _picking = false;

  int? _selectedFolderId;

  late String _currency;

  // Tu peux élargir la liste si besoin
  static const List<String> _currencyOptions = ['AED', 'USD', 'EUR', 'ILS'];

  @override
  void initState() {
    super.initState();
    _currency =
        (widget.currency.trim().isEmpty ? 'AED' : widget.currency.trim())
            .toUpperCase();
    if (!_currencyOptions.contains(_currency)) {
      // si devise par défaut non dans liste, on l’ajoute (ex: GBP)
      _currencyOptionsWithFallback.add(_currency);
    }
  }

  // Hack propre pour garder une liste modifiable sans rendre _currencyOptions mutable
  static final List<String> _currencyOptionsWithFallback = List<String>.from(
    _currencyOptions,
  );

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _invoiceNumberCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _picking = true;
      _fileError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }

      final f = result.files.single;
      if (f.bytes == null) {
        setState(() {
          _picking = false;
          _fileError = 'Could not read file content.';
        });
        return;
      }

      setState(() {
        _fileBytes = f.bytes;
        _fileName = f.name;
        _picking = false;
        _fileError = null;
      });
    } catch (e) {
      setState(() {
        _picking = false;
        _fileError = 'Error while picking file: $e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _issueDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_fileBytes == null || _fileName == null) {
      setState(() => _fileError = 'Please select a file (PDF/image).');
      return;
    }

    final supplierName = _supplierCtrl.text.trim();
    final invoiceNumber = _invoiceNumberCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final newFolder =
        _newFolderCtrl.text.trim().isEmpty ? null : _newFolderCtrl.text.trim();

    final amount =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount < 0) {
      setState(() {});
      return;
    }

    Navigator.of(context).pop(
      AttachExternalInvoiceResult(
        supplierName: supplierName,
        invoiceNumber: invoiceNumber,
        issueDate: _issueDate,
        totalAmount: amount,
        currency: _currency,
        folderId: newFolder != null ? null : _selectedFolderId,
        newFolderName: newFolder,
        notes: notes,
        fileBytes: _fileBytes!,
        fileName: _fileName!,
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final maxDialogW = math.min(520.0, screenW * 0.92); // ✅ responsive width
    final compact = screenW < 520; // ✅ compact layout to avoid Row overflows

    return AlertDialog(
      title: const Text('Attach external invoice / document'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxDialogW),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _supplierCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Provider / Supplier * (ex: Etisalat)',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _invoiceNumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'External invoice/reference number *',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // ✅ Amount + Currency + Date (responsive)
                if (compact) ...[
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Total amount ($_currency) *',
                    ),
                    validator: (v) {
                      final x = double.tryParse(
                          (v ?? '').trim().replaceAll(',', '.'));
                      if (x == null) return 'Invalid number';
                      if (x < 0) return 'Must be >= 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _currency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                    ),
                    items: _currencyOptionsWithFallback
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _currency = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text(_formatDate(_issueDate)),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Total amount ($_currency) *',
                          ),
                          validator: (v) {
                            final x = double.tryParse(
                                (v ?? '').trim().replaceAll(',', '.'));
                            if (x == null) return 'Invalid number';
                            if (x < 0) return 'Must be >= 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          value: _currency,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Currency',
                          ),
                          items: _currencyOptionsWithFallback
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _currency = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event),
                        label: Text(_formatDate(_issueDate)),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Folder selection
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Folder (optional)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  value: _selectedFolderId,
                  isExpanded: true, // ✅ helps avoid overflow with long names
                  decoration: const InputDecoration(
                    labelText: 'Select existing folder',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No folder'),
                    ),
                    ...widget.folders.map(
                      (f) => DropdownMenuItem<int?>(
                        value: f.id,
                        child: Text(
                          f.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedFolderId = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _newFolderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Or create new folder (path) e.g. Etisalat/2025',
                    hintText: 'Etisalat/phone',
                  ),
                ),

                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'File',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _picking ? null : _pickFile,
                      icon: _picking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      label: const Text('Select file'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fileName ?? 'No file selected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_fileError != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fileError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Attach'),
        ),
      ],
    );
  }
}
