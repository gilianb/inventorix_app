// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Optionnel : enlève le # des URL si tu veux du "path" pur
// import 'package:flutter_web_plugins/url_strategy.dart';

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

  if ((supabaseUrl ?? '').isNotEmpty && (supabaseAnonKey ?? '').isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl!,
        anonKey: supabaseAnonKey!,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  } else {
    debugPrint('No Supabase credentials found. Running in degraded mode.');
  }
  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Optionnel : supprime le hash des URL (sur Web)
  // usePathUrlStrategy();

  final hasSupabase = await _initEnvAndSupabase();
  runApp(InventorixApp(hasSupabase: hasSupabase));
}

class InventorixApp extends StatelessWidget {
  const InventorixApp({super.key, required this.hasSupabase});
  final bool hasSupabase;

  /// Détecte le path effectif sur Web :
  /// - soit dans Uri.base.path (/public)
  /// - soit dans Uri.base.fragment (#/public) si hash strategy
  String _effectivePath() {
    if (!kIsWeb) return '/';
    final path = Uri.base.path; // ex: /public
    final frag = Uri.base.fragment; // ex: /public si hash strategy
    if (path != '/' && path.isNotEmpty) return path;
    if (frag.isNotEmpty) return frag.startsWith('/') ? frag : '/$frag';
    return '/';
  }

  bool _isPublicUrl() {
    final p = _effectivePath(); // ex: /public ou /public/
    return p == '/public' || p.startsWith('/public/');
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT : si on arrive directement sur /public?org=...,
    // on évite d'afficher AuthGate au 1er frame.
    final initial = kIsWeb && _isPublicUrl() ? '/public' : '/';

    Route<dynamic> page(Widget w) => MaterialPageRoute(builder: (_) => w);

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

      // Empêche un flash de la page d'auth quand l'URL cible est /public
      initialRoute: initial,

      routes: {
        // Route publique TOUJOURS accessible (les query params sont lus via Uri.base)
        '/public': (context) => const PublicLinePage(),
        // Route login si tu l’utilises ailleurs
        '/login': (context) => const AuthGate(),
        // Route racine (zone protégée)
        '/': (context) =>
            hasSupabase ? const AuthGate() : const _DegradedHome(),
      },

      onGenerateRoute: (settings) {
        // Si ce n'est pas une route déclarée ci-dessus :
        if (kIsWeb) {
          // settings.name peut ressembler à "/public?org=...&g=...&s=..."
          final raw = settings.name ?? Uri.base.toString();
          final uri = Uri.tryParse(raw) ?? Uri();
          final pathOnly = uri.path;

          // Force la page publique si on détecte /public (quelque soit la query)
          if (pathOnly == '/public' || pathOnly == '/public/') {
            return page(const PublicLinePage());
          }

          // Cas hash strategy : fragment == "/public?...":
          final frag = Uri.base.fragment;
          if (frag.startsWith('/public')) {
            return page(const PublicLinePage());
          }
        }

        // Par défaut : zone protégée (ou mode dégradé)
        return page(hasSupabase ? const AuthGate() : const _DegradedHome());
      },

      onUnknownRoute: (_) =>
          page(hasSupabase ? const AuthGate() : const _DegradedHome()),
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
