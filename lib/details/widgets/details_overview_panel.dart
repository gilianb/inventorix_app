// lib/details/widgets/details_overview_panel.dart
import 'package:flutter/material.dart';

const kAccentA = Color(0xFF6C5CE7); // violet
const kAccentB = Color(0xFF00D1B2); // menthe

/// Responsive layout helper for the Details page.
///
/// - Wide (>= breakpoint): left side panel + right content column
/// - Narrow: stack everything in a single column
class DetailsOverviewPanel extends StatelessWidget {
  const DetailsOverviewPanel({
    super.key,
    required this.mediaThumb,
    required this.invoiceButtons,
    required this.qrRow,
    required this.publicPreviewButton,
    required this.showFinance,
    required this.finance,
    required this.infoCard,
    this.breakpoint = 760,
    this.sideWidth = 330,
  });

  final Widget mediaThumb;
  final Widget invoiceButtons;
  final Widget qrRow;
  final Widget publicPreviewButton;

  final bool showFinance;
  final Widget finance;
  final Widget infoCard;

  final double breakpoint;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final wide = cons.maxWidth >= breakpoint;

        final side = SizedBox(
          width: wide ? sideWidth : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              mediaThumb,
              const SizedBox(height: 8),
              _LinksCard(
                invoiceButtons: invoiceButtons,
                qrRow: qrRow,
                publicPreviewButton: publicPreviewButton,
              ),
            ],
          ),
        );

        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showFinance) finance,
            if (showFinance) const SizedBox(height: 12),
            infoCard,
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side,
              const SizedBox(width: 12),
              Expanded(child: main),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            side,
            const SizedBox(height: 12),
            main,
          ],
        );
      },
    );
  }
}

class _LinksCard extends StatelessWidget {
  const _LinksCard({
    required this.invoiceButtons,
    required this.qrRow,
    required this.publicPreviewButton,
  });

  final Widget invoiceButtons;
  final Widget qrRow;
  final Widget publicPreviewButton;

  bool get _hasInvoiceButtons => invoiceButtons is! SizedBox;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shadowColor: kAccentA.withOpacity(.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccentA.withOpacity(.06), kAccentB.withOpacity(.05)],
          ),
          border: Border.all(color: kAccentA.withOpacity(.15), width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documents & share',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),

              if (_hasInvoiceButtons) ...[
                invoiceButtons,
                const SizedBox(height: 10),
              ],

              qrRow,
              const SizedBox(height: 4),
              publicPreviewButton,
            ],
          ),
        ),
      ),
    );
  }
}
