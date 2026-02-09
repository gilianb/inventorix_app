// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:printing/printing.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../invoice_service.dart';
import '../invoice_actions.dart';
import '../invoice_format.dart';
import '../models/enums.dart';
import '../models/invoice.dart';
import '../models/invoice_folder.dart';

// Dialog de sélection des items pour créer une facture de vente
import 'invoice_select_items_dialog.dart';

// ✅ NEW: external invoice/document dialog
import 'attach_external_invoice_dialog.dart';

/// Internal tree node used only in this page to build a hierarchical folder view.
class _FolderNode {
  _FolderNode({
    required this.name,
    required this.path,
    this.folderId,
    this.directCount = 0,
    this.totalCount = 0,
  });

  String name; // e.g. "CardShouker"
  String path; // e.g. "CardShouker/purchase/ebay"
  int? folderId; // real DB folder id (only on leaf nodes)
  int directCount; // invoices directly inside this folder
  int totalCount; // aggregated invoices (this folder + subfolders)
  final List<_FolderNode> children = [];

  bool get hasRealFolder => folderId != null;
  bool get hasChildren => children.isNotEmpty;
}

class InvoiceManagementPage extends StatefulWidget {
  final String orgId;

  const InvoiceManagementPage({
    super.key,
    required this.orgId,
  });

  @override
  State<InvoiceManagementPage> createState() => _InvoiceManagementPageState();
}

class _InvoiceManagementPageState extends State<InvoiceManagementPage> {
  late final InvoiceService _invoiceService;

  List<InvoiceFolder> _folders = [];
  List<Invoice> _allInvoices = [];
  List<Invoice> _invoices = [];

  _FolderNode? _folderRoot;

  /// map folderId -> name (full path)
  Map<int, String> _folderNameById = {};

  /// null = show all
  int? _selectedFolderId;

  /// if non-null => show all invoices whose folder name starts with that prefix
  String? _selectedFolderPrefix;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _invoiceService = InvoiceService(Supabase.instance.client);
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers: download/save bytes (works on mobile + web)
  // ---------------------------------------------------------------------------

  MimeType _mimeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'pdf') return MimeType.pdf;
    if (e == 'png') return MimeType.png;
    if (e == 'jpg' || e == 'jpeg') return MimeType.jpeg;
    // fallback (best effort)
    return MimeType.pdf;
  }

  Future<void> _saveBytesDirect({
    required Uint8List bytes,
    required String baseName, // without extension
    required String ext, // e.g. "pdf"
  }) async {
    try {
      // Web: triggers direct download
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          fileExtension: ext,
          mimeType: _mimeFromExt(ext),
        );
        return;
      }

      // Mobile/Desktop: try saveAs first (lets user choose location when possible)
      try {
        await FileSaver.instance.saveAs(
          name: baseName,
          bytes: bytes,
          fileExtension: ext,
          mimeType: _mimeFromExt(ext),
        );
        return;
      } catch (_) {
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          fileExtension: ext,
          mimeType: _mimeFromExt(ext),
        );
        return;
      }
    } catch (_) {
      // last resort fallback
      if (ext.toLowerCase() == 'pdf') {
        await Printing.sharePdf(bytes: bytes, filename: '$baseName.$ext');
      } else {
        // for images/other, share sheet
        await Printing.sharePdf(bytes: bytes, filename: '$baseName.$ext');
      }
    }
  }

  String _extFromPath(String pathInBucket) {
    final lower = pathInBucket.toLowerCase();
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg')) return 'jpg';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    return 'pdf';
  }

  String _safeFileBaseName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^\w\-_\.]+'), '_');
    return s.isEmpty ? 'invoice' : s;
  }

  // ---------------------------------------------------------------------------
  // Data loading + tree building
  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1) fetch folders + ALL invoices of the org
      final folders = await _invoiceService.listFolders(widget.orgId);
      final invoices = await _invoiceService.listInvoices(
          orgId: widget.orgId, folderId: null);

      // 2) compute direct counts per folderId from invoices
      final Map<int, int> folderCounts = {};
      for (final inv in invoices) {
        final fid = inv.folderId;
        if (fid != null) {
          folderCounts[fid] = (folderCounts[fid] ?? 0) + 1;
        }
      }

      // 3) build folder tree from flat list of names
      final root = _buildFolderTree(folders, folderCounts);

      setState(() {
        _folders = folders;
        _allInvoices = invoices;
        _folderRoot = root;
        _folderNameById = {
          for (final f in folders) f.id: f.name,
        };

        // re-apply current filter (if any) on fresh data
        _applyCurrentFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error while loading invoices: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  _FolderNode _buildFolderTree(
    List<InvoiceFolder> folders,
    Map<int, int> folderCounts,
  ) {
    final root = _FolderNode(
      name: '',
      path: '',
      folderId: null,
      directCount: 0,
      totalCount: 0,
    );

    for (final folder in folders) {
      final fullName = folder.name.trim();
      if (fullName.isEmpty) continue;

      final segments = fullName
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.isEmpty) continue;

      _FolderNode current = root;
      String pathSoFar = '';

      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        pathSoFar = pathSoFar.isEmpty ? seg : '$pathSoFar/$seg';
        final bool isLast = (i == segments.length - 1);

        // find existing child
        _FolderNode? child;
        for (final c in current.children) {
          if (c.name == seg) {
            child = c;
            break;
          }
        }

        if (child == null) {
          child = _FolderNode(
            name: seg,
            path: pathSoFar,
            folderId: isLast ? folder.id : null,
            directCount: isLast ? (folderCounts[folder.id] ?? 0) : 0,
            totalCount: 0,
          );
          current.children.add(child);
        } else if (isLast) {
          // if node already existed as virtual parent, attach folderId and direct count
          child.folderId ??= folder.id;
          child.directCount = folderCounts[folder.id] ?? child.directCount;
        }

        current = child;
      }
    }

    // aggregate counts up the tree
    _computeAggregatedCounts(root);
    return root;
  }

  int _computeAggregatedCounts(_FolderNode node) {
    int sum = node.directCount;
    for (final child in node.children) {
      sum += _computeAggregatedCounts(child);
    }
    node.totalCount = sum;
    return sum;
  }

  // ---------------------------------------------------------------------------
  // Filtering helpers
  // ---------------------------------------------------------------------------

  void _applyCurrentFilter() {
    // no data yet
    if (_allInvoices.isEmpty && _folders.isEmpty) {
      _invoices = const [];
      return;
    }

    Iterable<Invoice> filtered = _allInvoices;

    if (_selectedFolderId != null) {
      filtered = filtered.where((inv) => inv.folderId == _selectedFolderId);
    } else if (_selectedFolderPrefix != null) {
      filtered = filtered.where((inv) {
        final fid = inv.folderId;
        if (fid == null) return false;
        final folderName = _folderNameById[fid] ?? '';
        return folderName.startsWith(_selectedFolderPrefix!);
      });
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((inv) {
        final folderName =
            inv.folderId != null ? _folderNameById[inv.folderId!] ?? '' : '';
        final counterpartyRaw =
            inv.type == InvoiceType.purchase ? inv.sellerName : inv.buyerName;
        final counterparty = (counterpartyRaw).toLowerCase();
        return inv.invoiceNumber.toLowerCase().contains(q) ||
            counterparty.contains(q) ||
            folderName.toLowerCase().contains(q) ||
            inv.currency.toLowerCase().contains(q) ||
            inv.totalInclTax.toString().contains(q);
      });
    }

    _invoices = filtered.toList();
  }

  void _selectAll() {
    setState(() {
      _selectedFolderId = null;
      _selectedFolderPrefix = null;
      _applyCurrentFilter();
    });
  }

  void _selectFolderById(int folderId) {
    setState(() {
      _selectedFolderId = folderId;
      _selectedFolderPrefix = null;
      _applyCurrentFilter();
    });
  }

  void _selectFolderByPrefix(String prefix) {
    setState(() {
      _selectedFolderId = null;
      _selectedFolderPrefix = prefix;
      _applyCurrentFilter();
    });
  }

  String _currentFilterLabel() {
    if (_selectedFolderId == null && _selectedFolderPrefix == null) {
      return 'All invoices (${_allInvoices.length})';
    }
    if (_selectedFolderId != null) {
      final name = _folderNameById[_selectedFolderId!] ?? 'Unknown folder';
      return 'Folder: $name (${_invoices.length})';
    }
    return 'All subfolders of "${_selectedFolderPrefix ?? ''}" (${_invoices.length})';
  }

  // ---------------------------------------------------------------------------
  // Folder actions (delete folder tree)
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteFolder(_FolderNode node) async {
    // collect all real folder IDs in this subtree
    final Set<int> folderIds = {};
    void collect(_FolderNode n) {
      if (n.folderId != null) folderIds.add(n.folderId!);
      for (final c in n.children) {
        collect(c);
      }
    }

    collect(node);

    if (folderIds.isEmpty) {
      return;
    }

    final invoicesToDelete = _allInvoices
        .where(
            (inv) => inv.folderId != null && folderIds.contains(inv.folderId))
        .toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder and content'),
        content: Text(
          'You are about to delete the folder "${node.path}"\n'
          '• Folders to delete: ${folderIds.length}\n'
          '• Invoices to delete: ${invoicesToDelete.length}\n\n'
          'All these invoices (and their PDF/files) will be permanently deleted.\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = Supabase.instance.client;

    try {
      // 1) delete all invoices (and their files) using existing service
      for (final inv in invoicesToDelete) {
        await _invoiceService.deleteInvoice(inv, deletePdf: true);
      }

      // 2) delete folders themselves
      for (final id in folderIds) {
        await client.from('invoice_folder').delete().eq('id', id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder "${node.path}" deleted.')),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while deleting folder: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Invoice actions: view, download, move, attach/remove document, mark paid, delete
  // ---------------------------------------------------------------------------

  Future<void> _downloadInvoiceDocument(Invoice invoice) async {
    if (invoice.documentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document attached to this invoice.')),
      );
      return;
    }

    final client = Supabase.instance.client;

    // document_url stocké comme: 'invoices/<...path in bucket...>'
    final fullPath = invoice.documentUrl!;
    final pathInBucket = fullPath.replaceFirst('invoices/', '');

    try {
      final bytes =
          await client.storage.from('invoices').download(pathInBucket);

      final ext = _extFromPath(pathInBucket);
      final baseName = _safeFileBaseName(
          'invoice_${invoice.invoiceNumber}_$ext'.replaceAll('.$ext', ''));

      await _saveBytesDirect(bytes: bytes, baseName: baseName, ext: ext);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded: $baseName.$ext')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while downloading document: $e')),
      );
    }
  }

  Future<void> _viewInvoicePdf(Invoice invoice) async {
    if (invoice.documentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document attached to this invoice.')),
      );
      return;
    }

    final client = Supabase.instance.client;

    final fullPath = invoice.documentUrl!;
    final pathInBucket = fullPath.replaceFirst('invoices/', '');
    final lower = pathInBucket.toLowerCase();
    final isPdf = lower.endsWith('.pdf');

    try {
      if (kIsWeb) {
        // 🌐 WEB : open in browser (and you also have "Download" in menu)
        final signedUrl = await client.storage
            .from('invoices')
            .createSignedUrl(pathInBucket, 60);

        final uri = Uri.tryParse(signedUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid document URL')),
          );
        }
        return;
      }

      // 📱/💻 Mobile & desktop : preview
      final bytes =
          await client.storage.from('invoices').download(pathInBucket);

      if (isPdf) {
        // Preview (may open print/preview UI depending on platform)
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Document preview'),
            content: SizedBox(
              width: 700,
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while loading document: $e')),
      );
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete invoice'),
        content: Text(
          'Are you sure you want to delete invoice ${invoice.invoiceNumber}?\n'
          'This will delete the invoice, its lines and the attached file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _invoiceService.deleteInvoice(invoice, deletePdf: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invoice ${invoice.invoiceNumber} deleted.'),
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while deleting invoice: $e')),
      );
    }
  }

  Future<void> _markInvoicePaid(Invoice invoice) async {
    try {
      await _invoiceService.markInvoicePaid(invoice.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invoice ${invoice.invoiceNumber} marked as paid.'),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while marking invoice as paid: $e')),
      );
    }
  }

  /// (2) Move invoice to another folder
  Future<void> _moveInvoiceToFolder(Invoice invoice) async {
    final selectedId =
        await _selectFolderDialog(initialFolderId: invoice.folderId);
    if (selectedId == null) return;

    try {
      final client = Supabase.instance.client;
      await client
          .from('invoice')
          .update({'folder_id': selectedId}).eq('id', invoice.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invoice ${invoice.invoiceNumber} moved to ${_folderNameById[selectedId] ?? 'folder'}',
          ),
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while moving invoice: $e')),
      );
    }
  }

  Future<int?> _selectFolderDialog({int? initialFolderId}) async {
    int? selectedId = initialFolderId;

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Move to folder'),
          content: SizedBox(
            width: 320,
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Choose the destination folder for this invoice.'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      RadioListTile<int?>(
                        value: null,
                        groupValue: selectedId,
                        onChanged: (v) {
                          setState(() {});
                          selectedId = v;
                          (ctx as Element).markNeedsBuild();
                        },
                        title: const Text('No folder'),
                        subtitle:
                            const Text('Invoice not attached to any folder'),
                      ),
                      const Divider(),
                      ..._folders.map(
                        (f) => RadioListTile<int?>(
                          value: f.id,
                          groupValue: selectedId,
                          onChanged: (v) {
                            selectedId = v;
                            (ctx as Element).markNeedsBuild();
                          },
                          title: Text(f.name),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(selectedId),
              child: const Text('Move'),
            ),
          ],
        );
      },
    );
  }

  /// (3) Attach or replace the document of an invoice (PDF/Image)
  Future<void> _attachOrReplacePdf(Invoice invoice) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to read the selected file.')),
      );
      return;
    }

    final client = Supabase.instance.client;

    try {
      // 1) delete old file if any
      if (invoice.documentUrl != null) {
        final oldFull = invoice.documentUrl!;
        final oldPath = oldFull.replaceFirst('invoices/', '');
        await client.storage.from('invoices').remove([oldPath]);
      }

      // 2) upload new file (keep extension)
      final now = DateTime.now().millisecondsSinceEpoch;
      final safeName = (file.name).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final newPathInBucket =
          'org_${widget.orgId}/inv_${invoice.id}_${now}_$safeName';

      final lower = safeName.toLowerCase();
      final contentType = lower.endsWith('.pdf')
          ? 'application/pdf'
          : lower.endsWith('.png')
              ? 'image/png'
              : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
                  ? 'image/jpeg'
                  : 'application/octet-stream';

      await client.storage.from('invoices').uploadBinary(
            newPathInBucket,
            file.bytes!,
            fileOptions: FileOptions(contentType: contentType),
          );

      final newDocumentUrl = 'invoices/$newPathInBucket';

      // 3) update invoice row
      await client
          .from('invoice')
          .update({'document_url': newDocumentUrl}).eq('id', invoice.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invoice.documentUrl == null
                ? 'Document attached to invoice ${invoice.invoiceNumber}.'
                : 'Document replaced for invoice ${invoice.invoiceNumber}.',
          ),
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while attaching document: $e')),
      );
    }
  }

  /// (3) Remove attached document from invoice (without deleting the invoice)
  Future<void> _detachPdf(Invoice invoice) async {
    if (invoice.documentUrl == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attached document'),
        content: Text(
          'Remove the document attached to invoice ${invoice.invoiceNumber}?\n'
          'The invoice itself will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = Supabase.instance.client;

    try {
      final fullPath = invoice.documentUrl!;
      final pathInBucket = fullPath.replaceFirst('invoices/', '');
      await client.storage.from('invoices').remove([pathInBucket]);

      await client
          .from('invoice')
          .update({'document_url': null}).eq('id', invoice.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Document removed from invoice ${invoice.invoiceNumber}.'),
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while removing document: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // External invoice/document (not linked to an item)
  // ---------------------------------------------------------------------------

  Future<void> _onAttachExternalInvoice() async {
    const defaultCurrency = 'AED';

    final result = await AttachExternalInvoiceDialog.show(
      context,
      currency: defaultCurrency,
      folders: _folders,
    );

    if (result == null) return;

    try {
      int? folderId = result.folderId;

      // create folder if user typed a new one
      final newFolderName = result.newFolderName?.trim();
      if (newFolderName != null && newFolderName.isNotEmpty) {
        final folder = await _invoiceService.getOrCreateFolder(
          orgId: widget.orgId,
          name: newFolderName,
        );
        folderId = folder.id;
      }

      final actions = InvoiceActions(Supabase.instance.client);

      final created = await actions.attachExternalInvoiceDocument(
        orgId: widget.orgId,
        currency: result.currency,
        supplierName: result.supplierName,
        externalInvoiceNumber: result.invoiceNumber,
        issueDate: result.issueDate,
        totalAmount: result.totalAmount,
        fileName: result.fileName,
        fileBytes: result.fileBytes,
        folderId: folderId,
        notes: result.notes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External document ${created.invoiceNumber} attached.'),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while attaching external document: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Folder name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      await _invoiceService.createFolder(orgId: widget.orgId, name: name);
      await _loadData();
    }
  }

  Widget _buildStatusChip(Invoice invoice) {
    Color color;
    String label;

    switch (invoice.status) {
      case InvoiceStatus.paid:
        color = Colors.green;
        label = 'PAID';
        break;
      case InvoiceStatus.draft:
        color = Colors.grey;
        label = 'DRAFT';
        break;
      case InvoiceStatus.sent:
        color = Colors.blue;
        label = 'SENT';
        break;
      case InvoiceStatus.overdue:
        color = Colors.red;
        label = 'OVERDUE';
        break;
      case InvoiceStatus.cancelled:
        color = Colors.orange;
        label = 'CANCELLED';
        break;
    }

    return _buildPill(label: label, color: color);
  }

  Widget _buildTypeChip(Invoice invoice) {
    Color color;
    String label;

    switch (invoice.type) {
      case InvoiceType.sale:
        color = Colors.indigo;
        label = 'SALE';
        break;
      case InvoiceType.purchase:
        color = Colors.deepPurple;
        label = 'PURCHASE';
        break;
      case InvoiceType.creditNote:
        color = Colors.teal;
        label = 'CREDIT NOTE';
        break;
    }

    return _buildPill(label: label, color: color);
  }

  Widget _buildPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Create NEW sales invoice (grouped) from this page
  // ---------------------------------------------------------------------------

  Future<void> _onCreateSalesInvoiceFromManagement() async {
    final result = await InvoiceSelectItemsDialog.show(
      context,
      orgId: widget.orgId,
    );

    if (result == null) return;

    if (result.itemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items selected for the invoice.')),
      );
      return;
    }

    try {
      final actions = InvoiceActions(Supabase.instance.client);

      final invoice = await actions.createBillForItemsAndGeneratePdf(
        orgId: widget.orgId,
        itemIds: result.itemIds,
        currency: result.currency,
        taxRate: result.taxRate,
        dueDate: result.dueDate,
        // Seller
        sellerName: result.sellerName,
        sellerAddress: result.sellerAddress,
        sellerCountry: result.sellerCountry,
        sellerVatNumber: result.sellerVatNumber,
        sellerTaxRegistration: result.sellerTaxRegistration,
        sellerRegistrationNumber: result.sellerRegistrationNumber,
        // Buyer
        buyerName: result.buyerName,
        buyerAddress: result.buyerAddress,
        buyerCountry: result.buyerCountry,
        buyerVatNumber: result.buyerVatNumber,
        buyerTaxRegistration: result.buyerTaxRegistration,
        buyerEmail: result.buyerEmail,
        buyerPhone: result.buyerPhone,
        // Other
        paymentTerms: result.paymentTerms,
        notes: result.notes,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${invoice.invoiceNumber} created.')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while creating invoice: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 980;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCommandBar(isWide: isWide),
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            SizedBox(
                              width: 300,
                              child: _buildFolderList(),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _buildInvoiceList(isWide: true)),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: 64,
                              child: _buildFolderChips(),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _buildInvoiceList(isWide: false),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCommandBar({required bool isWide}) {
    final theme = Theme.of(context);
    final actions = [
      _buildCommandButton(
        icon: Icons.receipt_long_outlined,
        label: 'New sales invoice',
        onPressed: _onCreateSalesInvoiceFromManagement,
        primary: true,
      ),
      _buildCommandButton(
        icon: Icons.upload_file_outlined,
        label: 'Attach document',
        onPressed: _onAttachExternalInvoice,
      ),
      _buildCommandButton(
        icon: Icons.create_new_folder_outlined,
        label: 'New folder',
        onPressed: _createFolderDialog,
      ),
    ];
    final actionWidgets = <Widget>[];
    for (int i = 0; i < actions.length; i++) {
      if (i > 0) {
        actionWidgets.add(const SizedBox(width: 8));
      }
      actionWidgets.add(actions[i]);
    }

    final searchField = SizedBox(
      width: isWide ? 300 : double.infinity,
      child: _buildSearchField(),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: isWide
          ? Row(
              children: [
                ...actionWidgets,
                const Spacer(),
                searchField,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
                const SizedBox(height: 10),
                searchField,
              ],
            ),
    );
  }

  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final buttonStyle = primary
        ? ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          )
        : OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          );

    final button = primary
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: buttonStyle,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: buttonStyle,
          );

    return Tooltip(message: label, child: button);
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchCtrl,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
          _applyCurrentFilter();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search invoices, people, totals...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: _clearSearch,
                icon: const Icon(Icons.close),
              ),
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _applyCurrentFilter();
    });
  }

  // ----- LEFT PANE (desktop) : hierarchical folder tree -----

  Widget _buildFolderList() {
    final root = _folderRoot;
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.22),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.storage_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Navigation',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tileColor:
                      _selectedFolderId == null && _selectedFolderPrefix == null
                          ? theme.colorScheme.primary.withOpacity(0.08)
                          : null,
                  selected: _selectedFolderId == null &&
                      _selectedFolderPrefix == null,
                  selectedTileColor:
                      theme.colorScheme.primary.withOpacity(0.08),
                  leading: const Icon(Icons.all_inbox_outlined),
                  title: const Text(
                    'All invoices',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${_allInvoices.length} documents'),
                  onTap: _selectAll,
                ),
                const SizedBox(height: 12),
                Text(
                  'Folders',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(),
                if (root != null)
                  ...root.children.map((node) => _buildFolderNodeTile(node)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildFolderMenuButton(_FolderNode node) {
    if (!node.hasRealFolder) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: 'Folder actions',
      onSelected: (value) {
        if (value == 'delete') {
          _confirmDeleteFolder(node);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete folder & invoices'),
        ),
      ],
      icon: const Icon(Icons.more_vert, size: 18),
    );
  }

  Widget _buildFolderNodeTile(_FolderNode node) {
    final bool isSelectedLeaf =
        node.folderId != null && node.folderId == _selectedFolderId;
    final bool isSelectedPrefix = node.path == _selectedFolderPrefix;

    final theme = Theme.of(context);
    final bool isSelected = isSelectedLeaf || isSelectedPrefix;

    if (!node.hasChildren) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        selected: isSelected,
        selectedTileColor: theme.colorScheme.primary.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        leading: const Icon(Icons.folder_outlined),
        title: Text(
          node.name,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCountBadge(node.directCount),
            const SizedBox(width: 4),
            _buildFolderMenuButton(node),
          ],
        ),
        onTap: () {
          if (node.folderId != null) {
            _selectFolderById(node.folderId!);
          }
        },
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 8, right: 4),
        childrenPadding: const EdgeInsets.only(left: 12),
        initiallyExpanded: true,
        leading: Icon(
          Icons.folder_outlined,
          color: isSelectedPrefix ? theme.colorScheme.primary : null,
        ),
        title: Text(
          node.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${node.totalCount} items'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCountBadge(node.totalCount),
            const SizedBox(width: 4),
            _buildFolderMenuButton(node),
          ],
        ),
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8, right: 8),
            selected: isSelectedPrefix,
            selectedTileColor: theme.colorScheme.primary.withOpacity(0.08),
            leading: const Icon(Icons.folder_special_outlined, size: 18),
            title: const Text('All items in this folder'),
            subtitle: Text(node.path),
            trailing: _buildCountBadge(node.totalCount),
            onTap: () => _selectFolderByPrefix(node.path),
          ),
          if (node.folderId != null)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 8, right: 8),
              selected: isSelectedLeaf,
              selectedTileColor: theme.colorScheme.primary.withOpacity(0.08),
              leading: const Icon(Icons.folder_open, size: 18),
              title: const Text('Only this folder'),
              subtitle: Text(node.path),
              trailing: _buildCountBadge(node.directCount),
              onTap: () => _selectFolderById(node.folderId!),
            ),
          ...node.children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _buildFolderNodeTile(child),
            ),
          ),
        ],
      ),
    );
  }

  // ----- TOP CHIPS (mobile) -----

  Widget _buildFolderChips() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: _selectedFolderId == null && _selectedFolderPrefix == null,
          onSelected: (_) => _selectAll(),
        ),
        const SizedBox(width: 8),
        ..._folders.map((folder) {
          final selected = _selectedFolderId == folder.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(folder.name),
              selected: selected,
              onSelected: (_) => _selectFolderById(folder.id),
            ),
          );
        }),
      ],
    );
  }

  // ----- RIGHT PANE : invoice list + header -----

  Widget _buildInvoiceList({required bool isWide}) {
    if (_invoices.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        _buildContentHeader(),
        _buildSummaryStrip(),
        const Divider(height: 1),
        Expanded(
          child: isWide ? _buildInvoiceTable() : _buildInvoiceCards(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No invoices yet in this view.'),
          const SizedBox(height: 4),
          Text(
            _currentFilterLabel(),
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildContentHeader() {
    final theme = Theme.of(context);
    final segments = _currentPathSegments();
    final showClear = _selectedFolderId != null ||
        _selectedFolderPrefix != null ||
        _searchQuery.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < segments.length; i++) ...[
                      Text(
                        segments[i],
                        style: TextStyle(
                          fontWeight:
                              i == segments.length - 1 ? FontWeight.w600 : null,
                        ),
                      ),
                      if (i < segments.length - 1)
                        const Icon(Icons.chevron_right, size: 16),
                    ],
                  ],
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildFilterChip('Search: $_searchQuery'),
                ],
              ],
            ),
          ),
          if (showClear)
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<String> _currentPathSegments() {
    if (_selectedFolderId == null && _selectedFolderPrefix == null) {
      return ['All invoices'];
    }

    final rawPath = _selectedFolderId != null
        ? _folderNameById[_selectedFolderId!] ?? ''
        : _selectedFolderPrefix ?? '';

    if (rawPath.isEmpty) return ['All invoices'];
    return ['All invoices', ...rawPath.split('/')];
  }

  void _clearAllFilters() {
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
      _selectedFolderId = null;
      _selectedFolderPrefix = null;
      _applyCurrentFilter();
    });
  }

  Widget _buildSummaryStrip() {
    final total = _invoices.length;
    final paid = _invoices.where((i) => i.status == InvoiceStatus.paid).length;
    final overdue =
        _invoices.where((i) => i.status == InvoiceStatus.overdue).length;
    final draft =
        _invoices.where((i) => i.status == InvoiceStatus.draft).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildSummaryCard('Total', total, Colors.blueGrey),
          _buildSummaryCard('Paid', paid, Colors.green),
          _buildSummaryCard('Overdue', overdue, Colors.redAccent),
          _buildSummaryCard('Draft', draft, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(width: 6),
          Text(
            value.toString(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showFolder = width >= 980;
        final showType = width >= 880;
        final showStatus = width >= 760;
        final showTotal = width >= 660;
        final showDate = width >= 560;

        return Column(
          children: [
            _buildInvoiceTableHeader(
              showFolder: showFolder,
              showType: showType,
              showStatus: showStatus,
              showTotal: showTotal,
              showDate: showDate,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _invoices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final invoice = _invoices[index];
                  return _buildInvoiceRow(
                    invoice,
                    showFolder: showFolder,
                    showType: showType,
                    showStatus: showStatus,
                    showTotal: showTotal,
                    showDate: showDate,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInvoiceTableHeader({
    required bool showFolder,
    required bool showType,
    required bool showStatus,
    required bool showTotal,
    required bool showDate,
  }) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );

    // Build children list explicitly to avoid collection-if/spread parsing issues.
    final List<Widget> children = [
      Expanded(flex: 4, child: Text('INVOICE', style: headerStyle)),
      const SizedBox(width: 12),
      Expanded(flex: 4, child: Text('COUNTERPARTY', style: headerStyle)),
    ];

    if (showDate) {
      children.addAll([
        const SizedBox(width: 12),
        Expanded(flex: 2, child: Text('DATE', style: headerStyle)),
      ]);
    }

    if (showTotal) {
      children.addAll([
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('TOTAL', style: headerStyle),
          ),
        ),
      ]);
    }

    if (showStatus) {
      children.addAll([
        const SizedBox(width: 12),
        SizedBox(width: 92, child: Text('STATUS', style: headerStyle)),
      ]);
    }

    if (showType) {
      children.addAll([
        const SizedBox(width: 12),
        SizedBox(width: 96, child: Text('TYPE', style: headerStyle)),
      ]);
    }

    if (showFolder) {
      children.addAll([
        const SizedBox(width: 12),
        Expanded(flex: 3, child: Text('FOLDER', style: headerStyle)),
      ]);
    }

    children.addAll([
      const SizedBox(width: 12),
      const SizedBox(width: 36),
    ]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Row(
        children: children,
      ),
    );
  }

  Widget _buildInvoiceRow(
    Invoice invoice, {
    required bool showFolder,
    required bool showType,
    required bool showStatus,
    required bool showTotal,
    required bool showDate,
  }) {
    final theme = Theme.of(context);
    final folderName = invoice.folderId != null
        ? _folderNameById[invoice.folderId!] ?? ''
        : '';
    final counterpartyValue = _counterpartyValue(invoice);
    final hasDoc = invoice.documentUrl != null;

    return InkWell(
        onTap: () => _viewInvoicePdf(invoice),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    _buildInvoiceIcon(invoice),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invoice.invoiceNumber,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            hasDoc ? 'Document attached' : 'No document',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Text(
                  counterpartyValue.isEmpty ? '-' : counterpartyValue,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showDate) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(formatDate(invoice.issueDate)),
                ),
              ],
              if (showTotal) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatMoney(invoice.totalInclTax, invoice.currency),
                    ),
                  ),
                ),
              ],
              if (showStatus) ...[
                const SizedBox(width: 12),
                SizedBox(width: 92, child: _buildStatusChip(invoice)),
              ],
              if (showType) ...[
                const SizedBox(width: 12),
                SizedBox(width: 96, child: _buildTypeChip(invoice)),
              ],
              if (showFolder) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    folderName.isEmpty ? '-' : folderName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(width: 36, child: _buildInvoiceMenuButton(invoice)),
            ],
          ),
        ));
  }

  Widget _buildInvoiceCards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _invoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final invoice = _invoices[index];
        return _buildInvoiceCard(invoice);
      },
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    final theme = Theme.of(context);
    final folderName = invoice.folderId != null
        ? _folderNameById[invoice.folderId!] ?? ''
        : '';
    final counterpartyLabel = _counterpartyLabel(invoice);
    final counterpartyValue = _counterpartyValue(invoice);

    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _viewInvoicePdf(invoice),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildInvoiceIcon(invoice),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      invoice.invoiceNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildInvoiceMenuButton(invoice),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildStatusChip(invoice),
                  _buildTypeChip(invoice),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                counterpartyValue.isEmpty
                    ? counterpartyLabel
                    : '$counterpartyLabel: $counterpartyValue',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Date: ${formatDate(invoice.issueDate)} • Total: ${formatMoney(invoice.totalInclTax, invoice.currency)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (folderName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Folder: $folderName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceIcon(Invoice invoice) {
    final theme = Theme.of(context);
    final hasDoc = invoice.documentUrl != null;
    final icon =
        hasDoc ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined;
    final color =
        hasDoc ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildInvoiceMenuButton(Invoice invoice) {
    final hasDoc = invoice.documentUrl != null;
    return PopupMenuButton<String>(
      onSelected: (value) => _onInvoiceMenuAction(value, invoice),
      itemBuilder: (context) => _buildInvoiceMenuItems(hasDoc),
      icon: const Icon(Icons.more_vert, size: 18),
    );
  }

  List<PopupMenuEntry<String>> _buildInvoiceMenuItems(bool hasDoc) {
    final items = <PopupMenuEntry<String>>[];

    items.add(
      PopupMenuItem(
        value: 'view',
        child: Text(
          hasDoc ? 'View document' : 'View document (none attached)',
        ),
      ),
    );

    if (hasDoc) {
      items.add(
        const PopupMenuItem(
          value: 'download',
          child: Text('Download document'),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        value: 'attach',
        child: Text(
          hasDoc ? 'Replace document' : 'Attach document',
        ),
      ),
    );

    if (hasDoc) {
      items.add(
        const PopupMenuItem(
          value: 'detach',
          child: Text('Remove attached document'),
        ),
      );
    }

    items.add(const PopupMenuDivider());

    items.add(
      const PopupMenuItem(
        value: 'move',
        child: Text('Move to folder...'),
      ),
    );
    items.add(
      const PopupMenuItem(
        value: 'paid',
        child: Text('Mark as paid'),
      ),
    );
    items.add(
      const PopupMenuItem(
        value: 'delete',
        child: Text('Delete invoice'),
      ),
    );

    return items;
  }

  Future<void> _onInvoiceMenuAction(String value, Invoice invoice) async {
    if (value == 'view') {
      await _viewInvoicePdf(invoice);
    } else if (value == 'download') {
      await _downloadInvoiceDocument(invoice);
    } else if (value == 'attach') {
      await _attachOrReplacePdf(invoice);
    } else if (value == 'detach') {
      await _detachPdf(invoice);
    } else if (value == 'move') {
      await _moveInvoiceToFolder(invoice);
    } else if (value == 'paid') {
      await _markInvoicePaid(invoice);
    } else if (value == 'delete') {
      await _deleteInvoice(invoice);
    }
  }

  String _counterpartyLabel(Invoice invoice) {
    switch (invoice.type) {
      case InvoiceType.sale:
        return 'Buyer';
      case InvoiceType.purchase:
        return 'Supplier';
      case InvoiceType.creditNote:
        return 'Counterparty';
    }
  }

  String _counterpartyValue(Invoice invoice) {
    if (invoice.type == InvoiceType.purchase) {
      return invoice.sellerName;
    }
    return invoice.buyerName;
  }
}
