// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'public/public_line_page.dart';

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
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
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
    // Chemin demandé (utile sur Web pour l'accès direct à /public)
    final String path = kIsWeb ? Uri.base.path : '/';

    Route<dynamic> buildRoute(Widget page) =>
        MaterialPageRoute(builder: (_) => page);

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

      // Router : ne force plus les non-authentifiés sur /public
      onGenerateRoute: (settings) {
        final String routeName = settings.name ?? path;

        // 1) Si Supabase n'est pas configuré → écran dégradé
        if (!hasSupabase) {
          return buildRoute(const _DegradedHome());
        }

        // 2) Routes publiques explicites
        if (routeName == '/public') {
          return buildRoute(const PublicLinePage());
        }

        // 3) Route de login utilisée ailleurs (pushNamed '/login')
        if (routeName == '/login') {
          return buildRoute(const AuthGate());
        }

        // 4) Routes par défaut : AuthGate (gère connecté / non connecté)
        //    - Si connecté → dashboard
        //    - Si non connecté → écran d'auth
        return buildRoute(const AuthGate());
      },

      onUnknownRoute: (settings) {
        if (!hasSupabase) {
          return MaterialPageRoute(builder: (_) => const _DegradedHome());
        }
        // Fallback pareil : on laisse AuthGate décider
        return MaterialPageRoute(builder: (_) => const AuthGate());
      },
    );
  }
}

/// Ecran minimal quand Supabase n’est pas configuré.
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
