// ignore_for_file: deprecated_member_use

part of '../table_by_status.dart';

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
