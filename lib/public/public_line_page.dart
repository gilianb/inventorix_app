// lib/public/public_line_page.dart
// Page publique minimaliste : Titre • Image • Prix estimé.
// - Pas d’auth requise
// - Responsive + scroll (pas d’overflow)
// - Lien appelée via /public?org=...&g=...&s=...

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
      // On récupère d’abord les params éventuellement fournis par la route web.
      final uri = Uri.base;
      final org = widget.org ?? uri.queryParameters['org'];
      final sig = widget.groupSig ?? uri.queryParameters['g'];
      final st = widget.status ?? uri.queryParameters['s'];

      if ((org == null || org.isEmpty) ||
          (sig == null || sig.isEmpty) ||
          (st == null || st.isEmpty)) {
        throw 'Lien invalide (org/g/s manquants).';
      }

      // On tente d’obtenir une vue agrégée s’il y en a une,
      // sinon on retombe sur item/product.
      Map<String, dynamic>? row;

      try {
        // v_item_groups (si dispo) — 1 ligne suffit
        row = await _sb
            .from('v_item_groups')
            .select('product_name, photo_url, estimated_price')
            .eq('org_id', org)
            .eq('group_sig', sig)
            .eq('status', st)
            .limit(1)
            .maybeSingle();
      } catch (_) {
        // Ignorer et fallback
      }

      if (row == null) {
        // Fallback : n’importe quel item de cette ligne
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
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
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
    final mq = MediaQuery.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Titre
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),

        const SizedBox(height: 16),

        // Image responsive sans overflow (hauteur cappée)
        LayoutBuilder(
          builder: (ctx, cons) {
            final maxW = cons.maxWidth; // <= 820
            final screenH = mq.size.height;
            final idealH = maxW / kCardAspect;
            final cappedH = math.min(idealH, screenH * 0.60); // cap 60% écran

            final img = (photoUrl == null || photoUrl!.isEmpty)
                ? Image.asset(
                    kFallbackAsset,
                    fit: BoxFit.cover,
                  )
                : Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        Image.asset(kFallbackAsset, fit: BoxFit.cover),
                  );

            return SizedBox(
              width: maxW,
              height: cappedH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.transparent,
                  child: Ink.image(
                    image: (photoUrl == null || photoUrl!.isEmpty)
                        ? const AssetImage(kFallbackAsset) as ImageProvider
                        : NetworkImage(photoUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 20),

        // Prix estimé
        _PriceBadge(value: estimated),
        const SizedBox(height: 8),
        Text(
          'Prix estimé (interne)',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.55),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txt = (value == null)
        ? '—'
        : '${value!.toStringAsFixed(0)} USD'; // simple & large

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.onSurface.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
        child: Text(
          txt,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
