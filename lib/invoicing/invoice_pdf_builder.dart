import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models/invoice.dart';
import 'models/invoiceLine.dart';
import 'invoice_format.dart';

class InvoicePdfBuilder {
  Future<Uint8List> buildPdf(
    Invoice invoice,
    List<InvoiceLine> lines,
  ) async {
    final doc = pw.Document();

    const title = 'INVOICE';
    final paymentTerms =
        invoice.paymentTerms ?? 'Payment due within 7 days by bank transfer.';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(invoice, title),
          pw.SizedBox(height: 20),
          _buildSellerBuyer(invoice),
          pw.SizedBox(height: 20),
          _buildItemsTable(invoice, lines),
          pw.SizedBox(height: 20),
          _buildTotals(invoice),
          pw.SizedBox(height: 20),
          _buildNotes(paymentTerms, invoice.notes),
        ],
      ),
    );

    return doc.save();
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
            pw.Text('Invoice No: ${invoice.invoiceNumber}'),
            pw.Text('Issue date: ${formatDate(invoice.issueDate)}'),
            if (invoice.dueDate != null)
              pw.Text('Due date: ${formatDate(invoice.dueDate!)}'),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              invoice.sellerName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (invoice.sellerAddress != null) pw.Text(invoice.sellerAddress!),
            if (invoice.sellerCountry != null) pw.Text(invoice.sellerCountry!),
            if (invoice.sellerVatNumber != null &&
                invoice.sellerVatNumber!.isNotEmpty)
              pw.Text('VAT: ${invoice.sellerVatNumber}'),
            if (invoice.sellerTaxRegistration != null &&
                invoice.sellerTaxRegistration!.isNotEmpty)
              pw.Text('Tax Reg: ${invoice.sellerTaxRegistration}'),
            if (invoice.sellerRegistrationNumber != null &&
                invoice.sellerRegistrationNumber!.isNotEmpty)
              pw.Text('Reg. No: ${invoice.sellerRegistrationNumber}'),
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
                pw.Text(invoice.sellerName),
                if (invoice.sellerAddress != null)
                  pw.Text(invoice.sellerAddress!),
                if (invoice.sellerCountry != null)
                  pw.Text(invoice.sellerCountry!),
                if (invoice.sellerVatNumber != null &&
                    invoice.sellerVatNumber!.isNotEmpty)
                  pw.Text('VAT: ${invoice.sellerVatNumber}'),
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
                pw.Text(invoice.buyerName),
                if (invoice.buyerAddress != null)
                  pw.Text(invoice.buyerAddress!),
                if (invoice.buyerCountry != null)
                  pw.Text(invoice.buyerCountry!),
                if (invoice.buyerVatNumber != null &&
                    invoice.buyerVatNumber!.isNotEmpty)
                  pw.Text('VAT: ${invoice.buyerVatNumber}'),
                if (invoice.buyerEmail != null)
                  pw.Text('Email: ${invoice.buyerEmail}'),
                if (invoice.buyerPhone != null)
                  pw.Text('Phone: ${invoice.buyerPhone}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable(Invoice invoice, List<InvoiceLine> lines) {
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
        line.description,
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
      // ❌ on ne met plus cellDecoration (source de l'erreur)
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
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    );
  }

  pw.Widget _buildTotals(Invoice invoice) {
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
              'Tax total',
              formatMoney(invoice.totalTax, invoice.currency),
            ),
            pw.Divider(),
            _rowTotal(
              'Total (incl. tax)',
              formatMoney(invoice.totalInclTax, invoice.currency),
              isBold: true,
            ),
          ],
        ),
      ),
    );
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
        pw.Text(paymentTerms),
        if (notes != null && notes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Notes',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(notes),
        ],
      ],
    );
  }
}
