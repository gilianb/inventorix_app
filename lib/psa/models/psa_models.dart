// lib/psa/models/psa_models.dart

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // expects YYYY-MM-DD
  return DateTime.tryParse(s);
}

class PsaOrderSummary {
  PsaOrderSummary({
    required this.psaOrderId,
    required this.orgId,
    required this.orderNumber,
    required this.gradingServiceId,
    required this.serviceLabel,
    required this.expectedDays,
    required this.defaultFee,
    required this.createdAt,
    required this.psaReceivedDate,
    required this.qtyTotal,
    required this.qtySentToGrader,
    required this.qtyAtGrader,
    required this.qtyGraded,
    required this.investedPurchase,
    required this.psaFees,
    required this.estRevenue,
  });

  final int psaOrderId;
  final String orgId;
  final String orderNumber;

  final int gradingServiceId;
  final String serviceLabel;
  final int expectedDays;
  final num defaultFee;

  final DateTime createdAt;
  final DateTime? psaReceivedDate;

  final int qtyTotal;
  final int qtySentToGrader;
  final int qtyAtGrader;
  final int qtyGraded;

  final num investedPurchase;
  final num psaFees;
  final num estRevenue;

  num get totalInvested => investedPurchase + psaFees;
  num get potentialMargin => estRevenue - totalInvested;

  factory PsaOrderSummary.fromJson(Map<String, dynamic> j) {
    return PsaOrderSummary(
      psaOrderId: (j['psa_order_id'] as num).toInt(),
      orgId: (j['org_id'] ?? '').toString(),
      orderNumber: (j['order_number'] ?? '').toString(),
      gradingServiceId: (j['grading_service_id'] as num).toInt(),
      serviceLabel: (j['service_label'] ?? '').toString(),
      expectedDays: ((j['expected_days'] ?? 0) as num).toInt(),
      defaultFee: (j['default_fee'] as num?) ?? 0,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.now(),
      psaReceivedDate: _parseDate(j['psa_received_date']),
      qtyTotal: ((j['qty_total'] ?? 0) as num).toInt(),
      qtySentToGrader: ((j['qty_sent_to_grader'] ?? 0) as num).toInt(),
      qtyAtGrader: ((j['qty_at_grader'] ?? 0) as num).toInt(),
      qtyGraded: ((j['qty_graded'] ?? 0) as num).toInt(),
      investedPurchase: (j['invested_purchase'] as num?) ?? 0,
      psaFees: (j['psa_fees'] as num?) ?? 0,
      estRevenue: (j['est_revenue'] as num?) ?? 0,
    );
  }
}

class PsaOrderItem {
  PsaOrderItem({
    required this.id,
    required this.orgId,
    required this.psaOrderId,
    required this.status,
    required this.type,
    required this.productId,
    required this.productName,
    required this.gameLabel,
    required this.language,
    required this.purchaseDate,
    required this.unitCost,
    required this.unitFees,
    required this.gradingFees,
    required this.estimatedPrice,
    required this.gradeId,
    required this.gradingNote,
    required this.photoUrl,
  });

  final int id;
  final String orgId;
  final int? psaOrderId;
  final String status;
  final String type;

  final int productId;
  final String productName;
  final String? gameLabel;

  final String? language;
  final DateTime? purchaseDate;

  final num? unitCost;
  final num? unitFees;
  final num? gradingFees;
  final num? estimatedPrice;

  final String? gradeId;
  final String? gradingNote;
  final String? photoUrl;

  factory PsaOrderItem.fromJson(Map<String, dynamic> j) {
    return PsaOrderItem(
      id: (j['id'] as num).toInt(),
      orgId: (j['org_id'] ?? '').toString(),
      psaOrderId: (j['psa_order_id'] as num?)?.toInt(),
      status: (j['status'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      productId: (j['product_id'] as num).toInt(),
      productName: (j['product_name'] ?? '').toString(),
      gameLabel: (j['game_label'] ?? '')?.toString(),
      language: (j['language'] ?? '')?.toString(),
      purchaseDate: _parseDate(j['purchase_date']),
      unitCost: j['unit_cost'] as num?,
      unitFees: j['unit_fees'] as num?,
      gradingFees: j['grading_fees'] as num?,
      estimatedPrice: j['estimated_price'] as num?,
      gradeId: (j['grade_id'] ?? '')?.toString(),
      gradingNote: (j['grading_note'] ?? '')?.toString(),
      photoUrl: (j['photo_url'] ?? '')?.toString(),
    );
  }
}
