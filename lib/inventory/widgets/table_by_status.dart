// lib/inventory/widgets/table_by_status.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/status_utils.dart';
import '../utils/format.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

class InventoryTableByStatus extends StatelessWidget {
  const InventoryTableByStatus({
    super.key,
    required this.lines,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
    this.showDelete = true,
    this.showUnitCosts = true,
    this.showRevenue = true,
    this.showEstimated = true,
  });

  final List<Map<String, dynamic>> lines;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;
  final void Function(Map<String, dynamic>)? onDelete;

  /// Flags RBAC
  final bool showDelete; // suppr. ligne
  final bool showUnitCosts; // "Prix / u." + "Prix (Qté×u)"
  final bool showRevenue; // "Sale price"
  final bool showEstimated; // "Estimated /u."

  // dimensions “fixes”
  static const double _headH = 56;
  static const double _rowH = 56;
  static const double _sideW = 52;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

  // ---- TABLEAU CENTRAL (scrollé) ----
  DataRow _centerRow(BuildContext context, Map<String, dynamic> r) {
    final s = (r['status'] ?? '').toString();
    final q = (r['qty_status'] as int?) ?? 0;

    // Calculs de coûts (affichés seulement si showUnitCosts == true)
    final qtyTotal = (r['qty_total'] as num?) ?? 0;
    final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
    final unit = (qtyTotal > 0) ? (totalWithFees / qtyTotal) : 0;
    final sumUnitTotal = unit * q;

    final est = (r['estimated_price'] as num?);

    // ✅ Couleur de ligne conservée
    final lineColor = MaterialStateProperty.resolveWith<Color?>(
      (_) => statusColor(context, s).withOpacity(0.06),
    );

    final currency = (r['currency']?.toString() ?? 'USD');

    // Construit dynamiquement la liste des cellules (selon les flags)
    final cells = <DataCell>[
      // Photo
      DataCell(_FileCell(
        url: r['photo_url']?.toString(),
        isImagePreferred: true,
      )),

      // Grading note
      DataCell(Text(_txt(r['grading_note']))),

      // Colonnes principales
      DataCell(Text(r['product_name']?.toString() ?? '')),
      DataCell(Text(r['language']?.toString() ?? '')),
      DataCell(Text(r['game_label']?.toString() ?? '—')),
      DataCell(Text(r['purchase_date']?.toString() ?? '')),

      // Qté & statut
      DataCell(Text('$q')),
      DataCell(
        Chip(
          label: Text(s.toUpperCase()),
          backgroundColor: statusColor(context, s).withOpacity(0.15),
          side: BorderSide(color: statusColor(context, s).withOpacity(0.6)),
        ),
      ),
    ];

    // Colonnes coûts unitaires (optionnelles)
    if (showUnitCosts) {
      cells.addAll([
        DataCell(Text('${money(unit)} $currency')),
        DataCell(Text('${money(sumUnitTotal)} $currency')),
      ]);
    }

    // Estimated /u. (optionnelle via showEstimated)
    if (showEstimated) {
      cells.add(
        DataCell(Text(est == null ? '—' : '${money(est)} $currency')),
      );
    }

    // Divers
    cells.addAll([
      DataCell(Text(_txt(r['supplier_name']))),
      DataCell(Text(_txt(r['buyer_company']))),
      DataCell(Text(_txt(r['item_location']))),
      DataCell(Text(_txt(r['grade_id']))),
      DataCell(Text(_txt(r['sale_date']))),
    ]);

    // Sale price (optionnel via showRevenue)
    if (showRevenue) {
      final sale = r['sale_price'];
      final saleTxt = (sale == null) ? '—' : '${money(sale)} $currency';
      cells.add(DataCell(Text(saleTxt)));
    }

    // Tracking + Doc
    cells.addAll([
      DataCell(Text(_txt(r['tracking']))),
      DataCell(_FileCell(url: r['document_url']?.toString())),
    ]);

    return DataRow(
      color: lineColor,
      onSelectChanged: (_) => onOpen(r),
      cells: cells,
    );
  }

  // Couleur de fond d’une ligne (pour colonnes fixes)
  Color _rowBg(BuildContext ctx, Map<String, dynamic> r) {
    final s = (r['status'] ?? '').toString();
    return statusColor(ctx, s).withOpacity(0.06);
  }

  @override
  Widget build(BuildContext context) {
    // ------ Colonne fixe gauche (✏️) ------
    final fixedLeft = Column(
      children: [
        Container(
          width: _sideW,
          height: _headH,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.35),
          child: const Icon(Icons.edit, size: 18, color: Colors.black45),
        ),
        for (final r in lines)
          Container(
            width: _sideW,
            height: _rowH,
            color: _rowBg(context, r),
            alignment: Alignment.center,
            child: IconButton(
              tooltip: 'Éditer ce listing',
              icon: const Iconify(Mdi.pencil,
                  size: 20, color: Color.fromARGB(255, 34, 35, 36)),
              onPressed: onEdit == null ? null : () => onEdit!(r),
            ),
          ),
      ],
    );

    // ------ Colonne fixe droite (❌) — optionnelle ------
    final fixedRight = !showDelete
        ? const SizedBox.shrink()
        : Column(
            children: [
              Container(
                width: _sideW,
                height: _headH,
                alignment: Alignment.center,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(.35),
                child: const Icon(Icons.close, size: 18, color: Colors.black45),
              ),
              for (final r in lines)
                Container(
                  width: _sideW,
                  height: _rowH,
                  color: _rowBg(context, r),
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: 'Supprimer cette ligne',
                    icon: const Iconify(Mdi.close,
                        size: 18, color: Colors.redAccent),
                    onPressed: onDelete == null ? null : () => onDelete!(r),
                  ),
                ),
            ],
          );

    // ------ DataColumns dynamiques (selon flags) ------
    final columns = <DataColumn>[
      const DataColumn(label: Text('Photo')),
      const DataColumn(label: Text('Grading note')),
      const DataColumn(label: Text('Produit')),
      const DataColumn(label: Text('Langue')),
      const DataColumn(label: Text('Jeu')),
      const DataColumn(label: Text('Achat')),
      const DataColumn(label: Text('Qté')),
      const DataColumn(label: Text('Statut')),
      if (showUnitCosts) const DataColumn(label: Text('Prix / u.')),
      if (showUnitCosts) const DataColumn(label: Text('Prix (Qté×u)')),
      if (showEstimated) const DataColumn(label: Text('Estimated /u.')),
      const DataColumn(label: Text('Supplier')),
      const DataColumn(label: Text('Buyer')),
      const DataColumn(label: Text('Item location')),
      const DataColumn(label: Text('Grade ID')),
      const DataColumn(label: Text('Sale date')),
      if (showRevenue) const DataColumn(label: Text('Sale price')),
      const DataColumn(label: Text('Tracking')),
      const DataColumn(label: Text('Doc')),
    ];

    // ------ Tableau central ------
    final centerTable = DataTableTheme(
      data: const DataTableThemeData(
        headingRowHeight: _headH,
        dataRowMinHeight: _rowH,
        dataRowMaxHeight: _rowH,
      ),
      child: DataTable(
        showCheckboxColumn: false,
        columns: columns,
        rows: lines.map((r) => _centerRow(context, r)).toList(),
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fixedLeft, // ✏️
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: centerTable, // ⇦ scroll groupé pour toutes les lignes
              ),
            ),
            fixedRight, // ❌ (ou vide si showDelete == false)
          ],
        ),
      ),
    );
  }
}

/* ============== Cellule fichier/photo ============== */

class _FileCell extends StatelessWidget {
  const _FileCell({this.url, this.isImagePreferred = false});
  final String? url;
  final bool isImagePreferred;

  bool get _isImage {
    final u = url ?? '';
    if (u.isEmpty) return false;
    try {
      final path =
          Uri.parse(u).path.toLowerCase(); // ignore la query ?token=...
      return path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.gif') ||
          path.endsWith('.webp');
    } catch (_) {
      final lu = u.toLowerCase();
      return RegExp(r'\.(png|jpe?g|gif|webp)(\?.*)?$').hasMatch(lu);
    }
  }

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
      // URL corrigée/encodée
      final imgUrl = () {
        final u = url!;
        try {
          final uri = Uri.parse(u);
          final fixed = Uri(
            scheme: uri.scheme,
            userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            query: uri.query.isEmpty ? null : uri.query,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          ).toString();
          return fixed;
        } catch (_) {
          return Uri.encodeFull(u);
        }
      }();

      return InkWell(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            imgUrl,
            height: 32,
            width: 32,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            cacheWidth: 64,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 32,
                width: 32,
                child: Center(
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 32,
              width: 32,
              child: Icon(Icons.broken_image, size: 18),
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: const Iconify(Mdi.file_document),
      tooltip: 'Ouvrir le document',
      onPressed: _open,
    );
  }
}
