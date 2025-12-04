// lib/invoicing/ui/attach_purchase_invoice_dialog.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class AttachPurchaseInvoiceResult {
  final String supplierName;
  final String invoiceNumber;
  final String? notes;
  final Uint8List fileBytes;
  final String fileName;

  AttachPurchaseInvoiceResult({
    required this.supplierName,
    required this.invoiceNumber,
    required this.fileBytes,
    required this.fileName,
    this.notes,
  });
}

class AttachPurchaseInvoiceDialog extends StatefulWidget {
  final String? defaultSupplierName;
  final String currency;

  const AttachPurchaseInvoiceDialog({
    super.key,
    required this.currency,
    this.defaultSupplierName,
  });

  static Future<AttachPurchaseInvoiceResult?> show(
    BuildContext context, {
    required String currency,
    String? supplierName,
  }) {
    return showDialog<AttachPurchaseInvoiceResult>(
      context: context,
      builder: (_) => AttachPurchaseInvoiceDialog(
        currency: currency,
        defaultSupplierName: supplierName,
      ),
    );
  }

  @override
  State<AttachPurchaseInvoiceDialog> createState() =>
      _AttachPurchaseInvoiceDialogState();
}

class _AttachPurchaseInvoiceDialogState
    extends State<AttachPurchaseInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _supplierCtrl;
  final TextEditingController _invoiceNumberCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  Uint8List? _fileBytes;
  String? _fileName;
  String? _fileError;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _supplierCtrl =
        TextEditingController(text: widget.defaultSupplierName ?? '');
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _invoiceNumberCtrl.dispose();
    _notesCtrl.dispose();
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
        withData: true, // important so we have bytes on all platforms
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _picking = false;
        });
        return; // user cancelled
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_fileBytes == null || _fileName == null) {
      setState(() {
        _fileError = 'Please select an invoice file.';
      });
      return;
    }

    final supplierName = _supplierCtrl.text.trim();
    final invoiceNumber = _invoiceNumberCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final result = AttachPurchaseInvoiceResult(
      supplierName: supplierName,
      invoiceNumber: invoiceNumber,
      fileBytes: _fileBytes!,
      fileName: _fileName!,
      notes: notes,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Attach purchase invoice'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Supplier',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _supplierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier name *',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Invoice',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _invoiceNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier invoice number *',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Currency: ${widget.currency}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Invoice file',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
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
                  const SizedBox(width: 8),
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
                const SizedBox(height: 4),
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
                decoration: const InputDecoration(
                  labelText: 'Notes',
                ),
                maxLines: 2,
              ),
            ],
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
