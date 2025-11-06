// lib/details/widgets/price_trends.dart
// 2 lignes (Collectr / CardTrader) — pas de graph.
// Collectr: passe par CollectrEdgeService.ensureFreshAndPersist (TTL 24h côté DB,
// n'écrase jamais les prix avec null).
// CardTrader: cache mémoire TTL 24h. Aucun appel à l’ouverture; uniquement au clic “Rafraîchir”.

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cardtrader_service.dart';
import '../services/collectr_api.dart'; // <--- service sécurisé Collectr

// ⚠️ Token CardTrader (si 401: régénérer ou passer par Edge Function)
const String kCardTraderToken =
    'eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJjYXJkdHJhZGVyLXByb2R1Y3Rpb24iLCJzdWIiOiJhcHA6MTYzNjciLCJhdWQiOiJhcHA6MTYzNjciLCJleHAiOjQ5MTE3MDA0MjgsImp0aSI6IjBiYTRhMjNlLTg0NjctNGViNS05YzdlLWRmNWIyZjU1OThjYiIsImlhdCI6MTc1NjAyNjgyOCwibmFtZSI6IkdpZ2liIEFwcCAyMDI1MDcyNzIyMDQwMSJ9.LQzgTNPkhs_UvPGO2jFHBK5q97NzGMY30XpXbR_tEx9XhshPmbPdO8_4otlqiAdPymcQedq8cT-2d3FulljERSOhdCbVPWSW5I2Axvu5Zw8J4bvadtLH1m1REHZBn2GZ0xWY4wOtk1Iya-HeNAQ07QsBE17O2gIXsdMXl3x81TdFt6n4URetX9Qscyn4Gb7MtflqPBh3_FWPLtUKcOdibFSSI5m69iNJH1kLBb2v0r46U66ZkoIE_ppiqvfNGZmglTYh_zynh2RC4pZ0mnZtn6-enJ79Q0oDRmRj8OghIFr19zCPvV2ZcB9-VSP4mrDGMu43oE9gFzrwXGH_Rb6K-g';

class PriceTrendsCard extends StatefulWidget {
  const PriceTrendsCard({
    super.key,
    required this.productId,
    required this.productType, // 'single' | 'sealed'
    required this.currency, // 'USD'
    this.photoUrl,
    this.tcgPlayerId, // utile si collectr_id absent (géré par l'EF via service)
    this.blueprintId, // CardTrader
    this.reloadTick,
  });

  final int? productId;
  final String productType;
  final String currency;
  final String? photoUrl;
  final String? tcgPlayerId;
  final int? blueprintId;
  final int? reloadTick;

  @override
  State<PriceTrendsCard> createState() => _PriceTrendsCardState();
}

class _PriceTrendsCardState extends State<PriceTrendsCard> {
  // ---------------- COLLECTR (via DB + Edge) ----------------
  bool _loadingCollectr = false;
  String? _errCollectr;
  double? _collectrRaw;
  double? _collectrPsa10;
  DateTime? _lastUpdate;

  // ---------------- CARDTRADER (client) ----------------
  bool _loadingCtRaw = false;
  String? _errCtRaw;
  double? _ctMedianRaw;

  bool _loadingCtGraded = false;
  String? _errCtGraded;
  double? _ctMedianGraded;

  /// Cache mémoire TTL 24h pour CardTrader par blueprint.
  static final Map<int, _CtCacheEntry> _ctRawCache = {};
  static final Map<int, _CtCacheEntry> _ctGradedCache = {};
  static const Duration _ctTtl = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    // Au premier affichage :
    // - Collectr passe par le service (respect TTL DB, pas d’écrasement avec null)
    // - CardTrader ne fait PAS d’appel réseau (hydrate depuis cache mémoire uniquement)
    _loadCollectrWithTTL();
    _hydrateCtFromCache();
  }

  @override
  void didUpdateWidget(covariant PriceTrendsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.productId != widget.productId ||
        oldWidget.reloadTick != widget.reloadTick ||
        oldWidget.blueprintId != widget.blueprintId ||
        oldWidget.productType != widget.productType;

    if (changed) {
      _loadCollectrWithTTL(); // TTL côté DB, no-spam
      _hydrateCtFromCache(); // pas de réseau ici
    }
  }

  Future<void> _onRefreshPressed() async {
    await Future.wait([
      _loadCollectrWithTTL(), // respecte TTL DB Collectr
      _fetchCardTraderRawWithTtl(),
      if (widget.productType.toLowerCase() == 'single')
        _fetchCardTraderGradedWithTtl(),
    ]);
  }

  // ---- Collectr (via service sécurisé + TTL 24h DB) ----
  Future<void> _loadCollectrWithTTL() async {
    final pid = widget.productId;
    if (pid == null) return;

    setState(() {
      _loadingCollectr = true;
      _errCollectr = null;
    });

    final sb = Supabase.instance.client;

    try {
      // 1) Service: vérifie TTL, résout ID si besoin, appelle EF si nécessaire,
      //    et met à jour la DB sans jamais écraser avec null.
      final svc = CollectrEdgeService(sb);
      await svc.ensureFreshAndPersist(pid);

      // 2) Re-lire la ligne produit actualisée pour alimenter l’UI
      final product = await sb
          .from('product')
          .select('type, price_raw, price_graded, last_update')
          .eq('id', pid)
          .maybeSingle();

      final isSingle =
          (product?['type']?.toString().toLowerCase() ?? 'single') == 'single';

      setState(() {
        _collectrRaw = (product?['price_raw'] as num?)?.toDouble();
        _collectrPsa10 =
            isSingle ? (product?['price_graded'] as num?)?.toDouble() : null;
        _lastUpdate = product?['last_update'] != null
            ? DateTime.tryParse(product!['last_update'].toString())?.toLocal()
            : null;
      });
    } catch (e) {
      setState(() => _errCollectr = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCollectr = false);
    }
  }

  // ---- CardTrader: lecture cache sans réseau au premier affichage ----
  void _hydrateCtFromCache() {
    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {
        _ctMedianRaw = null;
        _ctMedianGraded = null;
      });
      return;
    }
    final now = DateTime.now();
    final rawEntry = _ctRawCache[bp];
    final gradedEntry = _ctGradedCache[bp];
    setState(() {
      _ctMedianRaw = (rawEntry != null && now.difference(rawEntry.at) < _ctTtl)
          ? rawEntry.value
          : null;
      _ctMedianGraded =
          (gradedEntry != null && now.difference(gradedEntry.at) < _ctTtl)
              ? gradedEntry.value
              : null;
    });
  }

  // ---- CardTrader RAW avec TTL mémoire (réseau UNIQUEMENT sur refresh) ----
  Future<void> _fetchCardTraderRawWithTtl() async {
    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {
        _ctMedianRaw = null;
        _errCtRaw = null;
      });
      return;
    }
    // TTL check
    final now = DateTime.now();
    final cached = _ctRawCache[bp];
    if (cached != null && now.difference(cached.at) < _ctTtl) {
      setState(() {
        _ctMedianRaw = cached.value;
        _errCtRaw = null;
      });
      return;
    }

    setState(() {
      _loadingCtRaw = true;
      _errCtRaw = null;
    });
    try {
      final stats = await CardTraderService.fetchMarketplaceByBlueprint(
        blueprintId: bp,
        bearerToken: kCardTraderToken,
        graded: false,
        languageParam: 'en',
      );
      _ctRawCache[bp] = _CtCacheEntry(value: stats.medianUSD, at: now);
      setState(() => _ctMedianRaw = stats.medianUSD);
    } catch (e) {
      setState(() => _errCtRaw = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCtRaw = false);
    }
  }

  // ---- CardTrader GRADED avec TTL mémoire (réseau UNIQUEMENT sur refresh) ----
  Future<void> _fetchCardTraderGradedWithTtl() async {
    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {
        _ctMedianGraded = null;
        _errCtGraded = null;
      });
      return;
    }
    final now = DateTime.now();
    final cached = _ctGradedCache[bp];
    if (cached != null && now.difference(cached.at) < _ctTtl) {
      setState(() {
        _ctMedianGraded = cached.value;
        _errCtGraded = null;
      });
      return;
    }

    setState(() {
      _loadingCtGraded = true;
      _errCtGraded = null;
    });
    try {
      final stats = await CardTraderService.fetchMarketplaceByBlueprint(
        blueprintId: bp,
        bearerToken: kCardTraderToken,
        graded: true,
        languageParam: 'en',
      );
      _ctGradedCache[bp] = _CtCacheEntry(value: stats.medianUSD, at: now);
      setState(() => _ctMedianGraded = stats.medianUSD);
    } catch (e) {
      setState(() => _errCtGraded = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCtGraded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.productType.toLowerCase() == 'single';
    final refreshing = _loadingCollectr || _loadingCtRaw || _loadingCtGraded;

    // Couleurs d’accent (accessibles en dark & light)
    final collectrAccent = const Color(0xFF0FA3B1); // teal-600
    final ctAccent = const Color(0xFF5B5BD6); // indigo-500

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Entête
          ListTile(
            leading: (widget.photoUrl?.isNotEmpty ?? false)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.photoUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  )
                : const _CircleIcon(icon: Icons.trending_up),
            title: const Text(
              'Prix marché',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            subtitle: Text(
              'Devise: ${widget.currency}'
              '${_lastUpdate != null ? " • MAJ: ${_fmt(_lastUpdate!)}" : ""}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            trailing: IconButton.filledTonal(
              tooltip: 'Rafraîchir (Collectr TTL DB + CardTrader TTL mémoire)',
              onPressed: refreshing ? null : _onRefreshPressed,
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ),
          const Divider(height: 1),

          // LIGNE COLLECTR
          _SourceRow(
            icon: Icons.stacked_line_chart,
            title: 'Collectr (fiable)',
            caption: 'TTL 24h — DB source (pas d’écrasement si pas de prix)',
            loading: _loadingCollectr,
            error: _errCollectr,
            accent: collectrAccent,
            chips: [
              _Metric(label: 'Raw', valueUSD: _collectrRaw),
              if (isSingle) _Metric(label: 'PSA 10', valueUSD: _collectrPsa10),
            ],
          ),

          // LIGNE CARDTRADER
          _SourceRow(
            icon: Icons.store_rounded,
            title: 'CardTrader (indicatif)',
            caption:
                'Médianes marketplace — TTL 24h (mémoire) • Refresh manuel',
            loading: _loadingCtRaw || (isSingle && _loadingCtGraded),
            error: _errCtRaw ?? (isSingle ? _errCtGraded : null),
            accent: ctAccent,
            chips: [
              _Metric(label: 'Raw (med.)', valueUSD: _ctMedianRaw),
              if (isSingle)
                _Metric(label: 'Graded (med.)', valueUSD: _ctMedianGraded),
            ],
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _CtCacheEntry {
  final double? value;
  final DateTime at;
  _CtCacheEntry({required this.value, required this.at});
}

/// Petite pastille d’icône ronde pour l’entête
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary.withOpacity(0.10);
    final fg = Theme.of(context).colorScheme.primary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.15)),
      ),
      child: Icon(icon, color: fg),
    );
  }
}

class _Metric {
  final String label;
  final double? valueUSD;
  const _Metric({required this.label, required this.valueUSD});
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.loading,
    required this.error,
    required this.chips,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String caption;
  final bool loading;
  final String? error;
  final List<_Metric> chips;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = (error != null && error!.isNotEmpty);

    final bg = accent.withOpacity(0.08);
    final border = accent.withOpacity(0.22);
    final iconBg = accent.withOpacity(0.15);
    final iconFg = accent;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconFg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: chips
                .map((m) => _MetricChip(
                      label: m.label,
                      valueUSD: m.valueUSD,
                      accent: accent,
                      error: hasError ? error : null,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.valueUSD,
    required this.accent,
    this.error,
  });

  final String label;
  final double? valueUSD;
  final String? error;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = error != null && error!.isNotEmpty;

    final bg = hasError
        ? theme.colorScheme.errorContainer.withOpacity(0.30)
        : Colors.white.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.06 : 0.9);
    final border = hasError
        ? theme.colorScheme.error.withOpacity(0.55)
        : accent.withOpacity(0.35);
    final labelColor = hasError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface.withOpacity(0.85);
    final valueColor = hasError ? theme.colorScheme.error : accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: labelColor,
                letterSpacing: 0.2,
              )),
          const SizedBox(width: 10),
          if (hasError)
            Tooltip(
              message: error!,
              child: Icon(Icons.error_outline, size: 18, color: valueColor),
            )
          else
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: valueUSD != null ? valueUSD!.toStringAsFixed(2) : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18, // valeur bien visible
                      color: valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: '  USD',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: labelColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
