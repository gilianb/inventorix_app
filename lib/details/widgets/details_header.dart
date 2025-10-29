import 'package:flutter/material.dart';
import 'marge.dart';

/*Rôle : affiche le titre, sous-titre (jeu/langue/type),
 statut, quantité et la pastille de marge.*/

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);

class DetailsHeader extends StatelessWidget {
  const DetailsHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.qty,
    this.margin,
  });

  final String title;
  final String subtitle;
  final String status;
  final int qty;
  final num? margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0.8,
      color: cs.surface,
      // ignore: deprecated_member_use
      shadowColor: kAccentA.withOpacity(.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-1, 0),
            end: Alignment(1, 0),
            colors: [kAccentA, kAccentB],
          ).scale(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: kAccentA,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.inventory_2, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? 'Détails' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(status.toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                        backgroundColor: kAccentB,
                      ),
                      Chip(
                        avatar: const Icon(Icons.format_list_numbered,
                            size: 16, color: Colors.white),
                        label: Text('Qté : $qty',
                            style: const TextStyle(color: Colors.white)),
                        backgroundColor: kAccentC,
                      ),
                      Tooltip(
                        message:
                            margin == null ? 'Not sold yet' : 'Marge moyenne',
                        child: MarginChip(marge: margin),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
