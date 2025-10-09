import 'package:flutter/material.dart';

class TextFormFieldController {
  TextFormFieldController(String initial)
      : _c = TextEditingController(text: initial);
  final TextEditingController _c;
  String value() => _c.text.trim();
  Widget build({
    required String label,
    required TextInputType keyboard,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: _c,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: validator,
    );
  }
}

class DateInline extends StatelessWidget {
  const DateInline({
    super.key,
    required this.label,
    required this.date,
    required this.onPick,
  });
  final String label;
  final DateTime? date;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final txt = date == null ? '—' : date!.toIso8601String().split('T').first;
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Date', border: OutlineInputBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$label: $txt'),
              const Icon(Icons.calendar_today, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
