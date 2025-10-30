// lib/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sign_in_page.dart';
import '../inventory/main_inventory_page.dart';
import '../org/organizations_page.dart';
import '../org/organization_models.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _authStateStream = _supabase.auth.onAuthStateChange;
  }

  Future<String?> _resolveOrgId() async {
    final saved = await OrgPrefs.loadSelectedOrgId();
    if (saved == null) return null;
    // Vérifie appartenance
    final rows = await _supabase
        .from('v_my_organizations')
        .select('org_id')
        .eq('org_id', saved)
        .limit(1);
    if (rows.isNotEmpty) return saved;
    // sinon purge
    await OrgPrefs.clear();
    return null;
  }

  Future<Widget> _nextAfterAuth() async {
    final orgId = await _resolveOrgId();
    if (orgId != null) {
      return MainInventoryPage(orgId: orgId);
    }
    // ouvre la page Mes organisations et attend un choix
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const OrganizationsPage()),
    );
    if (picked != null) {
      return MainInventoryPage(orgId: picked);
    }
    // Si l’utilisateur revient sans choisir, rester sur la page d’orga
    return const OrganizationsPage();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStateStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snapshot.data!.session;
        if (session == null) {
          return const SignInPage();
        } else {
          // IMPORTANT : utiliser un FutureBuilder pour router proprement
          return FutureBuilder<Widget>(
            future: _nextAfterAuth(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return snap.data!;
            },
          );
        }
      },
    );
  }
}
