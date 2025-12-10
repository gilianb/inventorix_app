class InvoiceFolder {
  final int id;
  final String orgId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? invoiceCount;

  InvoiceFolder({
    required this.id,
    required this.orgId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.invoiceCount,
  });

  factory InvoiceFolder.fromMap(Map<String, dynamic> map) {
    return InvoiceFolder(
      id: map['id'] as int,
      orgId: map['org_id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      invoiceCount: map['invoice_count'] != null
          ? int.tryParse(map['invoice_count'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'org_id': orgId,
      'name': name,
    };
  }
}
