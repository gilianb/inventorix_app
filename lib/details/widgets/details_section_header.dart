// lib/details/widgets/details_section_header.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// A consistent, compact section header used across the Details page.
class DetailsSectionHeader extends StatelessWidget {
  const DetailsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tooltip,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? tooltip;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    final subtitleText = (subtitle ?? '').trim();

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    if (tooltip != null && tooltip!.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: tooltip!,
                        child: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: onSurface.withOpacity(.55),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitleText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withOpacity(.60),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
