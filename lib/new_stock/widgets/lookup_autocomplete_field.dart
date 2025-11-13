// Taken as-is from your page (minor import added)
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/* Generic autocomplete field wired to a Supabase table (name).
  Also allows adding a value if absent. */

class LookupAutocompleteField extends StatefulWidget {
  const LookupAutocompleteField({
    super.key,
    required this.tableName,
    required this.label,
    required this.controller,
    this.addDialogTitle,
    this.requiredField = false,
    this.whereActiveOnly = true,
    this.maxOptions = 10,
    this.autoAddOnEnter = true,
  });

  final String tableName;
  final String label;
  final TextEditingController controller;
  final String? addDialogTitle;
  final bool requiredField;
  final bool whereActiveOnly;
  final int maxOptions;
  final bool autoAddOnEnter;

  @override
  State<LookupAutocompleteField> createState() =>
      _LookupAutocompleteFieldState();
}

class _LookupAutocompleteFieldState extends State<LookupAutocompleteField> {
  final _sb = Supabase.instance.client;

  final FocusNode _focusNode = FocusNode();
  List<String> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final base = _sb.from(widget.tableName).select('name');
      List<dynamic> data;
      if (widget.whereActiveOnly) {
        try {
          data = await base.eq('active', true).order('name');
        } on PostgrestException {
          data = await base.order('name');
        }
      } else {
        data = await base.order('name');
      }
      _all = data
          .map<String>((e) => (e as Map)['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      _all = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasAnyMatch(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return _all.isNotEmpty;
    return _all.any((n) => n.toLowerCase().contains(s));
  }

  bool _hasExact(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return false;
    return _all.any((n) => n.toLowerCase() == s);
  }

  Future<void> _addValue(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;

    if (_all.any((x) => x.toLowerCase() == n.toLowerCase())) {
      widget.controller.text = n;
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Already present: "$n"')));
      }
      return;
    }

    try {
      final inserted = await _sb
          .from(widget.tableName)
          .insert({'name': n})
          .select('id, name')
          .single();
      if ((inserted['id'] != null)) {
        await _load();
        widget.controller.text = n;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added: "${inserted['name']}"')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Insertion not confirmed.')));
        }
      }
    } on PostgrestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('INSERT error: ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unknown error: $e')));
      }
    }
  }

  Future<void> _submitOrAdd(String currentText) async {
    final t = currentText.trim();
    if (t.isEmpty) return;

    final anyMatch = _hasAnyMatch(t);
    final exact = _hasExact(t);

    if (exact) {
      widget.controller.text = t;
      return;
    }

    if (widget.autoAddOnEnter && !anyMatch) {
      await _addValue(t);
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.requiredField ? '${widget.label} *' : widget.label;

    if (_loading) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return _all.take(widget.maxOptions);
        return _all
            .where((n) => n.toLowerCase().contains(q))
            .take(widget.maxOptions);
      },
      displayStringForOption: (opt) => opt,
      optionsViewBuilder: (context, onSelected, options) {
        final input = widget.controller.text.trim();
        final canAdd = input.isNotEmpty && !_hasExact(input);
        final merged = [...options, if (canAdd) '___ADD___$input'];

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: merged.length,
                itemBuilder: (ctx, i) {
                  final v = merged[i];
                  final isAdd = v.startsWith('___ADD___');
                  final text = isAdd ? v.substring(9) : v;
                  return ListTile(
                    dense: true,
                    title: isAdd
                        ? Text('➕ Add "$text"', overflow: TextOverflow.ellipsis)
                        : Text(text, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      if (isAdd) {
                        await _addValue(text);
                        _focusNode.unfocus();
                      } else {
                        onSelected(text);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label),
          onFieldSubmitted: (val) async {
            await _submitOrAdd(val);
            onFieldSubmitted();
          },
          validator: (v) {
            if (!widget.requiredField) return null;
            if (v == null || v.trim().isEmpty) return 'Required field';
            return null;
          },
        );
      },
      onSelected: (val) => widget.controller.text = val,
    );
  }
}
