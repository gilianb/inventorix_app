import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LotDetailsPage extends StatefulWidget {
  const LotDetailsPage({super.key, required this.lotId});
  final int lotId;

  @override
  State<LotDetailsPage> createState() => _LotDetailsPageState();
}

class _LotDetailsPageState extends State<LotDetailsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _header;
  List<Map<String, dynamic>> _allocs = const [];
  List<Map<String, dynamic>> _moves = const [];

  static const _allStatuses = <String>[
    'ordered',
    'in_transit',
    'paid',
    'received',
    'sent_to_grader',
    'at_grader',
    'graded',
    'listed',
    'sold',
    'shipped',
    'finalized',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hdr = await _sb.from('lot').select('''
        id, purchase_date, total_cost, currency, qty, fees,
        buyer_company, supplier_name, photo_url, document_url,
        notes, sale_date, sale_price,
        product:product_id(id, name, language)
      ''').eq('id', widget.lotId).maybeSingle();

      final allocs = await _sb
          .from('inventory_allocation')
          .select('status, qty, grade, channel:channel_id(code,label)')
          .eq('lot_id', widget.lotId)
          .order('status', ascending: true);

      final moves = await _sb
          .from('movement')
          .select(
              'ts, mtype, from_status, to_status, qty, unit_price, currency, '
              'fees, grader, grade, note, channel:channel_id(code,label)')
          .eq('lot_id', widget.lotId)
          .order('ts', ascending: false)
          .limit(200);

      setState(() {
        _header = hdr == null ? null : Map<String, dynamic>.from(hdr as Map);
        _allocs = allocs
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _moves = moves
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on PostgrestException catch (e) {
      _snack('Erreur Supabase: ${e.message}');
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      _snack('Erreur: $e');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int _qty(String status) => _allocs
      .where((a) => a['status'] == status)
      .fold(0, (p, a) => p + (a['qty'] as int));

  Color _statusColor(String status, BuildContext ctx) {
    final c = Theme.of(ctx).colorScheme;
    switch (status) {
      case 'ordered':
      case 'in_transit':
        return c.tertiaryContainer;
      case 'paid':
      case 'received':
        return c.primaryContainer;
      case 'sent_to_grader':
      case 'at_grader':
      case 'graded':
        return c.secondaryContainer;
      case 'listed':
        return Colors.amber.shade200;
      case 'sold':
      case 'shipped':
      case 'finalized':
        return Colors.green.shade200;
      default:
        return c.surfaceVariant;
    }
  }

  String _inferMtype(String from, String to) {
    if (from == 'paid' && to == 'received') return 'receive';
    if (from == 'received' && to == 'sent_to_grader') return 'ship_to_grader';
    if (to == 'listed') return 'list_for_sale';
    if (from == 'listed' && to == 'sold') return 'sell';
    if (from == 'sold' && to == 'finalized') return 'finalize_sale';
    return 'adjustment';
  }

  bool _needsChannel(String to, String from) {
    if (to == 'listed') return true;
    if (from == 'listed' && to == 'sold') return true;
    return false;
  }

  bool _needsPrice(String to, String from) =>
      (from == 'listed' && to == 'sold');

  Future<void> _openUnifiedMoveDialog() async {
    final formKey = GlobalKey<FormState>();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    int? channelId;

    String from =
        _allStatuses.firstWhere((s) => _qty(s) > 0, orElse: () => 'paid');
    String to = 'received';

    List<Map<String, dynamic>> channels = const [];
    Future<void> _maybeLoadChannels(bool need) async {
      if (!need || channels.isNotEmpty) return;
      final raw =
          await _sb.from('channel').select('id, code, label').order('label');
      channels = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    bool needChannel = _needsChannel(to, from);
    bool needPrice = _needsPrice(to, from);
    await _maybeLoadChannels(needChannel);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> onStatusChanged() async {
            final nc = _needsChannel(to, from);
            final np = _needsPrice(to, from);
            if (nc && channels.isEmpty) {
              await _maybeLoadChannels(true);
            }
            setLocal(() {
              needChannel = nc;
              needPrice = np;
            });
          }

          return AlertDialog(
            title: const Text('Mettre à jour le statut'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: from,
                          decoration:
                              const InputDecoration(labelText: 'Depuis'),
                          items: _allStatuses
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) {
                            from = v!;
                            onStatusChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: to,
                          decoration: const InputDecoration(labelText: 'Vers'),
                          items: _allStatuses
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) {
                            to = v!;
                            onStatusChanged();
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantité'),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0
                          ? null
                          : 'Quantité invalide',
                    ),
                    if (needChannel) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Canal'),
                        items: channels
                            .map((c) => DropdownMenuItem(
                                  value: c['id'] as int,
                                  child: Text('${c['label']} (${c['code']})'),
                                ))
                            .toList(),
                        onChanged: (v) => channelId = v,
                        validator: (v) => v == null ? 'Choisir un canal' : null,
                      ),
                    ],
                    if (needPrice) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Prix unitaire (USD)'),
                        validator: (v) =>
                            (double.tryParse((v ?? '').replaceAll(',', '.')) ??
                                        0) >
                                    0
                                ? null
                                : 'Prix invalide',
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Mouvement: ${_inferMtype(from, to)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler')),
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final qty = int.parse(qtyCtrl.text.trim());
    final unitPrice = _needsPrice(to, from)
        ? double.parse(priceCtrl.text.trim().replaceAll(',', '.'))
        : null;

    try {
      await _sb.rpc('fn_move_qty', params: {
        'p_lot_id': widget.lotId,
        'p_from_status': from,
        'p_to_status': to,
        'p_qty': qty,
        'p_channel_id': channelId,
        'p_mtype': _inferMtype(from, to),
        'p_unit_price': unitPrice,
        'p_currency': unitPrice != null ? 'USD' : null,
      });
      _snack('Statut mis à jour');
      await _load();
    } on PostgrestException catch (e) {
      _snack('Erreur: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détail du lot')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              Text('Erreur: $_error'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ]),
          ),
        ),
      );
    }
    if (_header == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détail du lot')),
        body: const Center(child: Text('Lot introuvable')),
      );
    }

    final h = _header!;
    final product = Map<String, dynamic>.from(h['product'] as Map);
    String money(num? n) => ((n ?? 0).toDouble()).toStringAsFixed(2);

    // Y a-t-il au moins un listing ?
    final listedChips = _allocs
        .where((a) => a['status'] == 'listed')
        .map((a) => Chip(
              label: Text('${(a['channel']?['label']) ?? '—'}: ${a['qty']}'),
              backgroundColor: Colors.amber.shade100,
            ))
        .toList();
    final hasListed = listedChips.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du lot')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Bandeau en-tête
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Text('${h['qty'] ?? ''}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product['name'] ?? '',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (product['language'] != null)
                              product['language'],
                            if ((h['supplier_name'] ?? '')
                                .toString()
                                .isNotEmpty)
                              'Fournisseur: ${h['supplier_name']}',
                            if ((h['buyer_company'] ?? '')
                                .toString()
                                .isNotEmpty)
                              'Acheteur: ${h['buyer_company']}',
                          ].join(' • '),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              avatar: const Icon(Icons.event, size: 18),
                              label: Text('Achat: ${h['purchase_date']}'),
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceVariant,
                            ),
                            Chip(
                              avatar: const Icon(Icons.payments, size: 18),
                              label: Text(
                                  'Total: ${money(h['total_cost'])} ${h['currency'] ?? 'USD'}'),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                            ),
                            if ((h['fees'] as num?) != null &&
                                (h['fees'] as num) > 0)
                              Chip(
                                avatar:
                                    const Icon(Icons.receipt_long, size: 18),
                                label: Text('Frais: ${money(h['fees'])}'),
                                backgroundColor: Colors.amber.shade200,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Infos complémentaires
            if ((h['photo_url'] ?? '').toString().isNotEmpty ||
                (h['document_url'] ?? '').toString().isNotEmpty ||
                (h['notes'] ?? '').toString().isNotEmpty ||
                h['sale_date'] != null ||
                h['sale_price'] != null)
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Infos complémentaires',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          if ((h['photo_url'] ?? '').toString().isNotEmpty)
                            ActionChip(
                              label: const Text('Photo'),
                              avatar: const Icon(Icons.photo),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    content: Image.network(
                                        h['photo_url'] as String,
                                        fit: BoxFit.contain),
                                  ),
                                );
                              },
                            ),
                          if ((h['document_url'] ?? '').toString().isNotEmpty)
                            ActionChip(
                              label: const Text('Document'),
                              avatar: const Icon(Icons.attach_file),
                              onPressed: () {
                                _snack('Document: ${h['document_url']}');
                              },
                            ),
                        ],
                      ),
                      if ((h['notes'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Notes: ${h['notes']}'),
                      ],
                      if (h['sale_date'] != null ||
                          h['sale_price'] != null) ...[
                        const SizedBox(height: 8),
                        Text('Vente prévue/faite: '
                            '${h['sale_date'] ?? '—'} • ${h['sale_price'] != null ? money(h['sale_price']) : '—'} ${h['currency'] ?? ''}'),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Statuts + (optionnel) Listé par canal + Bouton d'action
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Répartition par statut',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allStatuses.map((s) {
                        final q = _qty(s);
                        return Chip(
                          backgroundColor: _statusColor(s, context),
                          label: Text('$s: $q'),
                        );
                      }).toList(),
                    ),
                    if (hasListed) ...[
                      const SizedBox(height: 10),
                      Text('Listé par canal',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: listedChips),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _openUnifiedMoveDialog,
                        icon: const Icon(Icons.sync_alt),
                        label: const Text('Mettre à jour le statut'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Historique
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Historique',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._moves.map((m) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.change_circle_outlined),
                          title: Text('${m['mtype']}  •  ${m['qty']} u'),
                          subtitle: Text([
                            m['ts'],
                            '${m['from_status']} → ${m['to_status']}',
                            if (m['channel']?['code'] != null)
                              m['channel']!['code'],
                            if (m['unit_price'] != null)
                              '${(m['unit_price'] as num).toStringAsFixed(2)} ${m['currency'] ?? ''}',
                            if (m['grade'] != null) 'Grade: ${m['grade']}',
                            if (m['note'] != null) 'Note: ${m['note']}',
                          ]
                              .where(
                                  (e) => e != null && e.toString().isNotEmpty)
                              .join(' | ')),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
