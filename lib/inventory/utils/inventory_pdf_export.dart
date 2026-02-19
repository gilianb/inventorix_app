import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/status_utils.dart';
import '../widgets/products_grouped_view.dart' show InventoryProductSummary;

enum InventoryPdfViewMode { lines, products }

enum InventoryPdfSortMode { nameAsc, qtyDesc, statusThenName }

class InventoryPdfFieldDef {
  const InventoryPdfFieldDef({
    required this.key,
    required this.label,
    this.flex = 2,
    this.numeric = false,
    this.lineOnly = false,
    this.productOnly = false,
    this.maxLines = 1,
  });

  final String key;
  final String label;
  final int flex;
  final bool numeric;
  final bool lineOnly;
  final bool productOnly;
  final int maxLines;
}

const List<InventoryPdfFieldDef> kInventoryPdfFieldDefs = [
  InventoryPdfFieldDef(key: 'name', label: 'Name', flex: 4, maxLines: 2),
  InventoryPdfFieldDef(key: 'qty', label: 'Qty', flex: 1, numeric: true),
  InventoryPdfFieldDef(key: 'status', label: 'Status', flex: 2, lineOnly: true),
  InventoryPdfFieldDef(
    key: 'status_mix',
    label: 'Status mix',
    flex: 3,
    productOnly: true,
    maxLines: 2,
  ),
  InventoryPdfFieldDef(key: 'type', label: 'Type', flex: 1),
  InventoryPdfFieldDef(key: 'game', label: 'Game', flex: 2),
  InventoryPdfFieldDef(key: 'language', label: 'Language', flex: 1),
  InventoryPdfFieldDef(key: 'currency', label: 'Currency', flex: 1),
  InventoryPdfFieldDef(
    key: 'grade_id',
    label: 'Grade ID',
    flex: 2,
    lineOnly: true,
    maxLines: 2,
  ),
  InventoryPdfFieldDef(
    key: 'grading_note',
    label: 'Grading note',
    flex: 3,
    lineOnly: true,
    maxLines: 2,
  ),
  InventoryPdfFieldDef(
    key: 'estimated_unit',
    label: 'Estimated / unit',
    flex: 2,
  ),
  InventoryPdfFieldDef(key: 'buy_unit', label: 'Buy / unit', flex: 2),
  InventoryPdfFieldDef(
    key: 'sale_price',
    label: 'Sale price',
    flex: 2,
    lineOnly: true,
  ),
  InventoryPdfFieldDef(
    key: 'purchase_date',
    label: 'Purchase date',
    flex: 2,
    lineOnly: true,
  ),
  InventoryPdfFieldDef(
    key: 'sale_date',
    label: 'Sale date',
    flex: 2,
    lineOnly: true,
  ),
  InventoryPdfFieldDef(
    key: 'supplier',
    label: 'Supplier',
    flex: 2,
    lineOnly: true,
  ),
  InventoryPdfFieldDef(
    key: 'buyer',
    label: 'Buyer',
    flex: 2,
    lineOnly: true,
  ),
  InventoryPdfFieldDef(
    key: 'location',
    label: 'Location',
    flex: 2,
    lineOnly: true,
  ),
];

class InventoryPdfExportOptions {
  const InventoryPdfExportOptions({
    required this.viewMode,
    required this.fields,
    required this.selectedStatuses,
    this.selectedBuyerKeys = const [],
    this.selectedBuyerLabels = const [],
    required this.sortMode,
    required this.landscape,
    required this.expandQtyToRows,
    required this.includePhotos,
  });

  final InventoryPdfViewMode viewMode;
  final List<String> fields;
  final List<String> selectedStatuses;
  final List<String> selectedBuyerKeys;
  final List<String> selectedBuyerLabels;
  final InventoryPdfSortMode sortMode;
  final bool landscape;
  final bool expandQtyToRows;
  final bool includePhotos;
}

class InventoryPdfSectionData {
  const InventoryPdfSectionData({
    required this.title,
    required this.lines,
    required this.products,
  });

  final String title;
  final List<Map<String, dynamic>> lines;
  final List<InventoryProductSummary> products;
}

/// Inventory PDF export (Singles + Sealed)
/// - Manual pagination (pw.Page)
/// - ASCII sanitize (avoid Helvetica issues on long dashes or quotes)
Future<Uint8List> buildInventoryExportPdfBytes({
  required String orgId,
  required DateTime generatedAt,
  required List<InventoryPdfSectionData> sections,
  required InventoryPdfExportOptions options,
  void Function(double progress, String label)? onProgress,
}) async {
  final httpClient = http.Client();
  late final pw.Document doc;
  try {
    final fontData = await rootBundle.load('fonts/Roboto-Variable.ttf');
    final baseFont = pw.Font.ttf(fontData);
    doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: baseFont,
      ),
    );
  } catch (_) {
    doc = pw.Document();
  }

  // --- Formatting helpers ---
  String two(int v) => v.toString().padLeft(2, '0');
  String niceDate(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

  String sanitize(String s) {
    var out = s;

    // Common typographic replacements
    out = out
        .replaceAll('\u2014', '-') // —
        .replaceAll('\u2013', '-') // –
        .replaceAll('\u2018', "'") // ‘
        .replaceAll('\u2019', "'") // ’
        .replaceAll('\u201C', '"') // “
        .replaceAll('\u201D', '"') // ”
        .replaceAll('\u2026', '...') // …
        .replaceAll('\u00A0', ' '); // NBSP

    // Greek letters (if any in names)
    out = out
        .replaceAll('\u03B1', 'alpha')
        .replaceAll('\u03B2', 'beta')
        .replaceAll('\u03B3', 'gamma')
        .replaceAll('\u03B4', 'delta');

    // Remove invisible controls
    out = out.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');

    return out;
  }

  String? normalizePhotoUrl(String? raw) {
    final u = (raw ?? '').trim();
    if (u.isEmpty) return null;
    try {
      final uri = Uri.parse(u);
      if (!uri.hasScheme) return null;
      final fixed = Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        query: uri.query.isEmpty ? null : uri.query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      ).toString();
      return fixed;
    } catch (_) {
      final encoded = Uri.encodeFull(u);
      try {
        final uri = Uri.parse(encoded);
        if (!uri.hasScheme) return null;
        return uri.toString();
      } catch (_) {
        return null;
      }
    }
  }

  final Map<String, pw.ImageProvider?> photoCache =
      <String, pw.ImageProvider?>{};

  Future<pw.ImageProvider?> loadPhoto(String? rawUrl) async {
    final url = normalizePhotoUrl(rawUrl);
    if (url == null) return null;
    if (photoCache.containsKey(url)) return photoCache[url];
    try {
      final resp = await httpClient.get(Uri.parse(url));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        photoCache[url] = null;
        return null;
      }
      final contentType = resp.headers['content-type']?.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) {
        photoCache[url] = null;
        return null;
      }
      final img = pw.MemoryImage(resp.bodyBytes);
      photoCache[url] = img;
      return img;
    } catch (_) {
      photoCache[url] = null;
      return null;
    }
  }

  Future<void> prefetchPhotos(
    Iterable<String> urls, {
    int batchSize = 6,
  }) async {
    final list = urls.toList();
    if (list.isEmpty) return;
    for (int i = 0; i < list.length; i += batchSize) {
      final batch = list.sublist(i, min(i + batchSize, list.length));
      await Future.wait(batch.map(loadPhoto));
    }
  }

  String fmtText(dynamic v) {
    if (v == null) return '-';
    final s = v.toString().trim();
    if (s.isEmpty) return '-';
    return sanitize(s);
  }

  String fmtNum(num? n, {int decimals = 2}) {
    if (n == null) return '-';
    return n.toDouble().toStringAsFixed(decimals);
  }

  String fmtInt(num? n) {
    if (n == null) return '-';
    return n.toInt().toString();
  }

  String fmtDateOnly(dynamic v) {
    if (v == null) return '-';
    if (v is DateTime) {
      return '${v.year}-${two(v.month)}-${two(v.day)}';
    }
    final s = v.toString().trim();
    if (s.isEmpty) return '-';
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
    }
    return sanitize(s);
  }

  String summarizeList(List<String> items, {int max = 6}) {
    if (items.isEmpty) return 'none';
    if (items.length <= max) return items.join(', ');
    final head = items.take(max).join(', ');
    return '$head (+${items.length - max} more)';
  }

  List<List<T>> chunk<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final out = <List<T>>[];
    for (int i = 0; i < items.length; i += size) {
      out.add(items.sublist(i, min(i + size, items.length)));
    }
    return out;
  }

  InventoryPdfFieldDef? fieldByKey(String key) {
    for (final d in kInventoryPdfFieldDefs) {
      if (d.key == key) return d;
    }
    return null;
  }

  List<InventoryPdfFieldDef> resolveColumns() {
    final selected = options.fields.toSet();
    final out = <InventoryPdfFieldDef>[];
    for (final def in kInventoryPdfFieldDefs) {
      if (!selected.contains(def.key)) continue;
      if (def.lineOnly && options.viewMode != InventoryPdfViewMode.lines) {
        continue;
      }
      if (def.productOnly &&
          options.viewMode != InventoryPdfViewMode.products) {
        continue;
      }
      out.add(def);
    }

    if (out.isEmpty) {
      for (final k in const ['name', 'qty']) {
        final d = fieldByKey(k);
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  try {
    final columns = resolveColumns();

    final bool includePhotoColumn = options.includePhotos;
    // Card-like thumbnail (portrait)
    const double photoThumbWidth = 28;
    const double photoThumbHeight = 40;
    const double photoColWidth = 44;

    final int effectiveColumnCount =
        columns.length + (includePhotoColumn ? 1 : 0);

    final int cellFontSize = () {
      if (effectiveColumnCount >= 11) return 8;
      if (effectiveColumnCount >= 8) return 9;
      return 10;
    }();
    final double headerFontSize = cellFontSize + 1;

    int rowsPerPage;
    if (options.viewMode == InventoryPdfViewMode.lines) {
      rowsPerPage = options.landscape ? 18 : 28;
    } else {
      rowsPerPage = options.landscape ? 20 : 30;
    }

    int maxLines = 1;
    for (final c in columns) {
      if (c.maxLines > maxLines) maxLines = c.maxLines;
    }
    if (maxLines > 1) rowsPerPage -= (maxLines - 1) * 6;

    if (effectiveColumnCount >= 6) rowsPerPage -= 2;
    if (effectiveColumnCount >= 8) rowsPerPage -= 2;
    if (effectiveColumnCount >= 10) rowsPerPage -= 2;
    if (effectiveColumnCount >= 12) rowsPerPage -= 2;

    rowsPerPage = rowsPerPage.clamp(8, 32);

    final statusRank = <String, int>{};
    for (int i = 0; i < kStatusOrder.length; i++) {
      statusRank[kStatusOrder[i]] = i;
    }

    List<Map<String, dynamic>> sortLines(
      List<Map<String, dynamic>> lines,
      InventoryPdfSortMode mode,
    ) {
      final out = List<Map<String, dynamic>>.from(lines);
      int byName(Map<String, dynamic> a, Map<String, dynamic> b) {
        final an = (a['product_name'] ?? '').toString().toLowerCase();
        final bn = (b['product_name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      }

      switch (mode) {
        case InventoryPdfSortMode.qtyDesc:
          out.sort((a, b) {
            final aq = (a['qty_status'] as num?) ?? 0;
            final bq = (b['qty_status'] as num?) ?? 0;
            final q = bq.compareTo(aq);
            if (q != 0) return q;
            return byName(a, b);
          });
          break;
        case InventoryPdfSortMode.statusThenName:
          out.sort((a, b) {
            final sa = (a['status'] ?? '').toString();
            final sb = (b['status'] ?? '').toString();
            final ra = statusRank[sa] ?? 999;
            final rb = statusRank[sb] ?? 999;
            final q = ra.compareTo(rb);
            if (q != 0) return q;
            return byName(a, b);
          });
          break;
        case InventoryPdfSortMode.nameAsc:
          out.sort(byName);
      }
      return out;
    }

    List<InventoryProductSummary> sortProducts(
      List<InventoryProductSummary> items,
      InventoryPdfSortMode mode,
    ) {
      final out = List<InventoryProductSummary>.from(items);
      int byName(InventoryProductSummary a, InventoryProductSummary b) =>
          a.productName.toLowerCase().compareTo(b.productName.toLowerCase());

      switch (mode) {
        case InventoryPdfSortMode.qtyDesc:
          out.sort((a, b) {
            final q = b.totalQty.compareTo(a.totalQty);
            if (q != 0) return q;
            return byName(a, b);
          });
          break;
        case InventoryPdfSortMode.statusThenName:
        case InventoryPdfSortMode.nameAsc:
          out.sort(byName);
      }
      return out;
    }

    String statusMix(Map<String, int> qtyByStatus) {
      final parts = <String>[];
      for (final s in kStatusOrder) {
        if (s == 'vault') continue;
        final q = qtyByStatus[s] ?? 0;
        if (q > 0) parts.add('$s:$q');
      }
      if (parts.isEmpty) return '-';
      return parts.join(' | ');
    }

    String lineValue(String key, Map<String, dynamic> r) {
      switch (key) {
        case 'name':
          return fmtText(r['product_name']);
        case 'qty':
          return fmtInt(r['qty_status'] as num?);
        case 'status':
          return fmtText(r['status']);
        case 'type':
          return fmtText(r['type']);
        case 'game':
          return fmtText(r['game_label']);
        case 'language':
          return fmtText(r['language']);
        case 'currency':
          return fmtText(r['currency']);
        case 'grade_id':
          return fmtText(r['grade_id']);
        case 'grading_note':
          return fmtText(r['grading_note']);
        case 'estimated_unit':
          return fmtNum(r['estimated_price'] as num?);
        case 'buy_unit':
          final qtyTotal = (r['qty_total'] as num?) ?? 0;
          final totalWithFees = (r['total_cost_with_fees'] as num?) ?? 0;
          if (qtyTotal <= 0) return '-';
          return fmtNum(totalWithFees / qtyTotal);
        case 'sale_price':
          final price = r['sale_price'] as num?;
          if (price == null) return '-';
          final cur =
              (r['sale_currency'] ?? r['currency'] ?? '').toString().trim();
          final suffix = cur.isEmpty ? '' : ' $cur';
          return sanitize('${fmtNum(price)}$suffix');
        case 'purchase_date':
          return fmtDateOnly(r['purchase_date']);
        case 'sale_date':
          return fmtDateOnly(r['sale_date']);
        case 'supplier':
          return fmtText(r['supplier_name']);
        case 'buyer':
          return fmtText(r['buyer_company']);
        case 'location':
          return fmtText(r['item_location']);
        default:
          return '-';
      }
    }

    String productValue(String key, InventoryProductSummary p) {
      switch (key) {
        case 'name':
          return fmtText(p.productName);
        case 'qty':
          return fmtInt(p.totalQty);
        case 'status_mix':
          return statusMix(p.qtyByStatus);
        case 'type':
          return fmtText(p.type);
        case 'game':
          return fmtText(p.gameLabel);
        case 'language':
          return fmtText(p.language);
        case 'currency':
          return fmtText(p.currencyDisplay);
        case 'estimated_unit':
          return fmtNum(p.avgEstimatedUnit);
        case 'buy_unit':
          return fmtNum(p.avgBuyUnit);
        default:
          return '-';
      }
    }

    pw.Widget buildHeaderRow() {
      final double colGap = effectiveColumnCount >= 8 ? 6 : 8;
      final children = <pw.Widget>[];
      if (includePhotoColumn) {
        children.add(
          pw.SizedBox(
            width: photoColWidth,
            child: pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Photo',
                style: pw.TextStyle(
                  fontSize: headerFontSize - 1,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 2,
                softWrap: true,
              ),
            ),
          ),
        );
        if (columns.isNotEmpty) {
          children.add(pw.SizedBox(width: colGap));
        }
      }
      for (int i = 0; i < columns.length; i++) {
        final c = columns[i];
        children.add(
          pw.Expanded(
            flex: c.flex,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2),
              child: pw.Align(
                alignment: c.numeric
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
                child: pw.Text(
                  sanitize(c.label),
                  style: pw.TextStyle(
                    fontSize: headerFontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ),
            ),
          ),
        );
        if (i != columns.length - 1) {
          children.add(pw.SizedBox(width: colGap));
        }
      }

      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        ),
        child: pw.Row(children: children),
      );
    }

    pw.Widget buildPhotoThumb(pw.ImageProvider? image) {
      return pw.Container(
        width: photoThumbWidth,
        height: photoThumbHeight,
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: image == null
            ? pw.Center(
                child: pw.Text(
                  '-',
                  style: pw.TextStyle(fontSize: cellFontSize.toDouble()),
                ),
              )
            : pw.ClipRRect(
                horizontalRadius: 4,
                verticalRadius: 4,
                child: pw.Image(image, fit: pw.BoxFit.cover),
              ),
      );
    }

    pw.Widget buildDataRow({
      required List<String> values,
      pw.ImageProvider? photo,
    }) {
      final cellStyle = pw.TextStyle(fontSize: cellFontSize.toDouble());
      final double colGap = effectiveColumnCount >= 8 ? 6 : 8;
      final children = <pw.Widget>[];
      if (includePhotoColumn) {
        children.add(
          pw.SizedBox(
            width: photoColWidth,
            child: pw.Align(
              alignment: pw.Alignment.center,
              child: buildPhotoThumb(photo),
            ),
          ),
        );
        if (columns.isNotEmpty) {
          children.add(pw.SizedBox(width: colGap));
        }
      }
      for (int i = 0; i < columns.length; i++) {
        children.add(
          pw.Expanded(
            flex: columns[i].flex,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2),
              child: pw.Align(
                alignment: columns[i].numeric
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
                child: pw.Text(
                  sanitize(values[i]),
                  style: cellStyle,
                  maxLines: columns[i].maxLines,
                  softWrap: true,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
          ),
        );
        if (i != columns.length - 1) {
          children.add(pw.SizedBox(width: colGap));
        }
      }

      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
            right: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    pw.Widget tableBottomBorder() {
      return pw.Container(
        height: 0,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
            right: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
          ),
        ),
      );
    }

    pw.Widget footer({
      required int pageNumber,
      required int totalPages,
    }) {
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page $pageNumber / $totalPages',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      );
    }

    final viewLabel =
        options.viewMode == InventoryPdfViewMode.lines ? 'Lines' : 'Products';
    final statusNames =
        options.selectedStatuses.map((s) => s.replaceAll('_', ' ')).toList();
    final buyerNames = options.selectedBuyerLabels
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final rowLabel = options.viewMode == InventoryPdfViewMode.products
        ? 'grouped'
        : (options.expandQtyToRows ? 'per item' : 'per line');
    final fieldLabels = <String>[
      if (includePhotoColumn) 'Photo',
      ...columns.map((c) => c.label),
    ];
    final buyerSummary = buyerNames.isNotEmpty
        ? summarizeList(buyerNames, max: 4)
        : (options.selectedBuyerKeys.isNotEmpty
            ? '${options.selectedBuyerKeys.length} selected'
            : 'all');
    final settingsLine = sanitize(
      'View: $viewLabel ($rowLabel) | Statuses: ${summarizeList(statusNames)} | '
      'Buyer infos: $buyerSummary | '
      'Fields: ${summarizeList(fieldLabels, max: 5)}',
    );

    // --- Layout constants ---
    final pageFormat =
        options.landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    const margin = pw.EdgeInsets.fromLTRB(24, 24, 24, 24);

    int totalPages = 0;
    for (final s in sections) {
      final items =
          options.viewMode == InventoryPdfViewMode.lines ? s.lines : s.products;
      final c = chunk(items, rowsPerPage).length;
      totalPages += max(1, c);
    }
    final int totalPageCount = totalPages == 0 ? 1 : totalPages;
    onProgress?.call(0.0, 'Preparing export...');

    int pageNo = 0;
    for (final section in sections) {
      final List<Map<String, dynamic>> lines =
          options.viewMode == InventoryPdfViewMode.lines
              ? sortLines(section.lines, options.sortMode)
              : const <Map<String, dynamic>>[];
      final List<InventoryProductSummary> products =
          options.viewMode == InventoryPdfViewMode.products
              ? sortProducts(section.products, options.sortMode)
              : const <InventoryProductSummary>[];

      final items =
          options.viewMode == InventoryPdfViewMode.lines ? lines : products;

      final chunks = chunk(items, rowsPerPage);
      final int pageCount = max(1, chunks.length);

      for (int pi = 0; pi < pageCount; pi++) {
        pageNo++;
        onProgress?.call(
          (pageNo - 1) / totalPageCount,
          'Building PDF... It can take a few minutes',
        );

        final pageItems = (chunks.isEmpty) ? const <dynamic>[] : chunks[pi];
        if (includePhotoColumn && pageItems.isNotEmpty) {
          final urls = <String>{};
          if (options.viewMode == InventoryPdfViewMode.lines) {
            for (final item in pageItems.cast<Map<String, dynamic>>()) {
              final u = normalizePhotoUrl(item['photo_url']?.toString());
              if (u != null && u.isNotEmpty && !urls.contains(u)) urls.add(u);
            }
          } else {
            for (final item in pageItems.cast<InventoryProductSummary>()) {
              final u = normalizePhotoUrl(item.photoUrl);
              if (u != null && u.isNotEmpty && !urls.contains(u)) urls.add(u);
            }
          }
          if (urls.isNotEmpty) {
            await prefetchPhotos(urls);
          }
        }

        final int totalQty = section.lines.fold<int>(
          0,
          (sum, r) => sum + ((r['qty_status'] as int?) ?? 0),
        );

        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: margin,
            build: (ctx) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Inventorix - Inventory',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Org: ${sanitize(orgId)}',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.Text(
                            'Generated: ${niceDate(generatedAt)}',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    '${sanitize(section.title)} (${items.length})',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    settingsLine,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Total qty: $totalQty',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  buildHeaderRow(),
                  pw.SizedBox(height: 2),
                  if (pageItems.isEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 10),
                      child: pw.Text(
                        'No items.',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    )
                  else ...[
                    for (final item in pageItems)
                      buildDataRow(
                        values: options.viewMode == InventoryPdfViewMode.lines
                            ? columns
                                .map((c) => lineValue(c.key, item))
                                .toList()
                            : columns
                                .map((c) => productValue(c.key, item))
                                .toList(),
                        photo: () {
                          if (!includePhotoColumn) return null;
                          if (options.viewMode == InventoryPdfViewMode.lines) {
                            final u = normalizePhotoUrl(
                                (item as Map<String, dynamic>)['photo_url']
                                    ?.toString());
                            if (u == null) return null;
                            return photoCache[u];
                          }
                          final u = normalizePhotoUrl(
                              (item as InventoryProductSummary).photoUrl);
                          if (u == null) return null;
                          return photoCache[u];
                        }(),
                      ),
                    tableBottomBorder(),
                  ],
                  pw.Spacer(),
                  footer(pageNumber: pageNo, totalPages: totalPages),
                ],
              );
            },
          ),
        );
        onProgress?.call(
          pageNo / totalPageCount,
          'Building PDF...',
        );
      }
    }

    onProgress?.call(0.9, 'Finalizing...');
    return doc.save();
  } finally {
    httpClient.close();
  }
}
