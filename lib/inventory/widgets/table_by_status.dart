// lib/inventory/widgets/table_by_status.dart
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/status_utils.dart';
import '../utils/format.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

part 'table_by_status_widgets/tbs_build_and_logic.dart';
part 'table_by_status_widgets/tbs_fixed_side.dart';
part 'table_by_status_widgets/tbs_cells_edit.dart';
part 'table_by_status_widgets/tbs_header.dart';
part 'table_by_status_widgets/tbs_file_cell_pre_image.dart';

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
  final bool groupMode;
  final Set<String> selection;
  final String Function(Map<String, dynamic> line) lineKey;
  final void Function(Map<String, dynamic> line, bool selected)? onToggleSelect;
  final void Function(bool selectAll)? onToggleSelectAll;

  @override
  State<InventoryTableByStatus> createState() => _InventoryTableByStatusState();
}

class _InventoryTableByStatusState extends State<InventoryTableByStatus> {
  // ✅ Compact density (pro grid feel)
  static const double headH = 48;
  static const double rowH = 48;
  static const double sideW = 52;

  // limites de largeur des colonnes
  static const double minColWidth = 60;
  static const double maxColWidth = 720;

  /// Hover sync across fixed-left / center / fixed-right
  String? hoveredKey;

  static const List<String> allStatuses = [
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
  late List<Map<String, dynamic>> sortedLines;

  /// Index de la colonne triée
  int? sortColumnIndex;

  /// true = flèche vers le haut, false = flèche vers le bas
  bool sortAscending = true;

  /// Largeurs actuelles des colonnes
  List<double>? columnWidths;

  // ============================================================
  // ✅ NEW: Inline edit support (auto-widen column while editing)
  // ============================================================
  final Map<int, double> _editPrevWidths = <int, double>{};

  /// Called by _EditableTextCell.onBeginEdit (see tbs_build_and_logic.dart)
  void beginEditColumn(int col, {double minWidth = 240}) {
    if (columnWidths == null) return;
    if (col < 0 || col >= columnWidths!.length) return;

    // Already widened/managed
    if (_editPrevWidths.containsKey(col)) return;

    final prev = columnWidths![col];
    _editPrevWidths[col] = prev;

    final target = minWidth.clamp(minColWidth, maxColWidth);
    if (prev < target) {
      setState(() {
        columnWidths![col] = target;
      });
    }
  }

  /// Called by _EditableTextCell.onEndEdit
  void endEditColumn(int col) {
    if (columnWidths == null) return;
    if (col < 0 || col >= columnWidths!.length) return;

    final prev = _editPrevWidths.remove(col);
    if (prev == null) return;

    setState(() {
      columnWidths![col] = prev.clamp(minColWidth, maxColWidth);
    });
  }

  @override
  void initState() {
    super.initState();
    resetSortedLines();
  }

  @override
  void didUpdateWidget(covariant InventoryTableByStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    resetSortedLines();

    final columnsChanged = widget.mode != oldWidget.mode ||
        widget.showUnitCosts != oldWidget.showUnitCosts ||
        widget.showEstimated != oldWidget.showEstimated ||
        widget.showRevenue != oldWidget.showRevenue;

    if (columnsChanged) {
      columnWidths = null;

      // Safety: clear any edit-resize state when columns layout changes
      _editPrevWidths.clear();
    }

    if (oldWidget.lines != widget.lines) {
      hoveredKey = null;
    }
  }

  @override
  Widget build(BuildContext context) => buildTable(context);
}
