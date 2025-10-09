import 'package:flutter/material.dart';
import '../utils/form_widgets.dart';

class MoveRequest {
  MoveRequest({
    required this.from,
    required this.to,
    required this.qty,
    this.channelId,
    this.listingPrice,
    this.sellingPrice,
    this.feesShipping = 0,
    this.feesCommission = 0,
    this.listingDate,
    this.saleDate,
    this.note,
  });

  final String from;
  final String to;
  final int qty;
  final int? channelId;
  final double? listingPrice; // requis si to == 'listed'
  final double? sellingPrice; // requis si from=='listed' && to=='sold'
  final double feesShipping; // optionnel
  final double feesCommission; // optionnel
  DateTime? listingDate; // optionnel
  DateTime? saleDate; // optionnel
  final String? note;

  double? get totalFees {
    final t = feesShipping + feesCommission;
    return t > 0 ? t : null;
  }

  DateTime? get effectiveTimestamp => sellingPrice != null
      ? saleDate
      : (listingPrice != null ? listingDate : null);
}

bool _needsChannel(String to, String from) =>
    to == 'listed' || (from == 'listed' && to == 'sold');
bool _needsListingPrice(String to) => to == 'listed';
bool _needsSalePrice(String to, String from) =>
    (from == 'listed' && to == 'sold');

Future<MoveRequest?> showUpdateStatusDialog({
  required BuildContext context,
  required List<String> allStatuses,
  required int Function(String status) hasQtyFor,
  required Future<List<Map<String, dynamic>>> Function() loadChannels,
}) async {
  final formKey = GlobalKey<FormState>();
  final qtyCtrl = TextFormFieldController('1');
  final listPrice = TextFormFieldController('');
  final salePrice = TextFormFieldController('');
  final shipFee = TextFormFieldController('');
  final commFee = TextFormFieldController('');
  final noteCtrl = TextEditingController();

  int? channelId;
  DateTime? listingDate;
  DateTime? saleDate;

  String from =
      allStatuses.firstWhere((s) => hasQtyFor(s) > 0, orElse: () => 'paid');
  String to = 'received';

  List<Map<String, dynamic>> channels = const [];

  Future<void> maybeLoadChannels(bool need) async {
    if (!need || channels.isNotEmpty) return;
    channels = await loadChannels();
  }

  bool needChannel = _needsChannel(to, from);
  bool needListP = _needsListingPrice(to);
  bool needSaleP = _needsSalePrice(to, from);
  await maybeLoadChannels(needChannel);

  Future<void> pickDate(ValueSetter<DateTime?> dst, {DateTime? initial}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) dst(picked);
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> onStatusChanged() async {
          final nc = _needsChannel(to, from);
          final nl = _needsListingPrice(to);
          final ns = _needsSalePrice(to, from);
          if (nc && channels.isEmpty) await maybeLoadChannels(true);
          setLocal(() {
            needChannel = nc;
            needListP = nl;
            needSaleP = ns;
          });
        }

        return AlertDialog(
          title: const Text('Mettre à jour le statut'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: from,
                      decoration: const InputDecoration(labelText: 'Depuis'),
                      items: allStatuses
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
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
                      items: allStatuses
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        to = v!;
                        onStatusChanged();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // Quantité (toujours requise pour un mouvement)
                qtyCtrl.build(
                  label: 'Quantité',
                  keyboard: TextInputType.number,
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

                if (needListP) ...[
                  const SizedBox(height: 8),
                  listPrice.build(
                    label: 'Prix de listing (USD)',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1;
                      return n > 0 ? null : 'Prix requis';
                    },
                  ),
                  const SizedBox(height: 8),
                  DateInline(
                    label: 'Date de listing',
                    date: listingDate,
                    onPick: () async => await pickDate(
                        (d) => setLocal(() => listingDate = d),
                        initial: listingDate),
                  ),
                ],

                if (needSaleP) ...[
                  const SizedBox(height: 8),
                  salePrice.build(
                    label: 'Prix de vente (USD)',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1;
                      return n > 0 ? null : 'Prix requis';
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: shipFee.build(
                        label: 'Frais livraison (USD)',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: commFee.build(
                        label: 'Commission (USD)',
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  DateInline(
                    label: 'Date de vente',
                    date: saleDate,
                    onPick: () async => await pickDate(
                        (d) => setLocal(() => saleDate = d),
                        initial: saleDate),
                  ),
                ],

                const SizedBox(height: 8),
                TextFormField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Note (optionnelle)'),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
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

  if (ok != true) return null;

  final qty = int.tryParse(qtyCtrl.value()) ?? 0;
  final listingP =
      listPrice.value().isEmpty ? null : double.parse(listPrice.value());
  final sellingP =
      salePrice.value().isEmpty ? null : double.parse(salePrice.value());
  final feesShip = double.tryParse(shipFee.value()) ?? 0;
  final feesComm = double.tryParse(commFee.value()) ?? 0;

  final req = MoveRequest(
    from: from,
    to: to,
    qty: qty,
    channelId: channelId,
    listingPrice: listingP,
    sellingPrice: sellingP,
    feesShipping: feesShip,
    feesCommission: feesComm,
    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
  );
  req.listingDate = listingDate;
  req.saleDate = saleDate;
  return req;
}
