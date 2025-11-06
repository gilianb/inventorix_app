// lib/public/public_line_page.dart
// Page publique : Titre pleine largeur • Image "carte" à gauche • Prix estimé à droite.
// - Pas d’auth requise
// - Responsive (deux colonnes en large, vertical en étroit)
// - Lien appelée via /public?org=...&g=...&s=...

// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublicLinePage extends StatefulWidget {
  const PublicLinePage({
    super.key,
    this.org,
    this.groupSig,
    this.status,
  });

  final String? org;
  final String? groupSig;
  final String? status;

  @override
  State<PublicLinePage> createState() => _PublicLinePageState();
}

class _PublicLinePageState extends State<PublicLinePage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // Données minimales pour l’affichage public
  String _title = '';
  String? _photoUrl;
  double? _estimated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Params éventuels transmis par l’URL
      final uri = Uri.base;
      final org = widget.org ?? uri.queryParameters['org'];
      final sig = widget.groupSig ?? uri.queryParameters['g'];
      final st = widget.status ?? uri.queryParameters['s'];

      if ((org == null || org.isEmpty) ||
          (sig == null || sig.isEmpty) ||
          (st == null || st.isEmpty)) {
        throw 'Lien invalide (org/g/s manquants).';
      }

      // Tente la vue agrégée, sinon fallback item+product
      Map<String, dynamic>? row;

      try {
        row = await _sb
            .from('v_item_groups')
            .select('product_name, photo_url, estimated_price')
            .eq('org_id', org)
            .eq('group_sig', sig)
            .eq('status', st)
            .limit(1)
            .maybeSingle();
      } catch (_) {
        // ignore
      }

      if (row == null) {
        final item = await _sb
            .from('item')
            .select('product_id, estimated_price, photo_url')
            .eq('org_id', org)
            .eq('group_sig', sig)
            .eq('status', st)
            .limit(1)
            .maybeSingle();

        if (item == null) throw 'Ressource introuvable (404).';

        final pid = (item['product_id'] as num?)?.toInt();
        Map<String, dynamic>? product;
        if (pid != null) {
          product = await _sb
              .from('product')
              .select('name, photo_url')
              .eq('id', pid)
              .maybeSingle();
        }

        row = {
          'product_name': product?['name']?.toString() ?? 'Produit',
          'photo_url': (item['photo_url'] ?? product?['photo_url'])?.toString(),
          'estimated_price':
              (item['estimated_price'] as num?)?.toDouble() ?? 0.0,
        };
      }

      _title = (row['product_name'] ?? '').toString();
      _photoUrl = (row['photo_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : (row['photo_url'] as String);
      _estimated = (row['estimated_price'] as num?)?.toDouble();

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Inventorix — Fiche publique'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: _PublicContent(
                          title: _title,
                          photoUrl: _photoUrl,
                          estimated: _estimated,
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _PublicContent extends StatelessWidget {
  const _PublicContent({
    required this.title,
    required this.photoUrl,
    required this.estimated,
  });

  final String title;
  final String? photoUrl;
  final double? estimated;

  static const String kFallbackAsset = 'assets/images/default_card.png';
  static const double kCardAspect = 0.72; // portrait

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (ctx, cons) {
        final wide = cons.maxWidth >= 900;

        // ---------- Titre pleine largeur ----------
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        // ---------- Image (gauche) ----------
        Widget buildCardImage() {
          // Hauteur “idéale” basée sur la largeur dispo
          final double maxW = wide ? (cons.maxWidth * 0.55) : cons.maxWidth;
          // limite haute pour éviter que ça dépasse trop la hauteur écran
          final screenH = MediaQuery.of(context).size.height;
          final idealH = maxW / kCardAspect;
          final cappedH = math.min(idealH, screenH * (wide ? 0.8 : 0.6));

          final imageProvider = (photoUrl == null || photoUrl!.isEmpty)
              ? const AssetImage(kFallbackAsset) as ImageProvider
              : NetworkImage(photoUrl!);

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              elevation: 6,
              shadowColor:
                  theme.colorScheme.shadow.withOpacity(0.25), // soft shadow
              borderRadius: BorderRadius.circular(20),
              child: Ink.image(
                image: imageProvider,
                fit: BoxFit.cover,
                width: maxW,
                height: cappedH,
              ),
            ),
          );
        }

        // ---------- Panneau Prix (droite) ----------
        Widget buildPricePanel() {
          return _PricePanel(
            value: estimated,
          );
        }

        if (wide) {
          // Disposition 2 colonnes
          return Column(
            children: [
              header,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image à gauche (grand)
                  Expanded(flex: 11, child: buildCardImage()),
                  const SizedBox(width: 16),
                  // Prix à droite
                  Expanded(flex: 9, child: buildPricePanel()),
                ],
              ),
            ],
          );
        } else {
          // Disposition verticale (mobile)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              buildCardImage(),
              const SizedBox(height: 16),
              buildPricePanel(),
            ],
          );
        }
      },
    );
  }
}

class _PricePanel extends StatelessWidget {
  const _PricePanel({required this.value});
  final double? value;

  String _formatUsd(double? v) {
    if (v == null) return '—';
    final s = v.toStringAsFixed(0);
    // Ajoute des séparateurs de milliers simples (1 234 567)
    final regex = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '${s.replaceAllMapped(regex, (m) => ' ')} USD';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceTxt = _formatUsd(value);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // joli gradient “carte prix”
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.12),
            theme.colorScheme.secondary.withOpacity(0.10),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge “Prix estimé”
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.trending_up,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Prix de vente estimé',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Montant en GROS
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                priceTxt,
                maxLines: 1,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Sous-texte
            Text(
              'Valeur indicative — données internes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 0.2,
              ),
            ),

            const Spacer(),

            // Petit bloc décoratif (tags)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipOutline(icon: Icons.shield_moon, label: 'Read-only'),
                _ChipOutline(icon: Icons.public, label: 'Public'),
                _ChipOutline(icon: Icons.currency_exchange, label: 'USD'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipOutline extends StatelessWidget {
  const _ChipOutline({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.16),
        ),
        color: theme.colorScheme.surface.withOpacity(0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16, color: theme.colorScheme.onSurface.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}
