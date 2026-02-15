// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models/invoice.dart';
import 'models/invoice_line.dart';
import 'invoice_format.dart';

class InvoicePdfBuilder {
  static const String _fontAssetPath = 'fonts/Roboto-Variable.ttf';

  static const List<String> _logoAssetPaths = <String>[
    'assets/timage/logoCS.png',
    'assets/timage/logoCS.jpeg',
    'assets/images/logoCS.jpeg',
  ];

  static const String _bankAccountHolder = 'CARDSHOUKER TRADING LLC SOC';
  static const String _bankName = 'Mashreq Bank';
  static const String _bankAccountNumber = '019101921120';
  static const String _bankIban = 'AE040330000019101921120';

  static pw.Font? _pdfFontBase;
  static pw.Font? _pdfFontBold;
  static Future<pw.MemoryImage?>? _cachedLogoFuture;

  Future<Uint8List> buildPdf(
    Invoice invoice,
    List<InvoiceLine> lines, {
    bool showLogoInPdf = false,
    bool showBankInfoInPdf = false,
    bool showDisplayTotalInAed = false,
    double? aedPerInvoiceCurrencyRate,
  }) async {
    await _ensurePdfFonts();

    final doc = pw.Document(
      theme: (_pdfFontBase != null && _pdfFontBold != null)
          ? pw.ThemeData.withFont(
              base: _pdfFontBase!,
              bold: _pdfFontBold!,
              italic: _pdfFontBase!,
              boldItalic: _pdfFontBold!,
            )
          : null,
    );

    const title = 'INVOICE';
    final paymentTerms =
        invoice.paymentTerms ?? 'Payment due within 7 days by bank transfer.';

    final bool hasVat = _hasVat(invoice, lines);
    final logoImage = showLogoInPdf ? await _tryLoadLogo() : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          if (showLogoInPdf) ...[
            if (logoImage != null)
              _buildTopLogo(logoImage)
            else
              _buildTopLogoFallback(),
            pw.SizedBox(height: 12),
          ],
          _buildHeader(invoice, title),
          pw.SizedBox(height: 20),
          _buildSellerBuyer(invoice),
          pw.SizedBox(height: 20),
          _buildItemsTable(invoice, lines, hasVat: hasVat),
          pw.SizedBox(height: 20),
          _buildTotals(
            invoice,
            hasVat: hasVat,
            showDisplayTotalInAed: showDisplayTotalInAed,
            aedPerInvoiceCurrencyRate: aedPerInvoiceCurrencyRate,
          ),
          pw.SizedBox(height: 20),
          _buildNotes(paymentTerms, invoice.notes),
          if (showBankInfoInPdf) ...[
            pw.SizedBox(height: 20),
            _buildBankingInfo(),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _ensurePdfFonts() async {
    if (_pdfFontBase != null && _pdfFontBold != null) return;
    try {
      final data = await rootBundle.load(_fontAssetPath);
      final font = pw.Font.ttf(data);
      _pdfFontBase = font;
      _pdfFontBold = font;
    } catch (_) {
      // fallback to default Helvetica if font asset cannot be loaded
    }
  }

  Future<pw.MemoryImage?> _tryLoadLogo() async {
    _cachedLogoFuture ??= _loadLogoOnce();
    return _cachedLogoFuture!;
  }

  Future<pw.MemoryImage?> _loadLogoOnce() async {
    for (final path in _logoAssetPaths) {
      try {
        final data = await rootBundle.load(path);
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {
        // try next path
      }
    }
    return null;
  }

  pw.Widget _buildTopLogo(pw.MemoryImage image) {
    return pw.Align(
      alignment: pw.Alignment.topCenter,
      child: pw.Image(image, width: 190, height: 56, fit: pw.BoxFit.contain),
    );
  }

  pw.Widget _buildTopLogoFallback() {
    return pw.Align(
      alignment: pw.Alignment.topCenter,
      child: pw.Text(
        'CARDSHOUKER',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  String _sanitizePdfText(String? value) {
    final src = (value ?? '').trim();
    if (src.isEmpty) return '';

    final normalizedBars = src.replaceAll(RegExp(r'[|¦｜┃│￨]'), ' / ');

    final normalizedDashes = normalizedBars
        .replaceAll('\u2014', '-') // em dash
        .replaceAll('\u2013', '-') // en dash
        .replaceAll('\u2015', '-') // horizontal bar
        .replaceAll('\u2212', '-'); // minus sign

    final normalizedQuotes = normalizedDashes
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2026', '...');

    final normalizedSpaces =
        normalizedQuotes.replaceAll('\u00A0', ' ').replaceAll('\u200B', '');

    return normalizedSpaces.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Détecte si cette facture est "avec TVA" ou "sans TVA"
  bool _hasVat(Invoice invoice, List<InvoiceLine> lines) {
    if (invoice.totalTax != 0) return true;
    for (final l in lines) {
      if (l.taxRate != 0 || l.totalTax != 0) return true;
    }
    return false;
  }

  pw.Widget _buildHeader(Invoice invoice, String title) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Invoice No: ${_sanitizePdfText(invoice.invoiceNumber)}'),
            pw.Text('Issue date: ${formatDate(invoice.issueDate)}'),
            if (invoice.dueDate != null)
              pw.Text('Due date: ${formatDate(invoice.dueDate!)}'),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _sanitizePdfText(invoice.sellerName),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (invoice.sellerAddress != null)
              pw.Text(_sanitizePdfText(invoice.sellerAddress)),
            if (invoice.sellerCountry != null)
              pw.Text(_sanitizePdfText(invoice.sellerCountry)),
            if (invoice.sellerVatNumber != null &&
                invoice.sellerVatNumber!.isNotEmpty)
              pw.Text('VAT: ${_sanitizePdfText(invoice.sellerVatNumber)}'),
            if (invoice.sellerTaxRegistration != null &&
                invoice.sellerTaxRegistration!.isNotEmpty)
              pw.Text(
                'Tax Reg: ${_sanitizePdfText(invoice.sellerTaxRegistration)}',
              ),
            if (invoice.sellerRegistrationNumber != null &&
                invoice.sellerRegistrationNumber!.isNotEmpty)
              pw.Text(
                'Reg. No: ${_sanitizePdfText(invoice.sellerRegistrationNumber)}',
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildSellerBuyer(Invoice invoice) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Seller',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(_sanitizePdfText(invoice.sellerName)),
                if (invoice.sellerAddress != null)
                  pw.Text(_sanitizePdfText(invoice.sellerAddress)),
                if (invoice.sellerCountry != null)
                  pw.Text(_sanitizePdfText(invoice.sellerCountry)),
                if (invoice.sellerVatNumber != null &&
                    invoice.sellerVatNumber!.isNotEmpty)
                  pw.Text('VAT: ${_sanitizePdfText(invoice.sellerVatNumber)}'),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Bill to',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(_sanitizePdfText(invoice.buyerName)),
                if (invoice.buyerAddress != null)
                  pw.Text(_sanitizePdfText(invoice.buyerAddress)),
                if (invoice.buyerCountry != null)
                  pw.Text(_sanitizePdfText(invoice.buyerCountry)),
                if (invoice.buyerVatNumber != null &&
                    invoice.buyerVatNumber!.isNotEmpty)
                  pw.Text('VAT: ${_sanitizePdfText(invoice.buyerVatNumber)}'),
                if (invoice.buyerEmail != null)
                  pw.Text('Email: ${_sanitizePdfText(invoice.buyerEmail)}'),
                if (invoice.buyerPhone != null)
                  pw.Text('Phone: ${_sanitizePdfText(invoice.buyerPhone)}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable(
    Invoice invoice,
    List<InvoiceLine> lines, {
    required bool hasVat,
  }) {
    if (!hasVat) {
      // ===== Template SANS TVA =====
      final headers = [
        'Description',
        'Qty',
        'Unit price',
        'Total',
      ];

      final data = lines.map((line) {
        final total = line.totalInclTax; // = totalExcl quand pas de TVA
        return [
          _sanitizePdfText(line.description),
          line.quantity.toString(),
          formatMoney(line.unitPrice, invoice.currency),
          formatMoney(total, invoice.currency),
        ];
      }).toList();

      return pw.Table.fromTextArray(
        headers: headers,
        data: data,
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
        ),
        headerDecoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(width: 0.5),
          ),
        ),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
        },
        cellPadding: const pw.EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 2,
        ),
      );
    }

    // ===== Template AVEC TVA =====
    final headers = [
      'Description',
      'Qty',
      'Unit price',
      'Discount',
      'Tax %',
      'Total excl.',
      'Tax',
      'Total incl.',
    ];

    final data = lines.map((line) {
      return [
        _sanitizePdfText(line.description),
        line.quantity.toString(),
        formatMoney(line.unitPrice, invoice.currency),
        line.discount == 0 ? '-' : formatMoney(line.discount, invoice.currency),
        line.taxRate.toStringAsFixed(2),
        formatMoney(line.totalExclTax, invoice.currency),
        formatMoney(line.totalTax, invoice.currency),
        formatMoney(line.totalInclTax, invoice.currency),
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5),
        ),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(2),
        6: const pw.FlexColumnWidth(2),
        7: const pw.FlexColumnWidth(2),
      },
      cellPadding: const pw.EdgeInsets.symmetric(
        vertical: 4,
        horizontal: 2,
      ),
    );
  }

  double? _computeTotalAed(Invoice invoice, double? aedPerInvoiceCurrencyRate) {
    final cur = invoice.currency.trim().toUpperCase();
    final totalCurrent = invoice.totalInclTax.toDouble();

    if (cur == 'AED') return totalCurrent;
    if (aedPerInvoiceCurrencyRate == null || aedPerInvoiceCurrencyRate <= 0) {
      return null;
    }
    return totalCurrent * aedPerInvoiceCurrencyRate;
  }

  pw.Widget _buildTotals(
    Invoice invoice, {
    required bool hasVat,
    required bool showDisplayTotalInAed,
    double? aedPerInvoiceCurrencyRate,
  }) {
    final totalAed = showDisplayTotalInAed
        ? _computeTotalAed(invoice, aedPerInvoiceCurrencyRate)
        : null;

    if (!hasVat) {
      // ===== Bloc totaux SANS TVA =====
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 260,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _rowTotal(
                'Total',
                formatMoney(invoice.totalInclTax, invoice.currency),
                isBold: true,
              ),
              if (totalAed != null) ...[
                pw.SizedBox(height: 4),
                _rowTotal(
                  'Total (AED)',
                  formatMoney(totalAed, 'AED'),
                  isBold: true,
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ===== Bloc totaux AVEC TVA =====
    final vatLabel = _vatLabel(invoice);

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _rowTotal(
              'Subtotal (excl. tax)',
              formatMoney(invoice.totalExclTax, invoice.currency),
            ),
            _rowTotal(
              vatLabel,
              formatMoney(invoice.totalTax, invoice.currency),
            ),
            pw.Divider(),
            _rowTotal(
              'Total (incl. tax)',
              formatMoney(invoice.totalInclTax, invoice.currency),
              isBold: true,
            ),
            if (totalAed != null) ...[
              pw.SizedBox(height: 4),
              _rowTotal(
                'Total (AED)',
                formatMoney(totalAed, 'AED'),
                isBold: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Essaie de calculer un label du type "VAT 5 %"
  String _vatLabel(Invoice invoice) {
    final ex = invoice.totalExclTax;
    final t = invoice.totalTax;
    if (ex <= 0 || t <= 0) return 'VAT';
    final rate = (t / ex) * 100;
    if (rate > 0 && rate < 1000) {
      final rStr =
          rate % 1 == 0 ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1);
      return 'VAT $rStr %';
    }
    return 'VAT';
  }

  pw.Widget _rowTotal(String label, String value, {bool isBold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: isBold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
        ),
        pw.Text(
          value,
          style: isBold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
        ),
      ],
    );
  }

  pw.Widget _buildNotes(String paymentTerms, String? notes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Payment terms',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(_sanitizePdfText(paymentTerms)),
        if (notes != null && notes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Notes',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(_sanitizePdfText(notes)),
        ],
      ],
    );
  }

  pw.Widget _buildBankingInfo() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Banking information',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Account Holder Name : $_bankAccountHolder'),
          pw.Text('Bank Name : $_bankName'),
          pw.Text('Account Number : $_bankAccountNumber'),
          pw.Text('IBAN : $_bankIban'),
        ],
      ),
    );
  }
}
