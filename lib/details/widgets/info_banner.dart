import 'package:flutter/material.dart';

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.onTap,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      // ignore: deprecated_member_use
      color: cs.primaryContainer.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
              if (onTap != null) const Icon(Icons.open_in_new, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
