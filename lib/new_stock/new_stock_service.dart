/*Logique data/Supabase. Charge games, crée/retourne un product 
depuis un blueprint, insère les items (save via blueprint) et fallback 
RPC (création libre). Fournit aussi buildFullDisplay().*/

import 'package:supabase_flutter/supabase_flutter.dart';

class NewStockService {
  // Charge la table games
  static Future<List<Map<String, dynamic>>> loadGames(SupabaseClient sb) async {
    final raw = await sb.from('games').select('id, code, label').order('label');
    return raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // Affichage complet pour le picker si non fourni
  static String buildFullDisplay(Map<String, dynamic> bp) {
    final name = (bp['name'] as String?)?.trim() ?? '';

    final parts = <String>[];
    final exName = (bp['expansion_name'] as String?)?.trim() ?? '';
    final exCode = (bp['expansion_code'] as String?)?.trim() ?? '';
    final number = (bp['collector_number'] as String?)?.trim() ?? '';
    final rarity = (bp['rarity_text'] as String?)?.trim() ?? '';
    final version = (bp['version'] as String?)?.trim() ?? '';

    if (exName.isNotEmpty && exCode.isNotEmpty) {
      parts.add('$exName ($exCode)');
    } else if (exName.isNotEmpty) {
      parts.add(exName);
    } else if (exCode.isNotEmpty) {
      parts.add(exCode);
    }
    if (number.isNotEmpty) parts.add('No. $number');
    if (rarity.isNotEmpty) parts.add('Ver. $rarity');
    if (version.isNotEmpty) parts.add('v$version');

    if (parts.isEmpty) return name;
    if (name.isEmpty) return parts.join(' — ');
    return '$name — ${parts.join(' — ')}';
  }

  // Crée/retourne product depuis blueprint (scopé par org)
  static Future<int> _ensureProductFromBlueprint({
    required SupabaseClient sb,
    required String orgId, // ← AJOUT
    required Map<String, dynamic> bp,
    required int gameId,
    required String type,
    required String language,
    String? overridePhoto,
  }) async {
    final blueprintId = (bp['id'] as num).toInt();

    final existing = await sb
        .from('product')
        .select('id')
        .eq('blueprint_id', blueprintId)
        .eq('org_id', orgId) // ← AJOUT : ne pas mélanger entre orgs
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      return (existing['id'] as num).toInt();
    }

    final String? photo =
        (bp['image_url'] as String?)?.trim().isNotEmpty == true
            ? (bp['image_url'] as String)
            : (overridePhoto?.trim().isNotEmpty == true ? overridePhoto : null);

    final inserted = await sb
        .from('product')
        .insert({
          'type': type,
          'name': buildFullDisplay(bp),
          'language': language,
          'game_id': gameId,
          'blueprint_id': blueprintId,
          'version': bp['version'],
          'collector_number': bp['collector_number'],
          'expansion_code': bp['expansion_code'],
          'expansion_name': bp['expansion_name'],
          'rarity_text': bp['rarity_text'],
          'scryfall_id': bp['scryfall_id'],
          'tcg_player_id': bp['tcg_player_id'],
          'card_market_ids': bp['card_market_ids'],
          'image_storage': bp['image_storage'],
          'photo_url': photo,
          'fixed_properties': bp['fixed_properties'],
          'editable_properties': bp['editable_properties'],
          'data': bp['data'],
          'org_id': orgId, // ← AJOUT
        })
        .select('id')
        .single();

    return (inserted['id'] as num).toInt();
  }

  // Sauvegarde depuis blueprint sélectionné
  static Future<void> saveWithExternalCard({
    required SupabaseClient sb,
    required String orgId, // ← AJOUT
    required Map<String, dynamic> bp,
    required int selectedGameId,
    required String type,
    required String lang,
    required String initStatus,
    required DateTime purchaseDate,
    required String currency,
    String? supplierName,
    String? buyerCompany,
    required int qty,
    required double totalCost,
    required double fees,
    String? notes,
    String? gradeId,
    String? gradingNote,
    double? salePrice,
    String? tracking,
    String? photoUrl,
    String? documentUrl,
    double? estimatedPrice,
    String? itemLocation,
    double? shippingFees,
    double? commissionFees,
    String? paymentType,
    String? buyerInfos,
    double? gradingFees,
  }) async {
    final perUnitCost = qty > 0 ? (totalCost / qty) : 0;
    final perUnitFees = qty > 0 ? (fees / qty) : 0;

    final productId = await _ensureProductFromBlueprint(
      sb: sb,
      orgId: orgId, // ← AJOUT
      bp: bp,
      gameId: selectedGameId,
      type: type,
      language: lang,
      overridePhoto: photoUrl,
    );

    final items = List.generate(qty, (_) {
      return {
        'product_id': productId,
        'game_id': selectedGameId,
        'type': type,
        'language': lang,
        'status': initStatus,
        'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
        'currency': currency,
        'supplier_name': supplierName,
        'buyer_company': buyerCompany,
        'unit_cost': perUnitCost,
        'unit_fees': perUnitFees,
        'notes': notes,
        'grade_id': gradeId,
        'grading_note': gradingNote,
        'sale_date': null,
        'sale_price': salePrice,
        'tracking': tracking,
        'photo_url': (photoUrl?.isNotEmpty == true)
            ? photoUrl
            : ((bp['image_url'] as String?)?.isNotEmpty == true
                ? bp['image_url']
                : null),
        'document_url': documentUrl,
        'estimated_price': estimatedPrice,
        'item_location': itemLocation,
        'shipping_fees': shippingFees,
        'commission_fees': commissionFees,
        'payment_type': paymentType,
        'buyer_infos': buyerInfos,
        'grading_fees': gradingFees,
        'org_id': orgId, // ← AJOUT
      };
    });

    await sb.from('item').insert(items);
  }

  // Fallback RPC (création libre produit + items)
  static Future<void> saveFallbackRpc({
    required SupabaseClient sb,
    required String orgId, // ← AJOUT
    required String type,
    required String name,
    required String lang,
    required int selectedGameId,
    String? supplierName,
    String? buyerCompany,
    required DateTime purchaseDate,
    required int qty,
    required double totalCost,
    required double fees,
    required String initStatus,
    String? tracking,
    String? photoUrl,
    String? documentUrl,
    double? estimatedPrice,
    String? notes,
    String? gradeId,
    String? gradingNote,
    double? gradingFees,
    String? itemLocation,
    double? shippingFees,
    double? commissionFees,
    String? paymentType,
    String? buyerInfos,
    double? salePrice,
  }) async {
    await sb.rpc('fn_create_product_and_items', params: {
      'p_org_id':
          orgId, // ← AJOUT (assure-toi que la fonction SQL prend ce param)
      'p_type': type,
      'p_name': name,
      'p_language': lang,
      'p_game_id': selectedGameId,
      'p_supplier_name':
          (supplierName?.isNotEmpty == true) ? supplierName : null,
      'p_buyer_company':
          (buyerCompany?.isNotEmpty == true) ? buyerCompany : null,
      'p_purchase_date': purchaseDate.toIso8601String().substring(0, 10),
      'p_currency': 'USD',
      'p_qty': qty,
      'p_total_cost': totalCost,
      'p_fees': fees,
      'p_init_status': initStatus,
      'p_channel_id': null,
      'p_tracking': (tracking?.isNotEmpty == true) ? tracking : null,
      'p_photo_url': (photoUrl?.isNotEmpty == true) ? photoUrl : null,
      'p_document_url': (documentUrl?.isNotEmpty == true) ? documentUrl : null,
      'p_estimated_price': estimatedPrice,
      'p_notes': (notes?.isNotEmpty == true) ? notes : null,
      'p_grade_id': (gradeId?.isNotEmpty == true) ? gradeId : null,
      'p_grading_note': (gradingNote?.isNotEmpty == true) ? gradingNote : null,
      'p_grading_fees': gradingFees,
      'p_item_location':
          (itemLocation?.isNotEmpty == true) ? itemLocation : null,
      'p_shipping_fees': shippingFees,
      'p_commission_fees': commissionFees,
      'p_payment_type': (paymentType?.isNotEmpty == true) ? paymentType : null,
      'p_buyer_infos': (buyerInfos?.isNotEmpty == true) ? buyerInfos : null,
      'p_sale_price': salePrice,
    });
  }
}
