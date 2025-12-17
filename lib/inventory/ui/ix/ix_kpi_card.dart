import 'package:flutter/material.dart';
import 'ix_tokens.dart';

class IxKpiCard extends StatelessWidget {
  const IxKpiCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.value,
    this.subtitle,
    this.badge,
    this.gradient,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final Widget value;
  final String? subtitle;
  final Widget? badge;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = gradient ??
        <Color>[
          accent.withOpacity(.12),
          cs.surface.withOpacity(.02),
        ];

    return Card(
      elevation: 1,
      shadowColor: accent.withOpacity(.18),
      shape: RoundedRectangleBorder(borderRadius: IxRadii.r16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: IxRadii.r16,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g,
          ),
          border: Border.all(color: accent.withOpacity(.20), width: 0.9),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(icon, size: 20, color: Colors.white),
                  ),
                  if (badge != null)
                    Positioned(right: -6, top: -6, child: badge!),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ) ??
                              const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800),
                      child: value,
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IxBadgeDot extends StatelessWidget {
  const IxBadgeDot({super.key, this.color, this.tooltip});
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.redAccent;
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
    if ((tooltip ?? '').isEmpty) return dot;
    return Tooltip(message: tooltip!, child: dot);
  }
}
