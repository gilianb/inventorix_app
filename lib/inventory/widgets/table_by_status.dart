// lib/inventory/widgets/table_by_status.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/status_utils.dart';
import '../utils/format.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

class InventoryTableByStatus extends StatelessWidget {
  const InventoryTableByStatus({
    super.key,
    required this.lines,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
    this.showDelete = true,
    this.showUnitCosts = true,
    this.showRevenue = true,
    this.showEstimated = true,
    required this.onInlineUpdate,
  });

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

  // dimensions “fixes”
  static const double _headH = 56;
  static const double _rowH = 56;
  static const double _sideW = 52;

  String _txt(dynamic v) =>
      (v == null || (v is String && v.trim().isEmpty)) ? '—' : v.toString();

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
    'collection',
  ];

  // ---- TABLEAU CENTRAL (scrollé) ----
  DataRow _centerRow(BuildContext context, Map<String, dynamic> r) {
    final s = (r['status'] ?? '').toString();
    final q = (r['qty_status'] as int?) ?? 0;

    // Coûts
    final qtyTotal = (r['qty_total'] as num?) ?? 0;
    final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
    final unit = (qtyTotal > 0) ? (totalWithFees / qtyTotal) : 0;
    final sumUnitTotal = unit * q;

    final est = (r['estimated_price'] as num?);

    // Couleur de ligne
    final lineColor = MaterialStateProperty.resolveWith<Color?>(
      (_) => statusColor(context, s).withOpacity(0.06),
    );

    final currency = (r['currency']?.toString() ?? 'USD');

    // Colonnes
    final cells = <DataCell>[
      // Photo
      DataCell(_FileCell(
        url: r['photo_url']?.toString(),
        isImagePreferred: true,
      )),

      // Grading note
      DataCell(Text(_txt(r['grading_note']))),

      // Produit → détails
      DataCell(
        InkWell(
          onTap: () => onOpen(r),
          child: Text(
            r['product_name']?.toString() ?? '',
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        ),
      ),

      // Langue
      DataCell(Text(r['language']?.toString() ?? '')),

      // Jeu
      DataCell(Text(r['game_label']?.toString() ?? '—')),

      // Achat
      DataCell(Text(r['purchase_date']?.toString() ?? '')),

      // Qté
      DataCell(Text('$q')),

      // ====== ÉDITION INLINE ======
      // Statut
      DataCell(
        _EditableStatusCell(
          value: s,
          statuses: _allStatuses.where((x) => x != 'collection').toList(),
          color: statusColor(context, s),
          onSaved: (val) async {
            if (val != null && val.isNotEmpty && val != s) {
              await onInlineUpdate(r, 'status', val);
            }
          },
        ),
      ),
    ];

    if (showUnitCosts) {
      cells.addAll([
        DataCell(Text('${money(unit)} $currency')),
        DataCell(Text('${money(sumUnitTotal)} $currency')),
      ]);
    }

    if (showEstimated) {
      cells.add(
        DataCell(
          _EditableTextCell(
            initialText: est == null ? '' : est.toString(),
            placeholder: '—',
            onSaved: (t) async {
              await onInlineUpdate(r, 'estimated_price', t);
            },
          ),
        ),
      );
    }

    // Divers (tous éditables)
    cells.addAll([
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['supplier_name']) == '—'
              ? ''
              : r['supplier_name'].toString(),
          onSaved: (t) async => onInlineUpdate(r, 'supplier_name', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['buyer_company']) == '—'
              ? ''
              : r['buyer_company'].toString(),
          onSaved: (t) async => onInlineUpdate(r, 'buyer_company', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText: _txt(r['item_location']) == '—'
              ? ''
              : r['item_location'].toString(),
          onSaved: (t) async => onInlineUpdate(r, 'item_location', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['grade_id']) == '—' ? '' : r['grade_id'].toString(),
          onSaved: (t) async => onInlineUpdate(r, 'grade_id', t),
        ),
      ),
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['sale_date']) == '—' ? '' : r['sale_date'].toString(),
          placeholder: 'YYYY-MM-DD',
          onSaved: (t) async => onInlineUpdate(r, 'sale_date', t),
        ),
      ),
    ]);

    if (showRevenue) {
      final sale = r['sale_price'];
      cells.add(
        DataCell(
          _EditableTextCell(
            initialText: sale == null ? '' : sale.toString(),
            placeholder: '—',
            onSaved: (t) async => onInlineUpdate(r, 'sale_price', t),
          ),
        ),
      );
    }

    // Tracking
    cells.add(
      DataCell(
        _EditableTextCell(
          initialText:
              _txt(r['tracking']) == '—' ? '' : r['tracking'].toString(),
          onSaved: (t) async => onInlineUpdate(r, 'tracking', t),
        ),
      ),
    );

    // Doc
    cells.add(DataCell(_FileCell(url: r['document_url']?.toString())));

    return DataRow(
      color: lineColor,
      onSelectChanged: null,
      cells: cells,
    );
  }

  // Couleur de fond d’une ligne (pour colonnes fixes)
  Color _rowBg(BuildContext ctx, Map<String, dynamic> r) {
    final s = (r['status'] ?? '').toString();
    return statusColor(ctx, s).withOpacity(0.06);
  }

  @override
  Widget build(BuildContext context) {
    // ------ Colonne fixe gauche (✏️) ------
    final fixedLeft = Column(
      children: [
        Container(
          width: _sideW,
          height: _headH,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.35),
          child: const Icon(Icons.edit, size: 18, color: Colors.black45),
        ),
        for (final r in lines)
          Container(
            width: _sideW,
            height: _rowH,
            color: _rowBg(context, r),
            alignment: Alignment.center,
            child: IconButton(
              tooltip: 'Éditer ce listing',
              icon: const Iconify(Mdi.pencil,
                  size: 20, color: Color.fromARGB(255, 34, 35, 36)),
              onPressed: onEdit == null ? null : () => onEdit!(r),
            ),
          ),
      ],
    );

    // ------ Colonne fixe droite (❌) ------
    final fixedRight = !showDelete
        ? const SizedBox.shrink()
        : Column(
            children: [
              Container(
                width: _sideW,
                height: _headH,
                alignment: Alignment.center,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(.35),
                child: const Icon(Icons.close, size: 18, color: Colors.black45),
              ),
              for (final r in lines)
                Container(
                  width: _sideW,
                  height: _rowH,
                  color: _rowBg(context, r),
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: 'Supprimer cette ligne',
                    icon: const Iconify(Mdi.close,
                        size: 18, color: Colors.redAccent),
                    onPressed: onDelete == null ? null : () => onDelete!(r),
                  ),
                ),
            ],
          );

    // ------ DataColumns dynamiques ------
    final columns = <DataColumn>[
      const DataColumn(label: Text('Photo')),
      const DataColumn(label: Text('Grading note')),
      const DataColumn(label: Text('Produit')),
      const DataColumn(label: Text('Langue')),
      const DataColumn(label: Text('Jeu')),
      const DataColumn(label: Text('Achat')),
      const DataColumn(label: Text('Qté')),
      const DataColumn(label: Text('Statut')),
      if (showUnitCosts) const DataColumn(label: Text('Prix / u.')),
      if (showUnitCosts) const DataColumn(label: Text('Prix (Qté×u)')),
      if (showEstimated) const DataColumn(label: Text('Estimated /u.')),
      const DataColumn(label: Text('Supplier')),
      const DataColumn(label: Text('Buyer')),
      const DataColumn(label: Text('Item location')),
      const DataColumn(label: Text('Grade ID')),
      const DataColumn(label: Text('Sale date')),
      if (showRevenue) const DataColumn(label: Text('Sale price')),
      const DataColumn(label: Text('Tracking')),
      const DataColumn(label: Text('Doc')),
    ];

    // ------ Tableau central ------
    final centerTable = DataTableTheme(
      data: const DataTableThemeData(
        headingRowHeight: _headH,
        dataRowMinHeight: _rowH,
        dataRowMaxHeight: _rowH,
      ),
      child: DataTable(
        showCheckboxColumn: false,
        columns: columns,
        rows: lines.map((r) => _centerRow(context, r)).toList(),
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fixedLeft, // ✏️
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: centerTable, // ⇦ scroll groupé
              ),
            ),
            fixedRight, // ❌
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
  });

  final String initialText;
  final Future<void> Function(String newValue) onSaved;
  final String? placeholder;

  @override
  State<_EditableTextCell> createState() => _EditableTextCellState();
}

class _EditableTextCellState extends State<_EditableTextCell> {
  bool _editing = false;
  late final TextEditingController _c;
  bool _saving = false;

  // 🔁 annuler sur clic hors cellule (OK pour textfields)
  late final FocusNode _focusNode;
  String _original = '';

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_editing && !_focusNode.hasFocus && !_saving) {
        _c.text = _original; // annuler
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

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      final display = (_c.text.isEmpty ? (widget.placeholder ?? '—') : _c.text);
      return GestureDetector(
        onDoubleTap: _startEdit,
        onLongPress: _startEdit,
        child: Text(display),
      );
    }

    return RawKeyboardListener(
      focusNode: FocusNode(), // capter Esc
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
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  children: [
                    IconButton(
                      tooltip: 'Annuler',
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        _c.text = _original;
                        setState(() => _editing = false);
                      },
                    ),
                    IconButton(
                      tooltip: 'Enregistrer',
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
  });

  final String value;
  final List<String> statuses;
  final Color color;
  final Future<void> Function(String? newValue) onSaved;

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
    _original = _value;
    setState(() => _editing = true);
    // ⛔️ PAS de listener de perte de focus ici (sinon le menu ferme immédiatement)
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return GestureDetector(
        onDoubleTap: _startEdit,
        onLongPress: _startEdit,
        child: Chip(
          label: Text((widget.value).toUpperCase()),
          backgroundColor: widget.color.withOpacity(0.15),
          side: BorderSide(color: widget.color.withOpacity(0.6)),
        ),
      );
    }

    // En mode édition : dropdown + boutons Annuler/Enregistrer
    return RawKeyboardListener(
      focusNode: FocusNode(), // pour Esc
      onKey: (evt) {
        if (evt.isKeyPressed(LogicalKeyboardKey.escape)) {
          setState(() {
            _value = _original; // annuler
            _editing = false;
          });
        }
      },
      child: Row(
        children: [
          // on remplit toute la cellule pour capter les clics dans la zone
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _value,
                icon: const Icon(Icons.arrow_drop_down),
                items: widget.statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _value = v);
                },
                // on N'UTILISE PAS de focusNode ici pour ne pas annuler quand le menu s'ouvre
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
                      tooltip: 'Annuler',
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _value = _original;
                          _editing = false;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Enregistrer',
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
      // URL corrigée/encodée
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

      return InkWell(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            imgUrl,
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
      );
    }

    return IconButton(
      icon: const Iconify(Mdi.file_document),
      tooltip: 'Ouvrir le document',
      onPressed: _open,
    );
  }
}
