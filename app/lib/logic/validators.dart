import 'text_parse.dart';

class CustomerDraft {
  const CustomerDraft({
    required this.name,
    required this.phone,
    required this.address,
    required this.memo,
    required this.contractDate,
    required this.price,
    required this.statusId,
    this.lat,
    this.lng,
    this.locationSource = 'pending',
  });

  final String name;
  final String phone;
  final String address;
  final String memo;
  final String contractDate;
  final int price;
  final String statusId;
  final double? lat;
  final double? lng;
  final String locationSource;

  CustomerDraft copyWith({
    String? name,
    String? phone,
    String? address,
    String? memo,
    String? contractDate,
    int? price,
    String? statusId,
    double? lat,
    double? lng,
    String? locationSource,
    bool clearLocation = false,
  }) {
    return CustomerDraft(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      memo: memo ?? this.memo,
      contractDate: contractDate ?? this.contractDate,
      price: price ?? this.price,
      statusId: statusId ?? this.statusId,
      lat: clearLocation ? null : (lat ?? this.lat),
      lng: clearLocation ? null : (lng ?? this.lng),
      locationSource: locationSource ?? this.locationSource,
    );
  }
}

class ValidationResult {
  const ValidationResult(this.errors, this.warnings);
  final Map<String, String> errors;
  final List<String> warnings;
  bool get ok => errors.isEmpty;
}

ValidationResult validateCustomer(CustomerDraft draft, {DateTime? today, bool requireLocation = false}) {
  final errors = <String, String>{};
  final warnings = <String>[];
  final name = draft.name.trim();
  if (name.isEmpty) {
    errors['name'] = '顧客名を入力してください';
  } else if (name.length > 100) {
    errors['name'] = '100文字以内で入力してください';
  }
  if (!isValidJpPhone(draft.phone)) {
    errors['phone'] = '10〜11桁の電話番号を入力してください';
  }
  if (draft.address.trim().isEmpty) {
    errors['address'] = '住所を入力してください';
  } else if (draft.address.trim().length > 300) {
    errors['address'] = '住所は300文字以内にしてください';
  }
  if (draft.price < 1) {
    errors['price'] = '1円以上で入力してください';
  }
  if (draft.statusId.isEmpty) {
    errors['status'] = 'ステータスを選択してください';
  }
  if (draft.memo.length > 4000) {
    errors['memo'] = 'メモは4000文字以内にしてください';
  }
  if (draft.contractDate.trim().isEmpty) {
    errors['date'] = '契約日を入力してください';
  } else {
    final parsed = DateTime.tryParse(draft.contractDate);
    if (parsed == null) {
      errors['date'] = '契約日を入力してください';
    } else {
      final clock = today ?? DateTime.now();
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      final todayDay = DateTime(clock.year, clock.month, clock.day);
      if (day.isAfter(todayDay)) warnings.add('未来の日付です');
    }
  }
  if (requireLocation && (draft.lat == null || draft.lng == null)) {
    errors['location'] = '地図を長押ししてピンの位置を指定してください';
  }
  return ValidationResult(errors, warnings);
}

String memoExcerpt(String memo, {int maxChars = 42}) {
  final flat = memo.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return '';
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars)}…';
}
