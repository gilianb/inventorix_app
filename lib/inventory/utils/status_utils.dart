import 'package:flutter/material.dart';

/// Ordre canonique des statuts
const kStatusOrder = <String>[
  'ordered',
  'paid',
  'in_transit',
  'received',
  'waiting_for_gradation', // ← AJOUT ICI
  'sent_to_grader',
  'at_grader',
  'graded',
  'listed',
  'awaiting_payment', // ← AJOUT ICI (entre listed et sold)
  'sold',
  'shipped',
  'finalized',
  'vault',
];

/// Couleur associée à un statut
Color statusColor(BuildContext context, String s) {
  final cs = Theme.of(context).colorScheme;
  switch (s) {
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
      return const Color.fromARGB(
          255, 11, 206, 245); // amber-ish / ou ta palette
    case 'sold':
      return Colors.purple;
    case 'shipped':
      return Colors.indigo;
    case 'finalized':
      return const Color.fromARGB(255, 7, 76, 9);
    case 'vault':
      return const Color.fromARGB(255, 245, 228, 3);
    default:
      return cs.outline;
  }
}
