import 'text_parse.dart';

class OcrField {
  const OcrField({
    required this.key,
    required this.label,
    required this.value,
    required this.confidence,
    this.confirmed = false,
    this.hint,
  });

  final String key;
  final String label;
  final String value;
  final double confidence;
  final bool confirmed;
  final String? hint;

  bool get blocksSave => value.trim().isEmpty || (!confirmed && confidence < 0.9);

  OcrField copyWith({String? value, double? confidence, bool? confirmed, String? hint}) {
    return OcrField(
      key: key,
      label: label,
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      confirmed: confirmed ?? this.confirmed,
      hint: hint ?? this.hint,
    );
  }
}

class OcrParser {
  static bool looksLikeTemplate(String text) {
    if (text.contains('FMT:CONTRACT-V1')) return true;
    final labels = [
      RegExp(r'顧客名|氏名|契約者'),
      RegExp(r'住所|所在地'),
      RegExp(r'電話|TEL|Tel|携帯'),
      RegExp(r'契約日|締結日'),
      RegExp(r'単価|金額|料金'),
    ];
    return labels.where((label) => label.hasMatch(text)).length >= 4;
  }

  static List<OcrField> parse(String text, {String format = 'auto'}) {
    final useTemplate = format == 'template' || (format == 'auto' && looksLikeTemplate(text));
    final nameRaw = labeledValue(text, RegExp(r'顧客名|氏名|会社名|契約者名|名称'));
    final addressLabeled = labeledValue(text, RegExp(r'住所|所在地'));
    final phoneLabeled = labeledValue(text, RegExp(r'電話番号|電話|TEL|Tel|携帯'));
    final dateLabeled = labeledValue(text, RegExp(r'契約日|締結日|日付'));
    final priceLabeled = labeledValue(text, RegExp(r'単価|金額|料金|価格|合計'));

    final address = addressLabeled != null
        ? AddressHit(addressLabeled.replaceAll(RegExp(r'[、。\s]+$'), ''), useTemplate ? 0.98 : 0.93)
        : findAddress(text);
    final phone = phoneLabeled != null
        ? (isValidJpPhone(phoneLabeled)
            ? PhoneHit(formatJpPhone(phoneLabeled), useTemplate ? 0.98 : 0.93, phoneLabeled)
            : PhoneHit('', 0.55, phoneLabeled))
        : findPhone(text);
    final date = dateLabeled != null
        ? (parseDateToken(dateLabeled, confidence: useTemplate ? 0.98 : 0.93) ?? DateHit('', 0.5, dateLabeled))
        : findDate(text);
    final price = priceLabeled != null
        ? () {
            final amount = parseYen(priceLabeled);
            if (amount == null) return YenHit(0, 0.5, priceLabeled);
            return YenHit(amount, useTemplate ? 0.98 : 0.93, priceLabeled);
          }()
        : findYen(text);

    final name = _nameField(text, nameRaw, useTemplate, address?.address, phone?.formatted);

    return [
      _finish('name', '顧客名', name.value, name.confidence, name.hint),
      _finish('address', '住所', address?.address ?? '', address?.confidence ?? 0, address == null ? null : null),
      _finish('phone', '電話番号', phone?.formatted ?? '', phone?.confidence ?? 0, phone != null && phone.formatted.isEmpty ? phone.raw : null),
      _finish('date', '契約日', date?.iso ?? '', date?.confidence ?? 0, date != null && date.iso.isEmpty ? date.raw : null),
      _finish(
        'price',
        '単価（1回）',
        price == null || price.amount < 1 ? '' : '${price.amount}',
        price?.confidence ?? 0,
        price != null && price.amount < 1 ? price.raw : null,
      ),
    ];
  }

  static OcrField _finish(String key, String label, String value, double confidence, String? hint) {
    if (confidence < 0.7 && value.isNotEmpty) {
      return OcrField(key: key, label: label, value: '', confidence: confidence, hint: hint ?? value);
    }
    return OcrField(key: key, label: label, value: value, confidence: confidence, hint: hint);
  }

  static _Name _nameField(String text, String? labeled, bool template, String? address, String? phone) {
    if (labeled != null && labeled.trim().isNotEmpty) {
      final value = labeled.trim();
      if (value.length > 100) {
        return _Name(value.substring(0, 100), 0.6, value);
      }
      return _Name(value, template ? 0.98 : 0.93, null);
    }
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.contains('FMT:CONTRACT-V1')) continue;
      if (line.length < 2 || line.length > 40) continue;
      if (address != null && line.contains(address)) continue;
      if (findAddress(line) != null) continue;
      if (findPhone(line) != null) continue;
      if (parseDateToken(line) != null) continue;
      if (RegExp(r'契約書|控え|様$').hasMatch(line) && !line.contains('店') && !line.contains('会社')) continue;
      if (phone != null && line.contains(phone)) continue;
      return _Name(line, 0.75, null);
    }
    return const _Name('', 0, null);
  }
}

class _Name {
  const _Name(this.value, this.confidence, this.hint);
  final String value;
  final double confidence;
  final String? hint;
}
