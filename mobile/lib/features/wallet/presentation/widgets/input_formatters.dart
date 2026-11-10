import 'package:flutter/services.dart';

/// 4111111111111111 -> 4111 1111 1111 1111
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 19 ? digits.substring(0, 19) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// 1230 -> 12/30
class ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;
    final text = limited.length > 2 ? '${limited.substring(0, 2)}/${limited.substring(2)}' : limited;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Algoritmo de Luhn (mismo que valida el backend).
bool luhnValid(String digits) {
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return false;
  var total = 0;
  for (var i = 0; i < digits.length; i++) {
    var digit = int.parse(digits[digits.length - 1 - i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    total += digit;
  }
  return total % 10 == 0;
}

/// "12/30" -> [12, 2030]. Devuelve null si el formato no es válido.
List<int>? parseExpiry(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final month = int.parse(match.group(1)!);
  final year = 2000 + int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;
  return [month, year];
}

bool isExpired(int month, int year) {
  final now = DateTime.now();
  return year < now.year || (year == now.year && month < now.month);
}

/// Detecta la marca a partir del inicio del número (igual que el backend).
String detectBrand(String digits) {
  if (digits.startsWith('4')) return 'visa';
  if (digits.length >= 2) {
    final two = int.tryParse(digits.substring(0, 2)) ?? 0;
    if (two >= 51 && two <= 55) return 'mastercard';
    if (two == 34 || two == 37) return 'amex';
  }
  if (digits.length >= 4) {
    final four = int.tryParse(digits.substring(0, 4)) ?? 0;
    if (four >= 2221 && four <= 2720) return 'mastercard';
  }
  return 'desconocida';
}
