import 'enums.dart';

class Invoice {
  final int id;
  final String orgId;
  final int? folderId;
  final InvoiceType type;
  final InvoiceStatus status;
  final String invoiceNumber;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String currency;

  // Seller
  final String sellerName;
  final String? sellerAddress;
  final String? sellerCountry;
  final String? sellerVatNumber;
  final String? sellerTaxRegistration;
  final String? sellerRegistrationNumber;

  // Buyer
  final String buyerName;
  final String? buyerAddress;
  final String? buyerCountry;
  final String? buyerVatNumber;
  final String? buyerTaxRegistration;
  final String? buyerEmail;
  final String? buyerPhone;

  // Totals
  final num totalExclTax;
  final num totalTax;
  final num totalInclTax;

  final String? notes;
  final String? paymentTerms;
  final String? documentUrl;

  final int? relatedItemId;
  final int? relatedOrderId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  Invoice({
    required this.id,
    required this.orgId,
    required this.folderId,
    required this.type,
    required this.status,
    required this.invoiceNumber,
    required this.issueDate,
    required this.dueDate,
    required this.currency,
    required this.sellerName,
    this.sellerAddress,
    this.sellerCountry,
    this.sellerVatNumber,
    this.sellerTaxRegistration,
    this.sellerRegistrationNumber,
    required this.buyerName,
    this.buyerAddress,
    this.buyerCountry,
    this.buyerVatNumber,
    this.buyerTaxRegistration,
    this.buyerEmail,
    this.buyerPhone,
    required this.totalExclTax,
    required this.totalTax,
    required this.totalInclTax,
    this.notes,
    this.paymentTerms,
    this.documentUrl,
    this.relatedItemId,
    this.relatedOrderId,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'] as int,
      orgId: map['org_id'] as String,
      folderId: map['folder_id'] as int?,
      type: invoiceTypeFromString(map['invoice_type'] as String),
      status: invoiceStatusFromString(map['status'] as String),
      invoiceNumber: map['invoice_number'] as String,
      issueDate: DateTime.parse(map['issue_date'].toString()),
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      currency: map['currency'] as String,
      sellerName: map['seller_name'] as String,
      sellerAddress: map['seller_address'] as String?,
      sellerCountry: map['seller_country'] as String?,
      sellerVatNumber: map['seller_vat_number'] as String?,
      sellerTaxRegistration: map['seller_tax_registration'] as String?,
      sellerRegistrationNumber: map['seller_registration_number'] as String?,
      buyerName: map['buyer_name'] as String,
      buyerAddress: map['buyer_address'] as String?,
      buyerCountry: map['buyer_country'] as String?,
      buyerVatNumber: map['buyer_vat_number'] as String?,
      buyerTaxRegistration: map['buyer_tax_registration'] as String?,
      buyerEmail: map['buyer_email'] as String?,
      buyerPhone: map['buyer_phone'] as String?,
      totalExclTax: map['total_excl_tax'] ?? 0,
      totalTax: map['total_tax'] ?? 0,
      totalInclTax: map['total_incl_tax'] ?? 0,
      notes: map['notes'] as String?,
      paymentTerms: map['payment_terms'] as String?,
      documentUrl: map['document_url'] as String?,
      relatedItemId: map['related_item_id'] as int?,
      relatedOrderId: map['related_order_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'org_id': orgId,
      'folder_id': folderId,
      'invoice_type': invoiceTypeToString(type),
      'status': invoiceStatusToString(status),
      'invoice_number': invoiceNumber,
      'issue_date': issueDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'currency': currency,
      'seller_name': sellerName,
      'seller_address': sellerAddress,
      'seller_country': sellerCountry,
      'seller_vat_number': sellerVatNumber,
      'seller_tax_registration': sellerTaxRegistration,
      'seller_registration_number': sellerRegistrationNumber,
      'buyer_name': buyerName,
      'buyer_address': buyerAddress,
      'buyer_country': buyerCountry,
      'buyer_vat_number': buyerVatNumber,
      'buyer_tax_registration': buyerTaxRegistration,
      'buyer_email': buyerEmail,
      'buyer_phone': buyerPhone,
      'total_excl_tax': totalExclTax,
      'total_tax': totalTax,
      'total_incl_tax': totalInclTax,
      'notes': notes,
      'payment_terms': paymentTerms,
      'related_item_id': relatedItemId,
      'related_order_id': relatedOrderId,
    };
  }
}
