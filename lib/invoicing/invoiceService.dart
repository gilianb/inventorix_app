// lib/invoicing/invoiceService.dart

// ignore_for_file: unnecessary_cast

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/enums.dart';
import 'models/invoice.dart';
import 'models/invoiceFolder.dart';
import 'models/invoiceLine.dart';

class InvoiceService {
  final SupabaseClient client;

  InvoiceService(this.client);

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  /// Create a new folder for invoices (low-level, no dedup).
  Future<InvoiceFolder> createFolder({
    required String orgId,
    required String name,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Folder name cannot be empty.');
    }

    final data = await client
        .from('invoice_folder')
        .insert({'org_id': orgId, 'name': normalized})
        .select()
        .single();

    return InvoiceFolder.fromMap(data as Map<String, dynamic>);
  }

  /// Get an existing folder by (org_id, name) or create it atomically.
  Future<InvoiceFolder> getOrCreateFolder({
    required String orgId,
    required String name,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Folder name cannot be empty.');
    }

    // 1) Try to find existing
    try {
      final existing = await client
          .from('invoice_folder')
          .select()
          .eq('org_id', orgId)
          .eq('name', normalized)
          .maybeSingle();

      if (existing != null) {
        return InvoiceFolder.fromMap(existing as Map<String, dynamic>);
      }
    } catch (_) {
      // ignore, will try insert
    }

    // 2) Try to insert, handle possible race with unique constraint
    try {
      final inserted = await client
          .from('invoice_folder')
          .insert({'org_id': orgId, 'name': normalized})
          .select()
          .single();

      return InvoiceFolder.fromMap(inserted as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // unique_violation or similar => re-select
      if (e.code == '23505') {
        final existing = await client
            .from('invoice_folder')
            .select()
            .eq('org_id', orgId)
            .eq('name', normalized)
            .maybeSingle();

        if (existing != null) {
          return InvoiceFolder.fromMap(existing as Map<String, dynamic>);
        }
      }
      rethrow;
    }
  }

  /// Return all folders for an organization
  Future<List<InvoiceFolder>> listFolders(String orgId) async {
    // Simple select: we rely on InvoiceFolder.fromMap to handle fields.
    final rows = await client
        .from('invoice_folder')
        .select()
        .eq('org_id', orgId)
        .order('name', ascending: true);

    return (rows as List)
        .map((row) => InvoiceFolder.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Update the folder of an invoice (or clear it with folderId = null).
  Future<void> updateInvoiceFolder({
    required int invoiceId,
    int? folderId,
  }) async {
    await client
        .from('invoice')
        .update({'folder_id': folderId}).eq('id', invoiceId);
  }

  // ---------------------------------------------------------------------------
  // Invoices & lines
  // ---------------------------------------------------------------------------

  /// Return invoices for an organization, optionally filtered by folder
  Future<List<Invoice>> listInvoices({
    required String orgId,
    int? folderId,
  }) async {
    final query = client.from('invoice').select().eq('org_id', orgId);

    if (folderId != null) {
      query.eq('folder_id', folderId);
    }

    query.order('issue_date', ascending: false).order('id', ascending: false);

    final rows = await query;

    return (rows as List)
        .map((row) => Invoice.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Return all lines of a given invoice
  Future<List<InvoiceLine>> getInvoiceLines(int invoiceId) async {
    final rows = await client
        .from('invoice_line')
        .select()
        .eq('invoice_id', invoiceId)
        .order('line_order');

    return (rows as List)
        .map((row) => InvoiceLine.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Insert a new invoice (low level)
  Future<Invoice> createInvoice(Invoice invoice) async {
    final data = await client
        .from('invoice')
        .insert(invoice.toInsertMap())
        .select()
        .single();

    return Invoice.fromMap(data as Map<String, dynamic>);
  }

  /// Insert a new invoice line (low level)
  Future<InvoiceLine> createInvoiceLine(InvoiceLine line) async {
    final data = await client
        .from('invoice_line')
        .insert(line.toInsertMap())
        .select()
        .single();

    return InvoiceLine.fromMap(data);
  }

  /// Mark an invoice as paid
  Future<void> markInvoicePaid(int invoiceId) async {
    await client.from('invoice').update({'status': 'paid'}).eq('id', invoiceId);
  }

  /// Get the next invoice number for an organization (monotonic, year-based)
  ///
  /// Uses the RPC `app_next_invoice_number(p_org_id uuid)`.
  Future<String> getNextInvoiceNumber(String orgId) async {
    final res = await client.rpc(
      'app_next_invoice_number',
      params: {'p_org_id': orgId},
    );

    if (res == null) {
      throw Exception('Failed to generate invoice number (null result).');
    }

    return res.toString();
  }

  // ---------------------------------------------------------------------------
  // SALES invoice (generated by the app)
  // ---------------------------------------------------------------------------

  /// Create a SALES invoice for a specific item (use-case: "Create invoice" button)
  ///
  /// All seller / buyer fields can be overridden from the UI.
  Future<Invoice> createInvoiceForItem({
    required String orgId,
    required int itemId,
    required String invoiceNumber,
    required String currency,
    int? folderId,
    double taxRate = 0.0,
    DateTime? dueDate,

    // Seller overrides
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer overrides
    String? buyerNameOverride,
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
    // 1. Fetch the item and product name
    final itemRow = await client
        .from('item')
        .select('*, product:product(name)')
        .eq('id', itemId)
        .single();

    final productName =
        (itemRow['product'] as Map)['name']?.toString() ?? 'Item';

    // Prefer sale_price if present, otherwise fall back to unit_cost
    final unitBase = (itemRow['sale_price'] ?? itemRow['unit_cost'] ?? 0);
    final unitPrice = (unitBase as num).toDouble();

    // Default buyer name from item, overridable by buyerNameOverride
    final itemBuyerInfos = itemRow['buyer_infos'] as String?;
    final itemBuyerCompany = itemRow['buyer_company'] as String?;
    final computedBuyerName = itemBuyerCompany ?? itemBuyerInfos ?? 'Customer';

    final buyerName =
        (buyerNameOverride != null && buyerNameOverride.trim().isNotEmpty)
            ? buyerNameOverride.trim()
            : computedBuyerName;

    // 2. Compute totals (assuming unitPrice is tax-exclusive)
    final totalExcl = unitPrice;
    final totalTax = totalExcl * taxRate / 100;
    final totalIncl = totalExcl + totalTax;

    // 3. Build invoice object
    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.sale,
      status: InvoiceStatus.sent,
      invoiceNumber: invoiceNumber,
      issueDate: DateTime.now(),
      dueDate: dueDate,
      currency: currency,

      // Seller
      sellerName: sellerName?.trim().isNotEmpty == true
          ? sellerName!.trim()
          : 'Your Company Name',
      sellerAddress: sellerAddress,
      sellerCountry: sellerCountry,
      sellerVatNumber: sellerVatNumber,
      sellerTaxRegistration: sellerTaxRegistration,
      sellerRegistrationNumber: sellerRegistrationNumber,

      // Buyer
      buyerName: buyerName,
      buyerAddress: buyerAddress,
      buyerCountry: buyerCountry,
      buyerVatNumber: buyerVatNumber,
      buyerTaxRegistration: buyerTaxRegistration,
      buyerEmail: buyerEmail,
      buyerPhone: buyerPhone,

      // Totals
      totalExclTax: totalExcl,
      totalTax: totalTax,
      totalInclTax: totalIncl,

      notes: notes,
      paymentTerms:
          paymentTerms ?? 'Payment due within 7 days by bank transfer.',
      documentUrl: null,
      relatedItemId: itemId,
      relatedOrderId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: null,
    );

    final createdInvoice = await createInvoice(invoice);

    // 4. Create a single invoice line for this item
    final line = InvoiceLine(
      id: 0,
      invoiceId: createdInvoice.id,
      itemId: itemId,
      description: productName,
      quantity: 1,
      unitPrice: unitPrice,
      discount: 0,
      taxRate: taxRate,
      totalExclTax: totalExcl,
      totalTax: totalTax,
      totalInclTax: totalIncl,
      lineOrder: 0,
    );

    await createInvoiceLine(line);

    return createdInvoice;
  }

  // ---------------------------------------------------------------------------
  // PURCHASE invoice (external document attached to an item)
  // ---------------------------------------------------------------------------

  /// Create a PURCHASE invoice for an item, using an **external** document URL.
  ///
  Future<Invoice> createPurchaseInvoiceForItem({
    required String orgId,
    required int itemId,
    required String supplierName,
    required String invoiceNumber, // supplier invoice ref
    required String currency,
    required String documentUrl,
    int? folderId,
    DateTime? issueDate,
    String? notes,
  }) async {
    // 1. Fetch item (for costs & default issue date)
    final itemRow = await client
        .from('item')
        .select(
          'org_id, supplier_name, purchase_date, '
          'unit_cost, unit_fees, shipping_fees, commission_fees, grading_fees',
        )
        .eq('id', itemId)
        .single();

    final num unitCost = (itemRow['unit_cost'] as num?) ?? 0;
    final num unitFees = (itemRow['unit_fees'] as num?) ?? 0;
    final num shippingFees = (itemRow['shipping_fees'] as num?) ?? 0;
    final num commissionFees = (itemRow['commission_fees'] as num?) ?? 0;
    final num gradingFees = (itemRow['grading_fees'] as num?) ?? 0;

    final totalExcl =
        (unitCost + unitFees + shippingFees + commissionFees + gradingFees)
            .toDouble();
    final totalTax = 0.0; // no tax breakdown handled for purchase invoices now
    final totalIncl = totalExcl;

    // Issue date: use item.purchase_date if available
    DateTime effectiveIssueDate = DateTime.now();
    final purchaseDateRaw = itemRow['purchase_date'];
    if (purchaseDateRaw != null) {
      try {
        effectiveIssueDate = DateTime.parse(purchaseDateRaw.toString());
      } catch (_) {
        // ignore, keep now()
      }
    }

    // Buyer = organization name
    String buyerName = 'Inventory';
    try {
      final orgRow = await client
          .from('organization')
          .select('name')
          .eq('id', orgId)
          .maybeSingle();
      if (orgRow != null &&
          orgRow['name'] != null &&
          orgRow['name'].toString().trim().isNotEmpty) {
        buyerName = orgRow['name'].toString().trim();
      }
    } catch (_) {
      // ignore, keep default
    }

    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.purchase,
      status: InvoiceStatus.paid, // archived supplier invoice
      invoiceNumber: invoiceNumber,
      issueDate: issueDate ?? effectiveIssueDate,
      dueDate: null,
      currency: currency,

      // Seller (supplier)
      sellerName: supplierName,
      sellerAddress: null,
      sellerCountry: null,
      sellerVatNumber: null,
      sellerTaxRegistration: null,
      sellerRegistrationNumber: null,

      // Buyer (you / your org)
      buyerName: buyerName,
      buyerAddress: null,
      buyerCountry: null,
      buyerVatNumber: null,
      buyerTaxRegistration: null,
      buyerEmail: null,
      buyerPhone: null,

      totalExclTax: totalExcl,
      totalTax: totalTax,
      totalInclTax: totalIncl,

      notes: notes,
      paymentTerms: null,
      documentUrl: documentUrl,
      relatedItemId: itemId,
      relatedOrderId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: null,
    );

    // ⚠ On force la présence de document_url dans la map d'insert
    final insertMap = invoice.toInsertMap();
    insertMap['document_url'] = documentUrl;

    final data =
        await client.from('invoice').insert(insertMap).select().single();

    // ⚠ On reflète aussi sur l'item pour que la page details voie "un document disponible"
    await client
        .from('item')
        .update({'document_url': documentUrl}).eq('id', itemId);

    return Invoice.fromMap(data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Storage utils (mainly for SALES PDFs)
  // ---------------------------------------------------------------------------

  /// Upload the PDF to Supabase Storage and link it to invoice + item
  ///
  /// Typically used for SALES invoices generated by the app.
  Future<void> uploadInvoicePdfAndLink({
    required String orgId,
    required Invoice invoice,
    required Uint8List pdfBytes,
    int? relatedItemId,
  }) async {
    final year = invoice.issueDate.year.toString();
    final path = '$orgId/$year/${invoice.invoiceNumber}/invoice.pdf';

    await client.storage.from('invoices').uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final documentPath = 'invoices/$path';

    // Update invoice
    await client
        .from('invoice')
        .update({'document_url': documentPath}).eq('id', invoice.id);

    // Update related item (use same document_url)
    if (relatedItemId != null) {
      await client
          .from('item')
          .update({'document_url': documentPath}).eq('id', relatedItemId);
    }
  }

  /// Delete invoice + lines (+ pdf, optional) and clean related item.document_url
  Future<void> deleteInvoice(
    Invoice invoice, {
    bool deletePdf = true,
  }) async {
    // Delete lines
    await client.from('invoice_line').delete().eq('invoice_id', invoice.id);

    // Clear item.document_url if it matches this invoice
    if (invoice.relatedItemId != null && invoice.documentUrl != null) {
      await client
          .from('item')
          .update({'document_url': null})
          .eq('id', invoice.relatedItemId as Object)
          .eq('document_url', invoice.documentUrl as Object);
    }

    // Delete invoice row
    await client.from('invoice').delete().eq('id', invoice.id);

    // Delete PDF from storage (requires DELETE policy on `invoices` bucket)
    if (deletePdf && invoice.documentUrl != null) {
      final pathInBucket = invoice.documentUrl!.replaceFirst('invoices/', '');
      await client.storage.from('invoices').remove([pathInBucket]);
    }
  }
}
