import 'package:flutter/material.dart';

/// Ordre canonique des statuts
const kStatusOrder = <String>[
  'ordered',
  'in_transit',
  'paid',
  'received',
  'sent_to_grader',
  'at_grader',
  'graded',
  'listed',
  'sold',
  'shipped',
  'finalized',
  'collection',
];

/// Couleur associée à un statut
Color statusColor(BuildContext context, String s) {
  final cs = Theme.of(context).colorScheme;
  switch (s) {
    case 'ordered':
      return Colors.grey;
    case 'in_transit':
      return Colors.blueGrey;
    case 'paid':
      return Colors.teal;
    case 'received':
      return Colors.green;
    case 'sent_to_grader':
      return Colors.orange;
    case 'at_grader':
      return Colors.deepOrange;
    case 'graded':
      return Colors.amber;
    case 'listed':
      return Colors.blue;
    case 'sold':
      return Colors.purple;
    case 'shipped':
      return Colors.indigo;
    case 'finalized':
      return cs.primary;
    default:
      return cs.outline;
  }
}
