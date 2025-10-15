import 'package:flutter/material.dart';
import '../utils/status_utils.dart';
import '../utils/format.dart';
import 'package:url_launcher/url_launcher.dart';

class InventoryTableByStatus extends StatelessWidget {
  const InventoryTableByStatus({
    super.key,
    required this.lines,
    required this.onOpen,
    this.onEdit, // <-- edit déjà présent
  });

  /// Lignes déjà agrégées par statut :
  /// - product_name, language, game_label, purchase_date, currency
  /// - status (String), qty_status (int)
  /// - total_cost_with_fees, qty_total  (pour calculer le coût total du statut)
  /// - + opt : estimated_price, supplier_name, buyer_company, notes, grade_id,
  ///           sale_date, sale_price, tracking, photo_url, document_url
  final List<Map<String, dynamic>> lines;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

  @override
  Widget build(BuildContext context) {
    DataRow row(Map<String, dynamic> r) {
      final s = (r['status'] ?? '').toString();
      final q = (r['qty_status'] as int?) ?? 0;

      // coût total pour CE statut (fallback si la vue ne fournit pas sum_unit_total)
      final qtyTotal = (r['qty_total'] as num?) ?? 0;
      final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
      final unit = qtyTotal > 0 ? (totalWithFees / qtyTotal) : 0;
      final sumUnitTotal = unit * q;

      final lineColor = WidgetStateProperty.resolveWith<Color?>(
        // ignore: deprecated_member_use
        (states) => statusColor(context, s).withOpacity(0.06),
      );

      final est = (r['estimated_price'] as num?);

      return DataRow(
        color: lineColor,
        onSelectChanged: (_) => onOpen(r),
        cells: [
          // === 1ère cellule: bouton Edit ===
          DataCell(IconButton(
            tooltip: 'Éditer ce listing',
            icon: const Icon(Icons.edit),
            onPressed: onEdit == null ? null : () => onEdit!(r),
          )),

          // Colonnes principales
          DataCell(Text(r['product_name']?.toString() ?? '')),
          DataCell(Text(r['language']?.toString() ?? '')),
          DataCell(Text(r['game_label']?.toString() ?? '—')),
          DataCell(Text(r['purchase_date']?.toString() ?? '')),
          DataCell(Text('$q')), // Qté de CE statut
          DataCell(
            Chip(
              label: Text(s.toUpperCase()),
              // ignore: deprecated_member_use
              backgroundColor: statusColor(context, s).withOpacity(0.15),
              // ignore: deprecated_member_use
              side: BorderSide(color: statusColor(context, s).withOpacity(0.6)),
            ),
          ),
          // Prix / unité & Prix (Qté×u)
          DataCell(Text('${money(unit)} ${r['currency'] ?? 'USD'}')),
          DataCell(Text('${money(sumUnitTotal)} ${r['currency'] ?? 'USD'}')),

          // === Remplacement: Channel -> Estimated ===
          DataCell(
            Text(est == null ? '—' : '${money(est)} ${r['currency'] ?? 'USD'}'),
          ),

          // Champs additionnels (échantillon item)
          DataCell(Text(_txt(r['supplier_name']))),
          DataCell(Text(_txt(r['buyer_company']))),
          DataCell(Text(_txt(r['grade_id']))),
          DataCell(Text(_txt(r['sale_date']))),
          DataCell(Text(_txt(r['sale_price']))),
          DataCell(Text(_txt(r['tracking']))),
          DataCell(_FileCell(
              url: r['photo_url']?.toString(), isImagePreferred: true)),
          DataCell(_FileCell(url: r['document_url']?.toString())),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Icon(Icons.edit)), // colonne edit
          DataColumn(label: Text('Produit')),
          DataColumn(label: Text('Langue')),
          DataColumn(label: Text('Jeu')),
          DataColumn(label: Text('Achat')),
          DataColumn(label: Text('Qté')),
          DataColumn(label: Text('Statut')),
          DataColumn(label: Text('Prix / u.')),
          DataColumn(label: Text('Prix (Qté×u)')),
          // ⬇️ ICI : Channel -> Estimated
          DataColumn(label: Text('Estimated')),
          DataColumn(label: Text('Supplier')),
          DataColumn(label: Text('Buyer')),
          DataColumn(label: Text('Grade ID')),
          DataColumn(label: Text('Sale date')),
          DataColumn(label: Text('Sale price')),
          DataColumn(label: Text('Tracking')),
          DataColumn(label: Text('Photo')),
          DataColumn(label: Text('Doc')),
        ],
        rows: lines.map(row).toList(),
      ),
    );
  }
}

class _FileCell extends StatelessWidget {
  const _FileCell({this.url, this.isImagePreferred = false});
  final String? url;
  final bool isImagePreferred;

  bool get _isImage =>
      (url ?? '').toLowerCase().contains(RegExp(r'\.(png|jpe?g|gif|webp)$'));

  Future<void> _open() async {
    final u = url;
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const Text('—');

    final showImage = isImagePreferred && _isImage;

    if (showImage) {
      return InkWell(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            url!,
            height: 32,
            width: 32,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => IconButton(
              icon: const Icon(Icons.photo),
              onPressed: _open,
              tooltip: 'Ouvrir la photo',
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.description),
      tooltip: 'Ouvrir le document',
      onPressed: _open,
    );
  }
}
