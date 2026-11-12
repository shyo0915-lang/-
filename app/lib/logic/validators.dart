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

bool draftHasPin(CustomerDraft draft) => draft.lat != null && draft.lng != null;

/// 空の名前は、住所か「未入力の顧客」と日時で埋める。ステータスが空なら見込みを使う。
CustomerDraft prepareCustomerDraft(CustomerDraft draft, {DateTime? now, String fallbackStatusId = ''}) {
  final clock = now ?? DateTime.now();
  var name = draft.name.trim();
  final address = draft.address.trim();
  if (name.isEmpty) {
    if (address.isNotEmpty) {
      name = address.length > 100 ? address.substring(0, 100) : address;
    } else if (draftHasPin(draft)) {
      final stamp =
          '${clock.year}/${clock.month.toString().padLeft(2, '0')}/${clock.day.toString().padLeft(2, '0')} '
          '${clock.hour.toString().padLeft(2, '0')}:${clock.minute.toString().padLeft(2, '0')}';
      name = '未入力の顧客 $stamp';
    }
  }
  final hasPin = draftHasPin(draft);
  return draft.copyWith(
    name: name,
    statusId: draft.statusId.trim().isEmpty ? fallbackStatusId : draft.statusId,
    locationSource: hasPin ? (draft.locationSource == 'pending' ? 'manual' : draft.locationSource) : 'pending',
  );
}

ValidationResult validateCustomer(CustomerDraft draft, {DateTime? today, bool requireLocation = false}) {
  final errors = <String, String>{};
  final warnings = <String>[];
  final name = draft.name.trim();
  final hasPin = draftHasPin(draft);
  if (name.isEmpty && !hasPin) {
    errors['name'] = '顧客名を入力してください';
  } else if (name.length > 100) {
    errors['name'] = '100文字以内で入力してください';
  }
  final phone = draft.phone.trim();
  if (phone.isNotEmpty && !isValidJpPhone(phone)) {
    errors['phone'] = '10〜11桁の電話番号を入力してください';
  }
  final address = draft.address.trim();
  if (address.length > 300) {
    errors['address'] = '住所は300文字以内にしてください';
  }
  if (draft.price < 0) {
    errors['price'] = '0円以上で入力してください';
  }
  if (draft.memo.length > 4000) {
    errors['memo'] = 'メモは4000文字以内にしてください';
  }
  if (draft.contractDate.trim().isNotEmpty) {
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
  if (requireLocation && !hasPin && name.isEmpty) {
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
