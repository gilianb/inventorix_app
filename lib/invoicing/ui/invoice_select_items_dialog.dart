// ignore_for_file: unused_local_variable, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../inventory/utils/status_utils.dart';

// On réutilise le même dialog que pour la création d’une facture depuis la page details
import 'invoice_create_dialog.dart';

class MultiInvoiceSelectionResult {
  final List<int> itemIds;

  /// ✅ Devise de la facture (SALE currency) = sale_currency (fallback currency)
  final String currency;

  final double taxRate;
  final DateTime invoiceDate;
  final DateTime? dueDate;

  // Seller
  final String? sellerName;
  final String? sellerAddress;
  final String? sellerCountry;
  final String? sellerVatNumber;
  final String? sellerTaxRegistration;
  final String? sellerRegistrationNumber;

  // Buyer (end customer)
  final String? buyerName;
  final String? buyerAddress;
  final String? buyerCountry;
  final String? buyerVatNumber;
  final String? buyerTaxRegistration;
  final String? buyerEmail;
  final String? buyerPhone;

  // Other
  final String? paymentTerms;
  final String? notes;
  final bool showLogoInPdf;
  final bool showBankInfoInPdf;
  final bool showDisplayTotalInAed;
  final double? aedPerInvoiceCurrencyRate;

  MultiInvoiceSelectionResult({
    required this.itemIds,
    required this.currency,
    required this.taxRate,
    required this.invoiceDate,
    this.dueDate,
    // Seller
    this.sellerName,
    this.sellerAddress,
    this.sellerCountry,
    this.sellerVatNumber,
    this.sellerTaxRegistration,
    this.sellerRegistrationNumber,
    // Buyer
    this.buyerName,
    this.buyerAddress,
    this.buyerCountry,
    this.buyerVatNumber,
    this.buyerTaxRegistration,
    this.buyerEmail,
    this.buyerPhone,
    // Other
    this.paymentTerms,
    this.notes,
    required this.showLogoInPdf,
    required this.showBankInfoInPdf,
    required this.showDisplayTotalInAed,
    this.aedPerInvoiceCurrencyRate,
  });
}

// --------- GROUPE INTERNE POUR L’UI (x3 sur une ligne) ---------

class _GroupedItem {
  final String key;
  final List<Map<String, dynamic>> rows;

  _GroupedItem({
    required this.key,
    required this.rows,
  });

  int get quantity => rows.length;

  Map<String, dynamic> get sample => rows.first;

  int get firstItemId => (sample['id'] as num).toInt();

  String get productName => (sample['product']?['name'] ?? 'Item').toString();

  String get type => (sample['type'] ?? '').toString();

  String get status => (sample['status'] ?? '').toString().trim().toLowerCase();

  String? get photoUrl {
    final p = (sample['photo_url'] ?? '').toString().trim();
    return p.isEmpty ? null : p;
  }

  /// ✅ Devise affichée = sale_currency (fallback currency, fallback USD)
  String get currency {
    final sc = (sample['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc.toUpperCase();
    final c = (sample['currency'] ?? '').toString().trim();
    if (c.isNotEmpty) return c.toUpperCase();
    return 'USD';
  }

  num get unitPriceRaw =>
      (sample['sale_price'] ?? sample['unit_cost'] ?? 0) as num;

  String get saleDateRaw => sample['sale_date']?.toString() ?? '';

  /// buyer_company = société interne (CardShouker / Mister8 / YK...) qui achète la carte
  /// => correspond à society.name
  String get buyerCompany => (sample['buyer_company'] ?? '').toString();

  /// buyer_infos = client final qui achète la carte à vous
  String get buyerInfos => (sample['buyer_infos'] ?? '').toString();

  List<String> get buyerLabels {
    final out = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      final raw = (row['buyer_infos'] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final key = raw.toLowerCase();
      if (seen.add(key)) out.add(raw);
    }
    return out;
  }

  /// Libellé affiché et utilisé pour la recherche = client final
  String get buyerLabel {
    final labels = buyerLabels;
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.first} (+${labels.length - 1})';
  }

  String get buyerLabelVerbose {
    final labels = buyerLabels;
    if (labels.isEmpty) return '';
    if (labels.length <= 2) return labels.join(', ');
    return '${labels[0]}, ${labels[1]} +${labels.length - 2}';
  }

  String get typeLabel {
    final t = type.trim();
    if (t.isEmpty) return 'Item';
    return t[0].toUpperCase() + t.substring(1);
  }

  String get quantityLabel {
    return quantity > 1 ? 'x$quantity' : 'x1';
  }
}

// ===================================================================

class InvoiceSelectItemsDialog extends StatefulWidget {
  final String orgId;

  const InvoiceSelectItemsDialog({
    super.key,
    required this.orgId,
  });

  static Future<MultiInvoiceSelectionResult?> show(
    BuildContext context, {
    required String orgId,
  }) {
    return showDialog<MultiInvoiceSelectionResult>(
      context: context,
      builder: (ctx) => InvoiceSelectItemsDialog(orgId: orgId),
    );
  }

  @override
  State<InvoiceSelectItemsDialog> createState() =>
      _InvoiceSelectItemsDialogState();
}

class _InvoiceSelectItemsDialogState extends State<InvoiceSelectItemsDialog> {
  final _sb = Supabase.instance.client;
  static const List<String> _eligibleStatuses = <String>[
    'awaiting_payment',
    'sold',
    'shipped',
    'finalized',
  ];

  bool _loading = true;

  // Données regroupées pour l’UI (x3 etc.)
  List<_GroupedItem> _groups = [];

  // Sélection = clés de groupes
  final Set<String> _selected = {};

  String? _error;

  // Recherche
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEligibleItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _saleCurrencyOfRow(Map<String, dynamic> r) {
    final sc = (r['sale_currency'] ?? '').toString().trim();
    if (sc.isNotEmpty) return sc.toUpperCase();
    final c = (r['currency'] ?? '').toString().trim();
    if (c.isNotEmpty) return c.toUpperCase();
    return 'USD';
  }

  /// ✅ Récupère les item_id qui ont déjà une invoice de vente
  /// (via invoice_line.item_id ou invoice.related_item_id).
  Future<Set<int>> _fetchInvoicedItemIds() async {
    final ids = <int>{};
    final saleInvoiceDocUrls = <String>{};

    // 1) invoice.related_item_id
    try {
      final invRows = await _sb
          .from('invoice')
          .select('related_item_id, document_url')
          .eq('org_id', widget.orgId)
          .eq('invoice_type', 'sale')
          .limit(5000);

      for (final r in (invRows as List)) {
        final v = r['related_item_id'];
        if (v != null) ids.add((v as num).toInt());
        final doc = (r['document_url'] ?? '').toString().trim();
        if (doc.isNotEmpty) saleInvoiceDocUrls.add(doc);
      }
    } catch (_) {
      // best-effort
    }

    // 2) invoice_line.item_id (join invoice via invoice_id)
    try {
      final lineRows = await _sb
          .from('invoice_line')
          .select('item_id, invoice:invoice_id(org_id, invoice_type)')
          .not('item_id', 'is', null)
          .eq('invoice.org_id', widget.orgId)
          .eq('invoice.invoice_type', 'sale')
          .limit(20000);

      for (final r in (lineRows as List)) {
        final v = r['item_id'];
        if (v != null) ids.add((v as num).toInt());
      }
    } catch (_) {
      // Fallback si filtre relationnel "invoice.org_id" non supporté
      try {
        final invoices = await _sb
            .from('invoice')
            .select('id')
            .eq('org_id', widget.orgId)
            .eq('invoice_type', 'sale')
            .limit(10000);

        final invoiceIds = (invoices as List)
            .map((e) => (e['id'] as num).toInt())
            .toList(growable: false);

        if (invoiceIds.isNotEmpty) {
          final lineRows = await _sb
              .from('invoice_line')
              .select('item_id, invoice_id')
              .not('item_id', 'is', null)
              .inFilter('invoice_id', invoiceIds)
              .limit(20000);

          for (final r in (lineRows as List)) {
            final v = r['item_id'];
            if (v != null) ids.add((v as num).toInt());
          }
        }
      } catch (_) {
        // best-effort
      }
    }

    // 3) For multi-item sales invoices, all linked item IDs are reflected
    // via item.document_url == sale-invoice document_url.
    // This closes gaps where invoice_line.item_id stores only representative IDs.
    if (saleInvoiceDocUrls.isNotEmpty) {
      try {
        final itemRows = await _sb
            .from('item')
            .select('id, document_url')
            .eq('org_id', widget.orgId)
            .not('document_url', 'is', null)
            .limit(20000);

        for (final r in (itemRows as List)) {
          final doc = (r['document_url'] ?? '').toString().trim();
          if (doc.isEmpty) continue;
          if (saleInvoiceDocUrls.contains(doc)) {
            ids.add((r['id'] as num).toInt());
          }
        }
      } catch (_) {
        // best-effort
      }
    }

    return ids;
  }

  Future<void> _loadEligibleItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Items vendus/finalisés éligibles à la facture de vente
      final rows = await _sb
          .from('item')
          .select(
            'id, product:product(name), type, status, photo_url, currency, sale_currency, '
            'sale_price, unit_cost, buyer_company, buyer_infos, sale_date',
          )
          .eq('org_id', widget.orgId)
          .inFilter('status', _eligibleStatuses)
          .order('sale_date', ascending: false)
          .limit(5000);

      final items = List<Map<String, dynamic>>.from(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      // ✅ NOUVEAU: filtrage AU NIVEAU DU GROUPE:
      // si 1 item du groupe a déjà une invoice → on retire tout le groupe.
      final invoicedIds = await _fetchInvoicedItemIds();

      final allGroups = _buildGroups(items);

      final filteredGroups = invoicedIds.isEmpty
          ? allGroups
          : allGroups.where((g) {
              final hasAnyInvoiced = g.rows.any((r) {
                final id = (r['id'] as num).toInt();
                return invoicedIds.contains(id);
              });
              return !hasAnyInvoiced;
            }).toList(growable: false);

      _groups = filteredGroups;
    } catch (e) {
      _error = 'Error while loading items: $e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ------------- GROUPEMENT : une ligne par “vente” -----------------

  List<_GroupedItem> _buildGroups(List<Map<String, dynamic>> rows) {
    final Map<String, List<Map<String, dynamic>>> buckets = {};

    for (final r in rows) {
      final key = _groupKey(r);
      buckets.putIfAbsent(key, () => []).add(r);
    }

    return buckets.entries
        .map((e) => _GroupedItem(key: e.key, rows: e.value))
        .toList();
  }

  String _groupKey(Map<String, dynamic> r) {
    final productName =
        (r['product']?['name'] ?? '').toString().trim().toLowerCase();
    final type = (r['type'] ?? '').toString().trim().toLowerCase();
    final status = (r['status'] ?? '').toString().trim().toLowerCase();

    // ✅ group by SALE currency (sale_currency fallback currency)
    final currency = _saleCurrencyOfRow(r).toUpperCase();

    final price = (r['sale_price'] ?? r['unit_cost'] ?? '').toString();

    final buyerCompany =
        (r['buyer_company'] ?? '').toString().trim().toLowerCase();
    final buyerNameKey =
        (r['buyer_infos'] ?? '').toString().trim().toLowerCase();

    // On groupe aussi par date de vente (jour)
    final rawDate = r['sale_date']?.toString() ?? '';
    final saleDate = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    // => même product, même buyer, même date, même prix (+type/status/currency/company)
    // buyer est pris tel quel (trim/lower) pour éviter les fusions non voulues.
    return [
      productName,
      type,
      status,
      currency,
      price,
      buyerCompany,
      buyerNameKey,
      saleDate,
    ].join('|');
  }

  // ------------------ Sélection ------------------

  void _toggle(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  String _defaultBuyerForSelection(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final name = (r['buyer_infos'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }

    return 'Customer';
  }

  DateTime _defaultInvoiceDateForSelection(List<Map<String, dynamic>> rows) {
    DateTime? latest;
    for (final r in rows) {
      final raw = r['sale_date'];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed == null) continue;
      if (latest == null || parsed.isAfter(latest)) {
        latest = parsed;
      }
    }
    return latest ?? DateTime.now();
  }

  // ------------------ CONFIRMATION ------------------

  Future<void> _onConfirm() async {
    if (_selected.isEmpty) {
      setState(() {
        _error = 'Please select at least one item.';
      });
      return;
    }

    // Récupère tous les rows bruts des groupes sélectionnés
    final List<Map<String, dynamic>> selectedRows = [];
    for (final g in _groups) {
      if (_selected.contains(g.key)) {
        selectedRows.addAll(g.rows);
      }
    }

    if (selectedRows.isEmpty) {
      setState(() {
        _error = 'Selection is empty.';
      });
      return;
    }

    final first = selectedRows.first;

    // ✅ Currency de la facture = SALE currency (sale_currency fallback currency)
    final String currency = _saleCurrencyOfRow(first);

    // Buyer default: first non-empty buyer name from selection.
    // Mixed buyer names are allowed; user can edit in the next dialog.
    final firstBuyer = _defaultBuyerForSelection(selectedRows);
    final defaultInvoiceDate = _defaultInvoiceDateForSelection(selectedRows);

    // ✅ Vérification cohérence SALE currency
    for (final r in selectedRows) {
      final cur = _saleCurrencyOfRow(r);
      if (cur != currency) {
        setState(() {
          _error =
              'All selected items must share the same SALE currency. Found both $currency and $cur.';
        });
        return;
      }
    }

    // IDs des items
    final ids = selectedRows
        .map<int>((e) => (e['id'] as num).toInt())
        .toList(growable: false);

    // Société interne (buyer_company) pour le vendeur (→ society.name)
    String? internalCompany;
    for (final r in selectedRows) {
      final bc = (r['buyer_company'] as String?)?.trim();
      if (bc != null && bc.isNotEmpty) {
        internalCompany ??= bc;
      }
    }

    // Récup nom d’org comme fallback éventuel pour le vendeur
    String? orgName;
    try {
      final orgRow = await _sb
          .from('organization')
          .select('name')
          .eq('id', widget.orgId)
          .maybeSingle();

      if (orgRow != null &&
          orgRow['name'] != null &&
          orgRow['name'].toString().trim().isNotEmpty) {
        orgName = orgRow['name'].toString().trim();
      }
    } catch (_) {
      // best-effort
    }

    // Seller par défaut = buyer_company (society.name) si présent, sinon orgName
    final sellerNameDefault =
        (internalCompany != null && internalCompany.isNotEmpty)
            ? internalCompany
            : orgName;

    // Ouvre le formulaire de facture
    final formResult = await InvoiceCreateDialog.show(
      context,
      currency: currency,
      // sellerName: sellerNameDefault,
      sellerName: 'cardshouker',
      buyerName: firstBuyer,
      defaultInvoiceDate: defaultInvoiceDate,
    );

    if (formResult == null) return;

    // Résultat complet
    final result = MultiInvoiceSelectionResult(
      itemIds: ids,
      currency: currency,
      taxRate: formResult.taxRate,
      invoiceDate: formResult.invoiceDate,
      dueDate: null,

      // Seller
      sellerName: formResult.sellerName,
      sellerAddress: formResult.sellerAddress,
      sellerCountry: formResult.sellerCountry,
      sellerVatNumber: formResult.sellerVatNumber,
      sellerTaxRegistration: null,
      sellerRegistrationNumber: null,

      // Buyer (end customer)
      buyerName: formResult.buyerName,
      buyerAddress: formResult.buyerAddress,
      buyerCountry: formResult.buyerCountry,
      buyerVatNumber: null,
      buyerTaxRegistration: null,
      buyerEmail: formResult.buyerEmail,
      buyerPhone: null,

      // Other
      paymentTerms: formResult.paymentTerms,
      notes: formResult.notes,
      showLogoInPdf: formResult.showLogoInPdf,
      showBankInfoInPdf: formResult.showBankInfoInPdf,
      showDisplayTotalInAed: formResult.showDisplayTotalInAed,
      aedPerInvoiceCurrencyRate: formResult.aedPerInvoiceCurrencyRate,
    );

    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  // ------------------ Helpers UI ------------------

  String _formatSaleDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      return raw;
    }
  }

  bool _matchesSearch(_GroupedItem g) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;

    final haystack = StringBuffer()..write(g.productName.toLowerCase());

    if (g.buyerLabels.isNotEmpty) {
      haystack.write(' ');
      haystack.write(g.buyerLabels.join(' ').toLowerCase());
    }

    haystack.write(' ');
    haystack.write(g.status);

    return haystack.toString().contains(q);
  }

  String _statusLabel(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'Unknown';
    return s
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  Widget _buildStatusTag(String status, {double fontSize = 11}) {
    final color = statusColor(context, status);
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemThumb(_GroupedItem g) {
    final theme = Theme.of(context);
    final url = g.photoUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 52,
        height: 68,
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        child: (url == null || url.isEmpty)
            ? Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildGroupTile(_GroupedItem g, bool checked) {
    final theme = Theme.of(context);
    final name = g.productName;
    final currency = g.currency;
    final priceStr = g.unitPriceRaw.toStringAsFixed(2);
    final saleDate = _formatSaleDate(g.saleDateRaw);
    final salePart = saleDate.isNotEmpty ? ' • Sold: $saleDate' : '';
    final buyerText = g.buyerLabelVerbose;

    return Material(
      color: checked
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggle(g.key),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: checked
                  ? theme.colorScheme.primary.withValues(alpha: 0.35)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildItemThumb(g),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$name (${g.quantityLabel})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusTag(g.status, fontSize: 10),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${g.typeLabel} • $currency $priceStr$salePart',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (buyerText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Buyer: $buyerText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: checked,
                onChanged: (_) => _toggle(g.key),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groups.where(_matchesSearch).toList();

    return AlertDialog(
      title: const Text('Select items for new sales invoice'),
      content: SizedBox(
        width: 700,
        height: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
                ? const Center(
                    child: Text('No eligible non-invoiced items available.'),
                  )
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.28),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _eligibleStatuses
                                  .map((s) => _buildStatusTag(s))
                                  .toList(growable: false),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Only items without an existing sales invoice are shown. If one item in a sale-group already has a sales invoice, the whole group is hidden.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by item name, buyer, or status',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          setState(() {
                            _searchQuery = v;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${visibleGroups.length} group(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Text(
                            '${_selected.length} selected',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: visibleGroups.isEmpty
                            ? const Center(
                                child: Text('No items match your search.'),
                              )
                            : ListView.builder(
                                itemCount: visibleGroups.length,
                                itemBuilder: (ctx, index) {
                                  final g = visibleGroups[index];
                                  final checked = _selected.contains(g.key);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildGroupTile(g, checked),
                                  );
                                },
                              ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onConfirm,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
