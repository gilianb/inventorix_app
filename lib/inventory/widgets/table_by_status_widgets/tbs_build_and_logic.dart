// ignore_for_file: invalid_use_of_protected_member, use_build_context_synchronously, deprecated_member_use

part of '../table_by_status.dart';

extension _TbsLogic on _InventoryTableByStatusState {
  String txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

  String saleCurrency(Map<String, dynamic> r) {
    final sc = (r['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc;
    final c = (r['currency'] ?? '').toString().trim();
    return c.isNotEmpty ? c : 'USD';
  }

  DateTime? parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  void resetSortedLines() {
    sortedLines = List<Map<String, dynamic>>.from(widget.lines);

    final specs = columnSpecs();
    if (sortColumnIndex != null) {
      if (sortColumnIndex! < 0 || sortColumnIndex! >= specs.length) {
        sortColumnIndex = null;
      } else {
        sortLines(sortColumnIndex!, sortAscending);
      }
    }
  }

  List<_ColumnSortSpec> columnSpecs() {
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
        _ColumnSortSpec(_SortKind.date, (r) => parseDate(r['purchase_date'])),
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
      _ColumnSortSpec(_SortKind.date, (r) => parseDate(r['purchase_date'])),
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
      _ColumnSortSpec(_SortKind.date, (r) => parseDate(r['sale_date'])),
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

  List<String> columnTitles() {
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

  List<double> buildDefaultWidths(int count) {
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
        150,
      ];
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
    return base;
  }

  List<double> ensureColumnWidths(int count) {
    if (columnWidths == null || columnWidths!.length != count) {
      columnWidths = buildDefaultWidths(count);
    }
    return columnWidths!;
  }

  void onResizeColumn(int columnIndex, double delta) {
    if (columnWidths == null) return;
    setState(() {
      final w = columnWidths!;
      w[columnIndex] = (w[columnIndex] + delta).clamp(
          _InventoryTableByStatusState.minColWidth,
          _InventoryTableByStatusState.maxColWidth);
    });
  }

  double totalTableWidth(List<double> widths) {
    if (widths.isEmpty) return 0;
    return widths.fold<double>(0, (sum, w) => sum + w) +
        _kColumnDividerWidth * (widths.length - 1);
  }

  Alignment alignForColumn(int columnIndex) {
    final specs = columnSpecs();
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

  Widget maybeWrapWithTooltipAndCopy(BuildContext context, Widget child) {
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

  bool defaultAscendingFor(int columnIndex) {
    final specs = columnSpecs();
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

  void handleSort(int columnIndex) {
    setState(() {
      if (sortColumnIndex == columnIndex) {
        sortAscending = !sortAscending;
      } else {
        sortColumnIndex = columnIndex;
        sortAscending = defaultAscendingFor(columnIndex);
      }
      sortLines(sortColumnIndex!, sortAscending);
    });
  }

  void sortLines(int columnIndex, bool ascending) {
    final specs = columnSpecs();
    if (columnIndex < 0 || columnIndex >= specs.length || specs.isEmpty) return;

    final spec = specs[columnIndex];
    final sel = spec.selector;

    sortedLines.sort((a, b) {
      final av = sel(a);
      final bv = sel(b);

      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;

      final cmp = av.compareTo(bv);
      return ascending ? cmp : -cmp;
    });
  }

  void setHovered(String? key) {
    if (hoveredKey == key) return;
    setState(() => hoveredKey = key);
  }

  Color rowBg(BuildContext ctx, Map<String, dynamic> r,
      {required bool selected, required bool hovered}) {
    final s = (r['status'] ?? '').toString();
    final base = statusColor(ctx, s);

    final double baseOp = selected ? 0.26 : 0.14;
    final double hoverAdd = hovered ? 0.10 : 0.0;

    final double op = (baseOp + hoverAdd).clamp(0.10, 0.42);
    return base.withOpacity(op);
  }

  List<double> fitVaultToAvailable(
      double availableCenterWidth, List<double> base) {
    final baseTotal = totalTableWidth(base);
    if (availableCenterWidth <= 0) return base;
    if (baseTotal >= availableCenterWidth) return base;

    final extra = availableCenterWidth - baseTotal;

    const weights = <double>[0.6, 1.1, 3.6, 1.0, 1.2, 1.2, 0.6, 1.2, 1.0, 1.3];
    final wSum = weights.fold<double>(0, (s, w) => s + w);

    final out = List<double>.from(base);
    for (int i = 0; i < out.length; i++) {
      final add = extra * (weights[i] / wSum);
      out[i] = (out[i] + add).clamp(_InventoryTableByStatusState.minColWidth,
          _InventoryTableByStatusState.maxColWidth);
    }
    return out;
  }

  DataRow vaultRow(BuildContext context, Map<String, dynamic> r,
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

    final bg = rowBg(context, r, selected: selected, hovered: hovered);

    Widget marketCell() {
      final num effectiveDelta = deltaPct ?? 0;
      final trendColor = effectiveDelta > 0
          ? Colors.green
          : (effectiveDelta < 0 ? Colors.redAccent : Colors.black54);
      final trendIcon =
          effectiveDelta >= 0 ? Icons.trending_up : Icons.trending_down;

      final pctText =
          '${effectiveDelta >= 0 ? '+' : ''}${effectiveDelta.toStringAsFixed(1)}%';

      final priceText = market == null ? '—' : '${money(market)} $currency';

      return Tooltip(
        message: 'Market: $mk',
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                priceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Icon(trendIcon, size: 16, color: trendColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                pctText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: trendColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final cells = <DataCell>[
      DataCell(
          _FileCell(url: r['photo_url']?.toString(), isImagePreferred: true)),
      DataCell(Text(txt(r['grading_note']))),
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
          statuses: _InventoryTableByStatusState.allStatuses
              .where((x) => x != 'vault')
              .toList(),
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

  DataRow fullRow(BuildContext context, Map<String, dynamic> r,
      {required bool selected, required bool hovered}) {
    final s = (r['status'] ?? '').toString();
    final q = (r['qty_status'] as int?) ?? 0;

    final qtyTotal = (r['qty_total'] as num?) ?? 0;
    final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
    final unit = (qtyTotal > 0) ? (totalWithFees / qtyTotal) : 0;
    final sumUnitTotal = unit * q;

    final est = (r['estimated_price'] as num?);
    final currency = (r['currency']?.toString() ?? 'USD');

    final bg = rowBg(context, r, selected: selected, hovered: hovered);

    // ✅ IMPORTANT: track real column index so we can auto-widen the right column
    final cells = <DataCell>[];
    int col = 0;

    void addCell(DataCell c) {
      cells.add(c);
      col++;
    }

    void addEditableTextCell({
      required String initialText,
      required Future<void> Function(String t) onSaved,
      String? placeholder,
      String? displaySuffix,
      bool formatMoney = false,
      double minWidth = 260,
    }) {
      final myCol = col;
      addCell(
        DataCell(
          _EditableTextCell(
            initialText: initialText,
            placeholder: placeholder,
            displaySuffix: displaySuffix,
            formatMoney: formatMoney,
            // ✅ these are implemented on the State (table_by_status.dart)
            onBeginEdit: () => beginEditColumn(myCol, minWidth: minWidth),
            onEndEdit: () => endEditColumn(myCol),
            onSaved: onSaved,
          ),
        ),
      );
    }

    // Base columns
    addCell(DataCell(
        _FileCell(url: r['photo_url']?.toString(), isImagePreferred: true)));
    addCell(DataCell(Text(txt(r['grading_note']))));
    addCell(
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
    );
    addCell(DataCell(Text(r['language']?.toString() ?? '')));
    addCell(DataCell(Text(r['game_label']?.toString() ?? '—')));
    addCell(DataCell(Text(r['purchase_date']?.toString() ?? '')));
    addCell(DataCell(Text('$q')));
    addCell(
      DataCell(
        _EditableStatusCell(
          enabled: !widget.groupMode,
          value: s,
          statuses: _InventoryTableByStatusState.allStatuses.toList(),
          color: statusColor(context, s),
          onSaved: (val) async {
            if (val != null && val.isNotEmpty && val != s) {
              await widget.onInlineUpdate(r, 'status', val);
            }
          },
        ),
      ),
    );

    // Optional cost columns
    if (widget.showUnitCosts) {
      addCell(DataCell(Text('${money(unit)} $currency')));
      addCell(DataCell(Text('${money(sumUnitTotal)} $currency')));
    }

    // Estimated
    if (widget.showEstimated) {
      addEditableTextCell(
        initialText: est == null ? '' : est.toString(),
        placeholder: '—',
        minWidth: 220,
        onSaved: (t) async => widget.onInlineUpdate(r, 'estimated_price', t),
      );
    }

    // Supplier
    addEditableTextCell(
      initialText:
          txt(r['supplier_name']) == '—' ? '' : r['supplier_name'].toString(),
      minWidth: 260,
      onSaved: (t) async => widget.onInlineUpdate(r, 'supplier_name', t),
    );

    // Buyer
    addEditableTextCell(
      initialText:
          txt(r['buyer_company']) == '—' ? '' : r['buyer_company'].toString(),
      minWidth: 260,
      onSaved: (t) async => widget.onInlineUpdate(r, 'buyer_company', t),
    );

    // Item location
    addEditableTextCell(
      initialText:
          txt(r['item_location']) == '—' ? '' : r['item_location'].toString(),
      minWidth: 260,
      onSaved: (t) async => widget.onInlineUpdate(r, 'item_location', t),
    );

    // Grade ID
    addEditableTextCell(
      initialText: txt(r['grade_id']) == '—' ? '' : r['grade_id'].toString(),
      minWidth: 200,
      onSaved: (t) async => widget.onInlineUpdate(r, 'grade_id', t),
    );

    // Sale date
    addEditableTextCell(
      initialText: txt(r['sale_date']) == '—' ? '' : r['sale_date'].toString(),
      placeholder: 'YYYY-MM-DD',
      minWidth: 220,
      onSaved: (t) async => widget.onInlineUpdate(r, 'sale_date', t),
    );

    // Revenue (sale price)
    if (widget.showRevenue) {
      final sale = r['sale_price'];
      final saleCur = saleCurrency(r);

      addEditableTextCell(
        initialText: sale == null ? '' : sale.toString(),
        placeholder: '—',
        displaySuffix: sale == null ? null : ' $saleCur',
        formatMoney: true,
        minWidth: 220,
        onSaved: (t) async => widget.onInlineUpdate(r, 'sale_price', t),
      );
    }

    // Buyer infos
    addEditableTextCell(
      initialText:
          txt(r['buyer_infos']) == '—' ? '' : r['buyer_infos'].toString(),
      minWidth: 320,
      onSaved: (t) async => widget.onInlineUpdate(r, 'buyer_infos', t),
    );

    // Doc
    addCell(DataCell(_FileCell(url: r['document_url']?.toString())));

    return DataRow(
      color: MaterialStateProperty.all(bg),
      onSelectChanged: null,
      cells: cells,
    );
  }
}

extension _TbsBuild on _InventoryTableByStatusState {
  Widget buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final lines = sortedLines;

    final allSelected = widget.groupMode &&
        widget.selection.length == lines.length &&
        lines.isNotEmpty;
    final anySelected = widget.groupMode && widget.selection.isNotEmpty;
    final bool? headerCheckValue = !widget.groupMode
        ? false
        : (allSelected ? true : (anySelected ? null : false));

    final fixedLeft = _FixedSideColumn(
      width: _InventoryTableByStatusState.sideW,
      headerHeight: _InventoryTableByStatusState.headH,
      rowHeight: _InventoryTableByStatusState.rowH,
      side: _FixedSide.left,
      header: Container(
        height: _InventoryTableByStatusState.headH,
        alignment: Alignment.center,
        child: widget.groupMode
            ? Checkbox(
                tristate: true,
                value: headerCheckValue,
                onChanged: (_) => widget.onToggleSelectAll?.call(!allSelected),
              )
            : const Icon(Icons.edit, size: 18, color: Colors.black45),
      ),
      rows: [
        for (final r in lines)
          Builder(builder: (_) {
            final key = widget.lineKey(r);
            final selected =
                widget.groupMode ? widget.selection.contains(key) : false;
            final hovered = hoveredKey == key;

            return MouseRegion(
              onEnter: (_) => setHovered(key),
              onExit: (_) => setHovered(hoveredKey == key ? null : hoveredKey),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: _InventoryTableByStatusState.rowH,
                alignment: Alignment.center,
                color: rowBg(context, r, selected: selected, hovered: hovered),
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

    final fixedRight = !widget.showDelete
        ? const SizedBox.shrink()
        : _FixedSideColumn(
            width: _InventoryTableByStatusState.sideW,
            headerHeight: _InventoryTableByStatusState.headH,
            rowHeight: _InventoryTableByStatusState.rowH,
            side: _FixedSide.right,
            header: Container(
              height: _InventoryTableByStatusState.headH,
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 18, color: Colors.black45),
            ),
            rows: [
              for (final r in lines)
                Builder(builder: (_) {
                  final key = widget.lineKey(r);
                  final selected =
                      widget.groupMode ? widget.selection.contains(key) : false;
                  final hovered = hoveredKey == key;

                  return MouseRegion(
                    onEnter: (_) => setHovered(key),
                    onExit: (_) =>
                        setHovered(hoveredKey == key ? null : hoveredKey),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      height: _InventoryTableByStatusState.rowH,
                      alignment: Alignment.center,
                      color: rowBg(context, r,
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

    final titles = columnTitles();
    final colCount = titles.length;

    final baseWidths = ensureColumnWidths(colCount);

    final dataRows = <DataRow>[];
    for (final r in lines) {
      final key = widget.lineKey(r);
      final selected =
          widget.groupMode ? widget.selection.contains(key) : false;
      final hovered = hoveredKey == key;

      dataRows.add(
        widget.mode == InventoryTableMode.vault
            ? vaultRow(context, r, selected: selected, hovered: hovered)
            : fullRow(context, r, selected: selected, hovered: hovered),
      );
    }

    Widget buildHeaderRow(List<double> widths) {
      return Container(
        height: _InventoryTableByStatusState.headH,
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
                  title: titles[i],
                  isSorted: sortColumnIndex == i,
                  ascending: sortAscending,
                  onTap: () => handleSort(i),
                ),
              ),
              if (i < colCount - 1)
                _ColumnResizeHandle(
                  height: _InventoryTableByStatusState.headH,
                  accent: cs.primary,
                  onDrag: (delta) => onResizeColumn(i, delta),
                ),
            ],
          ],
        ),
      );
    }

    Widget buildDataRowWidget(
      List<double> widths,
      DataRow row,
      Map<String, dynamic> sourceRow,
    ) {
      final key = widget.lineKey(sourceRow);
      final selected =
          widget.groupMode ? widget.selection.contains(key) : false;
      final hovered = hoveredKey == key;

      final bg =
          rowBg(context, sourceRow, selected: selected, hovered: hovered);
      final cells = row.cells;

      return MouseRegion(
        onEnter: (_) => setHovered(key),
        onExit: (_) => setHovered(hoveredKey == key ? null : hoveredKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: _InventoryTableByStatusState.rowH,
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
                      alignment: alignForColumn(i),
                      child:
                          maybeWrapWithTooltipAndCopy(context, cells[i].child),
                    ),
                  ),
                ),
                if (i < colCount - 1)
                  _ColumnResizeHandle(
                    height: _InventoryTableByStatusState.rowH,
                    accent: cs.primary,
                    onDrag: (delta) => onResizeColumn(i, delta),
                    subtle: true,
                  ),
              ],
            ],
          ),
        ),
      );
    }

    final center = LayoutBuilder(
      builder: (ctx, cons) {
        final availableCenterWidth = cons.maxWidth;

        final effectiveWidths = (widget.mode == InventoryTableMode.vault)
            ? fitVaultToAvailable(availableCenterWidth, baseWidths)
            : baseWidths;

        final tableWidth = totalTableWidth(effectiveWidths);

        final centerTable = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(tableWidth, availableCenterWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildHeaderRow(effectiveWidths),
                for (int i = 0; i < dataRows.length; i++)
                  buildDataRowWidget(effectiveWidths, dataRows[i], lines[i]),
              ],
            ),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
              right: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
            ),
          ),
          child: centerTable,
        );
      },
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
              Expanded(child: center),
              fixedRight,
            ],
          ),
        ),
      ),
    );
  }
}
