import 'package:flutter/material.dart';
import '../utils/format.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.moves});
  final List<Map<String, dynamic>> moves;

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Aucun mouvement'),
        ),
      );
    }
    return Card(
      elevation: 0,
      child: Column(
        children: moves.map((m) {
          final ts = (m['ts'] ?? '').toString();
          final fs = (m['from_status'] ?? '').toString();
          final ts2 = (m['to_status'] ?? '').toString();
          final qty = (m['qty'] ?? 1).toString();
          final note = (m['note'] ?? '').toString();
          final price = m['unit_price'] == null
              ? ''
              : ' • ${money(m['unit_price'])} ${(m['currency'] ?? '')}';
          final fees = m['fees'] == null ? '' : ' • frais ${money(m['fees'])}';
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(
                fs.isEmpty && ts2.isEmpty ? 'Mouvement' : '$fs → $ts2 ($qty)'),
            subtitle: Text([ts, price, fees, if (note.isNotEmpty) ' • $note']
                .where((e) => e.isNotEmpty)
                .join('')),
          );
        }).toList(),
      ),
    );
  }
}
