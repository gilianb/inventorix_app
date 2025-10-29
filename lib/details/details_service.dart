import 'package:supabase_flutter/supabase_flutter.dart';
/*regroupe la logique non-UI :
 requêtes Supabase + calculs partagés*/

class DetailsService {
  static num sumNum(Iterable<dynamic> it) {
    num s = 0;
    for (final v in it) {
      final n = (v is num) ? v : num.tryParse(v?.toString() ?? '');
      if (n != null) s += n;
    }
    return s;
  }

  static num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static String _saleGroupKey(Map<String, dynamic> r) {
    final sd = (r['sale_date'] ?? '').toString();
    final buyer = (r['buyer_company'] ?? '').toString();
    final trk = (r['tracking'] ?? '').toString();
    final ch = (r['channel_id'] ?? '').toString();
    return [sd, buyer, trk, ch].join('|').trim();
  }

  /// Somme Investi basée sur les items visibles
  static num investedFromItems(List<Map<String, dynamic>> items) {
    num base = 0;
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final r in items) {
      base += (_asNum(r['unit_cost']) ?? 0) + (_asNum(r['unit_fees']) ?? 0);
      final key = _saleGroupKey(r);
      (groups[key] ??= <Map<String, dynamic>>[]).add(r);
    }

    num groupFees = 0;
    groups.forEach((key, list) {
      if (key.isEmpty) {
        for (final r in list) {
          groupFees += (_asNum(r['shipping_fees']) ?? 0) +
              (_asNum(r['commission_fees']) ?? 0) +
              (_asNum(r['grading_fees']) ?? 0);
        }
      } else {
        num maxShip = 0, maxComm = 0, maxGrad = 0;
        for (final r in list) {
          final s = _asNum(r['shipping_fees']) ?? 0;
          final c = _asNum(r['commission_fees']) ?? 0;
          final g = _asNum(r['grading_fees']) ?? 0;
          if (s > maxShip) maxShip = s;
          if (c > maxComm) maxComm = c;
          if (g > maxGrad) maxGrad = g;
        }
        groupFees += maxShip + maxComm + maxGrad;
      }
    });

    return base + groupFees;
  }

  static bool isRealized(String s) =>
      s == 'sold' || s == 'shipped' || s == 'finalized';

  // === DATA ===

  static Future<Map<String, dynamic>?> fetchViewRow(
    SupabaseClient sb,
    Map<String, dynamic> group,
    List<String> viewCols,
  ) async {
    var builder = sb.from('v_items_by_status').select(viewCols.join(','));
    for (final key in viewCols) {
      if (group.containsKey(key) && group[key] != null) {
        builder = builder.eq(key, group[key]);
      }
    }
    final res = await builder.limit(1);
    final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    return list.isNotEmpty ? list.first : null;
  }

  static Future<List<Map<String, dynamic>>> fetchItemsByLineKey(
    SupabaseClient sb,
    Map<String, dynamic> source,
    Set<String> strictKeys, {
    required Set<String> ignoreKeys,
  }) async {
    const itemCols = [
      'id',
      'product_id',
      'game_id',
      'type',
      'language',
      'status',
      'channel_id',
      'purchase_date',
      'currency',
      'supplier_name',
      'buyer_company',
      'unit_cost',
      'unit_fees',
      'notes',
      'grade_id',
      'grading_note',
      'grading_fees',
      'sale_date',
      'sale_price',
      'tracking',
      'photo_url',
      'document_url',
      'created_at',
      'estimated_price',
      'item_location',
      'shipping_fees',
      'commission_fees',
      'payment_type',
      'buyer_infos',
      'marge',
    ];

    var q = sb.from('item').select(itemCols.join(','));

    for (final k in strictKeys) {
      if (ignoreKeys.contains(k)) continue;
      if (!source.containsKey(k)) continue;
      final v = source[k];
      if (v == null) {
        q = q.filter(k, 'is', null);
      } else {
        q = q.filter(k, 'eq', v);
      }
    }

    final clickedStatus = (source['status'] ?? '').toString();
    if (clickedStatus.isNotEmpty) {
      q = q.eq('status', clickedStatus);
    }

    final raw = await q.order('id', ascending: true).limit(20000);
    return List<Map<String, dynamic>>.from(
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static Future<List<Map<String, dynamic>>> fetchMovementsFor(
      SupabaseClient sb, List<int> itemIds) async {
    if (itemIds.isEmpty) return [];
    final raw = await sb
        .from('movement')
        .select(
          'id, ts, mtype, from_status, to_status, channel_id, qty, unit_price, currency, fees, grader, grade, tracking, note, item_id',
        )
        .inFilter('item_id', itemIds)
        .order('ts', ascending: false)
        .limit(20000);

    return List<Map<String, dynamic>>.from(
        (raw as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }
}
