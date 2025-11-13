// lib/details/widgets/price_history_chart.dart
// DefaultTabController-based, no SingleTickerProviderStateMixin anywhere.

// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  List<_Point> _raw = const [];
  List<_Point> _psa = const [];

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
      _raw = const [];
      _psa = const [];
    });

    if (pid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final rows = await _sb
          .from('price_history')
          .select('grade, price, fetched_at')
          .eq('product_id', pid)
          .eq('source', 'collectr')
          .order('fetched_at', ascending: true);

      final raw = <_Point>[];
      final psa = <_Point>[];

      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        final grade = (m['grade'] ?? '').toString().toLowerCase();
        final price = (m['price'] as num?)?.toDouble();
        final atIso = m['fetched_at']?.toString();
        if (price == null || price <= 0 || atIso == null) continue;
        final at = DateTime.tryParse(atIso);
        if (at == null) continue;

        final p = _Point(at, price);
        if (grade == 'raw') raw.add(p);
        if (grade == 'psa') psa.add(p);
      }

      setState(() {
        _raw = raw;
        _psa = psa;
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
    // Determine tabs: always RAW; add PSA tab only when single.
    final tabConfs = <_TabConf>[
      _TabConf('Raw', _SeriesKind.raw),
      if (widget.isSingle) _TabConf('Graded (PSA 10)', _SeriesKind.psa),
    ];
    final tabCount = max(1, tabConfs.length); // never 0

    // No tabs? (shouldn’t happen due to max(1, ...)), show empty card anyway.
    if (tabCount == 0) {
      return const _CardShell(child: _EmptyState(label: 'No data'));
    }

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
                  child: Icon(Icons.show_chart,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Price history (Collectr)',
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
                          child: CircularProgressIndicator(strokeWidth: 2))
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
              height: 260,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null
                      ? _ErrorBox(message: _error!)
                      : TabBarView(
                          children: tabConfs.take(tabCount).map((t) {
                            final series =
                                (t.kind == _SeriesKind.raw) ? _raw : _psa;
                            return _HistorySeries(
                              points: series,
                              currency: widget.currency,
                              color: (t.kind == _SeriesKind.raw)
                                  ? const Color(0xFF0FA3B1)
                                  : const Color(0xFF5B5BD6),
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
    // Wrap in Material Card (gives proper InkFeatures ancestor).
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

class _HistorySeries extends StatelessWidget {
  const _HistorySeries({
    required this.points,
    required this.currency,
    required this.color,
  });

  final List<_Point> points;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyState(label: 'No data to display');
    }

    final base = DateTime.utc(1970, 1, 1);
    double dayX(DateTime d) => d.toUtc().difference(base).inDays.toDouble();

    final spots = points.map((p) => FlSpot(dayX(p.at), p.value)).toList();
    final minX = spots.first.x, maxX = spots.last.x;

    final vals = points.map((e) => e.value).toList();
    final minY = vals.reduce(min), maxY = vals.reduce(max);
    final dy = (maxY - minY).abs();
    final yPad = dy == 0 ? max(1.0, maxY * 0.1) : dy * 0.15;

    String fmtDate(double x) {
      final days = x.round();
      final d = base.add(Duration(days: days)).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: max(0, minY - yPad),
          maxY: maxY + yPad,
          gridData: FlGridData(
            show: true,
            horizontalInterval: dy == 0
                ? (max(1.0, maxY * 0.25))
                : (dy / 4).clamp(1, double.infinity),
            drawVerticalLine: false,
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                reservedSize: 44,
                showTitles: true,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    v.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: ((maxX - minX) / 5).clamp(1, double.infinity),
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    fmtDate(v),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (l) => l
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(2)} $currency',
                        const TextStyle(fontWeight: FontWeight.w800),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2.4,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData:
                  BarAreaData(show: true, color: color.withOpacity(0.18)),
            ),
          ],
        ),
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
        child: Text(label,
            style: TextStyle(color: dim, fontStyle: FontStyle.italic)));
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
              child: Text(message,
                  style:
                      TextStyle(color: c.error, fontWeight: FontWeight.w700))),
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
