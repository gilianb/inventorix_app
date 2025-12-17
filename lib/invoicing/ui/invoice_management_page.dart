// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';

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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Internal tree node used only in this page to build a hierarchical folder view.
class _FolderNode {
  _FolderNode({
    required this.name,
    required this.path,
    this.folderId,
    this.invoiceCount = 0,
  });

  String name; // e.g. "CardShouker"
  String path; // e.g. "CardShouker/purchase/ebay"
  int? folderId; // real DB folder id (only on leaf nodes)
  int invoiceCount; // aggregated invoice count
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

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _invoiceService = InvoiceService(Supabase.instance.client);
    _loadData();
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
    final root =
        _FolderNode(name: '', path: '', folderId: null, invoiceCount: 0);

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
            invoiceCount: isLast ? (folderCounts[folder.id] ?? 0) : 0,
          );
          current.children.add(child);
        } else if (isLast) {
          // if node already existed as virtual parent, attach folderId and direct count
          child.folderId ??= folder.id;
          child.invoiceCount = folderCounts[folder.id] ?? child.invoiceCount;
        }

        current = child;
      }
    }

    // aggregate counts up the tree
    _computeAggregatedCounts(root);
    return root;
  }

  int _computeAggregatedCounts(_FolderNode node) {
    int sum = node.invoiceCount;
    for (final child in node.children) {
      sum += _computeAggregatedCounts(child);
    }
    node.invoiceCount = sum;
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

    // All invoices
    if (_selectedFolderId == null && _selectedFolderPrefix == null) {
      _invoices = List<Invoice>.from(_allInvoices);
      return;
    }

    _invoices = _allInvoices.where((inv) {
      final fid = inv.folderId;
      if (_selectedFolderId != null) {
        return fid == _selectedFolderId;
      }
      if (_selectedFolderPrefix != null) {
        if (fid == null) return false;
        final folderName = _folderNameById[fid] ?? '';
        return folderName.startsWith(_selectedFolderPrefix!);
      }
      return true;
    }).toList();
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
  // Invoice actions: view, move, attach/remove document, mark paid, delete
  // ---------------------------------------------------------------------------

  Future<void> _viewInvoicePdf(Invoice invoice) async {
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
    final lower = pathInBucket.toLowerCase();
    final isPdf = lower.endsWith('.pdf');

    try {
      if (kIsWeb) {
        // 🌐 WEB : URL signée + open
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

      // 📱/💻 Mobile & desktop : download bytes then preview
      final bytes =
          await client.storage.from('invoices').download(pathInBucket);

      if (isPdf) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
        );
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
          'org_${widget.orgId}/inv_${invoice.id}_$now\_$safeName';

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
    // Devise par défaut (tu pourras la remplacer par un setting org)
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
            content:
                Text('External document ${created.invoiceNumber} attached.')),
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

    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
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

    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  // ---------------------------------------------------------------------------
  // Create NEW sales invoice (grouped) from this page
  // ---------------------------------------------------------------------------

  Future<void> _onCreateSalesInvoiceFromManagement() async {
    // Ouvre le dialog de sélection d’items + infos facture
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
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(
            onPressed: _onCreateSalesInvoiceFromManagement,
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'New sales invoice',
          ),
          IconButton(
            onPressed: _onAttachExternalInvoice,
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Attach external invoice/document',
          ),
          IconButton(
            onPressed: _createFolderDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _buildFolderList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildInvoiceList()),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 80,
                      child: _buildFolderChips(),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildInvoiceList()),
                  ],
                ),
    );
  }

  // ----- LEFT PANE (desktop) : hierarchical folder tree -----

  Widget _buildFolderList() {
    final root = _folderRoot;
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor:
                _selectedFolderId == null && _selectedFolderPrefix == null
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                    : null,
            selected:
                _selectedFolderId == null && _selectedFolderPrefix == null,
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text(
              'All invoices',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${_allInvoices.length} documents'),
            onTap: _selectAll,
          ),
          const SizedBox(height: 8),
          const Text(
            'Folders',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Divider(),
          if (root != null)
            ...root.children.map((node) => _buildFolderNodeTile(node)),
        ],
      ),
    );
  }

  Widget _buildFolderCountChip(_FolderNode node) {
    if (node.invoiceCount <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        node.invoiceCount.toString(),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildFolderMenuButton(_FolderNode node) {
    if (!node.hasRealFolder) {
      // on ne propose pas de supprimer les "conteneurs" virtuels sans folderId
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
    final bool isSelectedPrefix =
        node.folderId == null && node.path == _selectedFolderPrefix;

    final bool isSelected = isSelectedLeaf || isSelectedPrefix;

    if (!node.hasChildren) {
      // leaf: real folder only
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        selected: isSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        leading: const Icon(Icons.folder),
        title: Text(node.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFolderCountChip(node),
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

    // node with children: behaves like container + optional real folder
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 8, right: 8),
      leading: const Icon(Icons.folder),
      title: Text(
        node.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.only(left: 16),
      initiallyExpanded: true,
      children: [
        if (node.folderId != null)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8, right: 8),
            selected: isSelectedLeaf,
            leading: const Icon(Icons.folder_open),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            title: const Text('This folder'),
            subtitle: Text(node.path),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFolderCountChip(node),
                const SizedBox(width: 4),
                _buildFolderMenuButton(node),
              ],
            ),
            onTap: () => _selectFolderById(node.folderId!),
          ),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 8, right: 8),
          selected: isSelectedPrefix,
          leading: const Icon(Icons.folder_special_outlined),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          title: const Text('All subfolders'),
          subtitle: Text(node.path),
          trailing: _buildFolderCountChip(node),
          onTap: () => _selectFolderByPrefix(node.path),
        ),
        ...node.children.map(
          (child) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _buildFolderNodeTile(child),
          ),
        ),
      ],
    );
  }

  // ----- TOP CHIPS (mobile) : flat list, simpler -----

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

  Widget _buildInvoiceList() {
    if (_invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: Colors.grey),
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

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentFilterLabel(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _invoices.length,
            itemBuilder: (context, index) {
              final invoice = _invoices[index];

              final numberSuffix = invoice.invoiceNumber.contains('-')
                  ? invoice.invoiceNumber.split('-').last
                  : invoice.invoiceNumber;

              final folderName = (invoice.folderId != null)
                  ? _folderNameById[invoice.folderId!] ?? ''
                  : '';

              final hasDoc = invoice.documentUrl != null;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                elevation: 1.5,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      numberSuffix,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildTypeChip(invoice),
                      const SizedBox(width: 4),
                      _buildStatusChip(invoice),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      if (invoice.type == InvoiceType.sale)
                        Text('Buyer: ${invoice.buyerName}')
                      else if (invoice.type == InvoiceType.purchase)
                        Text('Supplier: ${invoice.sellerName}')
                      else
                        Text('Counterparty: ${invoice.buyerName}'),
                      Text(
                        'Date: ${formatDate(invoice.issueDate)}'
                        ' • Total: ${formatMoney(invoice.totalInclTax, invoice.currency)}',
                      ),
                      if (folderName.isNotEmpty)
                        Text(
                          'Folder: $folderName',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'view') {
                        await _viewInvoicePdf(invoice);
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
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<String>>[];

                      items.add(
                        PopupMenuItem(
                          value: 'view',
                          child: Text(
                            hasDoc
                                ? 'View document'
                                : 'View document (none attached)',
                          ),
                        ),
                      );

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
                    },
                  ),
                  onTap: () => _viewInvoicePdf(invoice),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
