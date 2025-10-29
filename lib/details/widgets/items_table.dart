// ignore_for_file: deprecated_member_use
/*Rôle : affiche la table DataTable avec colonnes statut, grading,
 prix, marge (%) via MarginChip, tracking, etc.*/
import 'package:flutter/material.dart';
import 'marge.dart';
import 'package:url_launcher/url_launcher.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class ItemsTable extends StatelessWidget {
  const ItemsTable({super.key, required this.items, required this.currency});
  final List<Map<String, dynamic>> items;
  final String currency;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();
  String _m(num? n) => n == null ? '—' : n.toDouble().toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Text('Aucun item dans ce groupe.',
          style: Theme.of(context).textTheme.bodyMedium);
    }

    return Card(
      elevation: 0.6,
      color: cs.surface,
      shadowColor: kAccentA.withOpacity(.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 42,
            dataRowMinHeight: 44,
            columnSpacing: 20,
            headingRowColor:
                MaterialStateProperty.all(kAccentA.withOpacity(.08)),
            headingTextStyle: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            dividerThickness: .6,
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Grade ID')),
              DataColumn(label: Text('Grade note')),
              DataColumn(label: Text('Grading fees')),
              DataColumn(label: Text('Est.')),
              DataColumn(label: Text('Sale')),
              DataColumn(label: Text('Marge')),
              DataColumn(label: Text('Tracking')),
              DataColumn(label: Text('Buyer')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Photo')),
              DataColumn(label: Text('Doc')),
            ],
            rows: List<DataRow>.generate(items.length, (i) {
              final r = items[i];
              final est = (r['estimated_price'] as num?);
              final sale = (r['sale_price'] as num?);
              final marge = (r['marge'] as num?);

              final s = (r['status'] ?? '').toString();
              final photo = (r['photo_url'] ?? '').toString();
              final doc = (r['document_url'] ?? '').toString();
              final bg = (i % 2 == 0) ? cs.surface : cs.surfaceContainerHighest;
              return DataRow(
                color: MaterialStateProperty.all(bg.withOpacity(.50)),
                cells: [
                  DataCell(Text('${r['id']}')),
                  DataCell(Chip(
                    label: Text(s.toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                    backgroundColor: _statusColor(s),
                  )),
                  DataCell(Text(_txt(r['grade_id']))),
                  DataCell(Text(_txt(r['grading_note']))),
                  DataCell(Text(_txt(r['grading_fees']))),
                  DataCell(Text(est == null ? '—' : '${_m(est)} $currency')),
                  DataCell(Text(sale == null ? '—' : '${_m(sale)} $currency')),
                  DataCell(MarginChip(marge: marge)),
                  DataCell(Text(_txt(r['tracking']))),
                  DataCell(Text(_txt(r['buyer_company']))),
                  DataCell(Text(_txt(r['supplier_name']))),
                  DataCell(_MiniLinkIcon(url: photo, icon: Icons.photo)),
                  DataCell(_MiniLinkIcon(url: doc, icon: Icons.description)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Couleur de chip par statut (visuel uniquement)
  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'received':
        return kAccentB;
      case 'listed':
        return kAccentA;
      case 'sold':
      case 'shipped':
      case 'finalized':
        return const Color(0xFF22C55E); // green
      case 'in_transit':
        return const Color(0xFF3B82F6); // blue
      case 'at_grader':
      case 'graded':
        return const Color(0xFFa855f7); // purple
      default:
        return kAccentC; // amber
    }
  }
}

class _MiniLinkIcon extends StatelessWidget {
  const _MiniLinkIcon({required this.url, required this.icon});
  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const Text('—');
    return IconButton(
      tooltip: 'Ouvrir',
      icon: Icon(icon, color: kAccentA),
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
