import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageHelper {
  StorageHelper(this.sb);
  final SupabaseClient sb;

  /// Upload des bytes vers un bucket. Retourne le chemin (key) stocké.
  Future<String> uploadBytes({
    required String bucket,
    required String objectPath, // ex: photos/ITEM-123/filename.jpg
    required Uint8List bytes,
    String? contentType, // ex: image/jpeg, application/pdf...
    bool upsert = true,
  }) async {
    final opts = FileOptions(
      cacheControl: '3600',
      contentType: contentType ?? lookupMimeType(objectPath),
      upsert: upsert,
    );
    await sb.storage
        .from(bucket)
        .uploadBinary(objectPath, bytes, fileOptions: opts);
    return objectPath; // clé dans le bucket
  }

  /// Retourne une URL publique si le bucket est public, sinon une URL signée.
  Future<String> getPublicOrSignedUrl({
    required String bucket,
    required String objectPath,
    Duration signedDuration = const Duration(hours: 24),
  }) async {
    // Essaie getPublicUrl (fonctionne si bucket public)
    final pub = sb.storage.from(bucket).getPublicUrl(objectPath);
    if (pub.isNotEmpty && !pub.contains('null')) return pub;

    // Sinon URL signée
    final signed = await sb.storage
        .from(bucket)
        .createSignedUrl(objectPath, signedDuration.inSeconds);
    return signed;
  }

  /// 1) Nettoie un nom de fichier pour Storage:
  ///    - minuscule
  ///    - remplace tout ce qui n'est pas [a-z0-9._-] par "_"
  ///    - compresse les "__" et coupe les "_" en début/fin
  static String sanitizeFileName(String name) {
    var n = name.toLowerCase();
    n = n.replaceAll(RegExp(r'[^\w\.\-]'), '_'); // accents, espaces, (), etc.
    n = n.replaceAll(RegExp(r'_+'), '_');
    n = n.replaceAll(RegExp(r'^_+|_+$'), '');
    return n.isEmpty ? 'file' : n;
  }

  /// 2) Construit un chemin sûr (SANS "/" en tête) du style:
  // ignore: unintended_html_in_doc_comment
  ///    items/<productId>/<timestamp>_<sanitizedName>
  static String buildSafeObjectPath({
    required int productId,
    required String originalName,
    String prefix = 'items',
  }) {
    final safe = sanitizeFileName(originalName);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$prefix/$productId/${ts}_$safe';
  }
}
