// lib/details/widgets/price_trends.dart
// 2 lignes (Collectr / CardTrader) — pas de graph.
// TTL Collectr 24h strict respecté (même sur "Rafraîchir").
// Design : contraste fort, valeurs très lisibles, couleurs par source.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cardtrader_service.dart';

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
    this.tcgPlayerId, // utile si collectr_id absent
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
  // Collectr (DB + TTL 24h)
  bool _loadingCollectr = false;
  String? _errCollectr;
  double? _collectrRaw;
  double? _collectrPsa10;
  DateTime? _lastUpdate;

  // CardTrader (client)
  bool _loadingCtRaw = false;
  String? _errCtRaw;
  double? _ctMedianRaw;

  bool _loadingCtGraded = false;
  String? _errCtGraded;
  double? _ctMedianGraded;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  @override
  void didUpdateWidget(covariant PriceTrendsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.productId != widget.productId ||
        oldWidget.reloadTick != widget.reloadTick ||
        oldWidget.blueprintId != widget.blueprintId ||
        oldWidget.productType != widget.productType;
    if (changed) _fetchAll();
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _loadCollectrWithTTL(), // respecte strictement TTL 24h
      _fetchCardTraderRaw(),
      if (widget.productType.toLowerCase() == 'single')
        _fetchCardTraderGraded(),
    ]);
  }

  /// Collectr avec TTL 24h.
  Future<void> _loadCollectrWithTTL() async {
    final pid = widget.productId;
    if (pid == null) return;

    setState(() {
      _loadingCollectr = true;
      _errCollectr = null;
    });

    final sb = Supabase.instance.client;

    try {
      // 1) Lire product
      final product = await sb
          .from('product')
          .select(
              'id,type,collectr_id,tcg_player_id,price_raw,price_graded,last_update')
          .eq('id', pid)
          .maybeSingle();

      if (product == null) {
        setState(() => _errCollectr = 'Produit introuvable');
        return;
      }

      final bool isSingle =
          (product['type']?.toString().toLowerCase() ?? 'single') == 'single';
      final double? dbRaw = (product['price_raw'] as num?)?.toDouble();
      final double? dbGraded = (product['price_graded'] as num?)?.toDouble();
      final DateTime? dbLast = product['last_update'] != null
          ? DateTime.tryParse(product['last_update'].toString())
          : null;

      // 2) TTL
      bool needsRefresh = false;
      if (dbRaw == null) needsRefresh = true;
      if (isSingle && dbGraded == null) needsRefresh = true;
      if (dbLast == null) needsRefresh = true;
      if (!needsRefresh &&
          DateTime.now().toUtc().difference(dbLast!.toUtc()).inHours >= 24) {
        needsRefresh = true;
      }

      // 3) Pas besoin => pas d'appel API
      if (!needsRefresh) {
        setState(() {
          _collectrRaw = dbRaw;
          _collectrPsa10 = isSingle ? dbGraded : null;
          _lastUpdate = dbLast?.toLocal();
        });
        return;
      }

      // 4) Besoin d’un refresh
      final collectrId = (product['collectr_id'] as String?)?.trim();
      final tcgId =
          (product['tcg_player_id'] as String?)?.trim() ?? widget.tcgPlayerId;

      if ((collectrId == null || collectrId.isEmpty) &&
          (tcgId == null || tcgId.isEmpty)) {
        setState(() {
          _collectrRaw = dbRaw;
          _collectrPsa10 = isSingle ? dbGraded : null;
          _lastUpdate = dbLast?.toLocal();
          _errCollectr = 'Collectr: missing id — do it manually';
        });
        return;
      }

      final res = await sb.functions.invoke(
        'collectr_resolve_and_price',
        body: {
          if (collectrId != null && collectrId.isNotEmpty)
            'collectr_id': collectrId,
          if ((collectrId == null || collectrId.isEmpty) && tcgId != null)
            'tcg_player_id': tcgId,
        },
      );

      final data = Map<String, dynamic>.from(res.data as Map);
      final double? priceRaw = (data['price_raw'] as num?)?.toDouble();
      final double? pricePSA10 = (data['price_psa10'] as num?)?.toDouble();
      final String? opaqueId = (data['opaqueId'] as String?);

      // MAJ collectr_id si découvert
      if ((collectrId == null || collectrId.isEmpty) &&
          opaqueId != null &&
          opaqueId.isNotEmpty) {
        await sb
            .from('product')
            .update({'collectr_id': opaqueId}).eq('id', pid);
      }

      // MAJ product (pas d’historique ici)
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final upd = <String, dynamic>{
        'price_raw': priceRaw,
        'last_update': nowIso,
      };
      if (isSingle) upd['price_graded'] = pricePSA10;
      await sb.from('product').update(upd).eq('id', pid);

      // UI
      setState(() {
        _collectrRaw = priceRaw;
        _collectrPsa10 = isSingle ? pricePSA10 : null;
        _lastUpdate = DateTime.now();
      });
    } catch (e) {
      setState(() => _errCollectr = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCollectr = false);
    }
  }

  // -------- CardTrader ----------
  Future<void> _fetchCardTraderRaw() async {
    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {
        _ctMedianRaw = null;
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
      setState(() => _ctMedianRaw = stats.medianUSD);
    } catch (e) {
      setState(() => _errCtRaw = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCtRaw = false);
    }
  }

  Future<void> _fetchCardTraderGraded() async {
    final bp = widget.blueprintId;
    if (bp == null || bp <= 0) {
      setState(() {
        _ctMedianGraded = null;
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
              tooltip: 'Rafraîchir (TTL Collectr respecté)',
              onPressed: refreshing ? null : _fetchAll,
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
            caption: 'TTL 24h • prix DB si récent',
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
            title: 'CardTrader ( prix à prendre avec des pincettes)',
            caption: 'Médianes (EN) marketplace',
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

/// Modèle d’un indicateur (capsule valeur)
class _Metric {
  final String label;
  final double? valueUSD;
  const _Metric({required this.label, required this.valueUSD});
}

/// Ligne source (Collectr / CardTrader)
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

    // Conteneur subtil avec bord + fond dépendant de l’accent
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

/// Capsule visuelle d’un indicateur (ex: Raw, PSA10, Median…)
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

    // Palette capsule : contraste fort, avec bord
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
                      fontSize: 18, // 👀 valeur bien visible
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
