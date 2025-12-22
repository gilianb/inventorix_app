// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'ix_tokens.dart';

/// A “premium” card shell:
/// - soft gradient background
/// - subtle border
/// - optional decorative bubbles
/// - supports InkWell if onTap != null
class IxCard extends StatelessWidget {
  const IxCard({
    super.key,
    required this.child,
    this.padding = IxSpace.card,
    this.onTap,
    this.elevation = 1,
    this.borderRadius = IxRadii.r16,
    this.gradient,
    this.borderColor,
    this.showDecorations = true,
    this.shadowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double elevation;
  final BorderRadius borderRadius;
  final List<Color>? gradient;
  final Color? borderColor;
  final bool showDecorations;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final g = gradient ??
        <Color>[
          cs.surface,
          cs.surface,
        ];

    final stroke = borderColor ?? cs.outlineVariant.withOpacity(.45);

    final content = Ink(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g,
        ),
        borderRadius: borderRadius,
        border: Border.all(color: stroke, width: 0.9),
      ),
      child: Stack(
        children: [
          if (showDecorations) ..._decorations(),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    return Card(
      elevation: elevation,
      shadowColor: shadowColor ?? IxColors.violet.withOpacity(.16),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }

  List<Widget> _decorations() {
    // subtle background bubbles
    return [
      Positioned(
        right: -30,
        top: -30,
        child: _bubble(IxColors.violet.withOpacity(.10), 120),
      ),
      Positioned(
        left: -40,
        bottom: -40,
        child: _bubble(IxColors.mint.withOpacity(.10), 140),
      ),
    ];
  }

  Widget _bubble(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
