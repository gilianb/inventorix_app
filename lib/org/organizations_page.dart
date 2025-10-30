// lib/org/organizations_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'organization_models.dart';

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
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Créer')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes organisations')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.add_business),
                    title: const Text('Créer une organisation'),
                    onTap: _createOrgDialog,
                  ),
                  const Divider(),
                  ..._orgs.map((o) => ListTile(
                        leading: const Icon(Icons.business),
                        title: Text(o.name),
                        subtitle: Text('Rôle : ${o.role}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _selectOrg(o),
                      )),
                  if (_orgs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Vous n’êtes membre d’aucune organisation.\nCréez-en une pour commencer.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
