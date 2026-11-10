const statusShapes = ['check', 'diamond', 'ring', 'cross', 'star', 'square'];

const statusPalette = [
  '#1A73E8',
  '#F9AB00',
  '#12B5CB',
  '#5F6368',
  '#E37400',
  '#1E8E3E',
  '#D93025',
  '#9334E6',
];

class CustomerStatus {
  const CustomerStatus({
    required this.id,
    required this.label,
    required this.colorHex,
    required this.shape,
    required this.sortOrder,
    required this.isDefault,
    required this.hidden,
  });

  final String id;
  final String label;
  final String colorHex;
  final String shape;
  final int sortOrder;
  final bool isDefault;
  final bool hidden;

  CustomerStatus copyWith({
    String? label,
    String? colorHex,
    String? shape,
    int? sortOrder,
    bool? hidden,
  }) {
    return CustomerStatus(
      id: id,
      label: label ?? this.label,
      colorHex: colorHex ?? this.colorHex,
      shape: shape ?? this.shape,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault,
      hidden: hidden ?? this.hidden,
    );
  }
}

String? validateStatusEdit(List<CustomerStatus> existing, CustomerStatus next) {
  final label = next.label.trim();
  if (label.isEmpty) return '名前を入力してください';
  if (label.length > 20) return '名前は20文字以内にしてください';
  if (!statusShapes.contains(next.shape)) return '形を選んでください';
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(next.colorHex)) return '色を選んでください';
  final isNew = existing.every((status) => status.id != next.id);
  if (isNew && existing.length >= 10) return 'ステータスは10個までです';
  final clash = existing.any(
    (status) =>
        status.id != next.id &&
        status.colorHex.toLowerCase() == next.colorHex.toLowerCase() &&
        status.shape == next.shape,
  );
  if (clash) return '同じ色と形の組み合わせは使えません';
  return null;
}
