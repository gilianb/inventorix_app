// ignore_for_file: unused_local_variable, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// On réutilise le même dialog que pour la création d’une facture depuis la page details
import 'invoice_create_dialog.dart';

class MultiInvoiceSelectionResult {
  final List<int> itemIds;

  /// ✅ Devise de la facture (SALE currency) = sale_currency (fallback currency)
  final String currency;

  final double taxRate;
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

  MultiInvoiceSelectionResult({
    required this.itemIds,
    required this.currency,
    required this.taxRate,
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

  /// Libellé affiché et utilisé pour la recherche = client final
  String get buyerLabel {
    if (buyerInfos.isNotEmpty) return buyerInfos;
    return '';
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

  /// ✅ Récupère les item_id qui ont déjà une invoice (via invoice_line.item_id)
  /// et aussi via invoice.related_item_id (si tu utilises ce champ dans certains flows).
  Future<Set<int>> _fetchInvoicedItemIds() async {
    final ids = <int>{};

    // 1) invoice.related_item_id
    try {
      final invRows = await _sb
          .from('invoice')
          .select('related_item_id')
          .eq('org_id', widget.orgId)
          .not('related_item_id', 'is', null)
          .limit(5000);

      for (final r in (invRows as List)) {
        final v = r['related_item_id'];
        if (v != null) ids.add((v as num).toInt());
      }
    } catch (_) {
      // best-effort
    }

    // 2) invoice_line.item_id (join invoice via invoice_id)
    try {
      final lineRows = await _sb
          .from('invoice_line')
          .select('item_id, invoice:invoice_id(org_id)')
          .not('item_id', 'is', null)
          .eq('invoice.org_id', widget.orgId)
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

    return ids;
  }

  Future<void> _loadEligibleItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Items finalisés (on filtre seulement sur status)
      final rows = await _sb
          .from('item')
          .select(
            'id, product:product(name), type, status, currency, sale_currency, '
            'sale_price, unit_cost, buyer_company, buyer_infos, sale_date',
          )
          .eq('org_id', widget.orgId)
          .eq('status', 'finalized')
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

      // Remet _itemsRaw cohérent avec les groupes visibles (utile pour confirm etc.)
      final allowedIds = filteredGroups
          .expand((g) => g.rows)
          .map<int>((r) => (r['id'] as num).toInt())
          .toSet();

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

    // ✅ group by SALE currency (sale_currency fallback currency)
    final currency = _saleCurrencyOfRow(r).toUpperCase();

    final price = (r['sale_price'] ?? r['unit_cost'] ?? '').toString();

    final buyerCompany =
        (r['buyer_company'] ?? '').toString().trim().toLowerCase();
    final buyerInfos = (r['buyer_infos'] ?? '').toString().trim().toLowerCase();

    // On groupe aussi par date de vente (jour)
    final rawDate = r['sale_date']?.toString() ?? '';
    final saleDate = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    // => même product, même type, même date, même prix, même SALE currency,
    //    même client final (buyer_infos) et même société interne (buyer_company)
    return [
      productName,
      type,
      currency,
      price,
      buyerCompany,
      buyerInfos,
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

    // Buyer = client final (buyer_infos)
    String buyer(Map<String, dynamic> r) {
      final bi = (r['buyer_infos'] as String?)?.trim();
      return (bi != null && bi.isNotEmpty) ? bi : 'Customer';
    }

    final firstBuyer = buyer(first);

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
    );

    if (formResult == null) return;

    // Résultat complet
    final result = MultiInvoiceSelectionResult(
      itemIds: ids,
      currency: currency,
      taxRate: formResult.taxRate,
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

    if (g.buyerLabel.isNotEmpty) {
      haystack.write(' ');
      haystack.write(g.buyerLabel.toLowerCase());
    }

    return haystack.toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groups.where(_matchesSearch).toList();

    return AlertDialog(
      title: const Text('Select items for invoice'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
                ? const Center(
                    child: Text('No finalized non-invoiced items available.'),
                  )
                : Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Only items with status "finalized" and without an existing invoice are shown. If any item in a sale-group is already invoiced, the whole group is hidden.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              'Search by item name or buyer (end customer)',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          setState(() {
                            _searchQuery = v;
                          });
                        },
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

                                  final key = g.key;
                                  final checked = _selected.contains(key);

                                  final name = g.productName;
                                  final type = g.type;

                                  // ✅ affichage en SALE currency
                                  final currency = g.currency;

                                  final priceRaw = g.unitPriceRaw;
                                  final priceStr = priceRaw.toStringAsFixed(2);

                                  final saleDate =
                                      _formatSaleDate(g.saleDateRaw);
                                  final buyerLabel = g.buyerLabel;

                                  final qtyPart =
                                      g.quantity > 1 ? 'x${g.quantity}' : 'x1';
                                  final salePart = saleDate.isNotEmpty
                                      ? ' • Sold: $saleDate'
                                      : '';
                                  final buyerPart = buyerLabel.isNotEmpty
                                      ? ' • Buyer: $buyerLabel'
                                      : '';

                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: (_) => _toggle(key),
                                    title: Text('$name ($qtyPart)'),
                                    subtitle: Text(
                                      '$type • $currency $priceStr$salePart$buyerPart',
                                    ),
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
