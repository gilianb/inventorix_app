import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../widgets/products_grouped_view.dart' show InventoryProductSummary;

/// Inventory PDF export (Singles + Sealed)
/// ✅ Sans photo
/// ✅ Pagination manuelle (pw.Page) => évite TooManyPagesException
/// ✅ Sanitize ASCII (évite soucis Helvetica sur “—”, “ ”, – , α/β, etc.)
Future<Uint8List> buildInventoryExportPdfBytes({
  required String orgId,
  required DateTime generatedAt,
  required List<InventoryProductSummary> singles,
  required List<InventoryProductSummary> sealed,
}) async {
  final doc = pw.Document();

  // --- Formatting helpers ---
  String two(int v) => v.toString().padLeft(2, '0');
  String niceDate(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

  String sanitize(String s) {
    var out = s;

    // Remplacements typographiques fréquents
    out = out
        .replaceAll('\u2014', '-') // —
        .replaceAll('\u2013', '-') // –
        .replaceAll('\u2018', "'") // ‘
        .replaceAll('\u2019', "'") // ’
        .replaceAll('\u201C', '"') // “
        .replaceAll('\u201D', '"') // ”
        .replaceAll('\u2026', '...') // …
        .replaceAll('\u00A0', ' '); // NBSP

    // Lettres grecques (si présentes dans certains noms)
    out = out
        .replaceAll('\u03B1', 'alpha')
        .replaceAll('\u03B2', 'beta')
        .replaceAll('\u03B3', 'gamma')
        .replaceAll('\u03B4', 'delta');

    // Retire contrôles invisibles
    out = out.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');

    return out;
  }

  List<List<T>> chunk<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final out = <List<T>>[];
    for (int i = 0; i < items.length; i += size) {
      out.add(items.sublist(i, min(i + size, items.length)));
    }
    return out;
  }

  // --- Layout constants ---
  const pageFormat = PdfPageFormat.a4;
  const margin = pw.EdgeInsets.fromLTRB(24, 24, 24, 24);

  // Ajuste si tu veux plus/moins de lignes par page
  const int rowsPerPage = 38;

  // --- Widgets ---
  pw.Widget pageHeader({
    required String sectionTitle,
    required int sectionCount,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Inventorix - Inventory',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
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
          '${sanitize(sectionTitle)} ($sectionCount)',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Name',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Qty',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 2),
      ],
    );
  }

  pw.Widget itemRow(InventoryProductSummary p) {
    final cellStyle = const pw.TextStyle(fontSize: 10);
    final qtyStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
          right: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              sanitize(p.productName),
              style: cellStyle,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          pw.SizedBox(
            width: 60,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('${p.totalQty}', style: qtyStyle),
            ),
          ),
        ],
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

  // --- Build pages plan (manual pagination) ---
  final singleChunks = chunk<InventoryProductSummary>(singles, rowsPerPage);
  final sealedChunks = chunk<InventoryProductSummary>(sealed, rowsPerPage);

  // Si une section est vide, on veut quand même 1 page "No items"
  final int singlesPageCount = max(1, singleChunks.length);
  final int sealedPageCount = max(1, sealedChunks.length);
  final int totalPages = singlesPageCount + sealedPageCount;

  int pageNo = 0;

  // --- Singles pages ---
  for (int pi = 0; pi < singlesPageCount; pi++) {
    pageNo++;

    final items = (singleChunks.isEmpty)
        ? const <InventoryProductSummary>[]
        : singleChunks[pi];

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: margin,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pageHeader(
                sectionTitle: 'Singles',
                sectionCount: singles.length,
                pageNumber: pageNo,
                totalPages: totalPages,
              ),
              if (items.isEmpty)
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
                for (final p in items) itemRow(p),
                tableBottomBorder(),
              ],
              pw.Spacer(),
              footer(pageNumber: pageNo, totalPages: totalPages),
            ],
          );
        },
      ),
    );
  }

  // --- Sealed pages ---
  for (int pi = 0; pi < sealedPageCount; pi++) {
    pageNo++;

    final items = (sealedChunks.isEmpty)
        ? const <InventoryProductSummary>[]
        : sealedChunks[pi];

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: margin,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pageHeader(
                sectionTitle: 'Sealed',
                sectionCount: sealed.length,
                pageNumber: pageNo,
                totalPages: totalPages,
              ),
              if (items.isEmpty)
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
                for (final p in items) itemRow(p),
                tableBottomBorder(),
              ],
              pw.Spacer(),
              footer(pageNumber: pageNo, totalPages: totalPages),
            ],
          );
        },
      ),
    );
  }

  return doc.save();
}
