// lib/details/widgets/price_trends.dart
// ✅ UI: 3 compact tiles (Collectr / PriceCharting / CardTrader)
// ✅ PriceCharting: reads latest from price_history (no network here)
// Collectr: via CollectrEdgeService.ensureFreshAndPersist (TTL 24h DB, never overwrites with null)
// CardTrader: memory cache TTL 24h. No call on open; only on "Refresh".

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cardtrader_service.dart';
import '../services/collectr_api.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

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
    this.tcgPlayerId, // (not used here, handled by CollectrEdgeService internally)
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

  // ---------------- PRICECHARTING (latest from price_history) ----------------
  bool _loadingPc = false;
  String? _errPc;
  double? _pcRaw;
  double? _pcPsa10;

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
    // - Collectr passe par le service (TTL DB, pas d’écrasement avec null)
    // - PriceCharting: lit la dernière valeur depuis price_history (DB)
    // - CardTrader ne fait PAS d’appel réseau (hydrate depuis cache mémoire uniquement)
    _loadCollectrWithTTL();
    _loadPriceChartingLatest();
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
      _loadCollectrWithTTL();
      _loadPriceChartingLatest();
      _hydrateCtFromCache();
    }
  }

  Future<void> _onRefreshPressed() async {
    await Future.wait([
      _loadCollectrWithTTL(), // TTL DB Collectr
      _loadPriceChartingLatest(), // latest DB
      _fetchCardTraderRawWithTtl(), // network only on refresh
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
      final svc = CollectrEdgeService(sb);
      await svc.ensureFreshAndPersist(pid);

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

  // ---- PriceCharting: latest from price_history (DB) ----
  Future<void> _loadPriceChartingLatest() async {
    final pid = widget.productId;
    if (pid == null) return;

    setState(() {
      _loadingPc = true;
      _errPc = null;
    });

    try {
      final sb = Supabase.instance.client;

      final rawRow = await sb
          .from('price_history')
          .select('price')
          .eq('product_id', pid)
          .eq('source', 'pricecharting')
          .eq('grade', 'raw')
          .order('fetched_at', ascending: false)
          .limit(1)
          .maybeSingle();

      Map<String, dynamic>? psaRow;
      if (widget.productType.toLowerCase() == 'single') {
        psaRow = await sb
            .from('price_history')
            .select('price')
            .eq('product_id', pid)
            .eq('source', 'pricecharting')
            .eq('grade', 'psa')
            .order('fetched_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      setState(() {
        _pcRaw = (rawRow?['price'] as num?)?.toDouble();
        _pcPsa10 = (widget.productType.toLowerCase() == 'single')
            ? (psaRow?['price'] as num?)?.toDouble()
            : null;
      });
    } catch (e) {
      setState(() => _errPc = e.toString());
    } finally {
      if (mounted) setState(() => _loadingPc = false);
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
    final refreshing =
        _loadingCollectr || _loadingPc || _loadingCtRaw || _loadingCtGraded;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
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
              'Market Price',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            subtitle: Text(
              'Currency: ${widget.currency}'
              '${_lastUpdate != null ? " • Updated: ${_fmt(_lastUpdate!)}" : ""}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            trailing: IconButton.filledTonal(
              tooltip:
                  'Refresh (Collectr DB TTL + PriceCharting DB + CardTrader TTL)',
              onPressed: refreshing ? null : _onRefreshPressed,
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Iconify(Mdi.refresh),
            ),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: LayoutBuilder(
              builder: (context, c) {
                final isNarrow = c.maxWidth < 420;

                final tiles = <Widget>[
                  _PriceMiniTile(
                    title: 'Collectr',
                    loading: _loadingCollectr,
                    error: _errCollectr,
                    raw: _collectrRaw,
                    psa10: isSingle ? _collectrPsa10 : null,
                    accent: const Color(0xFF0FA3B1),
                    currency: widget.currency,
                  ),
                  _PriceMiniTile(
                    title: 'PriceCharting',
                    loading: _loadingPc,
                    error: _errPc,
                    raw: _pcRaw,
                    psa10: isSingle ? _pcPsa10 : null,
                    accent: const Color(0xFFF39C12),
                    currency: widget.currency,
                  ),
                  _PriceMiniTile(
                    title: 'CardTrader',
                    loading: _loadingCtRaw || (isSingle && _loadingCtGraded),
                    error: _errCtRaw ?? (isSingle ? _errCtGraded : null),
                    raw: _ctMedianRaw,
                    psa10: isSingle ? _ctMedianGraded : null,
                    accent: const Color(0xFF5B5BD6),
                    currency: widget.currency,
                  ),
                ];

                if (isNarrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: tiles[0]),
                          const SizedBox(width: 10),
                          Expanded(child: tiles[1]),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(children: [Expanded(child: tiles[2])]),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: tiles[0]),
                    const SizedBox(width: 10),
                    Expanded(child: tiles[1]),
                    const SizedBox(width: 10),
                    Expanded(child: tiles[2]),
                  ],
                );
              },
            ),
          ),
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

class _PriceMiniTile extends StatelessWidget {
  const _PriceMiniTile({
    required this.title,
    required this.loading,
    required this.error,
    required this.raw,
    required this.psa10,
    required this.accent,
    required this.currency,
  });

  final String title;
  final bool loading;
  final String? error;
  final double? raw;
  final double? psa10;
  final Color accent;
  final String currency;

  String _fmt(double? v) => (v == null) ? '—' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = error != null && error!.isNotEmpty;

    final bg = hasError
        ? theme.colorScheme.errorContainer.withOpacity(0.25)
        : accent.withOpacity(0.08);

    final border = hasError
        ? theme.colorScheme.error.withOpacity(0.55)
        : accent.withOpacity(0.25);

    final titleColor = theme.colorScheme.onSurface.withOpacity(0.85);
    final valueColor = hasError ? theme.colorScheme.error : accent;

    Widget valueLine(String label, double? v, {bool big = false}) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: titleColor.withOpacity(0.75),
            ),
          ),
          Text(
            '${_fmt(v)} $currency',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: big ? FontWeight.w900 : FontWeight.w800,
              fontSize: big ? 14 : 12,
              color: valueColor,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!loading && hasError)
                Tooltip(
                  message: error!,
                  child: Icon(Icons.error_outline, size: 18, color: valueColor),
                ),
            ],
          ),
          const SizedBox(height: 10),
          valueLine('Raw', raw, big: true),
          if (psa10 != null) ...[
            const SizedBox(height: 6),
            valueLine('PSA 10', psa10),
          ],
        ],
      ),
    );
  }
}
