import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/storage_helper.dart';
import 'package:url_launcher/url_launcher.dart';

//icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

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
    this.onError, // <-- nouveau
  });

  final String label;
  final String bucket;
  final String objectPrefix;
  final String? initialUrl;
  final ValueChanged<String?> onUrlChanged;
  final bool acceptImagesOnly;
  final bool acceptDocsOnly;
  final ValueChanged<String>? onError; // <-- nouveau

  @override
  State<StorageUploadTile> createState() => _StorageUploadTileState();
}

class _StorageUploadTileState extends State<StorageUploadTile> {
  final _sb = Supabase.instance.client;
  late final StorageHelper _storage = StorageHelper(_sb);

  String? _url; // URL publique pour prévisualiser

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  bool get _isImage {
    final u = _url ?? '';
    if (u.isEmpty) return false;
    try {
      final path = Uri.parse(u).path.toLowerCase();
      return path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.gif') ||
          path.endsWith('.webp');
    } catch (_) {
      final lu = u.toLowerCase();
      return RegExp(r'\.(png|jpe?g|gif|webp)(\?.*)?$').hasMatch(lu);
    }
  }

  // Règle de nommage simple: lettres/chiffres/._- uniquement
  bool _isSafeFileName(String name) =>
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name);

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

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

    final originalName = f.name.trim();

    // Valide le nom AVANT upload
    if (!_isSafeFileName(originalName)) {
      widget.onError?.call(
        "Le nom de fichier « $originalName » contient des espaces ou des caractères spéciaux. "
        "Utilise uniquement lettres, chiffres, tirets (-), underscores (_) ou points (.).",
      );
      return;
    }

    final safeName = _sanitize(originalName);
    final objectPath =
        '${widget.objectPrefix}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    try {
      // 1) Upload brut (renvoie le chemin objet stocké)
      final key = await _storage.uploadBytes(
        bucket: widget.bucket,
        objectPath: objectPath,
        bytes: Uint8List.fromList(bytes),
      );

      // 2) URL **publique** (bucket doit être public)
      final publicUrl = _sb.storage.from(widget.bucket).getPublicUrl(key);

      if (!mounted) return;
      setState(() => _url = publicUrl);
      widget.onUrlChanged(publicUrl);
    } on StorageException catch (e) {
      // Erreurs storage précises -> remonte au parent via onError si fourni
      final msg = 'Upload échoué: ${e.message} (code ${e.statusCode ?? '-'})';
      if (widget.onError != null) {
        widget.onError!(msg);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      final msg = 'Upload échoué: $e';
      if (widget.onError != null) {
        widget.onError!(msg);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
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
            icon: const Iconify(Mdi.upload),
            label: const Text('Uploader'),
          ),
          const SizedBox(width: 8),
          if (_url != null && _url!.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _open,
              icon: Iconify(_isImage ? Mdi.photo_camera : Mdi.file_document),
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
              icon: Iconify(Mdi.close, color: cs.error),
            ),
        ],
      ),
    );
  }
}
