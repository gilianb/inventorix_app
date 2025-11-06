// lib/services/collectr_api.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectrEdgeService {
  CollectrEdgeService(this._sb);
  final SupabaseClient _sb;

  static const int _ttlHours = 24;

  /// TTL basé **uniquement** sur last_update.
  /// - Si last_update est non nul et < 24h => PAS de refresh.
  /// - Sinon => refresh.
  static bool needsRefresh(Map<String, dynamic> row) {
    final String? last = row['last_update']?.toString();
    if (last == null || last.isEmpty) return true;

    final dt = DateTime.tryParse(last);
    if (dt == null) return true;

    final nowUtc = DateTime.now().toUtc();
    final ageH = nowUtc.difference(dt.toUtc()).inHours;
    return ageH >= _ttlHours;
  }

  /// Charge la ligne produit minimale depuis la DB.
  Future<Map<String, dynamic>> _loadProductRow(int productId) async {
    final row = await _sb
        .from('product')
        .select(
          'id,type,collectr_id,tcg_player_id,price_raw,price_graded,last_update',
        )
        .eq('id', productId)
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  /// Vérifie la ligne et, si nécessaire, appelle l’Edge Function pour actualiser.
  ///
  /// - TTL : si `last_update` < 24h, on ne rappelle rien (même si des prix sont null).
  /// - Si aucun `collectr_id` **et** aucun `tcg_player_id` et qu’un refresh serait requis :
  ///   on ne peut pas résoudre => renvoie `missingId: true`.
  /// - Si l’EF renvoie `skipped: true` (par TTL côté EF), on ne modifie rien.
  /// - Si l’EF retourne des valeurs, on met à jour la DB (`collectr_id`, `price_raw`,
  ///   `price_graded` si single, et `last_update`).
  /// - Renvoie un résumé exploitable par l’UI.
  Future<Map<String, dynamic>> ensureFreshAndPersist(int productId) async {
    final row = await _loadProductRow(productId);

    // 1) TTL local (front) — si frais, pas d’appel EF.
    if (!needsRefresh(row)) {
      return {
        'updated': false,
        'reason': 'fresh', // frais côté app (moins de 24h)
        'price_raw': (row['price_raw'] as num?)?.toDouble(),
        'price_graded': (row['price_graded'] as num?)?.toDouble(),
        'last_update': row['last_update']?.toString(),
        'collectr_id': row['collectr_id']?.toString(),
      };
    }

    String? collectrId = row['collectr_id']?.toString();
    final String? tcgPlayerId = row['tcg_player_id']?.toString();
    final bool isSingle =
        (row['type']?.toString().toLowerCase() ?? 'single') == 'single';

    // 2) Si pas d’ID du tout, on ne peut pas résoudre.
    if ((collectrId == null || collectrId.isEmpty) &&
        (tcgPlayerId == null || tcgPlayerId.isEmpty)) {
      return {
        'updated': false,
        'missingId': true,
        'reason': 'no_id',
        'price_raw': (row['price_raw'] as num?)?.toDouble(),
        'price_graded': (row['price_graded'] as num?)?.toDouble(),
        'last_update': row['last_update']?.toString(),
      };
    }

    // 3) Appel Edge Function, en passant aussi last_update (pour que l’EF puisse skipper).
    final payload = <String, dynamic>{
      if (collectrId != null && collectrId.isNotEmpty)
        'collectr_id': collectrId,
      if ((collectrId == null || collectrId.isEmpty) &&
          tcgPlayerId != null &&
          tcgPlayerId.isNotEmpty)
        'tcg_player_id': tcgPlayerId,
      'last_update': row['last_update']?.toString(), // <-- IMPORTANT
    };

    try {
      final res = await _sb.functions.invoke(
        'collectr_resolve_and_price',
        body: payload,
      );

      final data = Map<String, dynamic>.from(res.data as Map? ?? const {});
      final bool skipped = (data['skipped'] == true);

      // 3a) Si l’EF a skippé (TTL <24h côté EF), on ne modifie rien.
      if (skipped) {
        return {
          'updated': false,
          'reason': 'ef_skipped_fresh', // frais côté EF
          'price_raw': (row['price_raw'] as num?)?.toDouble(),
          'price_graded': (row['price_graded'] as num?)?.toDouble(),
          'last_update': row['last_update']?.toString(),
          'collectr_id': collectrId,
        };
      }

      // 3b) Sinon, on tente d’extraire les valeurs et de persister.
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
    } catch (e) {
      // En cas d’erreur EF, on renvoie l’état actuel sans modifier la DB
      return {
        'updated': false,
        'error': e.toString(),
        'reason': 'edge_error',
        'price_raw': (row['price_raw'] as num?)?.toDouble(),
        'price_graded': (row['price_graded'] as num?)?.toDouble(),
        'last_update': row['last_update']?.toString(),
        'collectr_id': collectrId,
      };
    }
  }
}
