import 'package:flutter/material.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.moves});
  final List<Map<String, dynamic>> moves;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historique', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...moves.map((m) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.change_circle_outlined),
                  title: Text('${m['mtype']}  •  ${m['qty']} u'),
                  subtitle: Text([
                    m['ts'],
                    '${m['from_status']} → ${m['to_status']}',
                    if (m['channel']?['code'] != null) m['channel']!['code'],
                    if (m['unit_price'] != null)
                      '${(m['unit_price'] as num).toStringAsFixed(2)} ${m['currency'] ?? ''}',
                    if (m['fees'] != null)
                      'Frais: ${(m['fees'] as num).toStringAsFixed(2)}',
                    if (m['note'] != null) 'Note: ${m['note']}',
                  ]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' | ')),
                )),
          ],
        ),
      ),
    );
  }
}
