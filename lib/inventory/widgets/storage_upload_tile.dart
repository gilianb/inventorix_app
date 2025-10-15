import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/storage_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class StorageUploadTile extends StatefulWidget {
  const StorageUploadTile({
    super.key,
    required this.label,
    required this.bucket,
    required this.objectPrefix, // ex: 'items/${productId}' ou 'items'
    required this.initialUrl, // URL déjà en DB (peut être null)
    required this.onUrlChanged, // callback -> met à jour TextEditingController/DB
    this.acceptImagesOnly = false,
    this.acceptDocsOnly = false,
  });

  final String label;
  final String bucket;
  final String objectPrefix;
  final String? initialUrl;
  final ValueChanged<String?> onUrlChanged;
  final bool acceptImagesOnly;
  final bool acceptDocsOnly;

  @override
  State<StorageUploadTile> createState() => _StorageUploadTileState();
}

class _StorageUploadTileState extends State<StorageUploadTile> {
  final _sb = Supabase.instance.client;
  late final StorageHelper _storage = StorageHelper(_sb);

  String? _url; // URL publique/signée pour prévisualiser
// chemin dans le bucket (si on veut le conserver)

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    // Pas forcément possible de reconstituer objectKey depuis une URL complète;
    // si besoin, tu peux stocker la clé (objectKey) en plus dans ta DB.
  }

  bool get _isImage =>
      (_url ?? '').toLowerCase().contains(RegExp(r'\.(png|jpe?g|gif|webp)$'));

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: widget.acceptImagesOnly
          ? FileType.image
          : widget.acceptDocsOnly
              ? FileType.custom
              : FileType.any,
      allowedExtensions: widget.acceptDocsOnly ? ['pdf', 'doc', 'docx'] : null,
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;

    final name = f.name;
    // object path -> prefix/horodate-nom
    final objectPath =
        '${widget.objectPrefix}/${DateTime.now().millisecondsSinceEpoch}_$name';
    try {
      final key = await _storage.uploadBytes(
        bucket: widget.bucket,
        objectPath: objectPath,
        bytes: Uint8List.fromList(bytes),
      );
      final url = await _storage.getPublicOrSignedUrl(
          bucket: widget.bucket, objectPath: key);
      setState(() {
        _url = url;
      });
      widget.onUrlChanged(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload échoué: $e')));
    }
  }

  Future<void> _open() async {
    final u = _url;
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: InputDecoration(labelText: widget.label),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _pickAndUpload,
            icon: const Icon(Icons.upload),
            label: const Text('Uploader'),
          ),
          const SizedBox(width: 8),
          if (_url != null && _url!.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _open,
              icon: Icon(_isImage ? Icons.photo : Icons.description),
              label: Text(_isImage ? 'Voir photo' : 'Ouvrir document'),
            ),
          const Spacer(),
          if (_url != null && _url!.isNotEmpty)
            IconButton(
              tooltip: 'Effacer',
              onPressed: () {
                setState(() => _url = null);
                widget.onUrlChanged(null);
              },
              icon: Icon(Icons.clear, color: cs.error),
            ),
        ],
      ),
    );
  }
}
