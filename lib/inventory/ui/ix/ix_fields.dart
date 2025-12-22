// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'ix_tokens.dart';

InputDecoration ixDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withOpacity(.72),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: IxRadii.r14,
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: IxRadii.r14,
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: IxRadii.r14,
      borderSide: BorderSide(color: cs.primary.withOpacity(.85), width: 1.4),
    ),
  );
}

class IxDropdownField<T> extends StatelessWidget {
  const IxDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.leading,
    this.width,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? labelText;
  final String? hintText;
  final Widget? leading;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: ixDecoration(
        context,
        labelText: labelText,
        hintText: hintText,
        prefixIcon: leading,
      ),
    );

    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}

class IxHint extends StatelessWidget {
  const IxHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: cs.onSurfaceVariant),
    );
  }
}
