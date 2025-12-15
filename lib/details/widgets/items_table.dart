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
  const ItemsTable({
    super.key,
    required this.items,
    required this.currency,
    required this.showMargins,
  });

  final List<Map<String, dynamic>> items;
  final String currency;
  final bool showMargins;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();
  String _m(num? n) => n == null ? '—' : n.toDouble().toStringAsFixed(2);

  // ---- helpers marge dérivée (même logique que header/InfoExtras) ----
  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _saleCurrencyOf(Map<String, dynamic> r) {
    final v = _txt(
      r['sale_currency'] ?? r['sale_price_currency'] ?? r['sale_currency_code'],
    );
    return (v == '—' || v.trim().isEmpty) ? currency : v.trim();
  }

  /// Calcule une marge % à l’affichage si `marge` est null.
  /// ⚠️ Multi-devise : on ne dérive pas si sale_currency != currency (coûts).
  num? _derivedMarginPct(Map<String, dynamic> r) {
    final num? m = _asNum(r['marge']);
    if (m != null) return m;

    final saleCurrency = _saleCurrencyOf(r);
    final bool sameCurrencyForMargin = (saleCurrency == currency);
    if (!sameCurrencyForMargin) return null;

    final num? sale = _asNum(r['sale_price']);
    final num cost =
        (_asNum(r['unit_cost']) ?? 0) + (_asNum(r['unit_fees']) ?? 0);
    final num fees = (_asNum(r['shipping_fees']) ?? 0) +
        (_asNum(r['commission_fees']) ?? 0) +
        (_asNum(r['grading_fees']) ?? 0);
    final num invested = cost + fees;

    if (sale != null && invested > 0) {
      return ((sale - invested) / invested) * 100;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Text('No items in this group.',
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
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Grade ID')),
              DataColumn(label: Text('Grading note')),
              DataColumn(label: Text('Grading fees')),
              DataColumn(label: Text('Est. price')),
              DataColumn(label: Text('Sale')),
              DataColumn(label: Text('Margin')),
              DataColumn(label: Text('Tracking')),
              DataColumn(label: Text('Buyer')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Photo')),
              DataColumn(label: Text('Document')),
            ],
            rows: List<DataRow>.generate(items.length, (i) {
              final r = items[i];
              final est = (r['estimated_price'] as num?);
              final sale = (r['sale_price'] as num?);

              // ✅ devise de vente (multi-devise)
              final saleCurrency = _saleCurrencyOf(r);

              // ✅ marge affichée = marge DB ou marge dérivée (si mêmes devises)
              final num? margeDisplay = _derivedMarginPct(r);

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

                  // ✅ sale affiché avec sa devise
                  DataCell(
                      Text(sale == null ? '—' : '${_m(sale)} $saleCurrency')),

                  if (showMargins)
                    DataCell(MarginChip(marge: margeDisplay))
                  else
                    const DataCell(Text('—')),
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
      case 'ordered':
        return Colors.grey;
      case 'paid':
        return Colors.teal;
      case 'in_transit':
        return Colors.blueGrey;
      case 'received':
        return Colors.green;
      case 'waiting_for_gradation':
        return Colors.orangeAccent;
      case 'sent_to_grader':
        return Colors.orange;
      case 'at_grader':
        return Colors.deepOrange;
      case 'graded':
        return const Color.fromARGB(255, 255, 7, 164);
      case 'listed':
        return Colors.blue;
      case 'awaiting_payment':
        return const Color.fromARGB(255, 11, 206, 245);
      case 'sold':
        return Colors.purple;
      case 'shipped':
        return Colors.indigo;
      case 'finalized':
        return const Color.fromARGB(255, 7, 76, 9);
      default:
        return const Color.fromARGB(255, 235, 231, 231);
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
      tooltip: 'Open',
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
