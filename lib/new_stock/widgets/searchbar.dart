// ignore_for_file: use_build_context_synchronously, constant_identifier_names
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
/*Ton CatalogPicker : recherche/sélection d’une carte du catalogue 
(blueprint), renvoie l’item choisi et son affichage complet.*/

const String EXT_SUPABASE_URL = 'https://pejsdroimtdxrnyhtvlx.supabase.co';
const String EXT_SUPABASE_ANON_KEY =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBlanNkcm9pbXRkeHJueWh0dmx4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0OTU4NjkwMywiZXhwIjoyMDY1MTYyOTAzfQ.Mavg3-H8YXz11tY5sNReuTwtB47Yg7pFmbD7IAjBPtU';

final SupabaseClient extSb =
    SupabaseClient(EXT_SUPABASE_URL, EXT_SUPABASE_ANON_KEY);

// Mapping optionnel ext->local (non utilisé ici car on lit external_game_id côté local)
const Map<int, int> externalToLocalGameId = {};

Future<int?> loadExternalGameId(int? localId, SupabaseClient sbLocal) async {
  if (localId == null) return null;
  final row = await sbLocal
      .from('games')
      .select('external_game_id')
      .eq('id', localId)
      .maybeSingle();
  final extId = (row?['external_game_id'] as int?);
  return extId ?? localId;
}

// ===== Images
const String kStorageBucket = 'catalog';

Future<String?> resolveStorageUrl(String? storagePath) async {
  if (storagePath == null) return null;
  String s = storagePath.trim();
  if (s.isEmpty) return null;

  // Si c’est déjà une URL http(s), on renvoie tel quel
  if (s.startsWith('http://') || s.startsWith('https://')) return s;

  // Autoriser la forme "catalog/..."
  if (s.startsWith('$kStorageBucket/')) {
    s = s.substring(kStorageBucket.length + 1);
  }
  final path = s;

  // 1) Essayer l’URL publique (préférée)
  try {
    final pub = extSb.storage.from(kStorageBucket).getPublicUrl(path);
    if (pub.isNotEmpty) return pub;
  } catch (_) {}

  // 2) En secours : URL signée courte (si bucket non public)
  try {
    final signed =
        await extSb.storage.from(kStorageBucket).createSignedUrl(path, 3600);
    if (signed.isNotEmpty) return signed;
  } catch (_) {}

  return null;
}

// ===== Texte
String buildSubtitle(Map<String, dynamic> r) {
  final parts = <String>[];
  final exName = (r['expansion_name'] as String?) ?? '';
  final exCode = (r['expansion_code'] as String?) ?? '';
  final exVersion = (r['version'] as String?) ?? '';
  final no = (r['collector_number'] as String?) ?? '';
  final rarity = (r['rarity_text'] as String?) ?? '';
  if (exName.isNotEmpty && exCode.isNotEmpty) {
    parts.add('$exName ($exCode)');
  } else if (exName.isNotEmpty) {
    parts.add(exName);
  } else if (exCode.isNotEmpty) {
    parts.add(exCode);
  }
  if (exVersion.isNotEmpty) {
    parts.add(exVersion);
  }
  if (no.isNotEmpty) parts.add('No. $no');
  if (rarity.isNotEmpty) parts.add('Ver. $rarity');
  return parts.join(' — ');
}

String buildFullDisplay(Map<String, dynamic> r) {
  final name = (r['name'] as String?) ?? '';
  final details = buildSubtitle(r);
  if (details.isEmpty) return name;
  if (name.isEmpty) return details;
  return '$name — $details';
}

class CatalogPicker extends StatefulWidget {
  const CatalogPicker({
    super.key,
    required this.onSelected,
    required this.selectedGameId,
    this.onTextChanged,
    this.minChars = 2,
    this.limit = 80,
    this.labelText = 'Nom du produit *',
  });

  final void Function(Map<String, dynamic> blueprintResolved) onSelected;
  final int? selectedGameId;
  final void Function(String value)? onTextChanged;
  final int minChars;
  final int limit;
  final String labelText;

  @override
  State<CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<CatalogPicker> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();

  bool _loading = false;
  List<Map<String, dynamic>> _results = [];
  OverlayEntry? _overlay;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      widget.onTextChanged?.call(_q.text);
      _onChanged();
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _results.isNotEmpty) {
        _showOverlay();
      }
      // ne pas fermer ici : on laisse onTap/onClear gérer la fermeture
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _search(_q.text.trim());
    });
  }

  Future<void> _search(String q) async {
    if (q.length < widget.minChars) {
      setState(() => _results = []);
      _overlay?.markNeedsBuild();
      _removeOverlay();
      return;
    }

    final extGameId = await loadExternalGameId(
        widget.selectedGameId, Supabase.instance.client);
    if (extGameId == null) {
      setState(() => _results = []);
      _overlay?.markNeedsBuild();
      _removeOverlay();
      return;
    }

    setState(() => _loading = true);
    try {
      final rpc = await extSb.rpc('search_blueprints_ranked', params: {
        'p_game_id': extGameId,
        'p_q': q,
        'p_limit': widget.limit * 2,
      });

      final raw = (rpc as List?)
              ?.map<Map<String, dynamic>>(
                  (e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      final resolved = await Future.wait(raw.map((r) async {
        final storage = (r['image_storage'] as String?)?.trim();
        final img = await resolveStorageUrl(storage);
        return {
          ...r,
          'image_url': img ?? '',
          'subtitle_text': buildSubtitle(r),
          'display_text': buildFullDisplay(r),
        };
      }));

      setState(() => _results = resolved.take(widget.limit).toList());
      _overlay?.markNeedsBuild();

      if (_focus.hasFocus && _results.isNotEmpty) {
        _showOverlay();
      } else if (_results.isEmpty) {
        _removeOverlay();
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Catalogue (RPC): ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur RPC: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOverlay({bool forceRecreate = false}) {
    if (forceRecreate && _overlay != null) _removeOverlay();
    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }
    _overlay = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        return Positioned.fill(
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: const Offset(0, 56),
            child: Material(
              elevation: 8,
              color: theme.cardColor,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: _results.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (ctx, i) {
                          final r = _results[i];
                          final imageUrl = (r['image_url'] as String?) ?? '';
                          final title =
                              (r['display_text'] as String?) ?? r['name'] ?? '';
                          final subtitle =
                              (r['subtitle_text'] as String?) ?? '';

                          return ListTile(
                            leading: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(width: 48, height: 48),
                                  )
                                : const SizedBox(width: 48, height: 48),
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            // ... à l'intérieur de ListView.separated -> itemBuilder -> return ListTile(
                            onTap: () async {
                              final resolved = Map<String, dynamic>.from(r);

                              // Compléter avec toutes les colonnes du blueprint
                              try {
                                final full =
                                    await extSb.from('blueprints').select('''
      id, game_id, expansion_id, category_id,
      name, version, kind, 
      image_url, image, back_image_url, back_image,
      fixed_properties, editable_properties, data,
      scryfall_id, tcg_player_id, card_market_ids,
      collector_number, number_sort, rarity_text,
      expansion_code, expansion_name,
      image_show, image_storage,
      name_norm, version_norm, collector_number_norm,
      rarity_text_norm, expansion_code_norm, expansion_name_norm
    ''').eq('id', r['id']).single();

                                for (final e in (full as Map).entries) {
                                  if (e.key == 'image_url') continue;
                                  resolved[e.key] = e.value;
                                }
                                if ((resolved['image_url'] as String?) ==
                                        null ||
                                    (resolved['image_url'] as String?)!
                                        .isEmpty) {
                                  final storage =
                                      (resolved['image_storage'] as String?)
                                          ?.trim();
                                  final img = await resolveStorageUrl(storage);
                                  if (img != null) resolved['image_url'] = img;
                                }
                              } catch (_) {}

                              // ⚠️ IMPORTANT : d'abord notifier la sélection...
                              widget.onSelected(resolved);

                              // ...puis seulement mettre le texte dans le champ
                              final display =
                                  (resolved['display_text'] as String?) ??
                                      buildFullDisplay(resolved);
                              _q.text = display;
                              _q.selection = TextSelection.collapsed(
                                  offset: _q.text.length);

                              _removeOverlay();
                              FocusScope.of(context).unfocus();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Sélectionné: ${resolved['name'] ?? 'Item'}')),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: TextFormField(
        controller: _q,
        focusNode: _focus,
        decoration: InputDecoration(
          labelText: widget.labelText,
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (_q.text.length >= widget.minChars
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _q.clear();
                        setState(() => _results = []);
                        _overlay?.markNeedsBuild();
                        _removeOverlay();
                      },
                    )
                  : null),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
        onFieldSubmitted: (_) {
          // Entrée = on valide le texte libre, on ferme la liste
          _removeOverlay();
          FocusScope.of(context).unfocus();
          // Pas de _search ici : on n’impose pas la sélection catalogue
        },
      ),
    );
  }
}
