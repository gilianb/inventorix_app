// lib/org/manage_members_sheet.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);
const kAccentC = Color(0xFFFFB545);
const kAccentG = Color(0xFF22C55E);

class ManageMembersSheet extends StatefulWidget {
  const ManageMembersSheet({
    super.key,
    required this.orgId,
    required this.orgName,
  });
  final String orgId;
  final String orgName;

  @override
  State<ManageMembersSheet> createState() => _ManageMembersSheetState();
}

class _ManageMembersSheetState extends State<ManageMembersSheet> {
  final _sb = Supabase.instance.client;
  bool _loading = true;

  /// _members: chaque item = { user_id, role, created_at, email?, profile? }
  List<Map<String, dynamic>> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) membres bruts
      final rows = await _sb
          .from('organization_member')
          .select('user_id, role, created_at')
          .eq('org_id', widget.orgId)
          .order('created_at', ascending: true);

      final members = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) emails via RPC
      final ids = members
          .map((m) => (m['user_id'] as String?)?.trim())
          .whereType<String>()
          .toList();

      Map<String, String> emailById = {};
      if (ids.isNotEmpty) {
        final rpc = await _sb.rpc('get_users_by_ids', params: {'p_ids': ids});
        final list = (rpc as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final r in list) {
          emailById[(r['id'] as String)] = (r['email'] ?? '').toString();
        }
      }

      // 3) optionnel: profils (si tu veux afficher display_name)
      Map<String, Map<String, dynamic>> profById = {};
      if (ids.isNotEmpty) {
        final profRows = await _sb
            .from('profile')
            .select('id, display_name, avatar_url')
            .inFilter('id', ids);
        for (final p in profRows) {
          final mp = Map<String, dynamic>.from(p as Map);
          profById[(mp['id'] as String)] = mp;
        }
      }

      for (final m in members) {
        final uid = m['user_id'] as String;
        m['email'] = emailById[uid] ?? '';
        if (profById.containsKey(uid)) m['profile'] = profById[uid];
      }

      setState(() => _members = members);
    } catch (e) {
      _snack('Error loading members: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMemberDialog() async {
    final res = await showDialog<_AddResult>(
      context: context,
      builder: (ctx) => _AddMemberDialog(orgId: widget.orgId),
    );
    if (res == null) return;

    try {
      // Résoudre user_id (email -> RPC, sinon UUID direct accepté)
      final uid = await _resolveUserId(res.identifier);
      if (uid == null) {
        _snack('User not found (email/UUID).');
        return;
      }

      await _sb
          .from('organization_member')
          .upsert({
            'org_id': widget.orgId,
            'user_id': uid,
            'role': res.role,
          })
          .select('org_id')
          .single();

      _snack('Member added/updated.');
      _load();
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<String?> _resolveUserId(String input) async {
    final s = input.trim();
    final uuidRe = RegExp(r'^[0-9a-fA-F-]{36}$');
    if (uuidRe.hasMatch(s)) return s;
    try {
      final row = await _sb
          .rpc('get_user_id_by_email', params: {'p_email': s}).maybeSingle();
      final id = (row?['user_id'] as String?);
      return (id != null && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeMember(String userId) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove this member?'),
            content: const Text(
                'They will no longer have access to the organization.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      await _sb
          .from('organization_member')
          .delete()
          .eq('org_id', widget.orgId)
          .eq('user_id', userId);
      _snack('Member removed.');
      _load();
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      await _sb
          .from('organization_member')
          .update({'role': newRole})
          .eq('org_id', widget.orgId)
          .eq('user_id', userId);
      _snack('RRole updated.');
      _load();
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.group),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Members — ${widget.orgName}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Iconify(Mdi.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: _members.isEmpty
                  ? const Center(child: Text('No members.'))
                  : ListView.separated(
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = _members[i];
                        final uid = m['user_id'] as String;
                        final email = (m['email'] ?? '').toString();
                        final prof = Map<String, dynamic>.from(
                            (m['profile'] ?? const {}));
                        final display = (prof['display_name'] ?? '').toString();
                        final role = (m['role'] ?? 'member').toString();

                        return ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(
                            email.isEmpty ? uid : email,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            display.isNotEmpty ? '$display · $uid' : uid,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Rôle modifiable in-place
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: role,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'owner', child: Text('owner')),
                                    DropdownMenuItem(
                                        value: 'admin', child: Text('admin')),
                                    DropdownMenuItem(
                                        value: 'member', child: Text('member')),
                                    DropdownMenuItem(
                                        value: 'viewer', child: Text('viewer')),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    _changeRole(uid, v);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _removeMember(uid),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  onPressed: _addMemberDialog,
                  icon: const Iconify(Mdi.account_plus),
                  label: const Text('Add member'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ====== Dialogue: Ajouter un membre (auto-complétion en overlay via RawAutocomplete) ====== */

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.orgId});
  final String orgId;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _emailOrUuidCtrl = TextEditingController();
  final _fieldFocus = FocusNode();
  Timer? _debounce;

  String _role = 'member';
  List<_Suggestion> _suggestions = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _emailOrUuidCtrl.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res =
          await Supabase.instance.client.rpc('search_users_by_email', params: {
        'p_org_id': widget.orgId,
        'p_q': q,
        'p_limit': 12,
      });
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => _Suggestion(
                id: m['id'] as String,
                email: (m['email'] ?? '').toString(),
              ))
          .toList();
      setState(() => _suggestions = list);
    } catch (_) {
      setState(() => _suggestions = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // largeur bornée : min(520, largeur écran - 64)
    final double dialogWidth =
        math.min(MediaQuery.of(context).size.width - 64, 520.0);
    const double kMaxSuggestHeight = 220;

    return AlertDialog(
      title: const Text('Add member to organization'),
      content: SizedBox(
        width: dialogWidth, // <--- largeur FINIE (pas d'infini)
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RawAutocomplete = suggestions en overlay (pas de ListView dans le content)
            RawAutocomplete<_Suggestion>(
              textEditingController: _emailOrUuidCtrl,
              focusNode: _fieldFocus,
              optionsBuilder: (TextEditingValue tev) {
                // debounce pour RPC
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 220), () {
                  _fetchSuggestions(tev.text);
                });
                return _suggestions; // état courant (synchrone)
              },
              displayStringForOption: (s) => s.email,
              fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Email or User ID (UUID)',
                    hintText: 'ex: user@example.com',
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                  autofocus: true,
                  onSubmitted: (_) => onFieldSubmitted(),
                );
              },
              optionsViewBuilder: (ctx, onSelected, options) {
                final opts = options.toList(growable: false);
                if (opts.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: kMaxSuggestHeight,
                        minWidth: dialogWidth,
                        maxWidth: dialogWidth,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: opts.length,
                        itemBuilder: (ctx, i) {
                          final s = opts[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.alternate_email),
                            title: Text(s.email),
                            subtitle: Text(s.id),
                            onTap: () => onSelected(s),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: (s) {
                _emailOrUuidCtrl.text = s.email;
                setState(() => _suggestions = const []);
              },
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'owner', child: Text('owner')),
                DropdownMenuItem(value: 'admin', child: Text('admin')),
                DropdownMenuItem(value: 'member', child: Text('member')),
                DropdownMenuItem(value: 'viewer', child: Text('viewer')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'member'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<_AddResult>(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final id = _emailOrUuidCtrl.text.trim();
            if (id.isEmpty) return;
            Navigator.pop<_AddResult>(
              context,
              _AddResult(identifier: id, role: _role),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _Suggestion {
  final String id;
  final String email;
  const _Suggestion({required this.id, required this.email});
}

class _AddResult {
  final String identifier;
  final String role;
  const _AddResult({required this.identifier, required this.role});
}
