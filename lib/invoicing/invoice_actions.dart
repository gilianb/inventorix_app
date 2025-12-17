// lib/invoicing/invoiceActions.dart
// ignore_for_file: unintended_html_in_doc_comment

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'invoice_service.dart';
import 'invoice_pdf_builder.dart';
import 'models/invoice.dart';
import 'models/invoice_line.dart';

class InvoiceActions {
  final SupabaseClient client;
  final InvoiceService invoiceService;
  final InvoicePdfBuilder pdfBuilder;

  InvoiceActions(this.client)
      : invoiceService = InvoiceService(client),
        pdfBuilder = InvoicePdfBuilder();

  // Small helper to normalize segments used in folder names
  String _normalizeSegment(String? raw) {
    if (raw == null) return 'Unknown';
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Unknown';
    final noSlash = trimmed.replaceAll('/', ' ');
    return noSlash.replaceAll(RegExp(r'\s+'), ' ');
  }

  // ---------------------------------------------------------------------------
  // SALES: create invoice for ONE item + PDF + Storage + auto-folder
  // ---------------------------------------------------------------------------

  /// High-level helper (SALES invoice for ONE item):
  /// 1. Generate a new invoice number (server-side, monotonic)
  /// 2. Create invoice & line in DB for a given item
  ///    ✅ Invoice currency is derived from item.sale_currency (fallback item.currency)
  /// 3. Generate PDF
  /// 4. Upload to Supabase Storage
  /// 5. Link invoice + item.document_url
  /// 6. Auto-assign folder: "<Seller>/sells/<Buyer>"
  Future<Invoice> createBillForItemAndGeneratePdf({
    required String orgId,
    required int itemId,
    required String
        currency, // kept for compat; service uses it only as fallback
    double taxRate = 0.0,
    DateTime? dueDate,

    // Seller
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer (end customer, from buyer_infos)
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

    // 2. Create invoice + line
    final invoice = await invoiceService.createInvoiceForItem(
      orgId: orgId,
      itemId: itemId,
      invoiceNumber: invoiceNumber,
      currency: currency, // fallback only
      folderId: null,
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

    // 6. Auto-folder: "<Seller>/sells/<Buyer>"
    try {
      final sellerSeg = _normalizeSegment(invoice.sellerName);
      final buyerSeg = _normalizeSegment(invoice.buyerName);

      final folderName = '$sellerSeg/sells/$buyerSeg';

      final folder = await invoiceService.getOrCreateFolder(
        orgId: orgId,
        name: folderName,
      );

      await invoiceService.updateInvoiceFolder(
        invoiceId: invoice.id,
        folderId: folder.id,
      );
    } catch (_) {
      // best-effort
    }

    return invoice;
  }

  // ---------------------------------------------------------------------------
  // SALES: create invoice for MULTIPLE items + PDF + Storage + auto-folder
  // ---------------------------------------------------------------------------

  /// High-level helper (SALES invoice for MULTIPLE items):
  /// 1. Generate new invoice number
  /// 2. Create invoice & grouped lines in DB for the given items
  ///    ✅ Invoice currency is derived from items.sale_currency (must be consistent)
  /// 3. Generate PDF
  /// 4. Upload to Storage & attach to ALL items
  /// 5. Auto-folder "<Seller>/sells/<Buyer>"
  Future<Invoice> createBillForItemsAndGeneratePdf({
    required String orgId,
    required List<int> itemIds,
    required String
        currency, // kept for compat; service uses it only as fallback
    double taxRate = 0.0,
    DateTime? dueDate,

    // Seller
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer (end customer, from buyer_infos)
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
    if (itemIds.isEmpty) {
      throw ArgumentError('Cannot create multi-item invoice with no items.');
    }

    // 1. Get next invoice number
    final invoiceNumber = await invoiceService.getNextInvoiceNumber(orgId);

    // 2. Create invoice + all lines
    final invoice = await invoiceService.createInvoiceForItems(
      orgId: orgId,
      itemIds: itemIds,
      invoiceNumber: invoiceNumber,
      currency: currency, // fallback only
      folderId: null,
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

    // 5. Upload + link to invoice and ALL items
    await invoiceService.uploadInvoicePdfAndLinkToItems(
      orgId: orgId,
      invoice: invoice,
      pdfBytes: pdfBytes,
      relatedItemIds: itemIds,
    );

    // 6. Auto-folder: "<Seller>/sells/<Buyer>"
    try {
      final sellerSeg = _normalizeSegment(invoice.sellerName);
      final buyerSeg = _normalizeSegment(invoice.buyerName);

      final folderName = '$sellerSeg/sells/$buyerSeg';

      final folder = await invoiceService.getOrCreateFolder(
        orgId: orgId,
        name: folderName,
      );

      await invoiceService.updateInvoiceFolder(
        invoiceId: invoice.id,
        folderId: folder.id,
      );
    } catch (_) {
      // best-effort
    }

    return invoice;
  }

  // ---------------------------------------------------------------------------
  // PURCHASE: attach external invoice document + DB record + auto-folder
  // ---------------------------------------------------------------------------

  /// High-level helper (PURCHASE invoice, external document):
  ///
  /// 1. Upload supplier invoice file to Storage (`invoices` bucket)
  /// 2. Create PURCHASE invoice row linked to item
  /// 3. Auto-assign folder: "<BuyerCompany>/purchase/<Supplier>"
  ///
  /// [purchaseSource] is optional (platform / source, e.g. "Cardmarket").
  Future<Invoice> attachPurchaseInvoiceForItem({
    required String orgId,
    required int itemId,
    required String currency,
    required String supplierName,
    required String externalInvoiceNumber,
    required String fileName,
    required Uint8List fileBytes,
    String? purchaseSource,
    String? notes,
  }) async {
    final safeSupplier = _normalizeSegment(supplierName);
    final now = DateTime.now();
    final year = now.year.toString();

    // Clean file name for storage
    final cleanedFileName = fileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );

    // Path in Storage: <orgId>/purchases/<year>/<Supplier>/<timestamp>_<filename>
    final storageFileName = '${now.microsecondsSinceEpoch}_$cleanedFileName';
    final path = '$orgId/purchases/$year/$safeSupplier/$storageFileName';

    // 1. Upload supplier file
    await client.storage.from('invoices').uploadBinary(
          path,
          fileBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final documentUrl = 'invoices/$path';

    // (Optional) try to infer platform / source if not provided
    String source = purchaseSource?.trim() ?? '';
    String? buyerCompany;

    if (source.isEmpty) {
      try {
        final itemRow = await client
            .from('item')
            .select('payment_type, channel_id, buyer_company')
            .eq('id', itemId)
            .maybeSingle();

        source = (itemRow?['payment_type']?.toString() ?? '').trim();
        buyerCompany = itemRow?['buyer_company']?.toString();

        if (source.isEmpty && itemRow?['channel_id'] != null) {
          final ch = await client
              .from('channel')
              .select('label')
              .eq('id', itemRow!['channel_id'])
              .maybeSingle();
          source = (ch?['label']?.toString() ?? '').trim();
        }
      } catch (_) {
        // best-effort only
      }
    }
    if (source.isEmpty) {
      source = 'General';
    }

    // 2. Create PURCHASE invoice (no folderId yet)
    final invoice = await invoiceService.createPurchaseInvoiceForItem(
      orgId: orgId,
      itemId: itemId,
      supplierName: supplierName,
      invoiceNumber: externalInvoiceNumber,
      currency: currency,
      documentUrl: documentUrl,
      folderId: null,
      notes: notes,
    );

    // 3. Auto-folder: "<BuyerCompany>/purchase/<Supplier>"
    try {
      String buyerRoot = (buyerCompany ?? '').trim();
      if (buyerRoot.isEmpty) {
        buyerRoot = 'CardShouker';
      }

      final buyerSeg = _normalizeSegment(buyerRoot);
      final supplierSeg = _normalizeSegment(invoice.sellerName);

      final folderName = '$buyerSeg/purchase/$supplierSeg';

      final folder = await invoiceService.getOrCreateFolder(
        orgId: orgId,
        name: folderName,
      );

      await invoiceService.updateInvoiceFolder(
        invoiceId: invoice.id,
        folderId: folder.id,
      );
    } catch (_) {
      // best-effort only
    }

    return invoice;
  }

  String _contentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  /// External invoice/document (expense) not linked to any item:
  /// 1) upload file to Storage
  /// 2) create PURCHASE invoice with related_item_id = null
  Future<Invoice> attachExternalInvoiceDocument({
    required String orgId,
    required String currency,
    required String supplierName,
    required String externalInvoiceNumber,
    required DateTime issueDate,
    required double totalAmount,
    required String fileName,
    required Uint8List fileBytes,
    int? folderId,
    String? notes,
  }) async {
    final safeSupplier = _normalizeSegment(supplierName);
    final now = DateTime.now();
    final year = now.year.toString();

    final cleanedFileName = fileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );

    final storageFileName = '${now.microsecondsSinceEpoch}_$cleanedFileName';

    // Storage path: <orgId>/external/<year>/<Supplier>/<timestamp_filename>
    final path = '$orgId/external/$year/$safeSupplier/$storageFileName';

    await client.storage.from('invoices').uploadBinary(
          path,
          fileBytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForFileName(cleanedFileName),
          ),
        );

    final documentUrl = 'invoices/$path';

    final invoice = await invoiceService.createExternalPurchaseInvoice(
      orgId: orgId,
      supplierName: supplierName,
      invoiceNumber: externalInvoiceNumber,
      currency: currency,
      documentUrl: documentUrl,
      issueDate: issueDate,
      totalAmount: totalAmount,
      folderId: folderId,
      notes: notes,
    );

    return invoice;
  }
}
