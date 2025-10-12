import 'package:flutter/material.dart';
import '../utils/status_utils.dart';
import '../utils/format.dart';

class InventoryTableByStatus extends StatelessWidget {
  const InventoryTableByStatus({
    super.key,
    required this.lines,
    required this.onOpen,
  });

  /// Lignes déjà agrégées par statut, issues de v_items_by_status :
  /// - product_name, language, game_label, purchase_date, currency
  /// - status (String), qty_status (int)
  /// - sum_unit_total (num)  => somme (unit_cost+unit_fees) des items de ce statut
  /// - + opt : channel_id, supplier_name, buyer_company, notes, grade,
  ///           grading_submission_id, sale_date, sale_price, tracking,
  ///           photo_url, document_url, estimated_price_avg
  final List<Map<String, dynamic>> lines;
  final void Function(Map<String, dynamic>) onOpen;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

  @override
  Widget build(BuildContext context) {
    DataRow row(Map<String, dynamic> r) {
      final s = (r['status'] ?? '').toString();
      final q = (r['qty_status'] as int?) ?? 0;

      final sumUnitTotal =
          (r['sum_unit_total'] as num?) ?? 0; // coût total de CE statut
      final unit = q > 0 ? (sumUnitTotal / q) : 0;

      final lineColor = WidgetStateProperty.resolveWith<Color?>(
        (states) => statusColor(context, s).withOpacity(0.06),
      );

      return DataRow(
        color: lineColor,
        onSelectChanged: (_) => onOpen(r),
        cells: [
          DataCell(Text(r['product_name']?.toString() ?? '')),
          DataCell(Text(r['language']?.toString() ?? '')),
          DataCell(Text(r['game_label']?.toString() ?? '—')),
          DataCell(Text(r['purchase_date']?.toString() ?? '')),
          DataCell(Text('$q')), // Qté de CE statut
          DataCell(
            Chip(
              label: Text(s.toUpperCase()),
              backgroundColor: statusColor(context, s).withOpacity(0.15),
              side: BorderSide(color: statusColor(context, s).withOpacity(0.6)),
            ),
          ),
          // Prix / unité & Prix (Qté×u)
          DataCell(Text('${money(unit)} ${r['currency'] ?? 'USD'}')),
          DataCell(Text('${money(sumUnitTotal)} ${r['currency'] ?? 'USD'}')),

          // Champs additionnels
          DataCell(Text(_txt(r['channel_id']))),
          DataCell(Text(_txt(r['supplier_name']))),
          DataCell(Text(_txt(r['buyer_company']))),
          DataCell(Text(_txt(r['grade']))),
          DataCell(Text(_txt(r['grading_submission_id']))),
          DataCell(Text(_txt(r['sale_date']))),
          DataCell(Text(_txt(r['sale_price']))),
          DataCell(Text(_txt(r['tracking']))),
          DataCell(Text(_txt(r['notes']))),
          DataCell(Text(_txt(r['photo_url']))),
          DataCell(Text(_txt(r['document_url']))),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Produit')),
          DataColumn(label: Text('Langue')),
          DataColumn(label: Text('Jeu')),
          DataColumn(label: Text('Achat')),
          DataColumn(label: Text('Qté')),
          DataColumn(label: Text('Statut')),
          DataColumn(label: Text('Prix / u.')),
          DataColumn(label: Text('Prix (Qté×u)')),
          DataColumn(label: Text('Channel')),
          DataColumn(label: Text('Supplier')),
          DataColumn(label: Text('Buyer')),
          DataColumn(label: Text('Grade')),
          DataColumn(label: Text('Sub. id')),
          DataColumn(label: Text('Sale date')),
          DataColumn(label: Text('Sale price')),
          DataColumn(label: Text('Tracking')),
          DataColumn(label: Text('Notes')),
          DataColumn(label: Text('Photo')),
          DataColumn(label: Text('Doc')),
        ],
        rows: lines.map(row).toList(),
      ),
    );
  }
}
