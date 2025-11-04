// lib/org/organizations_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'organization_models.dart';

const kAccentA = Color(0xFF6C5CE7); // violet
const kAccentB = Color(0xFF00D1B2); // menthe
const kAccentC = Color(0xFFFFB545); // amber;
const kAccentG = Color(0xFF22C55E); // green

class OrganizationsPage extends StatefulWidget {
  const OrganizationsPage({super.key});

  @override
  State<OrganizationsPage> createState() => _OrganizationsPageState();
}

class _OrganizationsPageState extends State<OrganizationsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Organization> _orgs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw 'Utilisateur non connecté';

      // 1) Memberships directs (pas de vue récursive)
      final memRows = await _sb
          .from('organization_member')
          .select('org_id, role, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final memberships = (memRows as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (memberships.isEmpty) {
        _orgs = const [];
        return;
      }

      // 2) Orgs via inFilter
      final orgIds =
          memberships.map((m) => (m['org_id'] as String)).toSet().toList();

      final orgRows = await _sb
          .from('organization')
          .select('id, name, created_at')
          .inFilter('id', orgIds);

      final orgById = {
        for (final e in orgRows.map((x) => Map<String, dynamic>.from(x as Map)))
          (e['id'] as String): e
      };

      // 3) Assemblage
      final list = <Organization>[];
      for (final m in memberships) {
        final oid = m['org_id'] as String;
        final base = orgById[oid];
        if (base == null) continue;
        list.add(Organization(
          id: oid,
          name: (base['name'] ?? '').toString(),
          role: (m['role'] ?? '').toString(),
        ));
      }

      _orgs = list;
    } catch (e) {
      _snack('Erreur chargement: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _createOrgDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer une organisation'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nom'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw 'Utilisateur non connecté';

      final inserted = await _sb
          .from('organization')
          .insert({
            'name': name,
            'created_by': uid, // ⚠️ RLS: doit être = auth.uid()
          })
          .select('id,name')
          .single();

      _snack('Organisation créée.');
      await _load();

      final orgId = inserted['id'] as String;
      await OrgPrefs.saveSelectedOrgId(orgId);
      if (!mounted) return;
      Navigator.of(context).pop<String>(orgId);
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  Future<void> _selectOrg(Organization org) async {
    await OrgPrefs.saveSelectedOrgId(org.id);
    if (!mounted) return;
    Navigator.of(context).pop<String>(org.id);
  }

  Future<void> _openManageMembers(Organization org) async {
    // Owner only (UI). Doubler avec RLS côté DB.
    if (org.role.toLowerCase() != 'owner') {
      _snack('Seul le owner peut gérer les membres.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ManageMembersSheet(orgId: org.id, orgName: org.name),
    );
  }

  int _columnsForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 3;
    if (w >= 560) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes organisations')),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _createOrgDialog,
              backgroundColor: kAccentA,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business),
              label: const Text('Créer'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  final cols = _columnsForWidth(cons.maxWidth);
                  final items = [
                    const _CreateOrgCard(),
                    ..._orgs.map((o) => _OrgCard(
                          org: o,
                          onEnter: () => _selectOrg(o),
                          onManageMembers: o.role.toLowerCase() == 'owner'
                              ? () => _openManageMembers(o)
                              : null,
                        )),
                  ];

                  if (_orgs.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
                      children: [
                        _PageIntro(onCreate: _createOrgDialog),
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 1,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.4,
                          ),
                          itemBuilder: (ctx, i) => InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _createOrgDialog,
                            child: const _CreateOrgCard(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Center(
                          child: Text(
                            'Vous n’êtes membre d’aucune organisation.\nCréez-en une pour commencer.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 120),
                      ],
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      _PageIntro(onCreate: _createOrgDialog),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.4,
                        ),
                        itemBuilder: (ctx, i) {
                          final w = items[i];
                          if (w is _CreateOrgCard) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _createOrgDialog,
                              child: w,
                            );
                          } else if (w is _OrgCard) {
                            return w;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/* ====== Manage Members (Bottom Sheet) ====== */

class _ManageMembersSheet extends StatefulWidget {
  const _ManageMembersSheet({required this.orgId, required this.orgName});
  final String orgId;
  final String orgName;

  @override
  State<_ManageMembersSheet> createState() => _ManageMembersSheetState();
}

class _ManageMembersSheetState extends State<_ManageMembersSheet> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) membres (pas de FK implicite)
      final rows = await _sb
          .from('organization_member')
          .select('user_id, role, created_at')
          .eq('org_id', widget.orgId)
          .order('created_at', ascending: true);

      final members = (rows as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) profils via inFilter
      final ids = members
          .map((m) => (m['user_id'] as String?)?.trim())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profById = {};
      if (ids.isNotEmpty) {
        final profRows = await _sb
            .from('profile')
            .select('id, display_name, avatar_url')
            .inFilter('id', ids);

        profById = {
          for (final e
              in profRows.map((x) => Map<String, dynamic>.from(x as Map)))
            (e['id'] as String): e
        };
      }

      for (final m in members) {
        final uid = m['user_id'] as String?;
        if (uid != null && profById.containsKey(uid)) {
          m['profile'] = profById[uid];
        }
      }

      _members = members;
    } catch (e) {
      _snack('Erreur chargement membres: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addMemberDialog() async {
    final res = await showDialog<_AddResult>(
      context: context,
      builder: (ctx) => const _AddMemberDialog(),
    );
    if (res == null) return;

    try {
      // 1) Résoudre l’ID utilisateur (UUID direct ou email via RPC)
      final uid = await _resolveUserId(res.identifier);
      if (uid == null) {
        _snack(
            'Utilisateur introuvable. Donne un User ID (UUID) ou un email existant (RPC get_user_id_by_email).');
        return;
      }

      // 2) Upsert (RLS côté DB pour réserver au owner)
      await _sb
          .from('organization_member')
          .upsert({
            'org_id': widget.orgId,
            'user_id': uid,
            'role': res.role,
          })
          .select('org_id')
          .single();

      _snack('Membre ajouté/mis à jour.');
      _load();
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  Future<void> _removeMember(String userId) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Retirer ce membre ?'),
            content: const Text('Il n’aura plus accès à l’organisation.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Retirer')),
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
      _snack('Membre retiré.');
      _load();
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Erreur: $e');
    }
  }

  Future<String?> _resolveUserId(String input) async {
    final s = input.trim();
    // UUID direct ?
    final uuidRe = RegExp(r'^[0-9a-fA-F-]{36}$');
    if (uuidRe.hasMatch(s)) return s;

    // Email -> RPC (à créer côté DB)
    try {
      final row = await _sb
          .rpc('get_user_id_by_email', params: {'p_email': s}).maybeSingle();
      final id = (row?['user_id'] as String?);
      return (id != null && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
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
            // Header
            Row(
              children: [
                const Icon(Icons.group),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Membres — ${widget.orgName}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),

            Expanded(
              child: _members.isEmpty
                  ? const Center(child: Text('Aucun membre.'))
                  : ListView.separated(
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = _members[i];
                        final prof = Map<String, dynamic>.from(
                            (m['profile'] ?? const {}));
                        final display =
                            (prof['display_name'] ?? m['user_id']).toString();
                        final role = (m['role'] ?? '').toString();

                        return ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(display),
                          subtitle: Text(m['user_id'].toString()),
                          trailing: Chip(
                            label: Text(role.toUpperCase()),
                            backgroundColor: kAccentB.withOpacity(.12),
                            side: BorderSide(color: kAccentB.withOpacity(.20)),
                          ),
                          onLongPress: () =>
                              _removeMember(m['user_id'] as String),
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
                  icon: const Icon(Icons.person_add),
                  label: const Text('Ajouter un membre'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ====== Dialogue: Ajouter un membre ====== */

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _idOrEmailCtrl = TextEditingController();
  String _role = 'member'; // défaut

  @override
  void dispose() {
    _idOrEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un membre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _idOrEmailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email ou User ID (UUID)',
              hintText:
                  'ex: user@example.com ou 123e4567-e89b-12d3-a456-426614174000',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _role,
            decoration: const InputDecoration(labelText: 'Rôle'),
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
      actions: [
        TextButton(
            onPressed: () => Navigator.pop<_AddResult>(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final id = _idOrEmailCtrl.text.trim();
            if (id.isEmpty) return;
            Navigator.pop<_AddResult>(
                context, _AddResult(identifier: id, role: _role));
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _AddResult {
  final String identifier; // email OU uuid
  final String role;
  const _AddResult({required this.identifier, required this.role});
}

/* ====== Jolis widgets existants ====== */

class _PageIntro extends StatelessWidget {
  const _PageIntro({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kAccentA.withOpacity(.06),
              kAccentB.withOpacity(.05),
            ],
          ),
          border: Border.all(color: kAccentA.withOpacity(.12), width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: kAccentA,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sélectionnez votre organisation ou créez-en une nouvelle.',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateOrgCard extends StatelessWidget {
  const _CreateOrgCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shadowColor: kAccentA.withOpacity(.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccentA.withOpacity(.10), kAccentB.withOpacity(.06)],
          ),
          border: Border.all(color: kAccentA.withOpacity(.14), width: 0.8),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TileHeader(
              leading: _Avatar(seed: 'new', color: kAccentA),
              roleChip: Chip(
                label: const Text('Créer'),
                backgroundColor: kAccentB.withOpacity(.12),
                side: BorderSide.none,
              ),
            ),
            const Spacer(),
            Text(
              'Créer une organisation',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Invitez votre équipe, gérez vos stocks et ventes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add, size: 18),
                SizedBox(width: 6),
                Text('Nouvelle organisation'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({
    required this.org,
    this.onEnter,
    this.onManageMembers,
  });
  final Organization org;
  final VoidCallback? onEnter;
  final VoidCallback? onManageMembers;

  String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty) return 'O';
    if (p.length == 1) {
      return p.first.characters.take(2).toString().toUpperCase();
    }
    return (p.first.characters.take(1).toString() +
            p.last.characters.take(1).toString())
        .toUpperCase();
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
      case 'admin':
        return kAccentG;
      case 'manager':
        return kAccentC;
      default:
        return kAccentB;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(org.role);
    final isOwner = org.role.toLowerCase() == 'owner';

    return Card(
      elevation: 1,
      shadowColor: kAccentA.withOpacity(.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kAccentA.withOpacity(.04), kAccentB.withOpacity(.03)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kAccentA.withOpacity(.10), width: .8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  _Avatar(seed: org.id, label: _initials(org.name)),
                  const Spacer(),
                  if (isOwner && onManageMembers != null)
                    Tooltip(
                      message: 'Gérer les membres',
                      child: IconButton(
                        onPressed: onManageMembers,
                        icon: const Icon(Icons.group_add),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Chip(
                    label: Text(org.role.toUpperCase()),
                    labelStyle: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    backgroundColor: roleColor.withOpacity(.12),
                    side: BorderSide(color: roleColor.withOpacity(.20)),
                  ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  org.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onEnter,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.chevron_right, size: 18),
                      SizedBox(width: 6),
                      Text('Entrer'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileHeader extends StatelessWidget {
  const _TileHeader({required this.leading, required this.roleChip});
  final Widget leading;
  final Widget roleChip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const Spacer(),
        roleChip,
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.seed, this.label, this.color});
  final String seed;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // petit gradient stable basé sur le hash du seed
    final hash = seed.hashCode;
    final c1 = HSLColor.fromAHSL(
      1.0,
      (hash % 360).toDouble(),
      0.55,
      0.62,
    ).toColor();
    final c2 = HSLColor.fromAHSL(
      1.0,
      ((hash + 60) % 360).toDouble(),
      0.55,
      0.52,
    ).toColor();

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color ?? c1, (color ?? c2).withOpacity(.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (color ?? c1).withOpacity(.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        (label ?? '').isEmpty ? '★' : label!,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
