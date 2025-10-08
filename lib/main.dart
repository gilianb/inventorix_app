// lib/main.dart
import 'dart:async';
import 'dart:io' show InternetAddress, Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

const _disableSupabase =
    bool.fromEnvironment('DISABLE_SUPABASE', defaultValue: false);

Future<bool> _canResolveHost(Uri uri) async {
  try {
    final host = uri.host;
    if (host.isEmpty) return false;
    final result =
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
    return result.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Initialise .env + supabase si possible (et atteignable).
Future<bool> _initEnvAndSupabase() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  if (_disableSupabase) {
    debugPrint('DISABLE_SUPABASE=true → mode dégradé forcé.');
    return false;
  }

  final urlStr = dotenv.env['SUPABASE_URL']?.trim();
  final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

  if (urlStr == null || urlStr.isEmpty || anonKey == null || anonKey.isEmpty) {
    debugPrint('No Supabase credentials found. Running in degraded mode.');
    return false;
  }

  Uri? url;
  try {
    url = Uri.parse(urlStr);
    if (!url.hasScheme) {
      // Sécurise un oubli de https://
      url = Uri.parse('https://$urlStr');
    }
  } catch (e) {
    debugPrint('Invalid SUPABASE_URL: $e');
    return false;
  }

  // ⚠️ Spécifiquement utile sur Windows: on vérifie la résolution DNS
  if (Platform.isWindows) {
    final ok = await _canResolveHost(url);
    if (!ok) {
      debugPrint('Host lookup failed for ${url.host} → mode dégradé.');
      return false;
    }
  }

  try {
    await Supabase.initialize(
      url: url.toString(),
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
    return true;
  } catch (e) {
    debugPrint('Supabase init failed: $e');
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
      // Défocus global (utile aussi sur Desktop)
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child!,
      ),
      home: hasSupabase ? const AuthGate() : const _DegradedHome(),
    );
  }
}

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
            'Supabase non configuré ou injoignable (DNS/Proxy/Firewall).\n'
            'Ajoute/configure .env correctement et/ou connecte le PC au réseau.\n\n'
            'Tu peux aussi lancer en forçant le mode dégradé :\n'
            'flutter run -d windows --dart-define=DISABLE_SUPABASE=true',
          ),
          SizedBox(height: 16),
          Text(
            'L’UI reste testable sans réseau. Une fois le réseau OK, '
            'relance l’app pour activer Supabase.',
          ),
        ],
      ),
    );
  }
}
