import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';

import '../invoiceService.dart';
import '../invoice_format.dart';
import '../models/enums.dart';
import '../models/invoice.dart';
import '../models/invoiceFolder.dart';

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
  List<Invoice> _invoices = [];
  int? _selectedFolderId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _invoiceService = InvoiceService(Supabase.instance.client);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final folders = await _invoiceService.listFolders(widget.orgId);

      int? folderId;
      if (folders.isNotEmpty) {
        folderId = folders.first.id;
      }

      final invoices = await _invoiceService.listInvoices(
        orgId: widget.orgId,
        folderId: folderId,
      );

      setState(() {
        _folders = folders;
        _selectedFolderId = folderId;
        _invoices = invoices;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _onFolderSelected(int? folderId) async {
    setState(() {
      _selectedFolderId = folderId;
      _loading = true;
    });

    final invoices = await _invoiceService.listInvoices(
        orgId: widget.orgId, folderId: folderId);

    setState(() {
      _invoices = invoices;
      _loading = false;
    });
  }

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
      label: Text(
        label,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _viewInvoicePdf(Invoice invoice) async {
    if (invoice.documentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF generated yet for this invoice.')),
      );
      return;
    }

    final client = Supabase.instance.client;

    // document_url stored as: 'invoices/<org_id>/<year>/<invoice_number>/invoice.pdf'
    final fullPath = invoice.documentUrl!;
    final pathInBucket = fullPath.replaceFirst('invoices/', '');

    final bytes = await client.storage.from('invoices').download(pathInBucket);

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
    );
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete invoice'),
        content: Text(
          'Are you sure you want to delete invoice ${invoice.invoiceNumber}?\n'
          'This will delete the invoice, its lines and the PDF file.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invoice ${invoice.invoiceNumber} deleted.'),
        ),
      );
      await _onFolderSelected(_selectedFolderId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while deleting invoice: $e')),
      );
    }
  }

  Future<void> _markInvoicePaid(Invoice invoice) async {
    try {
      await _invoiceService.markInvoicePaid(invoice.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invoice ${invoice.invoiceNumber} marked as paid.'),
        ),
      );

      // reload list for current folder
      await _onFolderSelected(_selectedFolderId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while marking invoice as paid: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
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
                      width: 260,
                      child: _buildFolderList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildInvoiceList()),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 72,
                      child: _buildFolderChips(),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildInvoiceList()),
                  ],
                ),
    );
  }

  Widget _buildFolderList() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ListTile(
          selected: _selectedFolderId == null,
          leading: const Icon(Icons.folder_open),
          title: const Text('All invoices'),
          onTap: () => _onFolderSelected(null),
        ),
        const Divider(),
        ..._folders.map((folder) {
          final selected = _selectedFolderId == folder.id;
          return ListTile(
            selected: selected,
            leading: const Icon(Icons.folder),
            title: Text(folder.name),
            trailing: folder.invoiceCount != null
                ? CircleAvatar(
                    radius: 12,
                    child: Text(
                      folder.invoiceCount.toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  )
                : null,
            onTap: () => _onFolderSelected(folder.id),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildFolderChips() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: _selectedFolderId == null,
          onSelected: (_) => _onFolderSelected(null),
        ),
        const SizedBox(width: 8),
        ..._folders.map((folder) {
          final selected = _selectedFolderId == folder.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(folder.name),
              selected: selected,
              onSelected: (_) => _onFolderSelected(folder.id),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildInvoiceList() {
    if (_invoices.isEmpty) {
      return const Center(
        child: Text('No invoices yet in this folder.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final invoice = _invoices[index];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                invoice.invoiceNumber.split('-').last,
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
                _buildStatusChip(invoice),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Buyer: ${invoice.buyerName}'),
                Text(
                  'Date: ${formatDate(invoice.issueDate)}'
                  ' • Total: ${formatMoney(invoice.totalInclTax, invoice.currency)}',
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'view') {
                  await _viewInvoicePdf(invoice);
                } else if (value == 'paid') {
                  await _markInvoicePaid(invoice);
                } else if (value == 'delete') {
                  await _deleteInvoice(invoice);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'view',
                  child: Text('View PDF'),
                ),
                PopupMenuItem(
                  value: 'paid',
                  child: Text('Mark as paid'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete invoice'),
                ),
              ],
            ),
            onTap: () => _viewInvoicePdf(invoice),
          ),
        );
      },
    );
  }
}
