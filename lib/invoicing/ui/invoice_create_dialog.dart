import 'package:flutter/material.dart';

class InvoiceFormResult {
  final String sellerName;
  final String? sellerAddress;
  final String? sellerCountry;
  final String? sellerVatNumber;

  final String buyerName;
  final String? buyerAddress;
  final String? buyerCountry;
  final String? buyerEmail;

  final double taxRate;
  final String paymentTerms;
  final String? notes;

  InvoiceFormResult({
    required this.sellerName,
    this.sellerAddress,
    this.sellerCountry,
    this.sellerVatNumber,
    required this.buyerName,
    this.buyerAddress,
    this.buyerCountry,
    this.buyerEmail,
    required this.taxRate,
    required this.paymentTerms,
    this.notes,
  });
}

class InvoiceCreateDialog extends StatefulWidget {
  final String defaultCurrency;
  final String? defaultSellerName;
  final String? defaultBuyerName;

  const InvoiceCreateDialog({
    super.key,
    required this.defaultCurrency,
    this.defaultSellerName,
    this.defaultBuyerName,
  });

  static Future<InvoiceFormResult?> show(
    BuildContext context, {
    required String currency,
    String? sellerName,
    String? buyerName,
  }) {
    return showDialog<InvoiceFormResult>(
      context: context,
      builder: (_) => InvoiceCreateDialog(
        defaultCurrency: currency,
        defaultSellerName: sellerName,
        defaultBuyerName: buyerName,
      ),
    );
  }

  @override
  State<InvoiceCreateDialog> createState() => _InvoiceCreateDialogState();
}

class _InvoiceCreateDialogState extends State<InvoiceCreateDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _sellerNameCtrl;
  final _sellerAddressCtrl = TextEditingController();
  final _sellerCountryCtrl = TextEditingController();
  final _sellerVatCtrl = TextEditingController();

  late final TextEditingController _buyerNameCtrl;
  final _buyerAddressCtrl = TextEditingController();
  final _buyerCountryCtrl = TextEditingController();
  final _buyerEmailCtrl = TextEditingController();

  final _taxCtrl = TextEditingController(text: '0');
  final _paymentTermsCtrl = TextEditingController(
    text: 'Payment due within 7 days by bank transfer.',
  );
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sellerNameCtrl =
        TextEditingController(text: widget.defaultSellerName ?? '');
    _buyerNameCtrl = TextEditingController(text: widget.defaultBuyerName ?? '');
  }

  @override
  void dispose() {
    _sellerNameCtrl.dispose();
    _sellerAddressCtrl.dispose();
    _sellerCountryCtrl.dispose();
    _sellerVatCtrl.dispose();
    _buyerNameCtrl.dispose();
    _buyerAddressCtrl.dispose();
    _buyerCountryCtrl.dispose();
    _buyerEmailCtrl.dispose();
    _taxCtrl.dispose();
    _paymentTermsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final tax = double.tryParse(_taxCtrl.text.replaceAll(',', '.')) ?? 0.0;

    final result = InvoiceFormResult(
      sellerName: _sellerNameCtrl.text.trim(),
      sellerAddress: _sellerAddressCtrl.text.trim().isEmpty
          ? null
          : _sellerAddressCtrl.text.trim(),
      sellerCountry: _sellerCountryCtrl.text.trim().isEmpty
          ? null
          : _sellerCountryCtrl.text.trim(),
      sellerVatNumber: _sellerVatCtrl.text.trim().isEmpty
          ? null
          : _sellerVatCtrl.text.trim(),
      buyerName: _buyerNameCtrl.text.trim().isEmpty
          ? 'N/A'
          : _buyerNameCtrl.text.trim(),
      buyerAddress: _buyerAddressCtrl.text.trim().isEmpty
          ? null
          : _buyerAddressCtrl.text.trim(),
      buyerCountry: _buyerCountryCtrl.text.trim().isEmpty
          ? null
          : _buyerCountryCtrl.text.trim(),
      buyerEmail: _buyerEmailCtrl.text.trim().isEmpty
          ? null
          : _buyerEmailCtrl.text.trim(),
      taxRate: tax,
      paymentTerms: _paymentTermsCtrl.text.trim().isEmpty
          ? 'Payment due within 7 days by bank transfer.'
          : _paymentTermsCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create invoice'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // SELLER
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Seller',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _sellerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Seller name *',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _sellerAddressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Seller address',
                ),
              ),
              TextFormField(
                controller: _sellerCountryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Seller country',
                ),
              ),
              TextFormField(
                controller: _sellerVatCtrl,
                decoration: const InputDecoration(
                  labelText: 'Seller VAT number',
                ),
              ),
              const SizedBox(height: 12),

              // BUYER
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bill to',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _buyerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buyer name',
                ),
              ),
              TextFormField(
                controller: _buyerAddressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buyer address',
                ),
              ),
              TextFormField(
                controller: _buyerCountryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buyer country',
                ),
              ),
              TextFormField(
                controller: _buyerEmailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buyer email',
                ),
              ),
              const SizedBox(height: 12),

              // OTHER
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _taxCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tax rate (%)',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Currency',
                        hintText: widget.defaultCurrency,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _paymentTermsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Payment terms',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
