// lib/main.dart
// ignore_for_file: unintended_html_in_doc_comment

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';

import 'auth/auth_gate.dart';
import 'public/public_item_page.dart';

/// Essaie d'extraire un token public depuis l'URL actuelle.
/// Gère:
///   - /i/<token>
///   - #/i/<token>
///   - ?i=<token> ou ?token=<token>
String? _extractPublicTokenFromUri(Uri uri) {
  // 1) mode "path" classique : https://.../i/<token>
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'i') {
    return uri.pathSegments.length >= 2 ? uri.pathSegments[1] : null;
  }

  // 2) mode "hash" : https://.../#/i/<token>
  final frag = uri.fragment;
  if (frag.isNotEmpty) {
    // On force un "/" devant pour que Uri.parse comprenne bien la route
    final fUri = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
    if (fUri.pathSegments.isNotEmpty && fUri.pathSegments.first == 'i') {
      return fUri.pathSegments.length >= 2 ? fUri.pathSegments[1] : null;
    }
  }

  // 3) fallback via query : https://.../?i=<token> ou ?token=<token>
  final qp = uri.queryParameters;
  final t = qp['i'] ?? qp['token'];
  if (t != null && t.isNotEmpty) return t;

  return null;
}

/// Détecte si l'URL correspond à un ancien lien /public (query / hash)
bool _isLegacyPublicUri(Uri uri) {
  if (uri.path == '/public') return true;

  final frag = uri.fragment;
  if (frag.startsWith('/public') || frag == 'public') {
    return true;
  }

  return false;
}

Future<bool> _initEnvAndSupabase() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

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

  // 🔹 Sur le web: URLs "propres" (sans #)
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  final hasSupabase = await _initEnvAndSupabase();

  // 🔹 Mode WEB : on regarde l'URL AVANT même de lancer l'app privée
  if (kIsWeb) {
    final uri = Uri.base;

    // 1) Lien public basé sur token: /i/<token>, #/i/<token>, ?i=<token>
    final publicToken = _extractPublicTokenFromUri(uri);
    if (publicToken != null && publicToken.isNotEmpty) {
      runApp(_PublicItemBootstrapApp(token: publicToken));
      return;
    }

    // 2) Ancien lien public : /public... (path ou hash) -> app de redirection
    if (_isLegacyPublicUri(uri)) {
      runApp(_PublicLegacyBootstrapApp(hasSupabase: hasSupabase));
      return;
    }
  }

  // 🔹 Tous les autres cas : app interne normale (AuthGate)
  runApp(InventorixApp(hasSupabase: hasSupabase));
}

/// App publique minimale : ne montre QUE la fiche publique.
class _PublicItemBootstrapApp extends StatelessWidget {
  const _PublicItemBootstrapApp({required this.token});
  final String token;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventorix — Public sheet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: PublicItemPage(token: token),
    );
  }
}

/// App de compat /public -> /i/<token>
class _PublicLegacyBootstrapApp extends StatelessWidget {
  const _PublicLegacyBootstrapApp({required this.hasSupabase});
  final bool hasSupabase;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventorix — Public link',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: _PublicLegacyRedirect(hasSupabase: hasSupabase),
    );
  }
}

/// App interne (privée) avec AuthGate
class InventorixApp extends StatelessWidget {
  const InventorixApp({super.key, required this.hasSupabase});
  final bool hasSupabase;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventorix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: hasSupabase ? const AuthGate() : const _DegradedHome(),
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

/// Compat ascendante : /public?org=...&g=...&s=...  →  /i/<public_token>
class _PublicLegacyRedirect extends StatefulWidget {
  const _PublicLegacyRedirect({required this.hasSupabase});
  final bool hasSupabase;

  @override
  State<_PublicLegacyRedirect> createState() => _PublicLegacyRedirectState();
}

class _PublicLegacyRedirectState extends State<_PublicLegacyRedirect> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    if (!widget.hasSupabase) {
      setState(() => _error =
          'Supabase non configuré — impossible de résoudre le lien public.');
      return;
    }

    try {
      final base = Uri.base;

      final qp = <String, String>{
        ...base.queryParameters,
        if (base.fragment.contains('?'))
          ...Uri.splitQueryString(base.fragment.split('?').last),
      };

      final org = (qp['org'] ?? '').trim();
      final g = (qp['g'] ?? '').trim();
      final s = (qp['s'] ?? '').trim(); // optionnel

      if (org.isEmpty || g.isEmpty) {
        setState(() => _error = 'Lien invalide (org/g manquants).');
        return;
      }

      final sb = Supabase.instance.client;

      var filter = sb
          .from('item')
          .select('public_token')
          .eq('org_id', org)
          .eq('group_sig', g);

      if (s.isNotEmpty) {
        filter = filter.eq('status', s);
      }

      final rec =
          await filter.order('id', ascending: true).limit(1).maybeSingle();

      final token = (rec?['public_token'] ?? '').toString();

      if (token.isEmpty) {
        setState(() => _error = 'Ressource introuvable (404).');
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: RouteSettings(name: '/i/$token'),
          builder: (_) => PublicItemPage(token: token),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Erreur de redirection : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Inventorix — Public link')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Redirection…'),
                  ],
                )
              : Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
