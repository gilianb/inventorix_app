// lib/details/widgets/price_trends.dart
// Widget "Tendances des prix"
// - Collectr: via Supabase Edge Function get_product_prices (cache 24h côté serveur)
// - CardTrader: via CardTraderService (client) — restera tel quel pour l’instant

// ignore_for_file: unnecessary_getters_setters

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Service CardTrader centralisé
import '../services/cardtrader_service.dart';

/// ⚠️ Clé d'API CardTrader (Bearer token) — TODO: migrer côté serveur ultérieurement
const String kCardTraderToken =
    'eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJjYXJkdHJhZGVyLXByb2R1Y3Rpb24iLCJzdWIiOiJhcHA6MTYzNjciLCJhdWQiOiJhcHA6MTYzNjciLCJleHAiOjQ5MTE3MDA0MjgsImp0aSI6IjBiYTRhMjNlLTg0NjctNGViNS05YzdlLWRmNWIyZjU1OThjYiIsImlhdCI6MTc1NjAyNjgyOCwibmFtZSI6IkdpZ2liIEFwcCAyMDI1MDcyNzIyMDQwMSJ9.LQzgTNPkhs_UvPGO2jFHBK5q97NzGMY30XpXbR_tEx9XhshPmbPdO8_4otlqiAdPymcQedq8cT-2d3FulljERSOhdCbVPWSW5I2Axvu5Zw8J4bvadtLH1m1REHZBn2GZ0xWY4wOtk1Iya-HeNAQ07QsBE17O2gIXsdMXl3x81TdFt6n4URetX9Qscyn4Gb7MtflqPBh3_FWPLtUKcOdibFSSI5m69iNJH1kLBb2v0r46U66ZkoIE_ppiqvfNGZmglTYh_zynh2RC4pZ0mnZtn6-enJ79Q0oDRmRj8OghIFr19zCPvV2ZcB9-VSP4mrDGMu43oE9gFzrwXGH_Rb6K-g';

const _kSources = ['eBay', 'Collectr', 'CardTrader'];

/// ---- Widget principal ------------------------------------------------------

class PriceTrendsCard extends StatefulWidget {
  const PriceTrendsCard({
    super.key,
    required this.productId,
    required this.productType, // 'single' | 'sealed'
    required this.currency, // ex: 'USD'
    this.photoUrl,
    this.tcgPlayerId, // Collectr (ID présent dans product, utilisé côté serveur)
    this.blueprintId, // CardTrader (utilisé côté client)
    this.reloadTick, // pour forcer le refetch externe
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

class _PriceTrendsCardState extends State<PriceTrendsCard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  int _windowDays = 30; // 7 / 30 / 90

  final Map<String, Map<String, List<double>>> _series = {
    'raw': {},
    'graded': {},
  };

  // ---------------- Collectr (via Edge Function)
  Map<String, dynamic>? _collectrDto;
  String? _collectrError;
  bool _collectrLoading = false;

  // ---------------- CardTrader (client)
  CardTraderStats? _ctStatsRaw;
  String? _ctErrorRaw;
  bool _ctLoadingRaw = false;

  CardTraderStats? _ctStatsGraded;
  String? _ctErrorGraded;
  bool _ctLoadingGraded = false;

  @override
  void initState() {
    super.initState();
    final hasGradedTab = widget.productType.toLowerCase() == 'single';
    _tabCtrl = TabController(length: hasGradedTab ? 2 : 1, vsync: this);
    _generateMockData();

    // Fetch Collectr (serveur) puis CardTrader (client)
    _fetchCollectr();
    _fetchCardTrader();
  }

  @override
  void didUpdateWidget(covariant PriceTrendsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pidChanged = oldWidget.productId != widget.productId;
    final reloadChanged = oldWidget.reloadTick != widget.reloadTick;
    final bpChanged = oldWidget.blueprintId != widget.blueprintId;

    if (pidChanged || reloadChanged) {
      _fetchCollectr();
    }
    if (bpChanged || reloadChanged) {
      _fetchCardTrader();
    }
  }

  // ---------------- Data generation mock (eBay) just to keep UI filled
  void _generateMockData() {
    List<double> make(int len, double start, double vol) {
      final r = Random((widget.productId ?? 42) + len);
      final out = <double>[];
      var cur = start;
      for (var i = 0; i < len; i++) {
        cur = (cur + r.nextDouble() * vol - vol / 2).clamp(1, 9999);
        out.add(double.parse(cur.toStringAsFixed(2)));
      }
      return out;
    }

    int lenByWindow() {
      switch (_windowDays) {
        case 7:
          return 8;
        case 90:
          return 20;
        default:
          return 12; // 30j
      }
    }

    final len = lenByWindow();
    _series['raw'] = {
      'eBay': make(len, 35, 6),
      // 'Collectr' et 'CardTrader' seront injectées après fetch
      'Collectr': _series['raw']?['Collectr'] ?? make(len, 33, 5),
      'CardTrader': _series['raw']?['CardTrader'] ?? make(len, 31, 7),
    };
    _series['graded'] = {
      'eBay': make(len, 120, 18),
      'Collectr': _series['graded']?['Collectr'] ?? make(len, 115, 16),
      'CardTrader': _series['graded']?['CardTrader'] ?? make(len, 125, 20),
    };
    setState(() {});
  }

  // ---------------- Collectr (Edge Function)
  Future<void> _fetchCollectr() async {
    if (widget.productId == null) return;
    setState(() {
      _collectrLoading = true;
      _collectrError = null;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'get_product_prices',
        body: {'productId': widget.productId},
      );

      final dto = Map<String, dynamic>.from(res.data as Map);
      _collectrDto = dto;

      // ---- RAW
      final rawNode = dto['raw'] as Map<String, dynamic>?;
      final seriesRaw = (rawNode?['series'] as List? ?? const [])
          .map<double>((e) => (e['value'] as num).toDouble())
          .toList();

      if (seriesRaw.isNotEmpty) {
        _series['raw'] ??= {};
        _series['raw']!['Collectr'] = seriesRaw;
      }

      final lastRaw = (rawNode?['price_now'] as num?)?.toDouble();
      if (lastRaw != null) {
        _series['raw'] ??= {};
        final arr = (_series['raw']!['Collectr'] ?? <double>[]);
        if (arr.isEmpty || arr.last != lastRaw) {
          _series['raw']!['Collectr'] = [...arr, lastRaw];
        }
      }

      // ---- PSA (une seule ligne "graded")
      final psaNode = dto['psa'] as Map<String, dynamic>?;
      final seriesPsa = (psaNode?['series'] as List? ?? const [])
          .map<double>((e) => (e['value'] as num).toDouble())
          .toList();

      if (seriesPsa.isNotEmpty) {
        _series['graded'] ??= {};
        _series['graded']!['Collectr'] = seriesPsa;
      }

      final lastPsa = (psaNode?['price_now'] as num?)?.toDouble();
      if (lastPsa != null) {
        _series['graded'] ??= {};
        final arr = (_series['graded']!['Collectr'] ?? <double>[]);
        if (arr.isEmpty || arr.last != lastPsa) {
          _series['graded']!['Collectr'] = [...arr, lastPsa];
        }
      }
    } catch (e) {
      _collectrError = e.toString();
    } finally {
      if (mounted) setState(() => _collectrLoading = false);
    }
  }

  // ---------------- CardTrader (client)
  Future<void> _fetchCardTrader() async {
    _ctErrorRaw = null;
    _ctStatsRaw = null;
    _ctErrorGraded = null;
    _ctStatsGraded = null;

    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {});
      return;
    }
    if (kCardTraderToken.isEmpty) {
      setState(() {
        _ctErrorRaw = 'Token CardTrader manquant';
        _ctErrorGraded = 'Token CardTrader manquant';
      });
      return;
    }

    // ---- NON GRADÉ (anglais uniquement)
    setState(() => _ctLoadingRaw = true);
    try {
      final stats = await CardTraderService.fetchMarketplaceByBlueprint(
        blueprintId: bp,
        bearerToken: kCardTraderToken,
        graded: false,
        languageParam: 'en',
      );

      final median = stats.medianUSD;
      if (median != null) {
        _series['raw'] ??= {};
        final dataRaw = _series['raw']!['CardTrader'] ?? <double>[];
        if (dataRaw.isEmpty) {
          _series['raw']!['CardTrader'] = [median];
        } else {
          _series['raw']!['CardTrader'] = [
            ...dataRaw.sublist(0, dataRaw.length - 1),
            double.parse(median.toStringAsFixed(2))
          ];
        }
      }

      setState(() {
        _ctStatsRaw = stats;
        _ctLoadingRaw = false;
      });
    } catch (e) {
      setState(() {
        _ctErrorRaw = e.toString();
        _ctLoadingRaw = false;
      });
    }

    // ---- GRADÉ (anglais uniquement)
    setState(() => _ctLoadingGraded = true);
    try {
      final statsG = await CardTraderService.fetchMarketplaceByBlueprint(
        blueprintId: bp,
        bearerToken: kCardTraderToken,
        graded: true,
        languageParam: 'en',
      );

      final medianG = statsG.medianUSD;
      if (medianG != null) {
        _series['graded'] ??= {};
        final dataG = _series['graded']!['CardTrader'] ?? <double>[];
        if (dataG.isEmpty) {
          _series['graded']!['CardTrader'] = [medianG];
        } else {
          _series['graded']!['CardTrader'] = [
            ...dataG.sublist(0, dataG.length - 1),
            double.parse(medianG.toStringAsFixed(2))
          ];
        }
      }

      setState(() {
        _ctStatsGraded = statsG;
        _ctLoadingGraded = false;
      });
    } catch (e) {
      setState(() {
        _ctErrorGraded = e.toString();
        _ctLoadingGraded = false;
      });
    }
  }

  Future<void> _manualRefresh() async {
    // Côté Collectr, la fonction décidera (TTL 24h) si un appel externe est nécessaire.
    await Future.wait([
      _fetchCollectr(),
      _fetchCardTrader(),
    ]);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasGradedTab = widget.productType.toLowerCase() == 'single';
    final anyLoading = _collectrLoading || _ctLoadingRaw || _ctLoadingGraded;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            photoUrl: widget.photoUrl,
            title: 'Tendances des prix',
            currency: widget.currency,
            windowDays: _windowDays,
            onWindowChanged: (v) {
              setState(() {
                _windowDays = v;
                _generateMockData();
              });
            },
            onRefreshPressed: _manualRefresh, // bouton refresh
            refreshing: anyLoading,
          ),
          if (hasGradedTab)
            Material(
              color: Colors.transparent,
              child: TabBar(
                controller: _tabCtrl,
                labelColor: Theme.of(context).colorScheme.primary,
                tabs: const [Tab(text: 'Non gradé'), Tab(text: 'Graded')],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Non gradé',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (!hasGradedTab)
            _ConditionPane(
              conditionKey: 'raw',
              currency: widget.currency,
              series: _series['raw'] ?? const {},
              // CardTrader status pour l'onglet raw
              ctStats: _ctStatsRaw,
              ctError: _ctErrorRaw,
              ctLoading: _ctLoadingRaw,
              // Collectr status est passé via les flags "CardTrader" recyclés dans _SourceTile (voir plus bas)
              collectrError: _collectrError,
              collectrLoading: _collectrLoading,
            )
          else
            SizedBox(
              height: 260,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _ConditionPane(
                    conditionKey: 'raw',
                    currency: widget.currency,
                    series: _series['raw'] ?? const {},
                    ctStats: _ctStatsRaw,
                    ctError: _ctErrorRaw,
                    ctLoading: _ctLoadingRaw,
                    collectrError: _collectrError,
                    collectrLoading: _collectrLoading,
                  ),
                  _GradedPane(
                    currency: widget.currency,
                    series: _series['graded'] ?? const {},
                    // Collectr états
                    collectrLoading: _collectrLoading,
                    collectrError: _collectrError,
                    // CardTrader états
                    ctStats: _ctStatsGraded,
                    ctError: _ctErrorGraded,
                    ctLoading: _ctLoadingGraded,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.currency,
    required this.windowDays,
    required this.onWindowChanged,
    required this.onRefreshPressed,
    required this.refreshing,
    this.photoUrl,
  });

  final String title;
  final String currency;
  final int windowDays;
  final ValueChanged<int> onWindowChanged;
  final Future<void> Function() onRefreshPressed;
  final bool refreshing;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: (photoUrl?.isNotEmpty ?? false)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                photoUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.trending_up),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('Fenêtre: $windowDays j — Devise: $currency'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7j')),
              ButtonSegment(value: 30, label: Text('30j')),
              ButtonSegment(value: 90, label: Text('90j')),
            ],
            selected: {windowDays},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onWindowChanged(s.first);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Rafraîchir (Collectr + CardTrader)',
            onPressed: refreshing ? null : onRefreshPressed,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ConditionPane extends StatelessWidget {
  const _ConditionPane({
    required this.conditionKey,
    required this.currency,
    required this.series,
    this.ctStats,
    this.ctError,
    this.ctLoading = false,
    this.collectrError,
    this.collectrLoading = false,
  });

  final String conditionKey; // 'raw' | 'graded'
  final String currency;
  final Map<String, List<double>> series;

  // CardTrader
  final CardTraderStats? ctStats;
  final String? ctError;
  final bool ctLoading;

  // Collectr
  final String? collectrError;
  final bool collectrLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Row(
            children: _kSources.map((s) {
              final data = series[s] ?? const <double>[];
              final last = data.isNotEmpty ? data.last : null;

              // On recycle les props "cardTrader*" pour afficher les états Collectr sans refactor massif
              final isCT = s == 'CardTrader';
              final isCollectr = s == 'Collectr';

              return Expanded(
                child: _SourceTile(
                  source: s,
                  currency: currency,
                  lastPrice: last,
                  data: data,
                  cardTraderStats: isCT ? ctStats : null,
                  cardTraderError:
                      isCT ? ctError : (isCollectr ? collectrError : null),
                  cardTraderLoading:
                      isCT ? ctLoading : (isCollectr ? collectrLoading : false),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const _LegendRow(),
        ],
      ),
    );
  }
}

class _GradedPane extends StatelessWidget {
  const _GradedPane({
    required this.currency,
    required this.series,
    this.ctStats,
    this.ctError,
    this.ctLoading = false,
    this.collectrLoading = false,
    this.collectrError,
  });

  final String currency;
  final Map<String, List<double>> series;

  // CardTrader (existant)
  final CardTraderStats? ctStats;
  final String? ctError;
  final bool ctLoading;

  // Collectr (nouveau)
  final bool collectrLoading;
  final String? collectrError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Row(
            children: _kSources.map((s) {
              final data = series[s] ?? const <double>[];
              final last = data.isNotEmpty ? data.last : null;

              final isCT = s == 'CardTrader';
              final isCollectr = s == 'Collectr';

              return Expanded(
                child: _SourceTile(
                  source: s,
                  currency: currency,
                  lastPrice: last,
                  data: data,
                  cardTraderStats: isCT ? ctStats : null,
                  cardTraderError:
                      isCT ? ctError : (isCollectr ? collectrError : null),
                  cardTraderLoading:
                      isCT ? ctLoading : (isCollectr ? collectrLoading : false),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const _LegendRow(),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Icon(Icons.info_outline, size: 16),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Collectr & CardTrader: prix réels (USD). eBay: valeurs de démonstration.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.currency,
    required this.lastPrice,
    required this.data,
    this.cardTraderStats,
    this.cardTraderError,
    this.cardTraderLoading = false,
  });

  final String source;
  final String currency;
  final double? lastPrice;
  final List<double> data;

  final CardTraderStats? cardTraderStats; // uniquement pour CardTrader
  final String? cardTraderError; // réutilisé aussi pour Collectr
  final bool cardTraderLoading; // réutilisé aussi pour Collectr

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCT = source == 'CardTrader';
    final isCollectr = source == 'Collectr';

    // Pour CardTrader: afficher médiane USD si dispo
    final displayLast = isCT && (cardTraderStats?.medianUSD != null)
        ? cardTraderStats!.medianUSD
        : lastPrice;

    final displayCurrency = 'USD'; // Collectr & CardTrader en USD, eBay mock

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isCT
                      ? Icons.store
                      : (isCollectr
                          ? Icons.stacked_line_chart
                          : Icons.shopping_cart),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(source,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (cardTraderLoading) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                ] else
                  Text(
                    displayLast != null
                        ? '${displayLast.toStringAsFixed(2)} $displayCurrency'
                        : '—',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 64, child: _Sparkline(data: data)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (cardTraderError != null) ...[
                  const Icon(Icons.error_outline, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$source: $cardTraderError',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else if (isCT && cardTraderStats != null) ...[
                  const Icon(Icons.info_outline, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Listings (EN): ${cardTraderStats!.listings} • Pool: ${cardTraderStats!.usedForCalc} • Med/Min USD',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else if (isCollectr) ...[
                  const Icon(Icons.info_outline, size: 14),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'PSA = priorité 10, sinon 9, sinon mix',
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.data});
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(data),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.data);
  final List<double> data;

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.blueGrey;

    final paintFill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blueGrey.withOpacity(0.12);

    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    final minV = data.reduce(min);
    final maxV = data.reduce(max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    final dx = data.length > 1 ? size.width / (data.length - 1) : size.width;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * dx;
      final t = (data[i] - minV) / range;
      final y = size.height - t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fill, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.data.length != data.length) return true;
    for (var i = 0; i < data.length; i++) {
      if (oldDelegate.data[i] != data[i]) return true;
    }
    return false;
  }
}
