import 'dart:convert';

import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../models/models.dart';

Map<String, Object?> customerToJson(Customer customer) => {
  'id': customer.id,
  'orgId': customer.orgId,
  'ownerId': customer.ownerId,
  'ownerName': customer.ownerName,
  'name': customer.name,
  'phone': customer.phone,
  'address': customer.address,
  'memo': customer.memo,
  'lat': customer.lat,
  'lng': customer.lng,
  'locationSource': customer.locationSource,
  'statusId': customer.statusId,
  'version': customer.version,
  'updatedAt': customer.updatedAt.toIso8601String(),
  'contractId': customer.contractId,
  'contractDate': customer.contractDate?.toIso8601String(),
  'unitPrice': customer.unitPrice,
  'contractFormat': customer.contractFormat,
  'ocrConfidence': customer.ocrConfidence,
  'imageLocalPath': customer.imageLocalPath,
  'imageStoragePath': customer.imageStoragePath,
  'photos': [for (final photo in customer.photos) photo.toJson()],
  'pendingSync': customer.pendingSync,
  'sharedWithMe': customer.sharedWithMe,
  'updatedByName': customer.updatedByName,
  'baseVersion': customer.baseVersion,
};

Customer customerFromJson(Map<String, dynamic> json) {
  return Customer(
    id: json['id'] as String,
    orgId: json['orgId'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? '',
    ownerName: json['ownerName'] as String? ?? '',
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    address: json['address'] as String? ?? '',
    memo: json['memo'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    locationSource: json['locationSource'] as String? ?? 'pending',
    statusId: json['statusId'] as String? ?? '',
    version: json['version'] as int? ?? 1,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    contractId: json['contractId'] as String?,
    contractDate: DateTime.tryParse(json['contractDate'] as String? ?? ''),
    unitPrice: json['unitPrice'] as int? ?? 0,
    contractFormat: json['contractFormat'] as String? ?? 'template',
    ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
    imageLocalPath: json['imageLocalPath'] as String?,
    imageStoragePath: json['imageStoragePath'] as String?,
    photos: CustomerPhoto.listFromJson(json['photos']),
    pendingSync: json['pendingSync'] as bool? ?? false,
    sharedWithMe: json['sharedWithMe'] as bool? ?? false,
    updatedByName: json['updatedByName'] as String?,
    baseVersion: json['baseVersion'] as int?,
  );
}

Map<String, Object?> statusToJson(CustomerStatus status) => {
  'id': status.id,
  'label': status.label,
  'colorHex': status.colorHex,
  'shape': status.shape,
  'sortOrder': status.sortOrder,
  'isDefault': status.isDefault,
  'hidden': status.hidden,
};

CustomerStatus statusFromJson(Map<String, dynamic> json) => CustomerStatus(
  id: json['id'] as String,
  label: json['label'] as String? ?? '',
  colorHex: json['colorHex'] as String? ?? '#1A73E8',
  shape: json['shape'] as String? ?? 'check',
  sortOrder: json['sortOrder'] as int? ?? 0,
  isDefault: json['isDefault'] as bool? ?? false,
  hidden: json['hidden'] as bool? ?? false,
);

String encodeTier(PriceTierConfig config) => jsonEncode({'boundaries': config.boundaries, 'personal': config.personal});

PriceTierConfig decodeTier(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return PriceTierConfig(List<int>.from(json['boundaries'] as List), personal: json['personal'] as bool? ?? false);
}

Map<String, dynamic> decodeMap(String raw) => jsonDecode(raw) as Map<String, dynamic>;
