// lib/details/widgets/marge.dart
import 'package:flutter/material.dart';

/// Pastille de marge (en %).
/// - null  -> gris + "Not sold yet"
/// - < 0   -> noir
/// - 0–30  -> rouge
/// - 30–60 -> orange
/// - 60+   -> vert
class MarginChip extends StatelessWidget {
  const MarginChip({
    super.key,
    required this.marge,
    this.compact = false,
  });

  final num? marge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = marge;

    if (m == null) {
      return Chip(
        avatar:
            const Icon(Icons.hourglass_empty, size: 16, color: Colors.white),
        label:
            const Text('Not sold yet', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.grey,
      );
    }

    final color = _colorFor(m);
    final text = _format(m);

    return Chip(
      avatar: const Icon(Icons.percent, size: 16, color: Colors.white),
      label: Text(
        text,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: color,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
      visualDensity:
          compact ? const VisualDensity(horizontal: -2, vertical: -2) : null,
    );
  }

  String _format(num m) {
    // Affichage propre : entiers pour valeurs "propres", sinon 1 décimale
    final d = m.toDouble();
    final isInt = d == d.roundToDouble();
    return isInt ? '${d.toStringAsFixed(0)}%' : '${d.toStringAsFixed(1)}%';
  }

  Color _colorFor(num m) {
    if (m < 0) return Colors.black;
    if (m < 30) return Colors.redAccent;
    if (m < 60) return Colors.orangeAccent;
    return Colors.green;
  }
}
