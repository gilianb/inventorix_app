// lib/details/services/cardtrader_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class CardTraderStats {
  /// Total retourné par l’API (après éventuel filtre serveur `?language=...`)
  final int listings;

  /// Nombre d’items retenus après nos filtres “stricts” côté client
  final int includedStrict;

  /// Nombre d’items réellement utilisés pour le calcul (pool final)
  final int usedForCalc;
  final String nativeCurrency;
  final double? medianUSD;
  final double? minUSD;
  final bool fellBack;

  const CardTraderStats({
    required this.listings,
    required this.includedStrict,
    required this.usedForCalc,
    required this.nativeCurrency,
    required this.medianUSD,
    required this.minUSD,
    required this.fellBack,
  });
}

class CardTraderService {
  static const _base = 'https://api.cardtrader.com/api/v2';

  // Reste en strict
  static const bool _strictOnly = true;
  // On ne veut pas de langue indéfinie quand on filtre l'anglais
  static const bool _acceptUndefinedLanguage = false;

  // Exclure les annonces de grading via commentaires/notes
  static final RegExp _commentExclude = RegExp(
    [
      r'(?:grading|\bgrade\b)',
      r'(?:\bPSA\s*-?\s*\d+(?:\.\d+)?\b|\bPSA\b)',
      r'(?:\bBGS\s*-?\s*\d+(?:\.\d+)?\b|\bBGS\b)',
      r'(?:\bCGC\s*-?\s*\d+(?:\.\d+)?\b|\bCGC\b)',
      r'\bGRAAD\b',
      r'\bBCG\b',
      r'\bBECKETT\b',
      r'\bBECKET\b',
    ].join('|'),
    caseSensitive: false,
  );

  static double _median(List<double> xs) {
    if (xs.isEmpty) return double.nan;
    final a = xs.toList()..sort();
    final m = a.length ~/ 2;
    return a.length.isOdd ? a[m] : (a[m - 1] + a[m]) / 2.0;
  }

  static double? _fxToUSD(
    double amount,
    String currency,
    Map<String, double> fx,
  ) {
    final cur = (currency.isEmpty ? 'USD' : currency).toUpperCase();
    final rate = fx[cur];
    if (rate == null || !rate.isFinite) return amount; // si inconnu: brut
    return amount * rate;
  }

  /// Essaie de trouver un champ de langue fiable dans `properties_hash`
  /// pour différents jeux (One Piece, MTG, etc.).
  /// Exemples vus:
  ///   - properties_hash.onepiece_language: 'en' | 'jp' | 'zh' ...
  ///   - properties_hash.mtg_language
  ///   - properties_hash.language / language / language_code
  static String? _languageOf(Map it) {
    final ph = (it['properties_hash'] as Map?) ?? const {};
    final candidates = [
      ph['onepiece_language'],
      ph['mtg_language'],
      ph['pokemon_language'],
      ph['yugioh_language'],
      ph['language'],
      ph['language_code'],
      it['language'],
      it['mtg_language'],
    ];
    for (final v in candidates) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static String? _conditionOf(Map it) {
    final ph = (it['properties_hash'] as Map?) ?? const {};
    return ph['condition']?.toString();
  }

  /// Vrai anglais ? (évite les faux positifs type "chinese")
  static bool _isEnglishLanguage(String? lang) {
    if (lang == null) return false;
    final s = lang.trim().toLowerCase();

    // codes et libellés fréquents
    if (s == 'en' || s == 'eng') return true;
    if (RegExp(r'\benglish\b').hasMatch(s)) return true;
    if (RegExp(r'\banglais\b').hasMatch(s)) return true;

    // formats "en-US", "en gb", etc.
    if (s.startsWith('en-') || s.startsWith('en ')) return true;

    // nettoyage et tokens
    final cleaned = s.replaceAll(RegExp(r'[^a-z]'), ' ');
    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (t == 'en' || t == 'eng' || t == 'english' || t == 'anglais') {
        return true;
      }
    }
    return false;
  }

  /// Vrai si présence d'un mot-clé de grading dans un champ texte courant
  static bool _hasExcludedComment(Map it) {
    final fields = <String?>[
      it['comment']?.toString(),
      it['comments']?.toString(),
      it['note']?.toString(),
      it['notes']?.toString(),
      it['description']?.toString(),
      it['seller_comment']?.toString(),
      it['seller_note']?.toString(),
      ((it['properties_hash'] as Map?)?['comment'])?.toString(),
      ((it['properties_hash'] as Map?)?['notes'])?.toString(),
      ((it['properties_hash'] as Map?)?['description'])?.toString(),
    ].whereType<String>().toList();
    return fields.any((s) => _commentExclude.hasMatch(s));
  }

  /// Peut être renvoyé en top-level (price_cents / price_currency)
  /// ou dans price.cents / price.currency
  static int? _priceCents(Map it) {
    final direct = num.tryParse('${it['price_cents'] ?? ''}');
    if (direct != null) return direct.toInt();
    final cents = num.tryParse('${(it['price'] as Map?)?['cents'] ?? ''}');
    return cents?.toInt();
  }

  static String _currencyOf(Map it) {
    final direct = (it['price_currency'] ?? '').toString();
    if (direct.isNotEmpty) return direct;
    final cur = ((it['price'] as Map?)?['currency'])?.toString();
    return cur ?? 'EUR';
  }

  /// Détermine si une annonce est "graded-like":
  /// - `graded == true` OU
  /// - commentaire contenant mots-clés de grading.
  static bool _isGradedLike(Map it) {
    if ((it['graded'] ?? false) == true) return true;
    return _hasExcludedComment(it);
  }

  /// Récupère les stats CardTrader pour un blueprint donné.
  ///
  /// - [graded] :
  ///   - false => onglet **non gradé** : exclut tout graded-like, garde NM/SP uniquement
  ///   - true  => onglet **gradé**     : garde graded-like, sans filtre de condition
  ///
  /// - [languageParam] si fourni utilise le filtre **serveur** `?language=...`
  ///   ex: 'en', 'ja', 'zh', 'fr', ...
  static Future<CardTraderStats> fetchMarketplaceByBlueprint({
    required int blueprintId,
    required String bearerToken,
    bool graded = false,
    String? languageParam,
    Map<String, double> fxToUsd = const {
      'EUR': 1.08,
      'GBP': 1.27,
      'JPY': 0.0067,
      'USD': 1.0,
    },
  }) async {
    if (bearerToken.isEmpty) {
      throw StateError('CARDTRADER_TOKEN manquant');
    }

    final qp = <String, String>{'blueprint_id': '$blueprintId'};
    if (languageParam != null && languageParam.trim().isNotEmpty) {
      qp['language'] = languageParam.trim().toLowerCase();
    }

    final uri =
        Uri.parse('$_base/marketplace/products').replace(queryParameters: qp);

    final r = await http.get(uri, headers: {
      'Authorization': 'Bearer $bearerToken',
    });
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('CardTrader HTTP ${r.statusCode}');
    }

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (json['$blueprintId'] as List?)?.cast<Map>() ?? const <Map>[];

    // ---- Filtrage stricte EN (client) si languageParam n'impose pas autre chose
    final wantsEnglishOnly =
        (languageParam == null) || languageParam.toLowerCase() == 'en';

    final langFiltered = <Map>[];
    for (final it in items) {
      if (!wantsEnglishOnly) {
        langFiltered.add(it); // on fait confiance au serveur
        continue;
      }
      final lang = _languageOf(it);
      if (lang == null || lang.isEmpty) {
        if (_acceptUndefinedLanguage) langFiltered.add(it);
      } else if (_isEnglishLanguage(lang)) {
        langFiltered.add(it);
      }
    }

    // ---- Règles selon onglet (graded vs non-graded)
    final includedStrict = <Map>[];
    for (final it in langFiltered) {
      final isGradedLike = _isGradedLike(it);

      if (!graded) {
        // NON GRADÉ => exclure tout graded-like
        if (isGradedLike) continue;

        // Condition : NM / SP uniquement
        final cond = _conditionOf(it) ?? '';
        if (!(RegExp(r'Near\s*Mint|Slightly\s*Played', caseSensitive: false)
            .hasMatch(cond))) {
          continue;
        }
      } else {
        // GRADÉ => garder seulement graded-like, sans filtre de condition
        if (!isGradedLike) continue;
      }

      // Prix valide
      final cents = _priceCents(it);
      if (cents == null) continue;

      includedStrict.add(it);
    }

    // Pool final
    List<Map> pool = List.of(includedStrict);
    var fellBack = false;

    if (pool.isEmpty && !_strictOnly) {
      // Fallback éventuel (ici inactif car _strictOnly=true)
      final fallback = langFiltered
          .where((it) {
            final isGradedLike = _isGradedLike(it);
            if (!graded) {
              if (isGradedLike) return false;
            } else {
              if (!isGradedLike) return false;
            }
            return _priceCents(it) != null;
          })
          .cast<Map>()
          .toList();
      pool = fallback;
      fellBack = pool.isNotEmpty;
    }

    // Tri prix croissant
    pool.sort((a, b) =>
        (_priceCents(a) ?? 1 << 30).compareTo(_priceCents(b) ?? 1 << 30));

    // Devise native (à titre informatif)
    final nativeCurrency =
        (items.isNotEmpty ? _currencyOf(items.first) : 'EUR').toUpperCase();

    // Conversion USD
    final usdArr = <double>[];
    for (final it in pool) {
      final cents = _priceCents(it);
      if (cents == null) continue;
      final cur = _currencyOf(it).toUpperCase();
      final usd = _fxToUSD(cents / 100.0, cur, fxToUsd);
      if (usd != null && usd.isFinite) {
        usdArr.add(double.parse(usd.toStringAsFixed(2)));
      }
    }

    final medianUSD = usdArr.isNotEmpty ? _median(usdArr) : null;
    final minUSD = usdArr.isNotEmpty ? usdArr.reduce(min) : null;

    return CardTraderStats(
      listings: langFiltered.length, // après filtre langue
      includedStrict: includedStrict.length,
      usedForCalc: pool.length,
      nativeCurrency: nativeCurrency,
      medianUSD: medianUSD,
      minUSD: minUSD,
      fellBack: fellBack,
    );
  }
}
