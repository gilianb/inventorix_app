// ignore_for_file: unused_local_variable, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// On réutilise le même dialog que pour la création d’une facture depuis la page details
import 'invoice_create_dialog.dart';

class MultiInvoiceSelectionResult {
  final List<int> itemIds;
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

  String get currency => (sample['currency'] ?? 'USD').toString();

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

  // Données brutes
  List<Map<String, dynamic>> _itemsRaw = [];

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

  Future<void> _loadEligibleItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Items finalisés (single ou sealed ou autre type, on ne filtre que sur status)
      final rows = await _sb
          .from('item')
          .select(
            'id, product:product(name), type, status, currency, '
            'sale_price, unit_cost, buyer_company, buyer_infos, sale_date',
          )
          .eq('org_id', widget.orgId)
          .eq('status', 'finalized')
          .order('sale_date', ascending: false)
          .limit(500); // sécurité

      _itemsRaw = List<Map<String, dynamic>>.from(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      _groups = _buildGroups(_itemsRaw);
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
    final currency = (r['currency'] ?? '').toString().trim().toUpperCase();
    final price = (r['sale_price'] ?? r['unit_cost'] ?? '').toString();

    final buyerCompany =
        (r['buyer_company'] ?? '').toString().trim().toLowerCase();
    final buyerInfos = (r['buyer_infos'] ?? '').toString().trim().toLowerCase();

    // On groupe aussi par date de vente (jour) pour coller à la logique
    final rawDate = r['sale_date']?.toString() ?? '';
    final saleDate = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    // => même product, même type, même date, même prix, même currency,
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
    final String currency =
        (first['currency'] ?? 'USD').toString().toUpperCase();

    // Buyer = client final (buyer_infos)
    String buyer(Map<String, dynamic> r) {
      final bi = (r['buyer_infos'] as String?)?.trim();
      return (bi != null && bi.isNotEmpty) ? bi : 'Customer';
    }

    final firstBuyer = buyer(first);

    // Vérification cohérence currency + buyer_infos sur tous les rows
    for (final r in selectedRows) {
      final cur = (r['currency'] ?? currency).toString().toUpperCase();
      if (cur != currency) {
        setState(() {
          _error =
              'All selected items must share the same currency. Found both $currency and $cur.';
        });
        return;
      }
      final b = buyer(r);
      /*if (b != firstBuyer) {
        setState(() {
          _error =
              'All selected items must share the same buyer. Found "$firstBuyer" and "$b".';
        });
        return;
      }*/
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
        /*else if (internalCompany != bc) {
          setState(() {
            _error =
                'All selected items must share the same internal company (buyer_company). Found "$internalCompany" and "$bc".';
          });
          return;
        }*/
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

    // Ouvre le formulaire de facture (même que pour la création unitaire)
    final formResult = await InvoiceCreateDialog.show(
      context,
      currency: currency,
      //sellerName: sellerNameDefault,
      sellerName: 'cardshouker',
      buyerName: firstBuyer,
    );

    // L’utilisateur a fermé le formulaire -> on ne ferme pas ce dialog
    if (formResult == null) {
      return;
    }

    // On construit le résultat complet pour InvoiceManagementPage
    final result = MultiInvoiceSelectionResult(
      itemIds: ids,
      currency: currency,
      taxRate: formResult.taxRate, // gère TVA 0% ou 5% par ex.
      // si tu ajoutes dueDate dans InvoiceCreateDialog, remplace null par formResult.dueDate
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
                    child: Text('No finalized items available.'),
                  )
                : Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Only items with status "finalized" are shown. Items of the same sale are grouped (quantity xN).',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Barre de recherche
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
