// lib/invoicing/invoiceService.dart
// ignore_for_file: unnecessary_cast

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/enums.dart';
import 'models/invoice.dart';
import 'models/invoice_folder.dart';
import 'models/invoice_line.dart';

/// Petit helper d'arrondi à 2 décimales (type facture)
double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Internal helper to group items into one invoice line with quantity xN.
/// Ici `unitPrice` est **HT** (excl. tax).
class _InvoiceLineGroupData {
  final String description;
  final double unitPrice; // HT
  final int itemIdRepresentative;
  int quantity;

  _InvoiceLineGroupData({
    required this.description,
    required this.unitPrice,
    required this.itemIdRepresentative,
    // ignore: unused_element_parameter
    this.quantity = 0,
  });
}

class InvoiceService {
  final SupabaseClient client;

  InvoiceService(this.client);

  // -------------------- Helpers --------------------

  /// Devise de vente: priorité sale_currency, fallback currency, fallback fallbackCurrency, sinon USD.
  String _saleCurrencyOfRow(Map<String, dynamic> r,
      {String? fallbackCurrency}) {
    final sc = (r['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc.toUpperCase();

    final c = (r['currency'] ?? '').toString().trim();
    if (c.isNotEmpty) return c.toUpperCase();

    final fb = (fallbackCurrency ?? '').trim();
    if (fb.isNotEmpty) return fb.toUpperCase();

    return 'USD';
  }

  /// Safe parse date from Supabase row field.
  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

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
  // SALES invoice (generated by the app) – SINGLE ITEM
  // ---------------------------------------------------------------------------

  /// Create a SALES invoice for a specific item (use-case: "Create invoice" button)
  ///
  /// ✅ Currency is derived from item.sale_currency (fallback item.currency).
  /// Buyer = end customer from `buyer_infos` (NOT buyer_company).
  Future<Invoice> createInvoiceForItem({
    required String orgId,
    required int itemId,
    required String invoiceNumber,
    required String currency, // kept for backward-compat; used only as fallback
    int? folderId,
    double taxRate = 0.0,
    DateTime? issueDateOverride,
    DateTime? dueDate,

    // Seller overrides
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer overrides (end customer)
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
    // 1. Fetch the item and product name (+ sale_currency + sale_date)
    final itemRow = await client
        .from('item')
        .select(
          '*, sale_date, sale_currency, currency, buyer_infos, sale_price, unit_cost, product:product(name)',
        )
        .eq('id', itemId)
        .single();

    final productName =
        (itemRow['product'] as Map)['name']?.toString() ?? 'Item';

    // ✅ Issue date: override (si fourni), sinon sale_date, sinon date du jour
    final DateTime issueDate =
        issueDateOverride ?? _parseDate(itemRow['sale_date']) ?? DateTime.now();

    // ✅ Invoice currency = sale_currency (fallback currency, fallback param)
    final String invoiceCurrency = _saleCurrencyOfRow(
        Map<String, dynamic>.from(itemRow as Map),
        fallbackCurrency: currency);

    // ---------- LOGIQUE PRIX / TVA ----------
    // sale_price = TTC quand taxRate > 0
    final num? salePriceRaw = itemRow['sale_price'] as num?;
    final num? unitCostRaw = itemRow['unit_cost'] as num?;

    double unitPriceIncl; // TTC
    double unitPriceExcl; // HT

    if (taxRate > 0 && salePriceRaw != null) {
      // sale_price est TTC -> on en déduit l'HT
      unitPriceIncl = salePriceRaw.toDouble();
      unitPriceExcl = _round2(unitPriceIncl / (1 + taxRate / 100.0));
    } else {
      // Pas de TVA ou pas de sale_price -> on considère la base comme HT
      final base = (salePriceRaw ?? unitCostRaw ?? 0) as num;
      unitPriceExcl = _round2(base.toDouble());
      unitPriceIncl = (taxRate > 0)
          ? _round2(unitPriceExcl * (1 + taxRate / 100.0))
          : unitPriceExcl;
    }

    // Totaux pour 1 item
    final double totalExcl = unitPriceExcl;
    final double totalIncl = (taxRate > 0 && salePriceRaw != null)
        ? unitPriceIncl
        : _round2(unitPriceExcl * (1 + taxRate / 100.0));
    final double totalTax = _round2(totalIncl - totalExcl);
    // ---------- FIN LOGIQUE PRIX / TVA ----------

    // Default buyer name from item: use buyer_infos ONLY (end customer)
    final itemBuyerInfos = (itemRow['buyer_infos'] as String?)?.trim();
    final computedBuyerName =
        (itemBuyerInfos != null && itemBuyerInfos.isNotEmpty)
            ? itemBuyerInfos
            : 'Customer';

    final buyerName =
        (buyerNameOverride != null && buyerNameOverride.trim().isNotEmpty)
            ? buyerNameOverride.trim()
            : computedBuyerName;

    // 3. Build invoice object
    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.sale,
      status: InvoiceStatus.sent,
      invoiceNumber: invoiceNumber,
      issueDate: issueDate, // ✅
      dueDate: dueDate,
      currency: invoiceCurrency,

      // Seller
      sellerName: sellerName?.trim().isNotEmpty == true
          ? sellerName!.trim()
          : 'Your Company Name',
      sellerAddress: sellerAddress,
      sellerCountry: sellerCountry,
      sellerVatNumber: sellerVatNumber,
      sellerTaxRegistration: sellerTaxRegistration,
      sellerRegistrationNumber: sellerRegistrationNumber,

      // Buyer (end customer)
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
      unitPrice: unitPriceExcl, // HT sur la ligne
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
  // SALES invoice – MULTIPLE ITEMS
  // ---------------------------------------------------------------------------

  /// Create a SALES invoice for multiple items.
  ///
  /// ✅ All items must share the same SALE currency (sale_currency fallback currency).
  /// Buyer = end customer from `buyer_infos`.
  /// Lines are grouped by product name & unit TTC price.
  Future<Invoice> createInvoiceForItems({
    required String orgId,
    required List<int> itemIds,
    required String invoiceNumber,
    required String currency, // kept for backward-compat; used only as fallback
    int? folderId,
    double taxRate = 0.0,
    DateTime? issueDateOverride,
    DateTime? dueDate,

    // Seller overrides
    String? sellerName,
    String? sellerAddress,
    String? sellerCountry,
    String? sellerVatNumber,
    String? sellerTaxRegistration,
    String? sellerRegistrationNumber,

    // Buyer overrides (end customer)
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
    if (itemIds.isEmpty) {
      throw ArgumentError('itemIds cannot be empty for multi-item invoice.');
    }

    // 1. Fetch all items + product names (+ sale_currency + sale_date)
    final rows = await client
        .from('item')
        .select(
          'id, sale_date, sale_price, sale_currency, unit_cost, currency, buyer_infos, product:product(name)',
        )
        .inFilter('id', itemIds);

    if ((rows as List).isEmpty) {
      throw Exception('No items found for ids: $itemIds');
    }

    final items = (rows as List)
        .map<Map<String, dynamic>>(
          (e) => Map<String, dynamic>.from(e as Map),
        )
        .toList();

    // ✅ Issue date (multi):
    // - override (si fourni)
    // - sinon la sale_date la plus récente parmi les items
    // - sinon date du jour
    final parsedSaleDates = items
        .map((r) => _parseDate(r['sale_date']))
        .whereType<DateTime>()
        .toList();

    final DateTime issueDate;
    if (issueDateOverride != null) {
      issueDate = issueDateOverride;
    } else if (parsedSaleDates.isEmpty) {
      issueDate = DateTime.now();
    } else {
      parsedSaleDates.sort((a, b) => a.compareTo(b));
      issueDate = parsedSaleDates.last;
    }

    String computeBuyerName(Map<String, dynamic> r) {
      final itemBuyerInfos = (r['buyer_infos'] as String?)?.trim();
      return (itemBuyerInfos != null && itemBuyerInfos.isNotEmpty)
          ? itemBuyerInfos
          : 'Customer';
    }

    final firstItem = items.first;
    final defaultBuyerName = computeBuyerName(firstItem);

    final buyerName =
        (buyerNameOverride != null && buyerNameOverride.trim().isNotEmpty)
            ? buyerNameOverride.trim()
            : defaultBuyerName;

    // ✅ Consistency check: SALE currency (sale_currency fallback currency)
    final String firstSaleCurrency =
        _saleCurrencyOfRow(firstItem, fallbackCurrency: currency);

    for (final r in items) {
      final cur = _saleCurrencyOfRow(r, fallbackCurrency: currency);
      if (cur != firstSaleCurrency) {
        throw Exception(
          'All selected items must share the same SALE currency. Found both $firstSaleCurrency and $cur.',
        );
      }
    }

    // 2. Build base invoice (totals set to 0 for now)
    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.sale,
      status: InvoiceStatus.sent,
      invoiceNumber: invoiceNumber,
      issueDate: issueDate, // ✅
      dueDate: dueDate,
      currency: firstSaleCurrency,

      // Seller
      sellerName: sellerName?.trim().isNotEmpty == true
          ? sellerName!.trim()
          : 'Your Company Name',
      sellerAddress: sellerAddress,
      sellerCountry: sellerCountry,
      sellerVatNumber: sellerVatNumber,
      sellerTaxRegistration: sellerTaxRegistration,
      sellerRegistrationNumber: sellerRegistrationNumber,

      // Buyer (end customer)
      buyerName: buyerName,
      buyerAddress: buyerAddress,
      buyerCountry: buyerCountry,
      buyerVatNumber: buyerVatNumber,
      buyerTaxRegistration: buyerTaxRegistration,
      buyerEmail: buyerEmail,
      buyerPhone: buyerPhone,

      // Totals (computed after creating lines)
      totalExclTax: 0,
      totalTax: 0,
      totalInclTax: 0,

      notes: notes,
      paymentTerms:
          paymentTerms ?? 'Payment due within 7 days by bank transfer.',
      documentUrl: null,
      relatedItemId: null,
      relatedOrderId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: null,
    );

    final createdInvoice = await createInvoice(invoice);

    // 3. Group items (same product + même PRIX TTC) et créer les lignes
    final Map<String, _InvoiceLineGroupData> grouped = {};

    for (final r in items) {
      final int itemId = (r['id'] as num).toInt();

      final productRaw = r['product'];
      final String productName;
      if (productRaw is Map && productRaw['name'] != null) {
        productName = productRaw['name'].toString();
      } else {
        productName = 'Item';
      }

      // ---------- LOGIQUE PRIX / TVA PAR ITEM ----------
      final num? salePriceRaw = r['sale_price'] as num?;
      final num? unitCostRaw = r['unit_cost'] as num?;

      double unitPriceIncl; // TTC
      double unitPriceExcl; // HT

      if (taxRate > 0 && salePriceRaw != null) {
        unitPriceIncl = salePriceRaw.toDouble();
        unitPriceExcl = _round2(unitPriceIncl / (1 + taxRate / 100.0));
      } else {
        final base = (salePriceRaw ?? unitCostRaw ?? 0) as num;
        unitPriceExcl = _round2(base.toDouble());
        unitPriceIncl = (taxRate > 0)
            ? _round2(unitPriceExcl * (1 + taxRate / 100.0))
            : unitPriceExcl;
      }
      // ---------- FIN LOGIQUE PRIX / TVA ----------

      // Clé de regroupement = produit + PRIX TTC
      final key = '$productName|$unitPriceIncl';

      grouped
          .putIfAbsent(
            key,
            () => _InvoiceLineGroupData(
              description: productName,
              unitPrice: unitPriceExcl, // on stocke l'HT dans le groupe
              itemIdRepresentative: itemId,
            ),
          )
          .quantity++;
    }

    double totalExcl = 0.0;
    double totalTax = 0.0;
    double totalIncl = 0.0;

    int lineOrder = 0;
    for (final g in grouped.values) {
      final int quantity = g.quantity;
      final double unitPriceExcl = g.unitPrice;

      final double lineExcl = _round2(unitPriceExcl * quantity);
      final double lineIncl =
          (taxRate > 0) ? _round2(lineExcl * (1 + taxRate / 100.0)) : lineExcl;
      final double lineTax = _round2(lineIncl - lineExcl);

      totalExcl += lineExcl;
      totalTax += lineTax;
      totalIncl += lineIncl;

      final line = InvoiceLine(
        id: 0,
        invoiceId: createdInvoice.id,
        itemId: g.itemIdRepresentative,
        description: g.description,
        quantity: quantity,
        unitPrice: unitPriceExcl, // HT sur la ligne
        discount: 0,
        taxRate: taxRate,
        totalExclTax: lineExcl,
        totalTax: lineTax,
        totalInclTax: lineIncl,
        lineOrder: lineOrder++,
      );

      await createInvoiceLine(line);
    }

    // 4. Update invoice totals and return fresh row
    final updatedData = await client
        .from('invoice')
        .update({
          'total_excl_tax': totalExcl,
          'total_tax': totalTax,
          'total_incl_tax': totalIncl,
        })
        .eq('id', createdInvoice.id)
        .select()
        .single();

    return Invoice.fromMap(updatedData as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // PURCHASE invoice (external document attached to an item)
  // ---------------------------------------------------------------------------

  /// Create a PURCHASE invoice for an item, using an **external** document URL.
  Future<Invoice> createPurchaseInvoiceForItem({
    required String orgId,
    required int itemId,
    required String supplierName,
    required String invoiceNumber,
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
    final totalTax = 0.0;
    final totalIncl = totalExcl;

    // Issue date: use item.purchase_date if available
    DateTime effectiveIssueDate = DateTime.now();
    final purchaseDateRaw = itemRow['purchase_date'];
    if (purchaseDateRaw != null) {
      try {
        effectiveIssueDate = DateTime.parse(purchaseDateRaw.toString());
      } catch (_) {}
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
    } catch (_) {}

    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.purchase,
      status: InvoiceStatus.paid,
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

    // ⚠ On reflète aussi sur l'item
    await client
        .from('item')
        .update({'document_url': documentUrl}).eq('id', itemId);

    return Invoice.fromMap(data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Storage utils (mainly for SALES PDFs)
  // ---------------------------------------------------------------------------

  /// Upload the PDF to Supabase Storage and link it to invoice + ONE item.
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

    await client
        .from('invoice')
        .update({'document_url': documentPath}).eq('id', invoice.id);

    if (relatedItemId != null) {
      await client
          .from('item')
          .update({'document_url': documentPath}).eq('id', relatedItemId);
    }
  }

  /// Upload the PDF to Supabase Storage and link it to invoice + MULTIPLE items.
  Future<void> uploadInvoicePdfAndLinkToItems({
    required String orgId,
    required Invoice invoice,
    required Uint8List pdfBytes,
    required List<int> relatedItemIds,
  }) async {
    final year = invoice.issueDate.year.toString();
    final path = '$orgId/$year/${invoice.invoiceNumber}/invoice.pdf';

    await client.storage.from('invoices').uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final documentPath = 'invoices/$path';

    await client
        .from('invoice')
        .update({'document_url': documentPath}).eq('id', invoice.id);

    if (relatedItemIds.isNotEmpty) {
      await client.from('item').update({'document_url': documentPath}).inFilter(
          'id', relatedItemIds);
    }
  }

  /// Delete invoice + lines (+ pdf, optional) and clean related item.document_url
  Future<void> deleteInvoice(
    Invoice invoice, {
    bool deletePdf = true,
  }) async {
    await client.from('invoice_line').delete().eq('invoice_id', invoice.id);

    if (invoice.documentUrl != null) {
      await client.from('item').update({'document_url': null}).eq(
          'document_url', invoice.documentUrl as Object);
    }

    await client.from('invoice').delete().eq('id', invoice.id);

    if (deletePdf && invoice.documentUrl != null) {
      final pathInBucket = invoice.documentUrl!.replaceFirst('invoices/', '');
      await client.storage.from('invoices').remove([pathInBucket]);
    }
  }

  /// Create an "external" PURCHASE invoice not linked to any item (expense, phone bill, etc.)
  Future<Invoice> createExternalPurchaseInvoice({
    required String orgId,
    required String supplierName,
    required String invoiceNumber,
    required String currency,
    required String documentUrl,
    required DateTime issueDate,
    required double totalAmount,
    int? folderId,
    String? notes,
  }) async {
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
    } catch (_) {}

    final totalExcl = totalAmount;
    final totalTax = 0.0;
    final totalIncl = totalAmount;

    final invoice = Invoice(
      id: 0,
      orgId: orgId,
      folderId: folderId,
      type: InvoiceType.purchase,
      status: InvoiceStatus.paid,
      invoiceNumber: invoiceNumber,
      issueDate: issueDate,
      dueDate: null,
      currency: currency,

      // Seller (provider)
      sellerName: supplierName,
      sellerAddress: null,
      sellerCountry: null,
      sellerVatNumber: null,
      sellerTaxRegistration: null,
      sellerRegistrationNumber: null,

      // Buyer (your org)
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

      // ✅ important: not linked to an item
      relatedItemId: null,
      relatedOrderId: null,

      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: null,
    );

    final insertMap = invoice.toInsertMap();
    insertMap['document_url'] = documentUrl;
    insertMap['related_item_id'] = null;

    final data =
        await client.from('invoice').insert(insertMap).select().single();

    return Invoice.fromMap(data as Map<String, dynamic>);
  }
}
