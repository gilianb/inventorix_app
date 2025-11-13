import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RefLookupDropdown extends StatefulWidget {
  const RefLookupDropdown({
    super.key,
    required this.tableName,
    required this.label,
    this.initialId,
    this.onChanged,
    this.bindController, // if you want to reflect the label into a TextEditingController
    this.nullable = true, // allow "none"
    this.addDialogTitle,
    this.enabled = true,
    this.whereActiveOnly = true, // show only active = true if the column exists
  });

  final String tableName;
  final String label;
  final int? initialId;
  final void Function(int? id, String? name)? onChanged;
  final TextEditingController? bindController;
  final bool nullable;
  final String? addDialogTitle;
  final bool enabled;
  final bool whereActiveOnly;

  @override
  State<RefLookupDropdown> createState() => _RefLookupDropdownState();
}

class _RefLookupDropdownState extends State<RefLookupDropdown> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _rows = [];
  int? _selectedId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final base = _sb.from(widget.tableName).select('id, name');

      List<dynamic> data;

      if (widget.whereActiveOnly) {
        try {
          // ✅ filter first, then order
          data = await base.eq('active', true).order('name');
        } on PostgrestException {
          // If the "active" column doesn't exist, fall back without filter
          data = await base.order('name');
        }
      } else {
        data = await base.order('name');
      }

      _rows = data
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      _rows = [];
      debugPrint('RefLookupDropdown load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onAddPressed() async {
    final txt = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(widget.addDialogTitle ?? 'Add choice'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Name *'),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Add')),
          ],
        );
      },
    );

    final name = txt?.trim();
    if (name == null || name.isEmpty) return;

    try {
      final inserted = await _sb
          .from(widget.tableName)
          .insert({
            'name': name,
            // 'active': true, // if the table has the active column, PostgREST will ignore it otherwise
          })
          .select('id, name')
          .single();

      // reload + select the new value
      await _load();
      final newId = inserted['id'] as int;
      setState(() => _selectedId = newId);

      widget.onChanged?.call(newId, name);
      widget.bindController?.text = name;
    } catch (e) {
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return InputDecorator(
        decoration: InputDecoration(labelText: widget.label),
        child: const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final items = <DropdownMenuItem<int?>>[];

    if (widget.nullable) {
      items.add(const DropdownMenuItem<int?>(value: null, child: Text('—')));
    }

    items.addAll(_rows.map((r) {
      return DropdownMenuItem<int?>(
        value: r['id'] as int,
        child: Text((r['name'] as String?) ?? ''),
      );
    }));

    // Special "add…" item: use a sentinel value
    const addSentinel = -1;
    items.add(const DropdownMenuItem<int?>(
        value: addSentinel, child: Text('➕ Add…')));

    return DropdownButtonFormField<int?>(
      initialValue: _selectedId,
      items: items,
      onChanged: widget.enabled
          ? (v) async {
              if (v == addSentinel) {
                // open the add dialog
                await _onAddPressed();
                return;
              }
              setState(() => _selectedId = v);
              final name = (v == null)
                  ? null
                  : (_rows.firstWhere((r) => r['id'] == v)['name'] as String?);
              widget.onChanged?.call(v, name);
              if (widget.bindController != null) {
                widget.bindController!.text = name ?? '';
              }
            }
          : null,
      decoration: InputDecoration(labelText: widget.label),
    );
  }
}
