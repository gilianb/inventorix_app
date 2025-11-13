// lib/org/organizations_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'organization_models.dart';

// icons
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';

// >>> NEW: import du widget externalisé
import 'manage_members_sheet.dart';

const kAccentA = Color(0xFF6C5CE7); // violet
const kAccentB = Color(0xFF00D1B2); // menthe
const kAccentC = Color(0xFFFFB545); // amber
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
      if (uid == null) throw 'User not logged in';

      // 1) Direct memberships (no recursive view)
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
      _snack('Error loading: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ======== BOUTON Login/Logout (même logique que main_inventory) ========
  Future<void> _onTapAuthButton() async {
    final session = _sb.auth.currentSession;
    if (session != null) {
      try {
        await _sb.auth.signOut();
        if (!mounted) return;
        _snack('Logout successful.');
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
      } on AuthException catch (e) {
        _snack('Error logging out: ${e.message}');
      } catch (e) {
        _snack('Error logging out: $e');
      }
    } else {
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
    }
  }

  Future<void> _createOrgDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create an organization'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw 'User not logged in';

      final inserted = await _sb
          .from('organization')
          .insert({
            'name': name,
            'created_by': uid, // ⚠️ RLS: doit être = auth.uid()
          })
          .select('id,name')
          .single();

      _snack('Organization created.');
      await _load();

      final orgId = inserted['id'] as String;
      await OrgPrefs.saveSelectedOrgId(orgId);
      if (!mounted) return;
      Navigator.of(context).pop<String>(orgId);
    } on PostgrestException catch (e) {
      _snack('Supabase: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
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
      _snack('Only the owner can manage members.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => ManageMembersSheet(orgId: org.id, orgName: org.name),
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
    final isLoggedIn = _sb.auth.currentSession != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My organizations'),
        actions: [
          IconButton(
            tooltip: isLoggedIn ? 'Log out' : 'Log in',
            icon: Iconify(isLoggedIn ? Mdi.logout : Mdi.login),
            onPressed: _onTapAuthButton,
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _createOrgDialog,
              backgroundColor: kAccentA,
              foregroundColor: Colors.white,
              icon: const Iconify(Mdi.business),
              label: const Text('Create'),
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
                            'You are not a member of any organization.\nCreate one to get started.',
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
                'Select your organization or create a new one.',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Iconify(Mdi.add),
              label: const Text('Create'),
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
                label: const Text('Create'),
                backgroundColor: kAccentB.withOpacity(.12),
                side: BorderSide.none,
              ),
            ),
            const Spacer(),
            Text(
              'Create an organization',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Invite your team, manage your inventory and sales.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add, size: 18),
                SizedBox(width: 6),
                Text('New organization'),
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
                      message: 'Manage members',
                      child: IconButton(
                        onPressed: onManageMembers,
                        icon: const Iconify(Mdi.account_group),
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
                      Text('Enter'),
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
