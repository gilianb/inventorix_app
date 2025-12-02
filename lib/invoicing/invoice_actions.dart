import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'invoiceService.dart';
import 'invoice_pdf_builder.dart';
import 'models/invoice.dart';
import 'models/invoiceLine.dart';

class InvoiceActions {
  final SupabaseClient client;
  final InvoiceService invoiceService;
  final InvoicePdfBuilder pdfBuilder;

  InvoiceActions(this.client)
      : invoiceService = InvoiceService(client),
        pdfBuilder = InvoicePdfBuilder();

  /// High-level helper:
  /// 1. Generate a new invoice number (server-side, monotonic)
  /// 2. Create invoice & line in DB for a given item, using provided form values
  /// 3. Generate PDF
  /// 4. Upload to Supabase Storage
  /// 5. Link invoice + item.document_url
  Future<Invoice> createBillForItemAndGeneratePdf({
    required String orgId,
    required int itemId,
    required String currency,
    int? folderId,
    double taxRate = 0.0,
    DateTime? dueDate,

    // Seller
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer
    String? buyerName,
    String? buyerAddress,
    String? buyerCountry,
    String? buyerVatNumber,
    String? buyerTaxRegistration,
    String? buyerEmail,
    String? buyerPhone,

    // Other
    String? paymentTerms,
    String? notes,
  }) async {
    // 1. Get next invoice number from backend
    final invoiceNumber = await invoiceService.getNextInvoiceNumber(orgId);

    // 2. Create invoice + line with overrides
    final invoice = await invoiceService.createInvoiceForItem(
      orgId: orgId,
      itemId: itemId,
      invoiceNumber: invoiceNumber,
      currency: currency,
      folderId: folderId,
      taxRate: taxRate,
      dueDate: dueDate,
      sellerName: sellerName,
      sellerAddress: sellerAddress,
      sellerCountry: sellerCountry,
      sellerVatNumber: sellerVatNumber,
      sellerTaxRegistration: sellerTaxRegistration,
      sellerRegistrationNumber: sellerRegistrationNumber,
      buyerNameOverride: buyerName,
      buyerAddress: buyerAddress,
      buyerCountry: buyerCountry,
      buyerVatNumber: buyerVatNumber,
      buyerTaxRegistration: buyerTaxRegistration,
      buyerEmail: buyerEmail,
      buyerPhone: buyerPhone,
      paymentTerms: paymentTerms,
      notes: notes,
    );

    // 3. Fetch lines
    final List<InvoiceLine> lines =
        await invoiceService.getInvoiceLines(invoice.id);

    // 4. Generate PDF
    final Uint8List pdfBytes = await pdfBuilder.buildPdf(invoice, lines);

    // 5. Upload + link to invoice and item
    await invoiceService.uploadInvoicePdfAndLink(
      orgId: orgId,
      invoice: invoice,
      pdfBytes: pdfBytes,
      relatedItemId: itemId,
    );

    return invoice;
  }
}
