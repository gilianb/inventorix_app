// lib/details/widgets/price_history_chart.dart
// Collectr + PriceCharting on same graph (2 series).
// ✅ FIX: forward-fill per series until today (no holes when one source misses a day).
// ✅ Design: PriceCharting curve now uses SAME style as Collectr (SplineArea + gradient),
//           only color differs.
// DefaultTabController-based, no SingleTickerProviderStateMixin anywhere.

// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class PriceHistoryTabs extends StatefulWidget {
  const PriceHistoryTabs({
    super.key,
    required this.productId,
    required this.isSingle,
    required this.currency,
  });

  final int? productId;
  final bool isSingle;
  final String currency;

  @override
  State<PriceHistoryTabs> createState() => _PriceHistoryTabsState();
}

class _PriceHistoryTabsState extends State<PriceHistoryTabs> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // Collectr
  List<_Point> _rawCollectr = const [];
  List<_Point> _psaCollectr = const [];

  // PriceCharting
  List<_Point> _rawPc = const [];
  List<_Point> _psaPc = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PriceHistoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.isSingle != widget.isSingle) {
      _load();
    }
  }

  Future<void> _load() async {
    final pid = widget.productId;
    setState(() {
      _loading = true;
      _error = null;
      _rawCollectr = const [];
      _psaCollectr = const [];
      _rawPc = const [];
      _psaPc = const [];
    });

    if (pid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final rows = await _sb
          .from('price_history')
          .select('source, grade, price, fetched_at')
          .eq('product_id', pid)
          .inFilter('source', ['collectr', 'pricecharting']).order('fetched_at',
              ascending: true);

      final rawCollectr = <_Point>[];
      final psaCollectr = <_Point>[];
      final rawPc = <_Point>[];
      final psaPc = <_Point>[];

      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;

        final source = (m['source'] ?? '').toString().toLowerCase();
        final grade = (m['grade'] ?? '').toString().toLowerCase();
        final price = (m['price'] as num?)?.toDouble();
        final atIso = m['fetched_at']?.toString();

        if (price == null || price <= 0 || atIso == null) continue;

        final at = DateTime.tryParse(atIso);
        if (at == null) continue;

        final p = _Point(at.toLocal(), price);

        final isCollectr = source == 'collectr';
        final isPc = source == 'pricecharting';

        if (grade == 'raw') {
          if (isCollectr) rawCollectr.add(p);
          if (isPc) rawPc.add(p);
        } else if (grade == 'psa') {
          if (isCollectr) psaCollectr.add(p);
          if (isPc) psaPc.add(p);
        }
      }

      setState(() {
        _rawCollectr = rawCollectr;
        _psaCollectr = psaCollectr;
        _rawPc = rawPc;
        _psaPc = psaPc;
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
    final tabConfs = <_TabConf>[
      _TabConf('Raw', _SeriesKind.raw),
      if (widget.isSingle) _TabConf('Graded (PSA 10)', _SeriesKind.psa),
    ];
    final tabCount = max(1, tabConfs.length);

    if (tabCount == 0) {
      return const _CardShell(child: _EmptyState(label: 'No data'));
    }

    // Raw: Collectr teal, PriceCharting orange
    // PSA: Collectr indigo, PriceCharting purple-ish
    const collectrRawColor = Color(0xFF0FA3B1);
    const collectrPsaColor = Color(0xFF5B5BD6);
    const pcRawColor = Color(0xFFF39C12);
    const pcPsaColor = Color(0xFF9B59B6);

    return _CardShell(
      child: DefaultTabController(
        length: tabCount,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with refresh
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.show_chart,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Price history (Collectr + PriceCharting)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: tabConfs
                    .take(tabCount)
                    .map((t) => Tab(text: t.title))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null
                      ? _ErrorBox(message: _error!)
                      : TabBarView(
                          children: tabConfs.take(tabCount).map((t) {
                            final isRaw = t.kind == _SeriesKind.raw;

                            final collectr =
                                isRaw ? _rawCollectr : _psaCollectr;
                            final pc = isRaw ? _rawPc : _psaPc;

                            return _HistorySeriesDual(
                              primaryName: 'Collectr',
                              secondaryName: 'PriceCharting',
                              primary: collectr,
                              secondary: pc,
                              currency: widget.currency,
                              primaryColor:
                                  isRaw ? collectrRawColor : collectrPsaColor,
                              secondaryColor: isRaw ? pcRawColor : pcPsaColor,
                            );
                          }).toList(),
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: child,
      ),
    );
  }
}

class _HistorySeriesDual extends StatelessWidget {
  const _HistorySeriesDual({
    required this.primaryName,
    required this.secondaryName,
    required this.primary,
    required this.secondary,
    required this.currency,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String primaryName;
  final String secondaryName;

  final List<_Point> primary;
  final List<_Point> secondary;

  final String currency;

  final Color primaryColor;
  final Color secondaryColor;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<_Point> _forwardFillOnTimeline({
    required List<_Point> src,
    required List<DateTime> timeline,
  }) {
    if (src.isEmpty) return const [];

    final byDay = <DateTime, double>{};
    for (final p in src) {
      byDay[_dateOnly(p.at)] = p.value;
    }

    final firstDay = byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);

    double? last;
    bool started = false;
    final out = <_Point>[];

    for (final day in timeline) {
      if (day.isBefore(firstDay)) continue;

      final v = byDay[day];
      if (v != null) {
        last = v;
        started = true;
      }
      if (started && last != null) {
        out.add(_Point(day, last));
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (primary.isEmpty && secondary.isEmpty) {
      return const _EmptyState(label: 'No data to display');
    }

    final pData = [...primary]..sort((a, b) => a.at.compareTo(b.at));
    final sData = [...secondary]..sort((a, b) => a.at.compareTo(b.at));

    final datesSet = <DateTime>{};
    for (final p in pData) {
      datesSet.add(_dateOnly(p.at));
    }
    for (final p in sData) {
      datesSet.add(_dateOnly(p.at));
    }
    datesSet.add(_dateOnly(DateTime.now()));

    final timeline = datesSet.toList()..sort((a, b) => a.compareTo(b));

    // ✅ forward-fill each series on the shared timeline (no holes)
    final pFilled = _forwardFillOnTimeline(src: pData, timeline: timeline);
    final sFilled = _forwardFillOnTimeline(src: sData, timeline: timeline);

    final allDates = <DateTime>[
      ...pFilled.map((e) => e.at),
      ...sFilled.map((e) => e.at),
    ]..sort();

    final minDate =
        allDates.isNotEmpty ? allDates.first : _dateOnly(DateTime.now());
    final maxDate =
        allDates.isNotEmpty ? allDates.last : _dateOnly(DateTime.now());

    final allValues = <double>[
      ...pFilled.map((e) => e.value),
      ...sFilled.map((e) => e.value),
    ];

    final minValue = allValues.isNotEmpty ? allValues.reduce(min) : 0.0;
    final maxValue = allValues.isNotEmpty ? allValues.reduce(max) : 1.0;
    final range = (maxValue - minValue).abs();

    final pad = range == 0 ? max(1.0, maxValue * 0.25) : range * 0.15;
    final double axisMin = max(0, minValue - pad).toDouble();
    final double axisMax = (maxValue + pad).toDouble();

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface.withOpacity(0.85);
    final divider = theme.dividerColor.withOpacity(0.35);
    final locale = Localizations.localeOf(context).toString();

    final numberFormatCompact = NumberFormat.compact(locale: locale);
    final numberFormatFull = NumberFormat.currency(
      locale: locale,
      symbol: currency,
      decimalDigits: 2,
    );

    Widget legendItem(Color c, String name, List<_Point> data) {
      final last = data.isNotEmpty ? data.last.value : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.75),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
            width: 0.7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              last != null ? numberFormatFull.format(last) : '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final trackball = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      lineType: TrackballLineType.vertical,
      lineColor: theme.colorScheme.outline.withOpacity(0.5),
      lineWidth: 1.2,
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      tooltipSettings: InteractiveTooltip(
        enable: true,
        borderWidth: 0,
        color: theme.colorScheme.surface,
        textStyle: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
        format: 'series.name\npoint.y $currency',
      ),
      markerSettings: TrackballMarkerSettings(
        markerVisibility: TrackballVisibilityMode.visible,
        height: 8,
        width: 8,
        borderWidth: 2,
        borderColor: theme.colorScheme.surface,
        color: theme.colorScheme.primary,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                legendItem(primaryColor, primaryName, pFilled),
                legendItem(secondaryColor, secondaryName, sFilled),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              plotAreaBackgroundColor:
                  theme.colorScheme.primary.withOpacity(0.015),
              tooltipBehavior: TooltipBehavior(enable: false),
              trackballBehavior: trackball,
              zoomPanBehavior: ZoomPanBehavior(
                enablePanning: true,
                enablePinching: true,
              ),
              primaryXAxis: DateTimeAxis(
                minimum: minDate,
                maximum: maxDate,
                edgeLabelPlacement: EdgeLabelPlacement.shift,
                dateFormat: DateFormat('dd/MM', locale),
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 0),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              primaryYAxis: NumericAxis(
                minimum: axisMin,
                maximum: axisMax,
                axisLine: const AxisLine(width: 0),
                majorGridLines: MajorGridLines(
                  width: 0.7,
                  color: divider,
                ),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                ),
                numberFormat: numberFormatCompact,
              ),
              series: <CartesianSeries<_Point, DateTime>>[
                // Collectr (area)
                if (pFilled.isNotEmpty)
                  SplineAreaSeries<_Point, DateTime>(
                    name: primaryName,
                    dataSource: pFilled,
                    xValueMapper: (_Point p, _) => p.at,
                    yValueMapper: (_Point p, _) => p.value,
                    borderColor: primaryColor,
                    borderWidth: 2.4,
                    splineType: SplineType.natural,
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withOpacity(0.28),
                        primaryColor.withOpacity(0.03),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    animationDuration: 700,
                    markerSettings: const MarkerSettings(isVisible: false),
                  ),

                // ✅ PriceCharting (same design as Collectr: area + gradient, different color)
                if (sFilled.isNotEmpty)
                  SplineAreaSeries<_Point, DateTime>(
                    name: secondaryName,
                    dataSource: sFilled,
                    xValueMapper: (_Point p, _) => p.at,
                    yValueMapper: (_Point p, _) => p.value,
                    borderColor: secondaryColor,
                    borderWidth: 2.4,
                    splineType: SplineType.natural,
                    gradient: LinearGradient(
                      colors: [
                        secondaryColor.withOpacity(0.22),
                        secondaryColor.withOpacity(0.03),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    animationDuration: 700,
                    markerSettings: const MarkerSettings(isVisible: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return Center(
      child: Text(
        label,
        style: TextStyle(
          color: dim,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.error.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: c.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SeriesKind { raw, psa }

class _TabConf {
  final String title;
  final _SeriesKind kind;
  _TabConf(this.title, this.kind);
}

class _Point {
  final DateTime at;
  final double value;
  const _Point(this.at, this.value);
}
