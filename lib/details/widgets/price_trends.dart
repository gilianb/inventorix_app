// lib/details/widgets/price_trends.dart
// VERSION SIMPLE
// Affiche uniquement les prix Collectr stockés en base :
//   - product.price_raw
//   - product.price_graded (si type == 'single')
// Pas d'appel API ici. On lit juste la ligne "product".

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PriceTrendsCard extends StatefulWidget {
  const PriceTrendsCard({
    super.key,
    required this.productId,
    required this.productType, // 'single' | 'sealed'
    required this.currency, // ex: 'USD'
    this.photoUrl,
    this.reloadTick, // pour recharger depuis la DB si besoin
  });

  final int? productId;
  final String productType;
  final String currency;
  final String? photoUrl;
  final int? reloadTick;

  @override
  State<PriceTrendsCard> createState() => _PriceTrendsCardState();
}

class _PriceTrendsCardState extends State<PriceTrendsCard> {
  bool _loading = false;
  String? _error;

  double? _priceRaw;
  double? _priceGraded;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
  }

  @override
  void didUpdateWidget(covariant PriceTrendsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pidChanged = oldWidget.productId != widget.productId;
    final reloadChanged = oldWidget.reloadTick != widget.reloadTick;
    if (pidChanged || reloadChanged) {
      _loadFromDb();
    }
  }

  Future<void> _loadFromDb() async {
    final productId = widget.productId;
    if (productId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final row = await sb
          .from('product')
          .select('price_raw, price_graded, last_update')
          .eq('id', productId)
          .single();

      setState(() {
        _priceRaw = (row['price_raw'] as num?)?.toDouble();
        _priceGraded = (row['price_graded'] as num?)?.toDouble();
        _lastUpdate = row['last_update'] != null
            ? DateTime.tryParse(row['last_update'].toString())
            : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.productType.toLowerCase() == 'single';
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: (widget.photoUrl?.isNotEmpty ?? false)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      widget.photoUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.stacked_line_chart),
            title: const Text(
              'Prix (Collectr)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Devise: ${widget.currency}'
              '${_lastUpdate != null ? " • MAJ: ${_formatDate(_lastUpdate!)}" : ""}',
            ),
            trailing: IconButton(
              tooltip: 'Rafraîchir (DB uniquement)',
              onPressed: _loading ? null : _loadFromDb,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          const Divider(height: 1),

          // RAW
          _PriceRow(
            label: 'Non gradé',
            value: _priceRaw,
            currency: widget.currency,
          ),

          // PSA10 (si single)
          if (isSingle)
            _PriceRow(
              label: 'PSA 10',
              value: _priceGraded,
              currency: widget.currency,
            ),

          // Message d'erreur éventuel
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final double? value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.price_change),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(
        value != null ? '${value!.toStringAsFixed(2)} $currency' : '—',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
