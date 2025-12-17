// lib/inventory/widgets/table_by_status.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/status_utils.dart';
import '../utils/format.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

enum InventoryTableMode { full, vault }

/// Type de tri (pour choisir l'ordre par défaut)
enum _SortKind { text, number, date }

/// Descripteur d'une colonne triable
class _ColumnSortSpec {
  const _ColumnSortSpec(this.kind, this.selector);

  final _SortKind kind;
  final Comparable? Function(Map<String, dynamic> row) selector;
}

const double _kColumnDividerWidth = 10.0;

class InventoryTableByStatus extends StatefulWidget {
  const InventoryTableByStatus({
    super.key,
    this.mode = InventoryTableMode.full,
    required this.lines,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
    this.showDelete = true,
    this.showUnitCosts = true,
    this.showRevenue = true,
    this.showEstimated = true,
    required this.onInlineUpdate,

    // ⭐️ Mode édition de groupe
    this.groupMode = false,
    this.selection = const <String>{},
    required this.lineKey,
    this.onToggleSelect,
    this.onToggleSelectAll,
  });

  final InventoryTableMode mode;

  final List<Map<String, dynamic>> lines;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>)? onEdit;
  final void Function(Map<String, dynamic>)? onDelete;
  final Future<void> Function(
    Map<String, dynamic> line,
    String field,
    dynamic newValue,
  ) onInlineUpdate;

  /// Flags RBAC
  final bool showDelete;
  final bool showUnitCosts;
  final bool showRevenue;
  final bool showEstimated;

  // ======== Group Edit mode ========
  final bool groupMode; // remplace le stylo par des checkboxes
  final Set<String> selection; // keys des lignes sélectionnées
  final String Function(Map<String, dynamic> line) lineKey;
  final void Function(Map<String, dynamic> line, bool selected)? onToggleSelect;
  final void Function(bool selectAll)? onToggleSelectAll;

  @override
  State<InventoryTableByStatus> createState() => _InventoryTableByStatusState();
}

class _InventoryTableByStatusState extends State<InventoryTableByStatus> {
  // ✅ Compact density (pro grid feel)
  static const double _headH = 48;
  static const double _rowH = 48;
  static const double _sideW = 52;

  // limites de largeur des colonnes
  static const double _minColWidth = 60;
  static const double _maxColWidth = 720;

  /// Hover sync across fixed-left / center / fixed-right
  String? _hoveredKey;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

  // ✅ Multi-devise sale_price: on affiche sale_currency si dispo
  String _saleCurrency(Map<String, dynamic> r) {
    final sc = (r['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc;
    final c = (r['currency'] ?? '').toString().trim();
    return c.isNotEmpty ? c : 'USD';
  }

  static const List<String> _allStatuses = [
    'ordered',
    'paid',
    'in_transit',
    'received',
    'waiting_for_gradation',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
    'vault',
  ];

  /// Lignes triées localement (copie de widget.lines)
  late List<Map<String, dynamic>> _sortedLines;

  /// Index de la colonne triée
  int? _sortColumnIndex;

  /// true = flèche vers le haut, false = flèche vers le bas
  bool _sortAscending = true;

  /// Largeurs actuelles des colonnes
  List<double>? _columnWidths;

  @override
  void initState() {
    super.initState();
    _resetSortedLines();
  }

  @override
  void didUpdateWidget(covariant InventoryTableByStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetSortedLines();

    final columnsChanged = widget.mode != oldWidget.mode ||
        widget.showUnitCosts != oldWidget.showUnitCosts ||
        widget.showEstimated != oldWidget.showEstimated ||
        widget.showRevenue != oldWidget.showRevenue;

    if (columnsChanged) {
      _columnWidths = null; // on recalculera des valeurs par défaut
    }

    // reset hover if selection changed a lot
    if (oldWidget.lines != widget.lines) {
      _hoveredKey = null;
    }
  }

  void _resetSortedLines() {
    _sortedLines = List<Map<String, dynamic>>.from(widget.lines);

    final specs = _columnSpecs();
    if (_sortColumnIndex != null) {
      if (_sortColumnIndex! < 0 ||
          _sortColumnIndex! >= specs.length ||
          specs.isEmpty) {
        _sortColumnIndex = null;
      } else {
        _sortLines(_sortColumnIndex!, _sortAscending);
      }
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Déclare, dans le même ordre que les colonnes affichées,
  /// la façon de trier chaque colonne.
  List<_ColumnSortSpec> _columnSpecs() {
    if (widget.mode == InventoryTableMode.vault) {
      return [
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['photo_url'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['grading_note'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['product_name'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['language'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['game_label'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.date, (r) => _parseDate(r['purchase_date'])),
        _ColumnSortSpec(
            _SortKind.number, (r) => (r['qty_status'] as num? ?? 0)),
        _ColumnSortSpec(_SortKind.text,
            (r) => (r['status'] ?? '').toString().toLowerCase()),
        _ColumnSortSpec(_SortKind.number, (r) {
          final unitCost = (r['unit_cost'] as num?) ?? 0;
          final unitFees = (r['unit_fees'] as num?) ?? 0;
          return unitCost + unitFees;
        }),
        _ColumnSortSpec(
            _SortKind.number, (r) => (r['market_price'] as num?) ?? 0),
      ];
    }

    final specs = <_ColumnSortSpec>[
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['photo_url'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['grading_note'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['product_name'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['language'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['game_label'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.date, (r) => _parseDate(r['purchase_date'])),
      _ColumnSortSpec(_SortKind.number, (r) => (r['qty_status'] as num? ?? 0)),
      _ColumnSortSpec(
          _SortKind.text, (r) => (r['status'] ?? '').toString().toLowerCase()),
    ];

    if (widget.showUnitCosts) {
      specs.add(_ColumnSortSpec(_SortKind.number, (r) {
        final qtyTotal = (r['qty_total'] as num?) ?? 0;
        final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
        if (qtyTotal == 0) return 0;
        return totalWithFees / qtyTotal;
      }));
      specs.add(_ColumnSortSpec(_SortKind.number, (r) {
        final qtyTotal = (r['qty_total'] as num?) ?? 0;
        final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
        final q = (r['qty_status'] as num?) ?? 0;
        final unit = qtyTotal > 0 ? (totalWithFees / qtyTotal) : 0;
        return unit * q;
      }));
    }

    if (widget.showEstimated) {
      specs.add(_ColumnSortSpec(
          _SortKind.number, (r) => (r['estimated_price'] as num?) ?? 0));
    }

    specs.addAll([
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['supplier_name'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['buyer_company'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['item_location'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['grade_id'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.date, (r) => _parseDate(r['sale_date'])),
    ]);

    if (widget.showRevenue) {
      specs.add(_ColumnSortSpec(
          _SortKind.number, (r) => (r['sale_price'] as num?) ?? 0));
    }

    specs.addAll([
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['buyer_infos'] ?? '').toString().toLowerCase()),
      _ColumnSortSpec(_SortKind.text,
          (r) => (r['document_url'] ?? '').toString().toLowerCase()),
    ]);

    return specs;
  }

  /// Titres des colonnes, dans le même ordre que _columnSpecs()
  List<String> _columnTitles() {
    if (widget.mode == InventoryTableMode.vault) {
      return const [
        'Photo',
        'Grading note',
        'Product',
        'Language',
        'Game',
        'Purchase',
        'Qty',
        'Status',
        'Price / unit',
        'Market / unit',
      ];
    }

    return <String>[
      'Photo',
      'Grading note',
      'Product',
      'Language',
      'Game',
      'Purchase',
      'Qty',
      'Status',
      if (widget.showUnitCosts) 'Price / unit',
      if (widget.showUnitCosts) 'Price (Qty×unit)',
      if (widget.showEstimated) 'Estimated / unit',
      'Supplier',
      'Buyer',
      'Item location',
      'Grade ID',
      'Sale date',
      if (widget.showRevenue) 'Sale price',
      'buyer infos',
      'Doc',
    ];
  }

  List<double> _buildDefaultWidths(int count) {
    if (widget.mode == InventoryTableMode.vault) {
      final base = <double>[
        70,
        120,
        230,
        90,
        110,
        110,
        60,
        130,
        110,
        140,
      ];
      assert(base.length == count);
      return base;
    }

    final base = <double>[
      70,
      120,
      230,
      90,
      110,
      110,
      60,
      130,
      if (widget.showUnitCosts) 110,
      if (widget.showUnitCosts) 120,
      if (widget.showEstimated) 120,
      140,
      140,
      160,
      110,
      110,
      if (widget.showRevenue) 120,
      170,
      100,
    ];
    assert(base.length == count);
    return base;
  }

  List<double> _ensureColumnWidths(int count) {
    if (_columnWidths == null || _columnWidths!.length != count) {
      _columnWidths = _buildDefaultWidths(count);
    }
    return _columnWidths!;
  }

  void _onResizeColumn(int columnIndex, double delta) {
    if (_columnWidths == null) return;
    setState(() {
      final w = _columnWidths!;
      w[columnIndex] =
          (w[columnIndex] + delta).clamp(_minColWidth, _maxColWidth);
    });
  }

  double _totalTableWidth(List<double> widths) {
    if (widths.isEmpty) return 0;
    return widths.fold<double>(0, (sum, w) => sum + w) +
        _kColumnDividerWidth * (widths.length - 1);
  }

  Alignment _alignForColumn(int columnIndex) {
    final specs = _columnSpecs();
    if (columnIndex < 0 || columnIndex >= specs.length) {
      return Alignment.centerLeft;
    }
    switch (specs[columnIndex].kind) {
      case _SortKind.number:
        return Alignment.centerRight;
      case _SortKind.date:
        return Alignment.center;
      case _SortKind.text:
        return Alignment.centerLeft;
    }
  }

  /// Tooltip + copy-on-long-press (nice grid UX)
  Widget _maybeWrapWithTooltipAndCopy(BuildContext context, Widget child) {
    if (child is Text) {
      final data = child.data;
      if (data == null || data.isEmpty || data == '—') return child;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: data));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied')),
          );
        },
        child: Tooltip(
          message: data,
          waitDuration: const Duration(milliseconds: 350),
          child: Text(
            data,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: child.textAlign,
            style: child.style,
            softWrap: false,
          ),
        ),
      );
    }
    return child;
  }

  bool _defaultAscendingFor(int columnIndex) {
    final specs = _columnSpecs();
    if (columnIndex < 0 || columnIndex >= specs.length) return true;
    final kind = specs[columnIndex].kind;

    switch (kind) {
      case _SortKind.text:
        return true;
      case _SortKind.number:
      case _SortKind.date:
        return false;
    }
  }

  void _handleSort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = _defaultAscendingFor(columnIndex);
      }
      _sortLines(_sortColumnIndex!, _sortAscending);
    });
  }

  void _sortLines(int columnIndex, bool ascending) {
    final specs = _columnSpecs();
    if (columnIndex < 0 || columnIndex >= specs.length || specs.isEmpty) return;

    final spec = specs[columnIndex];
    final sel = spec.selector;

    _sortedLines.sort((a, b) {
      final av = sel(a);
      final bv = sel(b);

      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;

      final cmp = av.compareTo(bv);
      return ascending ? cmp : -cmp;
    });
  }

  void _setHovered(String? key) {
    if (_hoveredKey == key) return;
    setState(() => _hoveredKey = key);
  }

  // Couleur de fond d’une ligne (partagée entre colonnes fixes et center)
  Color _rowBg(BuildContext ctx, Map<String, dynamic> r,
      {required bool selected, required bool hovered}) {
    final s = (r['status'] ?? '').toString();
    final base = statusColor(ctx, s);

    // pro grid: lighter baseline, stronger on hover, strongest on selection
    final double baseOp = selected ? 0.26 : 0.14;
    final double hoverAdd = hovered ? 0.10 : 0.0;

    final double op = (baseOp + hoverAdd).clamp(0.10, 0.42);
    return base.withOpacity(op);
  }

  // ---- VAULT cells ----
  DataRow _vaultRow(BuildContext context, Map<String, dynamic> r,
      {required bool selected, required bool hovered}) {
    final s = (r['status'] ?? '').toString();
    final q = (r['qty_status'] as int?) ?? 0;

    final unitCost = (r['unit_cost'] as num?) ?? 0;
    final unitFees = (r['unit_fees'] as num?) ?? 0;
    final unit = unitCost + unitFees;

    final currency = (r['currency']?.toString() ?? 'USD');

    final num? market = (r['market_price'] as num?);
    final num? deltaPct = (r['market_change_pct'] as num?);
    final String mk = (r['market_kind']?.toString() ?? 'Raw');

    final bg = _rowBg(context, r, selected: selected, hovered: hovered);

    Widget marketCell() {
      final num effectiveDelta = deltaPct ?? 0;

      final trendColor = effectiveDelta > 0
          ? Colors.green
          : (effectiveDelta < 0 ? Colors.redAccent : Colors.black54);

      final trendIcon =
          effectiveDelta >= 0 ? Icons.trending_up : Icons.trending_down;

      final pctText =
          '${effectiveDelta >= 0 ? '+' : ''}${effectiveDelta.toStringAsFixed(1)}%';

      return Tooltip(
        message: 'Market: $mk',
        child: Row(
          children: [
            Text(
              market == null ? '—' : '${money(market)} $currency',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Icon(trendIcon, size: 16, color: trendColor),
            const SizedBox(width: 4),
            Text(pctText, style: TextStyle(color: trendColor)),
          ],
        ),
      );
    }

    final cells = <DataCell>[
      DataCell(
          _FileCell(url: r['photo_url']?.toString(), isImagePreferred: true)),
      DataCell(Text(_txt(r['grading_note']))),
      DataCell(
        Tooltip(
          message: r['product_name']?.toString() ?? '',
          waitDuration: const Duration(milliseconds: 350),
          child: InkWell(
            onTap: () => widget.onOpen(r),
            child: Text(
              r['product_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ),
      ),
      DataCell(Text(r['language']?.toString() ?? '')),
      DataCell(Text(r['game_label']?.toString() ?? '—')),
      DataCell(Text(r['purchase_date']?.toString() ?? '')),
      DataCell(Text('$q')),
      DataCell(
        _EditableStatusCell(
          enabled: !widget.groupMode,
          value: s,
          statuses: _allStatuses.where((x) => x != 'vault').toList(),
          color: statusColor(context, s),
          onSaved: (val) async {
            if (val != null && val.isNotEmpty && val != s) {
              await widget.onInlineUpdate(r, 'status', val);
            }
          },
        ),
      ),
      DataCell(Text('${money(unit)} $currency')),
      DataCell(marketCell()),
    ];

    return DataRow(
      color: MaterialStateProperty.all(bg),
      onSelectChanged: null,
      cells: cells,
    );
  }

  // ---- FULL row ----
  DataRow _fullRow(BuildContext context, Map<String, dynamic> r,
      {required bool selected, required bool hovered}) {
    final s = (r['status'] ?? '').toString();
    final q = (r['qty_status'] as int?) ?? 0;

    final qtyTotal = (r['qty_total'] as num?) ?? 0;
    final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
    final unit = (qtyTotal > 0) ? (totalWithFees / qtyTotal) : 0;
    final sumUnitTotal = unit * q;

    final est = (r['estimated_price'] as num?);
    final currency = (r['currency']?.toString() ?? 'USD');

    final bg = _rowBg(context, r, selected: selected, hovered: hovered);

    final cells = <DataCell>[
      DataCell(
          _FileCell(url: r['photo_url']?.toString(), isImagePreferred: true)),
      DataCell(Text(_txt(r['grading_note']))),
      DataCell(
        Tooltip(
          message: r['product_name']?.toString() ?? '',
          waitDuration: const Duration(milliseconds: 350),
          child: InkWell(
            onTap: () => widget.onOpen(r),
            child: Text(
              r['product_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ),
      ),
      DataCell(Text(r['language']?.toString() ?? '')),
      DataCell(Text(r['game_label']?.toString() ?? '—')),
      DataCell(Text(r['purchase_date']?.toString() ?? '')),
      DataCell(Text('$q')),
      DataCell(
        _EditableStatusCell(
          enabled: !widget.groupMode,
          value: s,
          statuses: _allStatuses.toList(),
          color: statusColor(context, s),
          onSaved: (val) async {
            if (val != null && val.isNotEmpty && val != s) {
              await widget.onInlineUpdate(r, 'status', val);
            }
          },
        ),
      ),
    ];

    if (widget.showUnitCosts) {
      cells.addAll([
        DataCell(Text('${money(unit)} $currency')),
        DataCell(Text('${money(sumUnitTotal)} $currency')),
      ]);
    }

    if (widget.showEstimated) {
      cells.add(
        DataCell(
          _EditableTextCell(
            initialText: est == null ? '' : est.toString(),
            placeholder: '—',
            onSaved: (t) async {
              await widget.onInlineUpdate(r, 'estimated_price', t);
            },
          ),
        ),
      );
    }

    cells.addAll([
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['supplier_name']) == '—'
              ? ''
              : r['supplier_name'].toString(),
          onSaved: (t) async => widget.onInlineUpdate(r, 'supplier_name', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['buyer_company']) == '—'
              ? ''
              : r['buyer_company'].toString(),
          onSaved: (t) async => widget.onInlineUpdate(r, 'buyer_company', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['item_location']) == '—'
              ? ''
              : r['item_location'].toString(),
          onSaved: (t) async => widget.onInlineUpdate(r, 'item_location', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['grade_id']) == '—' ? '' : r['grade_id'].toString(),
          onSaved: (t) async => widget.onInlineUpdate(r, 'grade_id', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['sale_date']) == '—' ? '' : r['sale_date'].toString(),
          placeholder: 'YYYY-MM-DD',
          onSaved: (t) async => widget.onInlineUpdate(r, 'sale_date', t),
        ),
      ),
    ]);

    if (widget.showRevenue) {
      final sale = r['sale_price'];
      final saleCur = _saleCurrency(r);

      cells.add(
        DataCell(
          _EditableTextCell(
            initialText: sale == null ? '' : sale.toString(),
            placeholder: '—',
            displaySuffix: sale == null ? null : ' $saleCur',
            formatMoney: true,
            onSaved: (t) async => widget.onInlineUpdate(r, 'sale_price', t),
          ),
        ),
      );
    }

    cells.add(
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['buyer_infos']) == '—' ? '' : r['buyer_infos'].toString(),
          onSaved: (t) async => widget.onInlineUpdate(r, 'buyer_infos', t),
        ),
      ),
    );

    cells.add(DataCell(_FileCell(url: r['document_url']?.toString())));

    return DataRow(
      color: MaterialStateProperty.all(bg),
      onSelectChanged: null,
      cells: cells,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final lines = _sortedLines;

    // ------ Fixed-left (✏️ or ✅) ------
    final allSelected = widget.groupMode &&
        widget.selection.length == lines.length &&
        lines.isNotEmpty;
    final anySelected = widget.groupMode && widget.selection.isNotEmpty;
    final bool? headerCheckValue = !widget.groupMode
        ? false
        : (allSelected ? true : (anySelected ? null : false));

    final fixedLeft = _FixedSideColumn(
      width: _sideW,
      headerHeight: _headH,
      rowHeight: _rowH,
      side: _FixedSide.left,
      header: Container(
        height: _headH,
        alignment: Alignment.center,
        child: widget.groupMode
            ? Checkbox(
                tristate: true,
                value: headerCheckValue,
                onChanged: (_) {
                  widget.onToggleSelectAll?.call(!allSelected);
                },
              )
            : const Icon(Icons.edit, size: 18, color: Colors.black45),
      ),
      rows: [
        for (final r in lines)
          Builder(builder: (_) {
            final key = widget.lineKey(r);
            final selected =
                widget.groupMode ? widget.selection.contains(key) : false;
            final hovered = _hoveredKey == key;

            return MouseRegion(
              onEnter: (_) => _setHovered(key),
              onExit: (_) =>
                  _setHovered(_hoveredKey == key ? null : _hoveredKey),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: _rowH,
                alignment: Alignment.center,
                color: _rowBg(context, r, selected: selected, hovered: hovered),
                child: widget.groupMode
                    ? Checkbox(
                        value: selected,
                        onChanged: (v) =>
                            widget.onToggleSelect?.call(r, (v ?? false)),
                      )
                    : IconButton(
                        tooltip: 'Edit this listing',
                        icon: const Iconify(
                          Mdi.pencil,
                          size: 20,
                          color: Color.fromARGB(255, 34, 35, 36),
                        ),
                        onPressed: widget.onEdit == null
                            ? null
                            : () => widget.onEdit!(r),
                      ),
              ),
            );
          }),
      ],
    );

    // ------ Fixed-right (❌) ------
    final fixedRight = !widget.showDelete
        ? const SizedBox.shrink()
        : _FixedSideColumn(
            width: _sideW,
            headerHeight: _headH,
            rowHeight: _rowH,
            side: _FixedSide.right,
            header: Container(
              height: _headH,
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 18, color: Colors.black45),
            ),
            rows: [
              for (final r in lines)
                Builder(builder: (_) {
                  final key = widget.lineKey(r);
                  final selected =
                      widget.groupMode ? widget.selection.contains(key) : false;
                  final hovered = _hoveredKey == key;

                  return MouseRegion(
                    onEnter: (_) => _setHovered(key),
                    onExit: (_) =>
                        _setHovered(_hoveredKey == key ? null : _hoveredKey),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      height: _rowH,
                      alignment: Alignment.center,
                      color: _rowBg(context, r,
                          selected: selected, hovered: hovered),
                      child: IconButton(
                        tooltip: 'Delete this row',
                        icon: const Iconify(Mdi.close,
                            size: 18, color: Colors.redAccent),
                        onPressed: widget.onDelete == null
                            ? null
                            : () => widget.onDelete!(r),
                      ),
                    ),
                  );
                }),
            ],
          );

    // ------ Center: columns + sorting + resizing ------
    final columnTitles = _columnTitles();
    final colCount = columnTitles.length;

    assert(_columnSpecs().length == colCount,
        'columnSpecs() and _columnTitles() length mismatch');

    final widths = _ensureColumnWidths(colCount);
    final tableWidth = _totalTableWidth(widths);

    final dataRows = <DataRow>[];
    for (final r in lines) {
      final key = widget.lineKey(r);
      final selected =
          widget.groupMode ? widget.selection.contains(key) : false;
      final hovered = _hoveredKey == key;

      dataRows.add(
        widget.mode == InventoryTableMode.vault
            ? _vaultRow(context, r, selected: selected, hovered: hovered)
            : _fullRow(context, r, selected: selected, hovered: hovered),
      );
    }

    Widget buildHeaderRow() {
      return Container(
        height: _headH,
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(.40),
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < colCount; i++) ...[
              SizedBox(
                width: widths[i],
                child: _HeaderCell(
                  title: columnTitles[i],
                  isSorted: _sortColumnIndex == i,
                  ascending: _sortAscending,
                  onTap: () => _handleSort(i),
                ),
              ),
              if (i < colCount - 1)
                _ColumnResizeHandle(
                  height: _headH,
                  accent: cs.primary,
                  onDrag: (delta) => _onResizeColumn(i, delta),
                ),
            ],
          ],
        ),
      );
    }

    Widget buildDataRowWidget(DataRow row, Map<String, dynamic> sourceRow) {
      final key = widget.lineKey(sourceRow);
      final selected =
          widget.groupMode ? widget.selection.contains(key) : false;
      final hovered = _hoveredKey == key;

      final bg =
          _rowBg(context, sourceRow, selected: selected, hovered: hovered);

      final cells = row.cells;

      return MouseRegion(
        onEnter: (_) => _setHovered(key),
        onExit: (_) => _setHovered(_hoveredKey == key ? null : _hoveredKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: _rowH,
          color: bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < colCount; i++) ...[
                SizedBox(
                  width: widths[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: _alignForColumn(i),
                      child: _maybeWrapWithTooltipAndCopy(
                        context,
                        cells[i].child,
                      ),
                    ),
                  ),
                ),
                if (i < colCount - 1)
                  _ColumnResizeHandle(
                    height: _rowH,
                    accent: cs.primary,
                    onDrag: (delta) => _onResizeColumn(i, delta),
                    subtle: true,
                  ),
              ],
            ],
          ),
        ),
      );
    }

    final centerTable = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeaderRow(),
            for (int i = 0; i < dataRows.length; i++)
              buildDataRowWidget(dataRows[i], lines[i]),
          ],
        ),
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SelectionArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fixedLeft,
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left:
                          BorderSide(color: cs.outlineVariant.withOpacity(.55)),
                      right:
                          BorderSide(color: cs.outlineVariant.withOpacity(.55)),
                    ),
                  ),
                  child: centerTable,
                ),
              ),
              fixedRight,
            ],
          ),
        ),
      ),
    );
  }
}

/* ============== Fixed side columns ============== */

enum _FixedSide { left, right }

class _FixedSideColumn extends StatelessWidget {
  const _FixedSideColumn({
    required this.width,
    required this.headerHeight,
    required this.rowHeight,
    required this.side,
    required this.header,
    required this.rows,
  });

  final double width;
  final double headerHeight;
  final double rowHeight;
  final _FixedSide side;
  final Widget header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final shadow = side == _FixedSide.left
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(2, 0),
            )
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(-2, 0),
            )
          ];

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: shadow,
          border: Border(
            right: side == _FixedSide.left
                ? BorderSide(color: cs.outlineVariant.withOpacity(.55))
                : BorderSide.none,
            left: side == _FixedSide.right
                ? BorderSide(color: cs.outlineVariant.withOpacity(.55))
                : BorderSide.none,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: headerHeight,
              alignment: Alignment.center,
              color: cs.surfaceVariant.withOpacity(.40),
              child: header,
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/* ============== Cellules éditables ============== */

class _EditableTextCell extends StatefulWidget {
  const _EditableTextCell({
    required this.initialText,
    required this.onSaved,
    this.placeholder,
    this.displaySuffix,
    this.formatMoney = false,
  });

  final String initialText;
  final Future<void> Function(String newValue) onSaved;
  final String? placeholder;
  final String? displaySuffix;
  final bool formatMoney;

  @override
  State<_EditableTextCell> createState() => _EditableTextCellState();
}

class _EditableTextCellState extends State<_EditableTextCell> {
  bool _editing = false;
  late final TextEditingController _c;
  bool _saving = false;

  late final FocusNode _focusNode;
  String _original = '';

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_editing && !_focusNode.hasFocus && !_saving) {
        _c.text = _original;
        setState(() => _editing = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EditableTextCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.initialText != widget.initialText) {
      _c.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSaved(_c.text.trim());
      if (!mounted) return;
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit() {
    _original = _c.text;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  String _formatMoneyIfPossible(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    final n = num.tryParse(t);
    if (n == null) return raw.trim();
    return n.toDouble().toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      final raw = _c.text.trim();

      final base = raw.isEmpty
          ? (widget.placeholder ?? '—')
          : (widget.formatMoney ? _formatMoneyIfPossible(raw) : raw);

      final suffix =
          (raw.isEmpty || base == '—') ? '' : (widget.displaySuffix ?? '');

      final display = '$base$suffix';

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _startEdit,
        onLongPress: _startEdit,
        child: Tooltip(
          message: display,
          waitDuration: const Duration(milliseconds: 350),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    return RawKeyboardListener(
      focusNode: FocusNode(),
      onKey: (evt) {
        if (evt.isKeyPressed(LogicalKeyboardKey.escape)) {
          _c.text = _original;
          setState(() => _editing = false);
        }
      },
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focusNode,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  children: [
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        _c.text = _original;
                        setState(() => _editing = false);
                      },
                    ),
                    IconButton(
                      tooltip: 'Save',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: _save,
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _EditableStatusCell extends StatefulWidget {
  const _EditableStatusCell({
    required this.value,
    required this.statuses,
    required this.color,
    required this.onSaved,
    this.enabled = true,
  });

  final String value;
  final List<String> statuses;
  final Color color;
  final Future<void> Function(String? newValue) onSaved;
  final bool enabled;

  @override
  State<_EditableStatusCell> createState() => _EditableStatusCellState();
}

class _EditableStatusCellState extends State<_EditableStatusCell> {
  bool _editing = false;
  String? _value;
  bool _saving = false;

  String? _original;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _EditableStatusCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _value = widget.value;
    }
    if (!widget.enabled && _editing) {
      setState(() {
        _value = _original;
        _editing = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSaved(_value);
      if (!mounted) return;
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit() {
    if (!widget.enabled) return;
    _original = _value;
    setState(() => _editing = true);
  }

  @override
  Widget build(BuildContext context) {
    final chip = Chip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text((widget.value).toUpperCase()),
      backgroundColor: widget.color.withOpacity(0.15),
      side: BorderSide(color: widget.color.withOpacity(0.6)),
    );

    if (!widget.enabled) return chip;

    if (!_editing) {
      return GestureDetector(
        onDoubleTap: _startEdit,
        onLongPress: _startEdit,
        child: chip,
      );
    }

    return RawKeyboardListener(
      focusNode: FocusNode(),
      onKey: (evt) {
        if (evt.isKeyPressed(LogicalKeyboardKey.escape)) {
          setState(() {
            _value = _original;
            _editing = false;
          });
        }
      },
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _value,
                icon: const Icon(Icons.arrow_drop_down),
                items: widget.statuses.map((s) {
                  final c = statusColor(context, s);
                  return DropdownMenuItem<String>(
                    value: s,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.withOpacity(0.7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.toUpperCase(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: c,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                selectedItemBuilder: (ctx) {
                  return widget.statuses.map((s) {
                    final c = statusColor(ctx, s);
                    return Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                focusColor:
                    _value == null ? null : statusColor(context, _value!),
                onChanged: (v) => setState(() => _value = v),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  children: [
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _value = _original;
                          _editing = false;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Save',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: _save,
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

/* ============== Header + resize handle ============== */

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.title,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  final String title;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            if (isSorted)
              Icon(
                ascending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.70),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.height,
    required this.onDrag,
    required this.accent,
    this.subtle = false,
  });

  final double height;
  final ValueChanged<double> onDrag;
  final Color accent;
  final bool subtle;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lineColor =
        _hover ? widget.accent.withOpacity(.80) : Colors.black.withOpacity(.12);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: _kColumnDividerWidth,
          height: widget.height,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: _hover ? 2.0 : 1.0,
              height:
                  widget.subtle ? widget.height * 0.55 : widget.height * 0.75,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ============== Cellule fichier/photo ============== */

class _FileCell extends StatelessWidget {
  const _FileCell({this.url, this.isImagePreferred = false});
  final String? url;
  final bool isImagePreferred;

  bool get _isImage {
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

  Future<void> _open() async {
    final u = url;
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const Text('—');

    final showImage = isImagePreferred && _isImage;

    if (showImage) {
      final imgUrl = () {
        final u = url!;
        try {
          final uri = Uri.parse(u);
          final fixed = Uri(
            scheme: uri.scheme,
            userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            query: uri.query.isEmpty ? null : uri.query,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          ).toString();
          return fixed;
        } catch (_) {
          return Uri.encodeFull(u);
        }
      }();

      return _HoverableImageThumb(
        imgUrl: imgUrl,
        onTap: _open,
      );
    }

    return IconButton(
      icon: const Iconify(Mdi.file_document),
      tooltip: 'Open document',
      onPressed: _open,
    );
  }
}

class _HoverableImageThumb extends StatefulWidget {
  const _HoverableImageThumb({
    required this.imgUrl,
    this.onTap,
  });

  final String imgUrl;
  final VoidCallback? onTap;

  @override
  State<_HoverableImageThumb> createState() => _HoverableImageThumbState();
}

class _HoverableImageThumbState extends State<_HoverableImageThumb> {
  OverlayEntry? _overlayEntry;

  void _showPreview(PointerEnterEvent event) {
    if (_overlayEntry != null) return;

    final overlay = Overlay.of(context);
    final offset = event.position;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: offset.dx + 12,
          top: offset.dy + 12,
          child: IgnorePointer(
            ignoring: true,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 320,
                ),
                child: Image.network(
                  widget.imgUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _hidePreview([PointerExitEvent? event]) {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hidePreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _showPreview,
      onExit: _hidePreview,
      child: InkWell(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            widget.imgUrl,
            height: 32,
            width: 32,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            cacheWidth: 64,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 32,
                width: 32,
                child: Center(
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 32,
              width: 32,
              child: Icon(Icons.broken_image, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}
