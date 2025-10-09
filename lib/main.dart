// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';

/// Initialise .env puis Supabase si les credentials existent.
/// Renvoie true si Supabase est bien initialisé, sinon false (mode dégradé).
Future<bool> _initEnvAndSupabase() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Pas de .env : mode dégradé
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        // ⚠️ 'persistSession' n'existe pas dans FlutterAuthClientOptions v2
        // Auto-persist et auto-refresh sont gérés par défaut.
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
          // detectSessionInUri: true, // valeur par défaut
          // authFlowType: AuthFlowType.pkce, // par défaut aussi
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Supabase init failed: $e');
      return false;
    }
  } else {
    debugPrint('No Supabase credentials found. Running in degraded mode.');
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasSupabase = await _initEnvAndSupabase();
  runApp(InventorixApp(hasSupabase: hasSupabase));
}

class InventorixApp extends StatelessWidget {
  const InventorixApp({super.key, required this.hasSupabase});

  final bool hasSupabase;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventorix',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: hasSupabase ? const AuthGate() : const _DegradedHome(),
    );
  }
}

/// Ecran minimal quand Supabase n’est pas configuré.
/// Permet de tester l’UI sans planter.
class _DegradedHome extends StatelessWidget {
  const _DegradedHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventorix (mode dégradé)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Supabase non configuré.\n'
            'Ajoute un fichier .env à la racine :\n\n'
            'SUPABASE_URL=...\nSUPABASE_ANON_KEY=...\n\n'
            'Puis relance l’app.',
          ),
          SizedBox(height: 16),
          Text(
            'Tu peux malgré tout continuer à intégrer l’UI. '
            'Une fois Supabase prêt, l’écran d’auth s’activera automatiquement.',
          ),
        ],
      ),
    );
  }
}
