import 'dart:ui';

String formatYen(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '¥$buffer';
}

String formatIso(DateTime? date) {
  if (date == null) return '—';
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}

String formatInputDate(DateTime? date) {
  if (date == null) return '';
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Color colorFromHex(String hex) {
  final value = int.parse(hex.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | value);
}

Color inkFor(Color fill) {
  final cyan = fill.b > 0.65 && fill.g > 0.55 && fill.r < 0.25;
  if (cyan || fill.computeLuminance() > 0.45) return const Color(0xFF151515);
  return const Color(0xFFFFFFFF);
}

int parseLooseInt(String raw) => int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
