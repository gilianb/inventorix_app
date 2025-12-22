// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'ix_tokens.dart';

class IxPill extends StatelessWidget {
  const IxPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;

    final child = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: IxRadii.r999,
        color: c.withOpacity(.10),
        border: Border.all(color: c.withOpacity(.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      borderRadius: IxRadii.r999,
      onTap: onTap,
      child: child,
    );
  }
}
