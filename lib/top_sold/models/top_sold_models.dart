class TopSoldGroupVM {
  TopSoldGroupVM({
    required this.orgId,
    required this.productId,
    required this.gameId,
    required this.type,
    required this.language,
    required this.groupSig,
    required this.status,
    required this.qty,
    required this.avgMarge,
    required this.revenueByCurrency,
    required this.costByCurrency,
    required this.photoUrl,
    required this.lastSaleDate,
  });

  final String orgId;
  final int productId;
  final int? gameId;
  final String type;
  final String language;

  final String groupSig;
  final String status;

  final int qty;
  final double avgMarge;

  /// total revenue par devise sur ce groupe (vide si masqué)
  final Map<String, double> revenueByCurrency;

  /// total cost par devise sur ce groupe (vide si masqué)
  final Map<String, double> costByCurrency;

  final String photoUrl;
  final DateTime? lastSaleDate;

  Map<String, dynamic> toOpenDetailsPayload() => {
        'org_id': orgId,
        'product_id': productId,
        'game_id': gameId,
        'type': type,
        'language': language,
        'group_sig': groupSig,
        'status': status,
        'photo_url': photoUrl,
        'qty': qty,
        'marge': avgMarge,
      };
}

class TopSoldProductVM {
  TopSoldProductVM({
    required this.orgId,
    required this.productId,
    required this.gameId,
    required this.type,
    required this.language,
    required this.productName,
    required this.sku,
    required this.gameLabel,
    required this.gameCode,
    required this.photoUrl,
    required this.soldQty,
    required this.avgMarge,
    required this.revenueByCurrency,
    required this.costByCurrency,
    required this.lastSaleDate,
    required this.groupsPreview,
    required this.anchorGroup,
    required this.inStockTopN,
  });

  final String orgId;
  final int productId;
  final int? gameId;
  final String type;
  final String language;

  final String productName;
  final String sku;
  final String gameLabel;
  final String gameCode;
  final String photoUrl;

  final int soldQty;
  final double avgMarge;

  /// total revenue par devise sur la période (vide si masqué)
  final Map<String, double> revenueByCurrency;

  /// total cost par devise sur la période (vide si masqué)
  final Map<String, double> costByCurrency;

  final DateTime? lastSaleDate;

  /// Groupes (ventes) récents pour la bottom sheet
  final List<TopSoldGroupVM> groupsPreview;

  /// Groupe “anchor” utilisé si on veut ouvrir Détails direct
  final TopSoldGroupVM? anchorGroup;

  /// null si pas calculé, true/false si calculé (uniquement top N)
  final bool? inStockTopN;

  bool get isOutOfStockTopN => inStockTopN == false;
  bool get isInStockTopN => inStockTopN == true;
}

enum TopSoldSort { marge, qty, revenue }

extension TopSoldSortX on TopSoldSort {
  String get label {
    switch (this) {
      case TopSoldSort.marge:
        return 'Marge';
      case TopSoldSort.qty:
        return 'Qty';
      case TopSoldSort.revenue:
        return 'Revenue';
    }
  }
}
