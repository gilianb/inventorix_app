// lib/services/collectr_api.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectrEdgeService {
  CollectrEdgeService(this._sb);
  final SupabaseClient _sb;

  /// Renvoie `true` si la ligne produit doit être rafraîchie (TTL 24h ou prix manquants).
  static bool needsRefresh(Map<String, dynamic> row) {
    final isSingle =
        (row['type']?.toString().toLowerCase() ?? 'single') == 'single';
    final double? priceRaw = (row['price_raw'] as num?)?.toDouble();
    final double? priceGraded = (row['price_graded'] as num?)?.toDouble();
    final String? last = row['last_update']?.toString();

    if (priceRaw == null) return true;
    if (isSingle && priceGraded == null) return true;
    if (last == null || last.isEmpty) return true;

    final dt = DateTime.tryParse(last);
    if (dt == null) return true;
    final ageH = DateTime.now().toUtc().difference(dt.toUtc()).inHours;
    return ageH >= 24;
  }

  /// Charge la ligne produit minimale depuis la DB.
  Future<Map<String, dynamic>> _loadProductRow(int productId) async {
    final row = await _sb
        .from('product')
        .select(
            'id,type,collectr_id,tcg_player_id,price_raw,price_graded,last_update')
        .eq('id', productId)
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  /// Vérifie la ligne et, si nécessaire, appelle l’Edge Function pour actualiser.
  ///
  /// - Si aucun `collectr_id` **et** aucun `tcg_player_id`: ne fait rien et renvoie `"missingId": true`.
  /// - Si l’EF retourne des prix, on met à jour la DB (`collectr_id`, `price_raw`, `price_graded`, `last_update`).
  /// - Renvoie un résumé utile pour le UI.
  Future<Map<String, dynamic>> ensureFreshAndPersist(int productId) async {
    final row = await _loadProductRow(productId);

    if (!needsRefresh(row)) {
      return {
        'updated': false,
        'reason': 'fresh',
        'price_raw': (row['price_raw'] as num?)?.toDouble(),
        'price_graded': (row['price_graded'] as num?)?.toDouble(),
        'last_update': row['last_update']?.toString(),
      };
    }

    String? collectrId = row['collectr_id']?.toString();
    final String? tcgPlayerId = row['tcg_player_id']?.toString();
    final bool isSingle =
        (row['type']?.toString().toLowerCase() ?? 'single') == 'single';

    final payload = <String, dynamic>{
      if (collectrId != null && collectrId.isNotEmpty)
        'collectr_id': collectrId,
      if ((collectrId == null || collectrId.isEmpty) &&
          tcgPlayerId != null &&
          tcgPlayerId.isNotEmpty)
        'tcg_player_id': tcgPlayerId,
    };

    if (payload.isEmpty) {
      return {'updated': false, 'missingId': true, 'reason': 'no_id'};
    }

    // Appel Edge Function (serveur => pas de CORS)
    final res = await _sb.functions.invoke(
      'collectr_resolve_and_price',
      body: payload,
    );
    final data = Map<String, dynamic>.from(res.data as Map);

    final String? opaqueId = data['opaqueId']?.toString();
    final double? newRaw = (data['price_raw'] as num?)?.toDouble();
    final double? newPsa10 = (data['price_psa10'] as num?)?.toDouble();

    // Prépare update DB
    final upd = <String, dynamic>{
      'last_update': DateTime.now().toUtc().toIso8601String(),
    };
    if (opaqueId != null && (collectrId == null || collectrId.isEmpty)) {
      upd['collectr_id'] = opaqueId;
      collectrId = opaqueId;
    }
    if (newRaw != null) upd['price_raw'] = newRaw;
    if (isSingle && newPsa10 != null) upd['price_graded'] = newPsa10;

    if (upd.length > 1) {
      await _sb.from('product').update(upd).eq('id', productId);
    }

    return {
      'updated': true,
      'collectr_id': collectrId,
      'price_raw': newRaw,
      'price_graded': isSingle ? newPsa10 : null,
    };
  }
}
