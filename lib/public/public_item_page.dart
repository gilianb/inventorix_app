// lib/public/public_item_page.dart
// Page publique (aperçu dans l'app) basée sur un token immuable : /i/<public_token>
// - Charge l'item via token, récupère product et infos affichables
// - Affiche une image, un panneau de prix estimé et l'historique (Raw / Graded)

// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Graphique d’historique (onglets Raw / Graded)
import '../details/widgets/price_history_chart.dart';

class PublicItemPage extends StatefulWidget {
  const PublicItemPage({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<PublicItemPage> createState() => _PublicItemPageState();
}

class _PublicItemPageState extends State<PublicItemPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // Données minimales pour l’affichage public
  String _title = '';
  String? _photoUrl;
  double? _estimated;

  // Infos nécessaires au graphique
  int? _productId;
  bool _isSingle = true; // défaut “single”
  String _currency = 'USD';

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
      final token = widget.token;
      if (token.isEmpty) {
        throw 'Invalid link (missing token).';
      }

      // 1) Essaye l'RPC si disponible (pub_get_item_by_token)
      Map<String, dynamic>? pubRow;
      try {
        final rpcRes = await _sb.rpc('pub_get_item_by_token', params: {
          'p_token': token,
        });

        if (rpcRes != null) {
          if (rpcRes is List && rpcRes.isNotEmpty) {
            pubRow = Map<String, dynamic>.from(rpcRes.first as Map);
          } else if (rpcRes is Map) {
            pubRow = Map<String, dynamic>.from(rpcRes);
          }
        }
      } catch (_) {
        // RPC non présent ou non accessible -> on tombera sur le fallback
      }

      if (pubRow != null) {
        _title = (pubRow['product_name'] ?? '').toString();
        final purl = (pubRow['photo_url'] ?? '').toString();
        _photoUrl = purl.isEmpty ? null : purl;
        _estimated = (pubRow['estimated_price'] as num?)?.toDouble();
        _productId = (pubRow['product_id'] as num?)?.toInt();
        _isSingle =
            ((pubRow['type'] ?? 'single').toString().toLowerCase() == 'single');
        _currency = (pubRow['currency'] ?? 'USD').toString();

        setState(() => _loading = false);
        return;
      }

      // 2) Fallback: jointure côté client item -> product -> games
      final item = await _sb
          .from('item')
          .select(
              'id, product_id, estimated_price, photo_url, currency, status, grade_id, language, game_id')
          .eq('public_token', token)
          .limit(1)
          .maybeSingle();

      if (item == null) throw 'Item not found (404).';

      final pid = (item['product_id'] as num?)?.toInt();
      Map<String, dynamic>? product;
      if (pid != null) {
        product = await _sb
            .from('product')
            .select('name, photo_url, type, game_id')
            .eq('id', pid)
            .maybeSingle();
      }

      final gid = (item['game_id'] as num?)?.toInt() ??
          (product?['game_id'] as num?)?.toInt();
      if (gid != null) {}

      _title = (product?['name'] ?? 'Item').toString();
      final purl =
          (item['photo_url'] ?? product?['photo_url'])?.toString() ?? '';
      _photoUrl = purl.trim().isEmpty ? null : purl.trim();
      _estimated = (item['estimated_price'] as num?)?.toDouble();
      _productId = pid;
      _isSingle =
          ((product?['type'] ?? 'single').toString().toLowerCase() == 'single');
      _currency = (item['currency'] ?? 'USD').toString();

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
        title: const Text('Inventorix — Public sheet'),
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
                          productId: _productId,
                          isSingle: _isSingle,
                          currency: _currency,
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
    required this.productId,
    required this.isSingle,
    required this.currency,
  });

  final String title;
  final String? photoUrl;
  final double? estimated;

  // infos graphe
  final int? productId;
  final bool isSingle;
  final String currency;

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
            currency: currency,
          );
        }

        // ---------- Bloc graphe (pleine largeur, sous le reste) ----------
        Widget buildHistoryCard() {
          if (productId == null) {
            return const SizedBox.shrink();
          }
          final double graphHeight = wide ? 380 : 320;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 22),
              Text(
                'Price history',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: graphHeight,
                child: PriceHistoryTabs(
                  productId: productId,
                  isSingle: isSingle,
                  currency: currency,
                ),
              ),
            ],
          );
        }

        if (wide) {
          // Disposition 2 colonnes + graphe dessous (pleine largeur)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              buildHistoryCard(),
            ],
          );
        } else {
          // Disposition verticale (mobile) + graphe dessous
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              buildCardImage(),
              const SizedBox(height: 16),
              buildPricePanel(),
              buildHistoryCard(),
            ],
          );
        }
      },
    );
  }
}

class _PricePanel extends StatelessWidget {
  const _PricePanel({required this.value, required this.currency});
  final double? value;
  final String currency;

  String _formatAmount(double? v) {
    if (v == null) return '—';
    final s = v.toStringAsFixed(0);
    final regex = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(regex, (m) => ' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceTxt = _formatAmount(value);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
          mainAxisSize: MainAxisSize.min, // ⬅️ important en scroll
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
                    'Estimated sale price',
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
                '$priceTxt $currency',
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
              'Indicative value — internal data',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 0.2,
              ),
            ),

            const SizedBox(height: 12),

            // Tags décoratifs
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _ChipOutline(icon: Icons.shield_moon, label: 'Read-only'),
                const _ChipOutline(icon: Icons.public, label: 'Public'),
                _ChipOutline(icon: Icons.currency_exchange, label: currency),
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
