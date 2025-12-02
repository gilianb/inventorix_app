import 'package:intl/intl.dart';

String formatMoney(num value, String currency) {
  final symbol = currency.toUpperCase(); // "EUR", "USD", "AED", etc.
  final formatter = NumberFormat.currency(
    symbol: '$symbol ',
    decimalDigits: 2,
  );
  return formatter.format(value);
}

String formatDate(DateTime date) {
  return DateFormat('yyyy-MM-dd').format(date);
}
