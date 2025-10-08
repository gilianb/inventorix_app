// lib/sales_archive_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesArchivePage extends StatefulWidget {
  const SalesArchivePage({super.key});

  @override
  State<SalesArchivePage> createState() => _SalesArchivePageState();
}

class _SalesArchivePageState extends State<SalesArchivePage> {
  final _supabase = Supabase.instance.client;

  final _searchCtrl = TextEditingController();
  String?
      _typeFilter; // ex: 'invoice', 'quote' ... selon ton enum documents.type
  bool _loading = true;
  final List<Map<String, dynamic>> _docs = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await _fetchDocuments();
    } catch (e) {
      _msg('Erreur de chargement : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchDocuments() async {
    final search = _searchCtrl.text.trim();

    const cols = '''
      id, number, type, status, issue_date, due_date,
      currency, grand_total,
      customer:customers(name)
    ''';

    // 1) on construit la sélection
    var sel = _supabase.from('documents').select(cols);

    // 2) filtres AVANT .order()
    if (_typeFilter != null && _typeFilter!.isNotEmpty) {
      sel = sel.eq('type', _typeFilter!);
    }
    if (search.isNotEmpty) {
      sel = sel.or('number.ilike.%$search%,customer.name.ilike.%$search%');
    }

    // 3) tri + limite au dernier moment
    final List<dynamic> raw =
        await sel.order('issue_date', ascending: false).limit(200);

    final data = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    _docs
      ..clear()
      ..addAll(data);
    setState(() {});
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mm-$dd';
    } catch (_) {
      return d.toString();
    }
  }

  String _fmtMoney(num? n, String? currency) {
    if (n == null) return '-';
    final c = currency ?? 'EUR';
    return '${n.toStringAsFixed(2)} $c';
  }

  Future<void> _openDocumentLines(Map<String, dynamic> doc) async {
    final docId = doc['id'];
    try {
      final List<dynamic> raw = await _supabase
          .from('document_lines')
          .select(
              'line_no, description, qty, unit_price, tax_rate, discount, total')
          .eq('document_id', docId)
          .order('line_no', ascending: true);

      final lines =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // ignore: use_build_context_synchronously
      showModalBottomSheet(
        // ignore: use_build_context_synchronously
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (ctx, controller) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document ${doc['number'] ?? ''} — ${doc['type']}',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text('Client: ${doc['customer']?['name'] ?? '-'}'),
                    Text('Date: ${_fmtDate(doc['issue_date'])}'),
                    const Divider(),
                    Expanded(
                      child: lines.isEmpty
                          ? const Center(child: Text('Aucune ligne'))
                          : ListView.builder(
                              controller: controller,
                              itemCount: lines.length,
                              itemBuilder: (c, i) {
                                final ln = lines[i];
                                final qty =
                                    (ln['qty'] as num?)?.toDouble() ?? 0;
                                final unit =
                                    (ln['unit_price'] as num?)?.toDouble() ?? 0;
                                final total =
                                    (ln['total'] as num?)?.toDouble() ??
                                        qty * unit;
                                return ListTile(
                                  dense: true,
                                  leading: Text('#${ln['line_no']}'),
                                  title: Text(ln['description'] ?? ''),
                                  subtitle: Text(
                                    'Qte: ${qty.toStringAsFixed(2)}  •  PU: ${unit.toStringAsFixed(2)}',
                                  ),
                                  trailing: Text(total.toStringAsFixed(2)),
                                );
                              },
                            ),
                    ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: ${_fmtMoney((doc['grand_total'] as num?)?.toDouble() ?? 0, doc['currency'])}',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        },
      );
    } on PostgrestException catch (e) {
      _msg('Erreur lignes document : ${e.message}');
    } catch (e) {
      _msg('Erreur : $e');
    }
  }

  Widget _buildRow(Map<String, dynamic> doc) {
    final number = (doc['number'] ?? '').toString();
    final customerName = (doc['customer']?['name'] ?? '').toString();
    final type = (doc['type'] ?? '').toString();
    final status = (doc['status'] ?? '').toString();
    final total = (doc['grand_total'] as num?)?.toDouble();
    final cur = (doc['currency'] ?? 'EUR').toString();

    return ListTile(
      onTap: () => _openDocumentLines(doc),
      leading: CircleAvatar(
        child: Text(type.isNotEmpty ? type[0].toUpperCase() : '?'),
      ),
      title: Text(number.isEmpty ? '(Sans numéro)' : number),
      subtitle: Text([
        if (customerName.isNotEmpty) customerName,
        'Type: $type',
        'Statut: $status',
        'Date: ${_fmtDate(doc['issue_date'])}',
      ].join(' • ')),
      trailing: Text(_fmtMoney(total ?? 0, cur)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: _docs.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onSubmitted: (_) => _fetchDocuments(),
                                decoration: InputDecoration(
                                  hintText: 'Rechercher (n° document, client)',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _fetchDocuments();
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _typeFilter,
                              hint: const Text('Type'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'invoice', child: Text('invoice')),
                                DropdownMenuItem(
                                    value: 'quote', child: Text('quote')),
                                DropdownMenuItem(
                                    value: 'order', child: Text('order')),
                              ],
                              onChanged: (v) {
                                setState(() => _typeFilter = v);
                                _fetchDocuments();
                              },
                            ),
                            IconButton(
                              tooltip: 'Actualiser',
                              onPressed: _fetchDocuments,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Documents: ${_docs.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final doc = _docs[i - 1];
                return _buildRow(doc);
              },
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventorix — Documents'),
      ),
      body: body,
    );
  }
}
