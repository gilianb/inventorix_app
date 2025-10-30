// lib/org/organizations_page.dart
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
      final rows = await _sb
          .from('v_my_organizations')
          .select('org_id,name,role,created_at')
          .order('created_at', ascending: false);

      _orgs = (rows as List<dynamic>)
          .map((e) => Organization.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
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

      // Sélection immédiate
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
                    const _CreateOrgCard(), // la tuile "Créer"
                    ..._orgs.map((o) => _OrgCard(org: o)).toList(),
                  ];

                  if (_orgs.isEmpty) {
                    // État vide sympa
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
                      children: [
                        _PageIntro(onCreate: _createOrgDialog),
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 1, // juste la tuile "Créer"
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

                  // Grille normale
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
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _selectOrg(w.org),
                              child: w,
                            );
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

/* ====== Jolis widgets ====== */

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
  const _OrgCard({required this.org});
  final Organization org;

  String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty) return 'O';
    if (p.length == 1)
      return p.first.characters.take(2).toString().toUpperCase();
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
              _TileHeader(
                leading: _Avatar(seed: org.id, label: _initials(org.name)),
                roleChip: Chip(
                  label: Text(org.role.toUpperCase()),
                  labelStyle: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  backgroundColor: roleColor.withOpacity(.12),
                  side: BorderSide(color: roleColor.withOpacity(.20)),
                ),
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
              Row(
                children: const [
                  Icon(Icons.chevron_right, size: 18),
                  SizedBox(width: 6),
                  Text('Entrer'),
                ],
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
