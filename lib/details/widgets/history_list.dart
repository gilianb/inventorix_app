import 'package:flutter/material.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.movements});
  final List<Map<String, dynamic>> movements;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.toString().trim().isEmpty))
          ? '—'
          : v.toString();

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return Text('Aucun mouvement.',
          style: Theme.of(context).textTheme.bodyMedium);
    }

    return Column(
      children: movements.map((m) {
        final ts = _txt(m['ts']);
        final mtype = _txt(m['mtype']);
        final from = _txt(m['from_status']);
        final to = _txt(m['to_status']);
        final qty = m['qty'] ?? 0;
        final note = _txt(m['note']);
        return Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text('$mtype  •  $ts'),
            subtitle: Text('De: $from  →  À: $to\nQté: $qty\nNote: $note'),
          ),
        );
      }).toList(),
    );
  }
}
