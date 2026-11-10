const syncFields = [
  'name',
  'phone',
  'address',
  'memo',
  'statusId',
  'lat',
  'lng',
  'locationSource',
  'contractDate',
  'unitPrice',
];

class FieldConflict {
  const FieldConflict(this.field, this.deviceValue, this.serverValue);
  final String field;
  final Object? deviceValue;
  final Object? serverValue;
}

class MergeResult {
  const MergeResult(this.merged, this.conflicts);
  final Map<String, Object?> merged;
  final List<FieldConflict> conflicts;
  bool get hasConflicts => conflicts.isNotEmpty;
}

/// 別項目は自動マージし、同じ項目はサーバー値を残して競合にする。
/// 手動ピン（locationSource=manual）は後からの住所変換で上書きしない。
MergeResult mergeCustomerFields({
  required Map<String, Object?> base,
  required Map<String, Object?> local,
  required Map<String, Object?> server,
}) {
  final merged = Map<String, Object?>.from(server);
  final conflicts = <FieldConflict>[];
  for (final field in syncFields) {
    final baseValue = base[field];
    final localValue = local[field];
    final serverValue = server[field];
    final localChanged = baseValue != localValue;
    final serverChanged = baseValue != serverValue;
    if (localChanged && !serverChanged) {
      merged[field] = localValue;
    } else if (localChanged && serverChanged && localValue != serverValue) {
      conflicts.add(FieldConflict(field, localValue, serverValue));
      merged[field] = serverValue;
    }
  }
  if (local['locationSource'] == 'manual') {
    merged['lat'] = local['lat'];
    merged['lng'] = local['lng'];
    merged['locationSource'] = 'manual';
    conflicts.removeWhere((conflict) => conflict.field == 'lat' || conflict.field == 'lng' || conflict.field == 'locationSource');
  }
  return MergeResult(merged, conflicts);
}

Map<String, Object?> applyConflictChoice({
  required Map<String, Object?> merged,
  required FieldConflict conflict,
  required bool useDevice,
}) {
  final next = Map<String, Object?>.from(merged);
  next[conflict.field] = useDevice ? conflict.deviceValue : conflict.serverValue;
  return next;
}
