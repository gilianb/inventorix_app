// lib/psa/ui/psa_order_details_page.dart
// ignore_for_file: use_build_context_synchronously, unused_element, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

import '../data/psa_repository.dart';
import '../models/psa_models.dart';
import '../utils/business_days.dart';
import '../../inventory/utils/status_utils.dart';

class PsaOrderDetailsPage extends StatefulWidget {
  const PsaOrderDetailsPage({
    super.key,
    required this.orgId,
    required this.order,
    required this.canEdit,
    required this.canSeeFinance,
    required this.canSeeUnitCosts,
  });

  final String orgId;
  final PsaOrderSummary order;
  final bool canEdit;
  final bool canSeeFinance;
  final bool canSeeUnitCosts;

  @override
  State<PsaOrderDetailsPage> createState() => _PsaOrderDetailsPageState();
}

enum _ItemFilter {
  all,
  sentToGrader,
  atGrader,
  graded,
}

class _PsaOrderDetailsPageState extends State<PsaOrderDetailsPage> {
  final _sb = Supabase.instance.client;
  late final PsaRepository repo = PsaRepository(_sb);

  bool _loading = true;
  late PsaOrderSummary _order = widget.order;
  List<PsaOrderItem> _items = const [];
  _ItemFilter _itemFilter = _ItemFilter.all;
  final Map<int, TextEditingController> _gradeCtrls = {};
  final Map<int, TextEditingController> _noteCtrls = {};
  final Set<int> _editingIds = <int>{};
  final Set<int> _savingIds = <int>{};

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : d.toIso8601String().split('T').first;

  String _fmtMoney(num v) => v.toStringAsFixed(2);

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

  TextEditingController _gradeCtrlFor(PsaOrderItem it) {
    return _gradeCtrls.putIfAbsent(
        it.id, () => TextEditingController(text: it.gradeId ?? ''));
  }

  TextEditingController _noteCtrlFor(PsaOrderItem it) {
    return _noteCtrls.putIfAbsent(
        it.id, () => TextEditingController(text: it.gradingNote ?? ''));
  }

  void _syncItemControllers(List<PsaOrderItem> items) {
    final ids = items.map((it) => it.id).toSet();
    final stale = _gradeCtrls.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      _gradeCtrls[id]?.dispose();
      _noteCtrls[id]?.dispose();
      _gradeCtrls.remove(id);
      _noteCtrls.remove(id);
      _editingIds.remove(id);
      _savingIds.remove(id);
    }

    for (final it in items) {
      final grade = it.gradeId ?? '';
      final note = it.gradingNote ?? '';
      final gc = _gradeCtrls[it.id];
      if (gc != null && gc.text != grade) gc.text = grade;
      final nc = _noteCtrls[it.id];
      if (nc != null && nc.text != note) nc.text = note;
    }
  }

  bool _isEditing(PsaOrderItem it) => _editingIds.contains(it.id);

  void _toggleEditing(PsaOrderItem it, {bool? value}) {
    if (!widget.canEdit) return;
    setState(() {
      if (value ?? !_editingIds.contains(it.id)) {
        _editingIds.add(it.id);
      } else {
        _editingIds.remove(it.id);
      }
    });
  }

  Future<void> _saveInlineGrade(PsaOrderItem it) async {
    if (!widget.canEdit) return;
    setState(() => _savingIds.add(it.id));
    try {
      await repo.updateItemGrade(
        orgId: widget.orgId,
        itemId: it.id,
        gradeId: _gradeCtrlFor(it).text,
        gradingNote: _noteCtrlFor(it).text,
      );
      _editingIds.remove(it.id);
      await _refresh();
    } finally {
      if (mounted) setState(() => _savingIds.remove(it.id));
    }
  }

  void _cancelInlineEdit(PsaOrderItem it) {
    _gradeCtrlFor(it).text = it.gradeId ?? '';
    _noteCtrlFor(it).text = it.gradingNote ?? '';
    setState(() => _editingIds.remove(it.id));
  }

  Widget _photoThumb(
    String? url, {
    double size = 52,
    double heightFactor = 1,
  }) {
    final u = (url ?? '').trim();
    final hasPhoto = u.isNotEmpty;
    final height = size * heightFactor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: height,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: hasPhoto
            ? Image.network(
                u,
                width: size,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.photo,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(
                Icons.photo,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      ),
    );
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

  String _statusLabel(String status) {
    switch (status) {
      case 'sent_to_grader':
        return 'Sent';
      case 'at_grader':
        return 'At PSA';
      case 'graded':
        return 'Graded';
      case 'received':
        return 'Received';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _statusTone(String status) => statusColor(context, status);

  String _filterLabel(_ItemFilter f) {
    switch (f) {
      case _ItemFilter.all:
        return 'All';
      case _ItemFilter.sentToGrader:
        return 'Sent';
      case _ItemFilter.atGrader:
        return 'At PSA';
      case _ItemFilter.graded:
        return 'Graded';
    }
  }

  String? _filterStatusValue(_ItemFilter f) {
    switch (f) {
      case _ItemFilter.all:
        return null;
      case _ItemFilter.sentToGrader:
        return 'sent_to_grader';
      case _ItemFilter.atGrader:
        return 'at_grader';
      case _ItemFilter.graded:
        return 'graded';
    }
  }

  List<PsaOrderItem> _filteredItems(List<PsaOrderItem> items) {
    final status = _filterStatusValue(_itemFilter);
    if (status == null) return items;
    return items.where((it) => it.status == status).toList();
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

  Widget _statusBadge(String status) {
    final theme = Theme.of(context);
    final tone = _statusTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.4)),
      ),
      child: Text(
        _statusLabel(status),
        style: theme.textTheme.labelMedium?.copyWith(
          color: tone,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final c in _gradeCtrls.values) {
      c.dispose();
    }
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final items = await repo.fetchOrderItems(
          orgId: widget.orgId, psaOrderId: _order.psaOrderId);
      // refresh summary too
      final summaries = await repo.fetchOrderSummaries(widget.orgId);
      final refreshed = summaries.firstWhere(
          (s) => s.psaOrderId == _order.psaOrderId,
          orElse: () => _order);

      setState(() {
        _items = items;
        _order = refreshed;
      });
      _syncItemControllers(items);
    } on PostgrestException catch (e) {
      _snack('Supabase error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpdateReceivedDate() async {
    if (!widget.canEdit) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _order.psaReceivedDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    await repo.updateOrderReceivedDate(
      orgId: widget.orgId,
      psaOrderId: _order.psaOrderId,
      psaReceivedDate: picked,
    );

    await _refresh();
  }

  Future<void> _addReceivedCardsToOrder() async {
    if (!widget.canEdit) return;

    final candidates = await repo.fetchReceivedCandidates(orgId: widget.orgId);
    if (candidates.isEmpty) {
      _snack('No received single cards available.');
      return;
    }

    final pickedIds = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _PsaPickItemsDialog(items: candidates),
    );

    if (pickedIds == null || pickedIds.isEmpty) return;

    await repo.addItemsToOrder(
      orgId: widget.orgId,
      psaOrderId: _order.psaOrderId,
      gradingServiceId: _order.gradingServiceId,
      defaultFee: _order.defaultFee,
      itemIds: pickedIds.toList(),
    );

    _snack('Added ${pickedIds.length} item(s) to order.');
    await _refresh();
  }

  Future<void> _removeItemFromOrder(PsaOrderItem it) async {
    if (!widget.canEdit) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove item from order?'),
            content: Text(
              'This will move item #${it.id} back to RECEIVED and clear PSA dates/fees. The item will not be deleted.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.removeItemsFromOrder(
      orgId: widget.orgId,
      itemIds: [it.id],
    );

    _snack('Removed item #${it.id} from order.');
    await _refresh();
  }

  Future<void> _deleteOrder() async {
    if (!widget.canEdit) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete PSA order?'),
            content: Text(
              'This will delete order ${_order.orderNumber} and move all items back to RECEIVED. Items will not be deleted.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.deleteOrder(
      orgId: widget.orgId,
      psaOrderId: _order.psaOrderId,
    );

    if (!mounted) return;
    _snack('Order deleted.');
    Navigator.pop(context, true);
  }

  Future<void> _markAtGrader() async {
    if (!widget.canEdit) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mark items as AT_GRADER?'),
            content: const Text(
              'All items currently "sent_to_grader" in this PSA order will become "at_grader".',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.markOrderAtGrader(
      orgId: widget.orgId,
      psaOrderId: _order.psaOrderId,
      psaReceivedDate: _order.psaReceivedDate,
    );

    _snack('Updated items to at_grader.');
    await _refresh();
  }

  Future<void> _markGraded() async {
    if (!widget.canEdit) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mark items as GRADED?'),
            content: const Text(
              'All items currently "at_grader" in this PSA order will become "graded".',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.markOrderGraded(
      orgId: widget.orgId,
      psaOrderId: _order.psaOrderId,
    );

    _snack('Updated items to graded.');
    await _refresh();
  }

  Future<void> _editGrade(PsaOrderItem it) async {
    if (!widget.canEdit) return;

    final gradeCtrl = TextEditingController(text: it.gradeId ?? '');
    final noteCtrl = TextEditingController(text: it.gradingNote ?? '');

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Update grade — #${it.id}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Product: ${it.productName}'),
                const SizedBox(height: 12),
                TextField(
                  controller: gradeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'grade_id (cert #)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'grading note (PSA 10, 9, ...)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await repo.updateItemGrade(
      orgId: widget.orgId,
      itemId: it.id,
      gradeId: gradeCtrl.text,
      gradingNote: noteCtrl.text,
    );

    _snack('Updated grade fields.');
    await _refresh();
  }

  Color _filterTone(_ItemFilter f) {
    switch (f) {
      case _ItemFilter.all:
        return Theme.of(context).colorScheme.primary;
      case _ItemFilter.sentToGrader:
        return statusColor(context, 'sent_to_grader');
      case _ItemFilter.atGrader:
        return statusColor(context, 'at_grader');
      case _ItemFilter.graded:
        return statusColor(context, 'graded');
    }
  }

  Widget _statTile({
    required String label,
    required String value,
    required Color tone,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroHeader() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rem = _daysRemaining(_order);
    final due = _dueDate(_order);
    final tone = _remainingTone(rem, cs);
    final statusLabel = _remainingLabel(rem);
    final serviceLabel = _serviceLabelWithMeta(
      label: _order.serviceLabel,
      days: _order.expectedDays,
      fee: _order.defaultFee,
    );

    String? heroUrl;
    for (final it in _items) {
      if ((it.photoUrl ?? '').trim().isNotEmpty) {
        heroUrl = it.photoUrl;
        break;
      }
    }
    heroUrl ??= _items.isNotEmpty ? _items.first.photoUrl : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer,
            cs.surfaceVariant,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 640;
          final meta = Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _metaLine(
                label: 'Received',
                value: _fmtDate(_order.psaReceivedDate),
                icon: Icons.calendar_today_outlined,
              ),
              _metaLine(
                label: 'Due',
                value: _fmtDate(due),
                icon: Icons.event_available_outlined,
              ),
              _metaLine(
                label: 'Expected',
                value: '${_order.expectedDays} bd',
                icon: Icons.timelapse,
              ),
            ],
          );

          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.16),
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
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _photoThumb(heroUrl, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _order.orderNumber,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serviceLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                meta,
                const SizedBox(height: 12),
                badge,
              ],
            );
          }

          return Row(
            children: [
              //_photoThumb(heroUrl, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _order.orderNumber,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      serviceLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    meta,
                  ],
                ),
              ),
              badge,
            ],
          );
        },
      ),
    );
  }

  Widget _summaryStrip() {
    final theme = Theme.of(context);
    final tiles = <Widget>[
      _statTile(
        label: 'Total',
        value: '${_order.qtyTotal}',
        tone: theme.colorScheme.primary,
        icon: Icons.inventory_2_outlined,
      ),
      _statTile(
        label: 'Sent',
        value: '${_order.qtySentToGrader}',
        tone: statusColor(context, 'sent_to_grader'),
        icon: Icons.local_shipping_outlined,
      ),
      _statTile(
        label: 'At PSA',
        value: '${_order.qtyAtGrader}',
        tone: statusColor(context, 'at_grader'),
        icon: Icons.business_outlined,
      ),
      _statTile(
        label: 'Graded',
        value: '${_order.qtyGraded}',
        tone: statusColor(context, 'graded'),
        icon: Icons.verified_outlined,
      ),
    ];

    if (widget.canSeeFinance) {
      tiles.addAll([
        _statTile(
          label: 'Invested',
          value: _fmtMoney(_order.totalInvested),
          tone: theme.colorScheme.secondary,
          icon: Icons.account_balance_wallet_outlined,
        ),
        _statTile(
          label: 'Est. revenue',
          value: _fmtMoney(_order.estRevenue),
          tone: theme.colorScheme.primary,
          icon: Icons.trending_up,
        ),
        _statTile(
          label: 'Est. margin',
          value: _fmtMoney(_order.potentialMargin),
          tone: theme.colorScheme.primary,
          icon: Icons.analytics_outlined,
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

  Widget _actionsCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.canEdit ? _pickAndUpdateReceivedDate : null,
                  icon: const Iconify(Mdi.calendar, size: 18),
                  label: const Text('Update PSA received date'),
                ),
                FilledButton.icon(
                  onPressed: widget.canEdit ? _addReceivedCardsToOrder : null,
                  icon: const Iconify(Mdi.plus_box, size: 18),
                  label: const Text('Add RECEIVED cards'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.canEdit ? _markAtGrader : null,
                  icon: const Iconify(Mdi.truck_check_outline, size: 18),
                  label: const Text('Mark AT_GRADER'),
                ),
                FilledButton.icon(
                  onPressed: widget.canEdit ? _markGraded : null,
                  icon: const Iconify(Mdi.check_decagram_outline, size: 18),
                  label: const Text('Mark GRADED'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemsToolbar(List<PsaOrderItem> items) {
    final theme = Theme.of(context);
    final counts = <_ItemFilter, int>{
      _ItemFilter.all: items.length,
      _ItemFilter.sentToGrader:
          items.where((it) => it.status == 'sent_to_grader').length,
      _ItemFilter.atGrader:
          items.where((it) => it.status == 'at_grader').length,
      _ItemFilter.graded: items.where((it) => it.status == 'graded').length,
    };

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
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Items',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${items.length} item(s)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ..._ItemFilter.values.map((f) {
              final count = counts[f] ?? 0;
              final tone = _filterTone(f);
              final selected = _itemFilter == f;
              return ChoiceChip(
                label: Text('${_filterLabel(f)} ($count)'),
                selected: selected,
                selectedColor: tone.withOpacity(0.18),
                onSelected: (_) => setState(() => _itemFilter = f),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? tone : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                shape: StadiumBorder(
                  side: BorderSide(color: tone.withOpacity(0.4)),
                ),
              );
            }),
            Text(
              widget.canEdit
                  ? 'Double-click a card to edit grade'
                  : 'Read-only mode',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(PsaOrderItem it) {
    final theme = Theme.of(context);
    final editing = _isEditing(it);
    final saving = _savingIds.contains(it.id);
    final tone = _statusTone(it.status);
    final gradeId = (it.gradeId ?? '').trim();
    final note = (it.gradingNote ?? '').trim();

    final gradeDisplay = gradeId.isEmpty ? '—' : gradeId;
    final noteDisplay = note.isEmpty ? '—' : note;

    final game =
        (it.gameLabel ?? '').trim().isEmpty ? '—' : it.gameLabel!.trim();
    final lang = (it.language ?? '').trim().isEmpty ? '—' : it.language!.trim();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onDoubleTap: widget.canEdit ? () => _toggleEditing(it) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _photoThumb(
                    it.photoUrl,
                    size: 48,
                    heightFactor: 1.5,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.productName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isTight = constraints.maxWidth < 520;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                if (!isTight && game != '—')
                                  _metaLine(
                                    label: 'Game',
                                    value: game,
                                    icon: Icons.sports_esports,
                                  ),
                                _metaLine(
                                  label: 'Lang',
                                  value: lang,
                                  icon: Icons.translate,
                                ),
                                _metaLine(
                                  label: 'Item',
                                  value: '#${it.id}',
                                  icon: Icons.tag,
                                ),
                                _statPill(
                                  label: 'Grade ID',
                                  value: gradeDisplay,
                                  leading: Icon(Icons.verified_outlined,
                                      size: 14, color: tone),
                                  tone: tone,
                                ),
                                _statPill(
                                  label: 'Note',
                                  value: noteDisplay,
                                  leading: Icon(Icons.sticky_note_2_outlined,
                                      size: 14,
                                      color: theme.colorScheme.secondary),
                                  tone: theme.colorScheme.secondary,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _statusBadge(it.status),
                      if (widget.canEdit)
                        IconButton(
                          tooltip: editing ? 'Close edit' : 'Edit grade',
                          onPressed: () => _toggleEditing(it),
                          icon: Iconify(Mdi.pencil_outline, size: 20),
                        ),
                      if (widget.canEdit)
                        IconButton(
                          tooltip: 'Remove from submission',
                          onPressed:
                              saving ? null : () => _removeItemFromOrder(it),
                          icon: Iconify(Mdi.trash_can_outline, size: 20),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (editing)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 520;
                    final gradeField = TextField(
                      controller: _gradeCtrlFor(it),
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Grade ID (cert #)',
                        border: OutlineInputBorder(),
                      ),
                    );
                    final noteField = TextField(
                      controller: _noteCtrlFor(it),
                      enabled: !saving,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Grading note (PSA 10, 9, ...)',
                        border: OutlineInputBorder(),
                      ),
                    );

                    return Column(
                      children: [
                        if (isNarrow) ...[
                          gradeField,
                          const SizedBox(height: 10),
                          noteField,
                        ] else
                          Row(
                            children: [
                              Expanded(child: gradeField),
                              const SizedBox(width: 12),
                              Expanded(child: noteField),
                            ],
                          ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed:
                                  saving ? null : () => _cancelInlineEdit(it),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed:
                                  saving ? null : () => _saveInlineGrade(it),
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                              label: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems(_items);

    return Scaffold(
      appBar: AppBar(
        title: Text('PSA — ${_order.orderNumber}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Iconify(Mdi.refresh, size: 20),
          ),
          if (widget.canEdit)
            IconButton(
              tooltip: 'Delete submission',
              onPressed: _deleteOrder,
              icon: const Iconify(Mdi.trash_can_outline, size: 20),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _heroHeader(),
            const SizedBox(height: 12),
            _summaryStrip(),
            const SizedBox(height: 12),
            _actionsCard(),
            const SizedBox(height: 12),
            _itemsToolbar(_items),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No items in this submission yet.')),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No items match this filter.')),
              )
            else
              ...filtered.map(_itemCard),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _PsaPickItemsDialog extends StatefulWidget {
  const _PsaPickItemsDialog({required this.items});
  final List<PsaOrderItem> items;

  @override
  State<_PsaPickItemsDialog> createState() => _PsaPickItemsDialogState();
}

class _PsaPickItemsDialogState extends State<_PsaPickItemsDialog> {
  final Set<int> _sel = <int>{};
  String _q = '';

  void _setSelected(PsaOrderItem it, bool selected) {
    setState(() {
      if (selected) {
        _sel.add(it.id);
      } else {
        _sel.remove(it.id);
      }
    });
  }

  bool _isImageUrl(String? url) {
    final u = url ?? '';
    if (u.isEmpty) return false;
    try {
      final path = Uri.parse(u).path.toLowerCase();
      return path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.gif') ||
          path.endsWith('.webp');
    } catch (_) {
      final lu = u.toLowerCase();
      return RegExp(r'\.(png|jpe?g|gif|webp)(\?.*)?$').hasMatch(lu);
    }
  }

  String _safeImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        query: uri.query.isEmpty ? null : uri.query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      ).toString();
    } catch (_) {
      return Uri.encodeFull(url);
    }
  }

  Widget _miniThumb(
    String? url, {
    double width = 44,
    double heightFactor = 1.5,
  }) {
    final u = (url ?? '').trim();
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.onSurfaceVariant;
    final height = width * heightFactor;

    Widget box(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: width,
            height: height,
            color: cs.surfaceVariant,
            child: child,
          ),
        );

    if (u.isEmpty) {
      return box(Icon(Icons.photo, color: iconColor, size: width * 0.6));
    }

    if (!_isImageUrl(u)) {
      return box(Icon(Icons.insert_drive_file_outlined,
          color: iconColor, size: width * 0.6));
    }

    final imgUrl = _safeImageUrl(u);

    return box(
      Image.network(
        imgUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: (width * 2).round(),
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image_outlined,
          color: iconColor,
          size: width * 0.6,
        ),
      ),
    );
  }

  Widget _metaChip({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawQ = _q.trim().toLowerCase();
    final tokens = rawQ.isEmpty
        ? const <String>[]
        : rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final filtered = tokens.isEmpty
        ? widget.items
        : widget.items.where((it) {
            final fields = <String>[
              it.productName,
              it.gameLabel ?? '',
              it.language ?? '',
              it.gradeId ?? '',
              it.gradingNote ?? '',
              it.id.toString(),
            ].map((s) => s.toLowerCase()).toList();

            return tokens.every((t) => fields.any((f) => f.contains(t)));
        }).toList();

    final allSelected =
        filtered.isNotEmpty && filtered.every((it) => _sel.contains(it.id));

    return AlertDialog(
      title: const Text('Pick RECEIVED cards'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _sel.addAll(filtered.map((e) => e.id));
                      } else {
                        _sel.removeAll(filtered.map((e) => e.id));
                      }
                    });
                  },
                ),
                const Text('Select all (filtered)'),
                const Spacer(),
                Text('Selected: ${_sel.length}'),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final it = filtered[i];
                  final checked = _sel.contains(it.id);
                  final theme = Theme.of(context);
                  final cs = theme.colorScheme;
                  final gameLabel = (it.gameLabel ?? '').trim().isEmpty
                      ? '—'
                      : it.gameLabel!.trim();
                  final langLabel = (it.language ?? '').trim().isEmpty
                      ? '—'
                      : it.language!.trim();

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Material(
                      color:
                          checked ? cs.primary.withOpacity(0.08) : cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _setSelected(it, !checked),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: checked
                                  ? cs.primary.withOpacity(0.45)
                                  : cs.outlineVariant,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: checked,
                                onChanged: (v) => _setSelected(it, v == true),
                              ),
                              _miniThumb(
                                it.photoUrl,
                                width: 44,
                                heightFactor: 1.5,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it.productName,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _metaChip(
                                          icon: Icons.sports_esports,
                                          label: gameLabel,
                                        ),
                                        _metaChip(
                                          icon: Icons.translate,
                                          label: langLabel,
                                        ),
                                        _metaChip(
                                          icon: Icons.tag,
                                          label: '#${it.id}',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel),
          child: const Text('Add selected'),
        ),
      ],
    );
  }
}
