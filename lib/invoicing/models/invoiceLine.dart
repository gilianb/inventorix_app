class InvoiceLine {
  final int id;
  final int invoiceId;
  final int? itemId;
  final String description;
  final num quantity;
  final num unitPrice;
  final num discount;
  final num taxRate;
  final num totalExclTax;
  final num totalTax;
  final num totalInclTax;
  final int lineOrder;

  InvoiceLine({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.totalExclTax,
    required this.totalTax,
    required this.totalInclTax,
    required this.lineOrder,
  });

  factory InvoiceLine.fromMap(Map<String, dynamic> map) {
    return InvoiceLine(
      id: map['id'] as int,
      invoiceId: map['invoice_id'] as int,
      itemId: map['item_id'] as int?,
      description: map['description'] as String,
      quantity: map['quantity'],
      unitPrice: map['unit_price'],
      discount: map['discount'],
      taxRate: map['tax_rate'],
      totalExclTax: map['total_excl_tax'],
      totalTax: map['total_tax'],
      totalInclTax: map['total_incl_tax'],
      lineOrder: map['line_order'] ?? 0,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'invoice_id': invoiceId,
      'item_id': itemId,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'tax_rate': taxRate,
      'total_excl_tax': totalExclTax,
      'total_tax': totalTax,
      'total_incl_tax': totalInclTax,
      'line_order': lineOrder,
    };
  }
}
