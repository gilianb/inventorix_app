import 'package:flutter/material.dart';

/*Champ date cliquable réutilisable (affiche la date, 
déclenche le showDatePicker via un callback).*/

class DateField extends StatelessWidget {
  const DateField(
      {super.key,
      required this.label,
      required this.date,
      required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final txt = date.toIso8601String().split('T').first;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('$label: $txt'),
        ),
      ),
    );
  }
}
