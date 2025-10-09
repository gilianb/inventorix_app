import 'package:flutter/material.dart';

class InfoExtrasCard extends StatelessWidget {
  const InfoExtrasCard({
    super.key,
    required this.photoUrl,
    required this.documentUrl,
    required this.notes,
    required this.onShowDocSnack,
    this.saleInfoText,
  });

  final String photoUrl;
  final String documentUrl;
  final String notes;
  final void Function(String) onShowDocSnack;
  final String? saleInfoText;

  @override
  Widget build(BuildContext context) {
    final hasAnything = photoUrl.isNotEmpty ||
        documentUrl.isNotEmpty ||
        notes.isNotEmpty ||
        saleInfoText != null;
    if (!hasAnything) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Infos complémentaires',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (photoUrl.isNotEmpty)
                  ActionChip(
                    label: const Text('Photo'),
                    avatar: const Icon(Icons.photo),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          content: Image.network(photoUrl, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                if (documentUrl.isNotEmpty)
                  ActionChip(
                    label: const Text('Document'),
                    avatar: const Icon(Icons.attach_file),
                    onPressed: () => onShowDocSnack('Document: $documentUrl'),
                  ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notes: $notes'),
            ],
            if (saleInfoText != null) ...[
              const SizedBox(height: 8),
              Text(saleInfoText!),
            ],
          ],
        ),
      ),
    );
  }
}
