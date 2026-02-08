// lib/psa/data/psa_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/psa_models.dart';

String _dateStr(DateTime d) => d.toIso8601String().split('T').first;
String _idsCsv(List<int> ids) => '(${ids.join(",")})';

class PsaRepository {
  PsaRepository(this.sb);
  final SupabaseClient sb;

  Future<List<Map<String, dynamic>>> fetchGradingServices(String orgId) async {
    final raw = await sb
        .from('grading_service')
        .select(
            'id, code, label, expected_days, default_fee, sort_order, active')
        .eq('active', true)
        .order('sort_order', ascending: true, nullsFirst: false)
        .order('label', ascending: true);

    return raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<PsaOrderSummary>> fetchOrderSummaries(String orgId) async {
    final raw = await sb
        .from('v_psa_order_summary_masked')
        .select('*')
        .eq('org_id', orgId)
        .order('created_at', ascending: false);

    return raw
        .map<PsaOrderSummary>((e) =>
            PsaOrderSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> createOrder({
    required String orgId,
    required String orderNumber,
    required int gradingServiceId,
    DateTime? psaReceivedDate,
  }) async {
    final row = await sb
        .from('psa_order')
        .insert({
          'org_id': orgId,
          'order_number': orderNumber.trim(),
          'grading_service_id': gradingServiceId,
          'psa_received_date':
              psaReceivedDate == null ? null : _dateStr(psaReceivedDate),
        })
        .select('id')
        .single();

    return (row['id'] as num).toInt();
  }

  Future<void> updateOrderReceivedDate({
    required String orgId,
    required int psaOrderId,
    required DateTime? psaReceivedDate,
  }) async {
    await sb
        .from('psa_order')
        .update({
          'psa_received_date':
              psaReceivedDate == null ? null : _dateStr(psaReceivedDate),
        })
        .eq('org_id', orgId)
        .eq('id', psaOrderId);
  }

  Future<List<PsaOrderItem>> fetchOrderItems({
    required String orgId,
    required int psaOrderId,
  }) async {
    final raw = await sb
        .from('v_psa_order_items_masked')
        .select('*')
        .eq('org_id', orgId)
        .eq('psa_order_id', psaOrderId)
        .order('psa_order_position', ascending: true, nullsFirst: false)
        .order('id', ascending: true);

    return raw
        .map<PsaOrderItem>(
            (e) => PsaOrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
  }

  Future<Map<int, List<String?>>> fetchOrderItemThumbs({
    required String orgId,
    required List<int> psaOrderIds,
    int perOrderLimit = 10,
  }) async {
    if (psaOrderIds.isEmpty) return {};

    final idsCsv = _idsCsv(psaOrderIds);
    final raw = await sb
        .from('v_psa_order_items_masked')
        .select('psa_order_id, photo_url, psa_order_position, id')
        .eq('org_id', orgId)
        .filter('psa_order_id', 'in', idsCsv)
        .order('psa_order_id', ascending: true)
        .order('psa_order_position', ascending: true, nullsFirst: false)
        .order('id', ascending: true);

    final out = <int, List<String?>>{};
    for (final row in raw) {
      final m = Map<String, dynamic>.from(row as Map);
      final orderId = (m['psa_order_id'] as num?)?.toInt();
      if (orderId == null) continue;
      final list = out.putIfAbsent(orderId, () => <String?>[]);
      if (list.length >= perOrderLimit) continue;
      final rawUrl = (m['photo_url'] ?? '').toString().trim();
      list.add(rawUrl.isEmpty ? null : rawUrl);
    }

    return out;
  }

  Future<List<PsaOrderItem>> fetchReceivedCandidates({
    required String orgId,
  }) async {
    final raw = await sb
        .from('v_psa_order_items_masked')
        .select('*')
        .eq('org_id', orgId)
        .eq('type', 'single')
        .eq('status', 'received')
        .filter('psa_order_id', 'is', null)
        .order('id', ascending: true);

    return raw
        .map<PsaOrderItem>(
            (e) => PsaOrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addItemsToOrder({
    required String orgId,
    required int psaOrderId,
    required int gradingServiceId,
    required num defaultFee,
    required List<int> itemIdsInOrder,
    required int startPosition,
  }) async {
    if (itemIdsInOrder.isEmpty) return;

    final today = _dateStr(DateTime.now());
    final addedAt = DateTime.now().toUtc().toIso8601String();

    for (var i = 0; i < itemIdsInOrder.length; i++) {
      final id = itemIdsInOrder[i];
      final pos = startPosition + i;

      await sb
          .from('item')
          .update({
            'psa_order_id': psaOrderId,
            'status': 'sent_to_grader',
            'grading_service_id': gradingServiceId,
            'sent_to_grader_date': today,
            'grading_fees':
                defaultFee, // override simple & consistent; tu peux éditer ensuite si besoin
            'psa_order_position': pos,
            'psa_order_added_at': addedAt,
          })
          .eq('org_id', orgId)
          .eq('id', id);
    }

    await _logBatchEdit(
      orgId: orgId,
      itemIds: itemIdsInOrder,
      changes: {
        'psa_order_id': {'old': null, 'new': psaOrderId},
        'status': {'old': 'received', 'new': 'sent_to_grader'},
        'grading_service_id': {'old': null, 'new': gradingServiceId},
        'sent_to_grader_date': {'old': null, 'new': today},
        'grading_fees': {'old': null, 'new': defaultFee},
        'psa_order_position': {'old': null, 'new': 'set'},
        'psa_order_added_at': {'old': null, 'new': addedAt},
      },
      reason: 'psa_add_to_order',
    );
  }

  Future<void> seedOrderPositions({
    required String orgId,
    required List<int> itemIdsInOrder,
    required int startPosition,
  }) async {
    if (itemIdsInOrder.isEmpty) return;

    for (var i = 0; i < itemIdsInOrder.length; i++) {
      final id = itemIdsInOrder[i];
      final pos = startPosition + i;
      await sb
          .from('item')
          .update({'psa_order_position': pos})
          .eq('org_id', orgId)
          .eq('id', id);
    }

    await _logBatchEdit(
      orgId: orgId,
      itemIds: itemIdsInOrder,
      changes: {
        'psa_order_position': {'old': null, 'new': 'set'},
      },
      reason: 'psa_seed_order_positions',
    );
  }

  Future<void> removeItemsFromOrder({
    required String orgId,
    required List<int> itemIds,
  }) async {
    if (itemIds.isEmpty) return;

    final idsCsv = _idsCsv(itemIds);

      await sb
          .from('item')
          .update({
            'psa_order_id': null,
            'status': 'received',
            'grading_service_id': null,
            'sent_to_grader_date': null,
            'at_grader_date': null,
            'graded_date': null,
            'grading_fees': null,
            'psa_order_position': null,
            'psa_order_added_at': null,
          })
          .eq('org_id', orgId)
          .filter('id', 'in', idsCsv);

    await _logBatchEdit(
      orgId: orgId,
      itemIds: itemIds,
        changes: {
          'psa_order_id': {'old': 'set', 'new': null},
          'status': {'old': 'in_order', 'new': 'received'},
          'grading_service_id': {'old': 'set', 'new': null},
          'sent_to_grader_date': {'old': 'set', 'new': null},
          'at_grader_date': {'old': 'set', 'new': null},
          'graded_date': {'old': 'set', 'new': null},
          'grading_fees': {'old': 'set', 'new': null},
          'psa_order_position': {'old': 'set', 'new': null},
          'psa_order_added_at': {'old': 'set', 'new': null},
        },
        reason: 'psa_remove_from_order',
      );
  }

  Future<void> deleteOrder({
    required String orgId,
    required int psaOrderId,
  }) async {
    final raw = await sb
        .from('item')
        .select('id')
        .eq('org_id', orgId)
        .eq('psa_order_id', psaOrderId)
        .limit(20000);

    final ids = raw.map((e) => (e as Map)['id']).whereType<int>().toList();
    if (ids.isNotEmpty) {
      await removeItemsFromOrder(orgId: orgId, itemIds: ids);
    }

    await sb
        .from('psa_order')
        .delete()
        .eq('org_id', orgId)
        .eq('id', psaOrderId);
  }

  Future<void> markOrderAtGrader({
    required String orgId,
    required int psaOrderId,
    required DateTime? psaReceivedDate,
  }) async {
    // collect ids to log
    final raw = await sb
        .from('item')
        .select('id')
        .eq('org_id', orgId)
        .eq('psa_order_id', psaOrderId)
        .eq('status', 'sent_to_grader')
        .limit(20000);

    final ids = raw.map((e) => (e as Map)['id']).whereType<int>().toList();
    if (ids.isEmpty) return;

    final d = _dateStr(psaReceivedDate ?? DateTime.now());
    final idsCsv = _idsCsv(ids);

    await sb
        .from('item')
        .update({
          'status': 'at_grader',
          'at_grader_date': d,
        })
        .eq('org_id', orgId)
        .filter('id', 'in', idsCsv);

    await _logBatchEdit(
      orgId: orgId,
      itemIds: ids,
      changes: {
        'status': {'old': 'sent_to_grader', 'new': 'at_grader'},
        'at_grader_date': {'old': null, 'new': d},
      },
      reason: 'psa_mark_at_grader',
    );
  }

  Future<void> markOrderGraded({
    required String orgId,
    required int psaOrderId,
  }) async {
    final raw = await sb
        .from('item')
        .select('id')
        .eq('org_id', orgId)
        .eq('psa_order_id', psaOrderId)
        .eq('status', 'at_grader')
        .limit(20000);

    final ids = raw.map((e) => (e as Map)['id']).whereType<int>().toList();
    if (ids.isEmpty) return;

    final today = _dateStr(DateTime.now());
    final idsCsv = _idsCsv(ids);

    await sb
        .from('item')
        .update({
          'status': 'graded',
          'graded_date': today,
        })
        .eq('org_id', orgId)
        .filter('id', 'in', idsCsv);

    await _logBatchEdit(
      orgId: orgId,
      itemIds: ids,
      changes: {
        'status': {'old': 'at_grader', 'new': 'graded'},
        'graded_date': {'old': null, 'new': today},
      },
      reason: 'psa_mark_graded',
    );
  }

  Future<void> updateItemGrade({
    required String orgId,
    required int itemId,
    required String? gradeId,
    required String? gradingNote,
  }) async {
    await sb
        .from('item')
        .update({
          'grade_id': (gradeId ?? '').trim().isEmpty ? null : gradeId!.trim(),
          'grading_note':
              (gradingNote ?? '').trim().isEmpty ? null : gradingNote!.trim(),
        })
        .eq('org_id', orgId)
        .eq('id', itemId);

    await _logBatchEdit(
      orgId: orgId,
      itemIds: [itemId],
      changes: {
        'grade_id': {'old': null, 'new': gradeId},
        'grading_note': {'old': null, 'new': gradingNote},
      },
      reason: 'psa_update_grade_fields',
    );
  }

  Future<void> _logBatchEdit({
    required String orgId,
    required List<int> itemIds,
    required Map<String, Map<String, dynamic>> changes,
    String? reason,
  }) async {
    if (changes.isEmpty) return;
    try {
      await sb.rpc('app_log_batch_edit', params: {
        'p_org_id': orgId,
        'p_item_ids': itemIds,
        'p_changes': changes,
        'p_reason': reason,
      });
    } catch (_) {
      // ignore log failures
    }
  }
}
