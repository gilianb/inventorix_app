/// FX rates: "1 unit of currency -> USD"
/// ⚠️ À maintenir à jour (valeurs d’exemple).
const String kBaseCurrency = 'USD';

const Map<String, double> kFxToUsd = {
  'USD': 1.0,

  // Examples (update as needed):
  'EUR': 1.17,
  'GBP': 1.34,
  'JPY': 0.0065,
  'CHF': 1.26,
  'CAD': 0.73,

  // Important for your project:
  'ILS': 0.31,
  'AED': 0.272, // (peg) 1 USD ≈ 3.6725 AED
};
