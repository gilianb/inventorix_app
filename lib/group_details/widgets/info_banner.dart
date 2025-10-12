import 'package:flutter/material.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.qty,
    required this.purchaseDate,
  });

  final String title;
  final String subtitle;
  final int qty;
  final String? purchaseDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Text('$qty'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  if (subtitle.isNotEmpty) Text(subtitle),
                  if ((purchaseDate ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Chip(
                      avatar: const Icon(Icons.event, size: 18),
                      label: Text("Achat: $purchaseDate"),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
