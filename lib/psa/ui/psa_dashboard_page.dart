// lib/psa/ui/psa_dashboard_page.dart
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

import '../data/psa_repository.dart';
import '../models/psa_models.dart';
import '../utils/business_days.dart';
import 'psa_order_details_page.dart';

class PsaDashboardPage extends StatefulWidget {
  const PsaDashboardPage({
    super.key,
    required this.orgId,
    required this.canEdit,
    required this.canSeeUnitCosts,
    required this.canSeeFinance,
  });

  final String orgId;
  final bool canEdit;
  final bool canSeeUnitCosts;
  final bool canSeeFinance;

  @override
  State<PsaDashboardPage> createState() => _PsaDashboardPageState();
}

enum _OrderSortMode {
  daysRemainingAsc,
  receivedDateDesc,
  createdDateDesc,
  orderNumberAsc,
}

class _PsaDashboardPageState extends State<PsaDashboardPage> {
  final _sb = Supabase.instance.client;
  late final PsaRepository repo = PsaRepository(_sb);

  bool _loading = true;

  List<Map<String, dynamic>> _services = const [];
  List<PsaOrderSummary> _orders = const [];

  _OrderSortMode _sortMode = _OrderSortMode.daysRemainingAsc;

  // Create order form
  final _orderNumberCtrl = TextEditingController();
  int? _serviceId;
  DateTime? _psaReceivedDate;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : d.toIso8601String().split('T').first;

  String _fmtMoney(num v) => v.toStringAsFixed(2);

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  num? _asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  String _serviceLabelWithMeta({
    required String label,
    int? days,
    num? fee,
  }) {
    final parts = <String>[];
    if (days != null && days > 0) parts.add('${days}d');
    if (fee != null && fee > 0) parts.add('\$${_fmtMoney(fee)}');
    final meta = parts.join(' • ');
    return meta.isEmpty ? label : '$label ($meta)';
  }

  String _serviceLabelForOrder(PsaOrderSummary o) {
    return _serviceLabelWithMeta(
      label: o.serviceLabel,
      days: o.expectedDays,
      fee: o.defaultFee,
    );
  }

  String _serviceLabelForService(Map<String, dynamic> s) {
    final label = (s['label'] ?? s['code']).toString();
    final days = _asInt(s['expected_days']);
    final fee = _asNum(s['default_fee']);
    return _serviceLabelWithMeta(label: label, days: days, fee: fee);
  }

  Color _remainingTone(int? rem, ColorScheme scheme) {
    if (rem == null) return scheme.outline;
    if (rem < 0) return scheme.error;
    if (rem <= 5) return scheme.tertiary;
    return scheme.primary;
  }

  String _remainingLabel(int? rem) {
    if (rem == null) return 'Received date missing';
    if (rem < 0) return 'Overdue ${rem.abs()} bd';
    return 'Due in $rem bd';
  }

  Widget _summaryTile({
    required String label,
    required String value,
    Widget? icon,
    Color? tone,
  }) {
    final theme = Theme.of(context);
    final accent = tone ?? theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: icon),
            ),
          if (icon != null) const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    Widget? leading,
    Color? tone,
  }) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          if (leading != null) const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLine({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: $value',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _orderNumberCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  List<Map<String, dynamic>> _psaServicesOnly(List<Map<String, dynamic>> all) {
    bool isPsa(Map<String, dynamic> s) {
      final code = (s['code'] ?? '').toString().toLowerCase();
      final label = (s['label'] ?? '').toString().toLowerCase();
      return code.contains('psa') || label.contains('psa');
    }

    final psa = all.where(isPsa).toList();
    return psa.isNotEmpty ? psa : all;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final services = await repo.fetchGradingServices(widget.orgId);
      final orders = await repo.fetchOrderSummaries(widget.orgId);

      final filteredServices = _psaServicesOnly(services);

      setState(() {
        _services = filteredServices;
        _orders = orders;
        // auto select service if none selected
        _serviceId ??=
            _services.isNotEmpty ? (_services.first['id'] as int) : null;
      });
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _daysRemaining(PsaOrderSummary o) {
    final r = o.psaReceivedDate;
    if (r == null) return null;
    final elapsed = businessDaysElapsed(r, DateTime.now());
    return o.expectedDays - elapsed;
  }

  DateTime? _dueDate(PsaOrderSummary o) {
    final r = o.psaReceivedDate;
    if (r == null) return null;
    return addBusinessDays(r, o.expectedDays);
  }

  List<PsaOrderSummary> _sortedOrders(List<PsaOrderSummary> src) {
    final list = [...src];
    int cmpNullLast(int? a, int? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    switch (_sortMode) {
      case _OrderSortMode.daysRemainingAsc:
        list.sort((a, b) => cmpNullLast(_daysRemaining(a), _daysRemaining(b)));
        return list;
      case _OrderSortMode.receivedDateDesc:
        list.sort((a, b) => (b.psaReceivedDate ?? DateTime(1970))
            .compareTo(a.psaReceivedDate ?? DateTime(1970)));
        return list;
      case _OrderSortMode.createdDateDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      case _OrderSortMode.orderNumberAsc:
        list.sort((a, b) =>
            a.orderNumber.toLowerCase().compareTo(b.orderNumber.toLowerCase()));
        return list;
    }
  }

  Future<void> _createOrderFromDialog({
    required String orderNumber,
    required int gradingServiceId,
    DateTime? psaReceivedDate,
  }) async {
    if (!widget.canEdit) {
      _snack('No permission to create orders.');
      return;
    }

    try {
      final id = await repo.createOrder(
        orgId: widget.orgId,
        orderNumber: orderNumber,
        gradingServiceId: gradingServiceId,
        psaReceivedDate: psaReceivedDate,
      );

      _orderNumberCtrl.clear();
      setState(() => _psaReceivedDate = null);

      _snack('PSA order created (#$id).');
      await _refresh();
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _showCreateOrderDialog() async {
    if (!widget.canEdit) {
      _snack('No permission to create orders.');
      return;
    }

    final numberCtrl = TextEditingController(text: _orderNumberCtrl.text);
    int? serviceId = _serviceId;
    final serviceIds = _services.map((s) => (s['id'] as int)).toSet();
    if (serviceId != null && !serviceIds.contains(serviceId)) {
      serviceId = null;
    }
    DateTime? receivedDate = _psaReceivedDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: receivedDate ?? now,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setLocal(() => receivedDate = picked);
            }

            final dateLabel = receivedDate == null
                ? 'PSA received date (optional)'
                : 'Received: ${_fmtDate(receivedDate)}';

            return AlertDialog(
              title: const Text('Create PSA order'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: numberCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Order number',
                        prefixIcon: Icon(Icons.receipt_long_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: serviceId,
                      isExpanded: true,
                      items: _services
                          .map((s) => DropdownMenuItem<int>(
                                value: (s['id'] as int),
                                child: Text(_serviceLabelForService(s)),
                              ))
                          .toList(),
                      onChanged: (v) => setLocal(() => serviceId = v),
                      decoration: const InputDecoration(
                        labelText: 'Grading service',
                        prefixIcon: Icon(Icons.apartment_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_services.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No grading services available yet.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: pickDate,
                      icon: const Iconify(Mdi.calendar, size: 18),
                      label: Text(dateLabel),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final numStr = numberCtrl.text.trim();
                    if (numStr.isEmpty) {
                      _snack('Enter an order number.');
                      return;
                    }
                    if (serviceId == null) {
                      _snack('Pick a grading service.');
                      return;
                    }
                    Navigator.pop(dialogContext);
                    await _createOrderFromDialog(
                      orderNumber: numStr,
                      gradingServiceId: serviceId!,
                      psaReceivedDate: receivedDate,
                    );
                  },
                  icon: const Iconify(Mdi.plus, size: 18),
                  label: const Text('Create order'),
                ),
              ],
            );
          },
        );
      },
    );

    numberCtrl.dispose();
  }

  Widget _orderCard(PsaOrderSummary o) {
    final rem = _daysRemaining(o);
    final due = _dueDate(o);
    final theme = Theme.of(context);
    final tone = _remainingTone(rem, theme.colorScheme);
    final statusLabel = _remainingLabel(rem);

    final qtyChips = <Widget>[
      _statPill(
        label: 'Total',
        value: '${o.qtyTotal}',
        leading: Icon(Icons.inventory_2_outlined, size: 16, color: tone),
        tone: tone,
      ),
      _statPill(
        label: 'Sent',
        value: '${o.qtySentToGrader}',
        leading: Icon(Icons.local_shipping_outlined,
            size: 16, color: theme.colorScheme.tertiary),
        tone: theme.colorScheme.tertiary,
      ),
      _statPill(
        label: 'At PSA',
        value: '${o.qtyAtGrader}',
        leading: Icon(Icons.business_outlined,
            size: 16, color: theme.colorScheme.secondary),
        tone: theme.colorScheme.secondary,
      ),
      _statPill(
        label: 'Graded',
        value: '${o.qtyGraded}',
        leading: Icon(Icons.verified_outlined,
            size: 16, color: theme.colorScheme.primary),
        tone: theme.colorScheme.primary,
      ),
    ];

    final finance = widget.canSeeFinance
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financials',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _statPill(
                    label: 'Invested',
                    value: _fmtMoney(o.investedPurchase),
                    leading: Icon(Icons.account_balance_wallet_outlined,
                        size: 16, color: theme.colorScheme.secondary),
                    tone: theme.colorScheme.secondary,
                  ),
                  _statPill(
                    label: 'PSA fees',
                    value: _fmtMoney(o.psaFees),
                    leading: Icon(Icons.receipt_long_outlined,
                        size: 16, color: theme.colorScheme.tertiary),
                    tone: theme.colorScheme.tertiary,
                  ),
                  _statPill(
                    label: 'Est. rev',
                    value: _fmtMoney(o.estRevenue),
                    leading: Icon(Icons.trending_up,
                        size: 16, color: theme.colorScheme.primary),
                    tone: theme.colorScheme.primary,
                  ),
                  _statPill(
                    label: 'Est. margin',
                    value: _fmtMoney(o.potentialMargin),
                    leading: Icon(Icons.analytics_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    tone: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          )
        : const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PsaOrderDetailsPage(
              orgId: widget.orgId,
              order: o,
              canEdit: widget.canEdit,
              canSeeFinance: widget.canSeeFinance,
              canSeeUnitCosts: widget.canSeeUnitCosts,
            ),
          ),
        );
        if (mounted) _refresh();
      },
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Iconify(Mdi.certificate_outline, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      o.orderNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: tone.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tone.withOpacity(0.5)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _serviceLabelForOrder(o),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _metaLine(
                    label: 'Received',
                    value: _fmtDate(o.psaReceivedDate),
                    icon: Icons.calendar_today_outlined,
                  ),
                  _metaLine(
                    label: 'Due',
                    value: _fmtDate(due),
                    icon: Icons.event_available_outlined,
                  ),
                  _metaLine(
                    label: 'Expected',
                    value: '${o.expectedDays} bd',
                    icon: Icons.timelapse,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, children: qtyChips),
              if (widget.canSeeFinance) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                finance,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceVariant,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: const Center(
              child: Iconify(Mdi.certificate_outline, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PSA dashboard',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Monitor submissions, turnaround, and results at a glance.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Iconify(Mdi.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final theme = Theme.of(context);

    final totalOrders = _orders.length;
    final totalCards = _orders.fold<int>(0, (sum, o) => sum + o.qtyTotal);
    final totalSent = _orders.fold<int>(0, (sum, o) => sum + o.qtySentToGrader);
    final totalAtPsa = _orders.fold<int>(0, (sum, o) => sum + o.qtyAtGrader);
    final totalGraded = _orders.fold<int>(0, (sum, o) => sum + o.qtyGraded);
    final overdue = _orders.where((o) {
      final rem = _daysRemaining(o);
      return rem != null && rem < 0;
    }).length;

    final tiles = <Widget>[
      _summaryTile(
        label: 'Orders',
        value: '$totalOrders',
        icon: Icon(Icons.receipt_long_outlined,
            size: 18, color: theme.colorScheme.primary),
        tone: theme.colorScheme.primary,
      ),
      _summaryTile(
        label: 'Cards',
        value: '$totalCards',
        icon: Icon(Icons.inventory_2_outlined,
            size: 18, color: theme.colorScheme.primary),
        tone: theme.colorScheme.primary,
      ),
      _summaryTile(
        label: 'Sent',
        value: '$totalSent',
        icon: Icon(Icons.local_shipping_outlined,
            size: 18, color: theme.colorScheme.tertiary),
        tone: theme.colorScheme.tertiary,
      ),
      _summaryTile(
        label: 'At PSA',
        value: '$totalAtPsa',
        icon: Icon(Icons.business_outlined,
            size: 18, color: theme.colorScheme.secondary),
        tone: theme.colorScheme.secondary,
      ),
      _summaryTile(
        label: 'Graded',
        value: '$totalGraded',
        icon: Icon(Icons.verified_outlined,
            size: 18, color: theme.colorScheme.primary),
        tone: theme.colorScheme.primary,
      ),
      _summaryTile(
        label: 'Overdue',
        value: '$overdue',
        icon: Icon(Icons.warning_amber_outlined,
            size: 18, color: theme.colorScheme.error),
        tone: theme.colorScheme.error,
      ),
    ];

    if (widget.canSeeFinance) {
      final totalInvested = _orders.fold<num>(
          0, (sum, o) => sum + o.investedPurchase + o.psaFees);
      final totalRevenue = _orders.fold<num>(0, (sum, o) => sum + o.estRevenue);
      final totalMargin = totalRevenue - totalInvested;

      tiles.addAll([
        _summaryTile(
          label: 'Invested',
          value: _fmtMoney(totalInvested),
          icon: Icon(Icons.account_balance_wallet_outlined,
              size: 18, color: theme.colorScheme.secondary),
          tone: theme.colorScheme.secondary,
        ),
        _summaryTile(
          label: 'Est. revenue',
          value: _fmtMoney(totalRevenue),
          icon: Icon(Icons.trending_up,
              size: 18, color: theme.colorScheme.primary),
          tone: theme.colorScheme.primary,
        ),
        _summaryTile(
          label: 'Est. margin',
          value: _fmtMoney(totalMargin),
          icon: Icon(Icons.analytics_outlined,
              size: 18, color: theme.colorScheme.primary),
          tone: theme.colorScheme.primary,
        ),
      ]);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles,
        ),
      ),
    );
  }

  Widget _ordersToolbar() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;
            if (isNarrow) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Orders',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<_OrderSortMode>(
                      value: _sortMode,
                      decoration: const InputDecoration(
                        labelText: 'Sort by',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _OrderSortMode.daysRemainingAsc,
                          child: Text('Days remaining'),
                        ),
                        DropdownMenuItem(
                          value: _OrderSortMode.receivedDateDesc,
                          child: Text('Received date'),
                        ),
                        DropdownMenuItem(
                          value: _OrderSortMode.createdDateDesc,
                          child: Text('Created date'),
                        ),
                        DropdownMenuItem(
                          value: _OrderSortMode.orderNumberAsc,
                          child: Text('Order number'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _sortMode = v ?? _sortMode),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: widget.canEdit ? _showCreateOrderDialog : null,
                    icon: const Iconify(Mdi.plus, size: 18),
                    label: const Text('Create order'),
                  ),
                  Text(
                    '${_orders.length} order(s)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Text(
                  'Orders',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<_OrderSortMode>(
                    value: _sortMode,
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _OrderSortMode.daysRemainingAsc,
                        child: Text('Days remaining'),
                      ),
                      DropdownMenuItem(
                        value: _OrderSortMode.receivedDateDesc,
                        child: Text('Received date'),
                      ),
                      DropdownMenuItem(
                        value: _OrderSortMode.createdDateDesc,
                        child: Text('Created date'),
                      ),
                      DropdownMenuItem(
                        value: _OrderSortMode.orderNumberAsc,
                        child: Text('Order number'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _sortMode = v ?? _sortMode),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_orders.length} order(s)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.canEdit ? _showCreateOrderDialog : null,
                  icon: const Iconify(Mdi.plus, size: 18),
                  label: const Text('Create order'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedOrders(_orders);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _pageHeader(),
          const SizedBox(height: 12),
          _summaryCard(),
          const SizedBox(height: 12),
          _ordersToolbar(),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No PSA orders yet.')),
            )
          else
            ...sorted.map(_orderCard),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
