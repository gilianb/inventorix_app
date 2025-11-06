// lib/details/services/cardtrader_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class CardTraderStats {
  final int listings;
  final int includedStrict;
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
  static const bool _strictOnly = true;
  static const bool _acceptUndefinedLanguage = false;

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
    if (rate == null || !rate.isFinite) return amount;
    return amount * rate;
  }

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

  static bool _isEnglishLanguage(String? lang) {
    if (lang == null) return false;
    final s = lang.trim().toLowerCase();
    if (s == 'en' || s == 'eng') return true;
    if (RegExp(r'\benglish\b').hasMatch(s)) return true;
    if (RegExp(r'\banglais\b').hasMatch(s)) return true;
    if (s.startsWith('en-') || s.startsWith('en ')) return true;
    final cleaned = s.replaceAll(RegExp(r'[^a-z]'), ' ');
    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (t == 'en' || t == 'eng' || t == 'english' || t == 'anglais')
        return true;
    }
    return false;
  }

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

  static bool _isGradedLike(Map it) {
    if ((it['graded'] ?? false) == true) return true;
    return _hasExcludedComment(it);
  }

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
      'Accept': 'application/json',
    });

    if (r.statusCode < 200 || r.statusCode >= 300) {
      final prefix = r.statusCode == 401
          ? 'CardTrader 401 (token invalide/expiré)'
          : 'CardTrader HTTP ${r.statusCode}';
      final body = r.body.isNotEmpty
          ? ' — ${r.body.substring(0, r.body.length.clamp(0, 300))}'
          : '';
      throw StateError('$prefix$body');
    }

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (json['$blueprintId'] as List?)?.cast<Map>() ?? const <Map>[];

    final wantsEnglishOnly =
        (languageParam == null) || languageParam.toLowerCase() == 'en';

    final langFiltered = <Map>[];
    for (final it in items) {
      if (!wantsEnglishOnly) {
        langFiltered.add(it);
        continue;
      }
      final lang = _languageOf(it);
      if (lang == null || lang.isEmpty) {
        if (_acceptUndefinedLanguage) langFiltered.add(it);
      } else if (_isEnglishLanguage(lang)) {
        langFiltered.add(it);
      }
    }

    final includedStrict = <Map>[];
    for (final it in langFiltered) {
      final isGradedLike = _isGradedLike(it);

      if (!graded) {
        if (isGradedLike) continue;
        final cond = _conditionOf(it) ?? '';
        if (!(RegExp(r'Near\s*Mint|Slightly\s*Played', caseSensitive: false)
            .hasMatch(cond))) {
          continue;
        }
      } else {
        if (!isGradedLike) continue;
      }

      final cents = _priceCents(it);
      if (cents == null) continue;

      includedStrict.add(it);
    }

    List<Map> pool = List.of(includedStrict);
    var fellBack = false;

    if (pool.isEmpty && !_strictOnly) {
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

    pool.sort((a, b) =>
        (_priceCents(a) ?? 1 << 30).compareTo(_priceCents(b) ?? 1 << 30));

    final nativeCurrency =
        (items.isNotEmpty ? _currencyOf(items.first) : 'EUR').toUpperCase();

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
      listings: langFiltered.length,
      includedStrict: includedStrict.length,
      usedForCalc: pool.length,
      nativeCurrency: nativeCurrency,
      medianUSD: medianUSD,
      minUSD: minUSD,
      fellBack: fellBack,
    );
  }
}
