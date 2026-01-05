// ignore_for_file: deprecated_member_use

part of '../table_by_status.dart';

class _EditableTextCell extends StatefulWidget {
  const _EditableTextCell({
    required this.initialText,
    required this.onSaved,
    this.placeholder,
    this.displaySuffix,
    this.formatMoney = false,

    // ✅ allow table to auto-widen the column while editing
    this.onBeginEdit,
    this.onEndEdit,
  });

  final String initialText;
  final Future<void> Function(String newValue) onSaved;
  final String? placeholder;
  final String? displaySuffix;
  final bool formatMoney;

  /// Called when entering edit mode (e.g., widen the column)
  final VoidCallback? onBeginEdit;

  /// Called when leaving edit mode (e.g., restore the column width)
  final VoidCallback? onEndEdit;

  @override
  State<_EditableTextCell> createState() => _EditableTextCellState();
}

class _EditableTextCellState extends State<_EditableTextCell> {
  bool _editing = false;
  late final TextEditingController _c;
  late final FocusNode _focusNode;

  bool _saving = false;
  String _original = '';

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
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

  void _startEdit() {
    _original = _c.text;
    widget.onBeginEdit?.call();

    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
  }

  void _endEditUi() {
    widget.onEndEdit?.call();
    setState(() => _editing = false);
  }

  void _cancel() {
    _c.text = _original;
    _endEditUi();
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      await widget.onSaved(_c.text.trim());
      if (!mounted) return;
      _endEditUi();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

    return TapRegion(
      onTapOutside: (_) {
        if (!_saving) _cancel();
      },
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (evt) {
          if (evt.isKeyPressed(LogicalKeyboardKey.escape)) {
            _cancel();
          }
        },
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _c,
                focusNode: _focusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: 'Cancel',
                          icon:
                              const Icon(Icons.close, color: Colors.redAccent),
                          onPressed: _cancel,
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: 'Save',
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: _save,
                        ),
                      ),
                    ],
                  ),
          ],
        ),
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

    // ✅ allow table to auto-widen the column while editing
    this.onBeginEdit,
    this.onEndEdit,
  });

  final String value;
  final List<String> statuses;
  final Color color;
  final Future<void> Function(String? newValue) onSaved;
  final bool enabled;

  final VoidCallback? onBeginEdit;
  final VoidCallback? onEndEdit;

  @override
  State<_EditableStatusCell> createState() => _EditableStatusCellState();
}

class _EditableStatusCellState extends State<_EditableStatusCell> {
  bool _editing = false;
  String? _value;
  bool _saving = false;

  String? _original;

  // ✅ dropdown menu opens in an overlay; protect tapOutside while it's open
  bool _menuOpen = false;

  String _label(String s) => s.replaceAll('_', ' ').toUpperCase();

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
      _value = _original;
      _menuOpen = false;
      widget.onEndEdit?.call();
      setState(() => _editing = false);
    }
  }

  void _startEdit() {
    if (!widget.enabled) return;
    _original = _value;
    _menuOpen = false;

    widget.onBeginEdit?.call();
    setState(() => _editing = true);
  }

  void _endEditUi() {
    _menuOpen = false;
    widget.onEndEdit?.call();
    setState(() => _editing = false);
  }

  void _cancel() {
    setState(() => _value = _original);
    _endEditUi();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await widget.onSaved(_value);
      if (!mounted) return;
      _endEditUi();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _statusRow(BuildContext ctx, String s) {
    final c = statusColor(ctx, s);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _label(s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // ✅ FIX overflow
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chip = Chip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text(_label(widget.value)),
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

    return TapRegion(
      onTapOutside: (_) {
        if (_saving) return;

        // if dropdown overlay is open, don't cancel (selection clicks happen outside)
        if (_menuOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _menuOpen = false);
          });
          return;
        }

        _cancel();
      },
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (evt) {
          if (evt.isKeyPressed(LogicalKeyboardKey.escape)) {
            _cancel();
          }
        },
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) {
                  if (!_menuOpen) setState(() => _menuOpen = true);
                },
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
                            vertical: 6,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.withOpacity(0.7)),
                          ),
                          child: _statusRow(context, s), // ✅ overflow-safe row
                        ),
                      );
                    }).toList(),
                    selectedItemBuilder: (ctx) {
                      return widget.statuses.map((s) {
                        // ✅ also overflow-safe inside the button
                        return _statusRow(ctx, s);
                      }).toList();
                    },
                    focusColor:
                        _value == null ? null : statusColor(context, _value!),
                    onChanged: (v) {
                      setState(() {
                        _value = v;
                        _menuOpen = false;
                      });
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
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
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: 'Cancel',
                          icon:
                              const Icon(Icons.close, color: Colors.redAccent),
                          onPressed: _cancel,
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: 'Save',
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: _save,
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
