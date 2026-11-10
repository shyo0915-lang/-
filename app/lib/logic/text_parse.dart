// 電話番号・和暦を含む日付・金額・住所の抽出。OCR と手入力の両方から使います。

String toHalfWidth(String input) {
  final buf = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buf.writeCharCode(0x30 + (rune - 0xFF10));
    } else if (rune >= 0xFF21 && rune <= 0xFF3A) {
      buf.writeCharCode(rune - 0xFF21 + 0x41);
    } else if (rune >= 0xFF41 && rune <= 0xFF5A) {
      buf.writeCharCode(rune - 0xFF41 + 0x61);
    } else if (rune == 0xFF0D || rune == 0x30FC || rune == 0x2212 || rune == 0x2010 || rune == 0x2014 || rune == 0x2015) {
      buf.write('-');
    } else if (rune == 0xFF1A) {
      buf.write(':');
    } else if (rune == 0xFF0C) {
      buf.write(',');
    } else if (rune == 0xFFE5) {
      buf.write('¥');
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

String digitsOnly(String input) => toHalfWidth(input).replaceAll(RegExp(r'\D'), '');

bool isValidJpPhone(String input) {
  final digits = digitsOnly(input);
  return RegExp(r'^0\d{9,10}$').hasMatch(digits);
}

/// 保存時のハイフン整形。不正な番号はそのまま返します。
String formatJpPhone(String input) {
  final digits = digitsOnly(input);
  if (!isValidJpPhone(input)) return input.trim();
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
  }
  if (digits.startsWith('03') || digits.startsWith('06')) {
    return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6)}';
  }
  return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
}

class PhoneHit {
  const PhoneHit(this.formatted, this.confidence, this.raw);
  final String formatted;
  final double confidence;
  final String raw;
}

PhoneHit? findPhone(String text, {bool labeled = false}) {
  final normalized = toHalfWidth(text);
  final pattern = RegExp(r'(?<!\d)(0\d{1,4}-\d{1,4}-\d{3,4}|0\d{9,10})(?!\d)');
  PhoneHit? best;
  for (final match in pattern.allMatches(normalized)) {
    final raw = match.group(1)!;
    if (!isValidJpPhone(raw)) continue;
    final lineStart = normalized.lastIndexOf('\n', match.start) + 1;
    final lineEnd = normalized.indexOf('\n', match.end);
    final line = normalized.substring(lineStart, lineEnd == -1 ? normalized.length : lineEnd);
    final hasLabel = RegExp(r'電話|TEL|Tel|携帯|FAX', caseSensitive: false).hasMatch(line);
    final confidence = hasLabel || labeled ? 0.96 : 0.84;
    final hit = PhoneHit(formatJpPhone(raw), confidence, raw);
    if (best == null || hit.confidence > best.confidence) best = hit;
  }
  return best;
}

class DateHit {
  const DateHit(this.iso, this.confidence, this.raw);
  final String iso;
  final double confidence;
  final String raw;
}

int? warekiYear(String era, String yearToken) {
  final token = yearToken.trim();
  final year = token == '元' ? 1 : int.tryParse(token);
  if (year == null || year < 1) return null;
  switch (era.toUpperCase()) {
    case '令和':
    case 'R':
      return 2018 + year;
    case '平成':
    case 'H':
      return 1988 + year;
    case '昭和':
    case 'S':
      return 1925 + year;
    default:
      return null;
  }
}

String? isoDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  final m = month.toString().padLeft(2, '0');
  final d = day.toString().padLeft(2, '0');
  return '$year-$m-$d';
}

DateHit? parseDateToken(String raw, {double confidence = 0.9}) {
  final text = toHalfWidth(raw).trim();
  final wareki = RegExp(
    r'(令和|平成|昭和|R|H|S)\s*(元|\d{1,2})\s*(?:年|[./\-])\s*(\d{1,2})\s*(?:月|[./\-])\s*(\d{1,2})\s*日?',
    caseSensitive: false,
  ).firstMatch(text);
  if (wareki != null) {
    final year = warekiYear(wareki.group(1)!, wareki.group(2)!);
    final iso = year == null ? null : isoDate(year, int.parse(wareki.group(3)!), int.parse(wareki.group(4)!));
    if (iso != null) return DateHit(iso, confidence, raw.trim());
  }
  final gregorian = RegExp(r'(\d{4})\s*(?:年|[./\-])\s*(\d{1,2})\s*(?:月|[./\-])\s*(\d{1,2})\s*日?').firstMatch(text);
  if (gregorian != null) {
    final iso = isoDate(
      int.parse(gregorian.group(1)!),
      int.parse(gregorian.group(2)!),
      int.parse(gregorian.group(3)!),
    );
    if (iso != null) return DateHit(iso, confidence, raw.trim());
  }
  return null;
}

DateHit? findDate(String text) {
  final normalized = toHalfWidth(text);
  DateHit? best;
  final pattern = RegExp(
    r'(令和|平成|昭和|R|H|S)\s*(?:元|\d{1,2})\s*(?:年|[./\-])\s*\d{1,2}\s*(?:月|[./\-])\s*\d{1,2}\s*日?|\d{4}\s*(?:年|[./\-])\s*\d{1,2}\s*(?:月|[./\-])\s*\d{1,2}\s*日?',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(normalized)) {
    final raw = match.group(0)!;
    final lineStart = normalized.lastIndexOf('\n', match.start) + 1;
    final lineEnd = normalized.indexOf('\n', match.end);
    final line = normalized.substring(lineStart, lineEnd == -1 ? normalized.length : lineEnd);
    final labeled = RegExp(r'契約日|締結日|日付').hasMatch(line);
    final hit = parseDateToken(raw, confidence: labeled ? 0.97 : 0.9);
    if (hit == null) continue;
    if (best == null || hit.confidence > best.confidence) best = hit;
  }
  return best;
}

class YenHit {
  const YenHit(this.amount, this.confidence, this.raw);
  final int amount;
  final double confidence;
  final String raw;
}

int? parseYen(String raw) {
  var text = toHalfWidth(raw).trim();
  text = text.replaceAll(RegExp(r'[¥￥円,\s]'), '');
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  final value = int.tryParse(text);
  if (value == null || value < 1 || value > 1000000000) return null;
  return value;
}

YenHit? findYen(String text) {
  final normalized = toHalfWidth(text);
  final dateLike = RegExp(
    r'(?:令和|平成|昭和|R|H|S)\s*(?:元|\d{1,2})\s*(?:年|[./\-])\s*\d{1,2}\s*(?:月|[./\-])\s*\d{1,2}\s*日?|\d{4}\s*(?:年|[./\-])\s*\d{1,2}\s*(?:月|[./\-])\s*\d{1,2}\s*日?',
    caseSensitive: false,
  );
  final masked = normalized
      .replaceAllMapped(dateLike, (match) => ' ' * match.group(0)!.length)
      .replaceAllMapped(RegExp(r'0\d{1,4}-\d{1,4}-\d{3,4}|0\d{9,10}'), (match) => ' ' * match.group(0)!.length);
  YenHit? best;
  final pattern = RegExp(r'(?:¥|￥)?\s*(\d{1,3}(?:,\d{3})+|\d{2,9})\s*円?');
  for (final match in pattern.allMatches(masked)) {
    final raw = match.group(0)!;
    final amount = parseYen(raw);
    if (amount == null) continue;
    final lineStart = masked.lastIndexOf('\n', match.start) + 1;
    final lineEnd = masked.indexOf('\n', match.end);
    final line = masked.substring(lineStart, lineEnd == -1 ? masked.length : lineEnd);
    final labeled = RegExp(r'単価|金額|料金|価格|合計|円|¥|￥').hasMatch(line);
    // 日付の一部（年や月）を金額とみなさない。
    if (RegExp(r'\d{4}\s*年|\d{1,2}\s*月').hasMatch(line) && !RegExp(r'円|¥|￥|単価|金額').hasMatch(line)) {
      continue;
    }
    final confidence = labeled ? 0.95 : 0.78;
    final hit = YenHit(amount, confidence, raw.trim());
    if (best == null || hit.confidence > best.confidence || (hit.confidence == best.confidence && hit.amount > best.amount)) {
      best = hit;
    }
  }
  return best;
}

const prefectures = [
  '北海道',
  '青森県',
  '岩手県',
  '宮城県',
  '秋田県',
  '山形県',
  '福島県',
  '茨城県',
  '栃木県',
  '群馬県',
  '埼玉県',
  '千葉県',
  '東京都',
  '神奈川県',
  '新潟県',
  '富山県',
  '石川県',
  '福井県',
  '山梨県',
  '長野県',
  '岐阜県',
  '静岡県',
  '愛知県',
  '三重県',
  '滋賀県',
  '京都府',
  '大阪府',
  '兵庫県',
  '奈良県',
  '和歌山県',
  '鳥取県',
  '島根県',
  '岡山県',
  '広島県',
  '山口県',
  '徳島県',
  '香川県',
  '愛媛県',
  '高知県',
  '福岡県',
  '佐賀県',
  '長崎県',
  '熊本県',
  '大分県',
  '宮崎県',
  '鹿児島県',
  '沖縄県',
];

class AddressHit {
  const AddressHit(this.address, this.confidence);
  final String address;
  final double confidence;
}

AddressHit? findAddress(String text) {
  final normalized = toHalfWidth(text);
  AddressHit? best;
  final pattern = RegExp('(${prefectures.join('|')})[^\\n]{1,80}');
  for (final match in pattern.allMatches(normalized)) {
    var address = match.group(0)!.trim();
    address = address.replaceFirst(RegExp(r'^(住所|所在地)\s*[:：]?\s*'), '');
    address = address.replaceAll(RegExp(r'[、。\s]+$'), '');
    if (address.length < 4) continue;
    final lineStart = normalized.lastIndexOf('\n', match.start) + 1;
    final lineEnd = normalized.indexOf('\n', match.end);
    final line = normalized.substring(lineStart, lineEnd == -1 ? normalized.length : lineEnd);
    final labeled = RegExp(r'住所|所在地').hasMatch(line);
    final confidence = labeled ? 0.96 : 0.88;
    final hit = AddressHit(address, confidence);
    if (best == null || hit.confidence > best.confidence || (hit.confidence == best.confidence && hit.address.length > best.address.length)) {
      best = hit;
    }
  }
  return best;
}

String? labeledValue(String text, RegExp label) {
  final normalized = toHalfWidth(text);
  final pattern = RegExp('(?:${label.pattern})\\s*[:：]\\s*(.+)');
  for (final line in normalized.split(RegExp(r'\r?\n'))) {
    final match = pattern.firstMatch(line.trim());
    if (match != null) {
      final value = match.group(1)!.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}
