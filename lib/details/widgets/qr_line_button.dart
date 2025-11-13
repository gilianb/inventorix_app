// lib/details/widgets/qr_line_button.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

typedef QrCopyCallback = Future<void> Function(String link);

class QrLineButton extends StatelessWidget {
  final String? publicUrl;
  final String? appLink;
  final QrCopyCallback? onCopy;
  final bool _appBarStyle;

  const QrLineButton._({
    super.key,
    required this.publicUrl,
    required this.appLink,
    required this.onCopy,
    required bool appBarStyle,
  }) : _appBarStyle = appBarStyle;

  factory QrLineButton.appBar({
    Key? key,
    required String? publicUrl,
    required String? appLink,
    QrCopyCallback? onCopy,
  }) =>
      QrLineButton._(
        key: key,
        publicUrl: publicUrl,
        appLink: appLink,
        onCopy: onCopy,
        appBarStyle: true,
      );

  factory QrLineButton.inline({
    Key? key,
    required String? publicUrl,
    required String? appLink,
    QrCopyCallback? onCopy,
  }) =>
      QrLineButton._(
        key: key,
        publicUrl: publicUrl,
        appLink: appLink,
        onCopy: onCopy,
        appBarStyle: false,
      );

  @override
  Widget build(BuildContext context) {
    final enabled = publicUrl != null && publicUrl!.isNotEmpty;
    final onTap = enabled ? () => _showQrBottomSheet(context) : null;

    if (_appBarStyle) {
      return TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: onTap,
        icon: const Iconify(Mdi.qrcode),
        label: const Text('QR code'),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Iconify(Mdi.qrcode),
      label: const Text('QR code'),
    );
  }

  Future<void> _showQrBottomSheet(BuildContext ctx) async {
    final link = publicUrl;
    if (link == null || link.isEmpty) return;

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true, // <<< permet d'ouvrir grand
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final link = publicUrl!;

        return FractionallySizedBox(
          heightFactor: 0.9, // <<< occupe 90% écran
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  // <<< évite overflow vertical
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      Text('QR code (line)',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 16),
                      // Taille fixe du QR
                      QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 240,
                        gapless: true,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      // Le lien peut être long -> wrap activé
                      SelectableText(
                        link,
                        textAlign: TextAlign.center,
                        // forcer le wrap des très longues URLs
                        // (SelectableText wrappe si la largeur est contrainte)
                      ),
                      if (appLink != null && appLink!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          'App link: $appLink',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            icon: const Iconify(Mdi.open_in_new),
                            label: const Text('Open'),
                            onPressed: () async {
                              final uri = Uri.tryParse(link);
                              if (uri != null) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Iconify(Mdi.content_copy),
                            label: const Text('Copy'),
                            onPressed: () async {
                              if (onCopy != null) await onCopy!(link);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _QrFullScreen extends StatelessWidget {
  // ignore: unused_element_parameter
  const _QrFullScreen({required this.link, this.appLink, this.onCopy});
  final String link;
  final String? appLink;
  final QrCopyCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR code (line)')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 320,
                  gapless: true,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  link,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (appLink != null && appLink!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'App link: $appLink',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Iconify(Mdi.open_in_new),
                      label: const Text('Open'),
                      onPressed: () async {
                        final uri = Uri.tryParse(link);
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Iconify(Mdi.content_copy),
                      label: const Text('Copy'),
                      onPressed: () async {
                        if (onCopy != null) await onCopy!(link);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
