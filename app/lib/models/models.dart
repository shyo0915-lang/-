import '../logic/status_rules.dart';

class OrgMember {
  const OrgMember({required this.id, required this.displayName, required this.role, required this.active});
  final String id;
  final String displayName;
  final String role;
  final bool active;
}

class CustomerShare {
  const CustomerShare({
    required this.customerId,
    required this.userId,
    required this.userName,
    required this.role,
    this.expiresAt,
  });

  final String customerId;
  final String userId;
  final String userName;
  final String role;
  final DateTime? expiresAt;
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.field,
    required this.deviceValue,
    required this.serverValue,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String field;
  final String deviceValue;
  final String serverValue;
}

class CustomerPhoto {
  const CustomerPhoto({
    required this.id,
    this.localPath,
    this.storagePath,
    this.pending = false,
  });

  final String id;
  final String? localPath;
  final String? storagePath;
  final bool pending;

  CustomerPhoto copyWith({String? localPath, String? storagePath, bool? pending}) {
    return CustomerPhoto(
      id: id,
      localPath: localPath ?? this.localPath,
      storagePath: storagePath ?? this.storagePath,
      pending: pending ?? this.pending,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'localPath': localPath,
    'storagePath': storagePath,
    'pending': pending,
  };

  static CustomerPhoto fromJson(Map<String, dynamic> json) {
    return CustomerPhoto(
      id: json['id'] as String,
      localPath: json['localPath'] as String?,
      storagePath: json['storagePath'] as String?,
      pending: json['pending'] as bool? ?? false,
    );
  }

  static List<CustomerPhoto> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) CustomerPhoto.fromJson(Map<String, dynamic>.from(item)),
    ];
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.phone,
    required this.address,
    required this.memo,
    required this.lat,
    required this.lng,
    required this.locationSource,
    required this.statusId,
    required this.version,
    required this.updatedAt,
    required this.contractId,
    required this.contractDate,
    required this.unitPrice,
    required this.contractFormat,
    required this.pendingSync,
    required this.sharedWithMe,
    this.ocrConfidence,
    this.imageLocalPath,
    this.imageStoragePath,
    this.photos = const [],
    this.updatedByName,
    this.baseVersion,
  });

  final String id;
  final String orgId;
  final String ownerId;
  final String ownerName;
  final String name;
  final String phone;
  final String address;
  final String memo;
  final double? lat;
  final double? lng;
  final String locationSource;
  final String statusId;
  final int version;
  final DateTime updatedAt;
  final String? contractId;
  final DateTime? contractDate;
  final int unitPrice;
  final String contractFormat;
  final double? ocrConfidence;
  final String? imageLocalPath;
  final String? imageStoragePath;
  final List<CustomerPhoto> photos;
  final bool pendingSync;
  final bool sharedWithMe;
  final String? updatedByName;
  final int? baseVersion;

  bool get hasLocation => lat != null && lng != null;

  Customer copyWith({
    String? ownerId,
    String? ownerName,
    String? name,
    String? phone,
    String? address,
    String? memo,
    double? lat,
    double? lng,
    String? locationSource,
    String? statusId,
    int? version,
    DateTime? updatedAt,
    String? contractId,
    DateTime? contractDate,
    int? unitPrice,
    String? contractFormat,
    double? ocrConfidence,
    String? imageLocalPath,
    String? imageStoragePath,
    List<CustomerPhoto>? photos,
    bool? pendingSync,
    bool? sharedWithMe,
    String? updatedByName,
    int? baseVersion,
    bool clearImage = false,
  }) {
    return Customer(
      id: id,
      orgId: orgId,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      memo: memo ?? this.memo,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      locationSource: locationSource ?? this.locationSource,
      statusId: statusId ?? this.statusId,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      contractId: contractId ?? this.contractId,
      contractDate: contractDate ?? this.contractDate,
      unitPrice: unitPrice ?? this.unitPrice,
      contractFormat: contractFormat ?? this.contractFormat,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      imageLocalPath: clearImage ? null : (imageLocalPath ?? this.imageLocalPath),
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      photos: photos ?? this.photos,
      pendingSync: pendingSync ?? this.pendingSync,
      sharedWithMe: sharedWithMe ?? this.sharedWithMe,
      updatedByName: updatedByName ?? this.updatedByName,
      baseVersion: baseVersion ?? this.baseVersion,
    );
  }

  Map<String, Object?> toSyncMap() => {
    'name': name,
    'phone': phone,
    'address': address,
    'memo': memo,
    'statusId': statusId,
    'lat': lat,
    'lng': lng,
    'locationSource': locationSource,
    'contractDate': contractDate == null
        ? ''
        : '${contractDate!.year.toString().padLeft(4, '0')}-${contractDate!.month.toString().padLeft(2, '0')}-${contractDate!.day.toString().padLeft(2, '0')}',
    'unitPrice': unitPrice,
  };
}

class SyncReport {
  const SyncReport({required this.pushed, required this.conflicts, required this.message});
  final int pushed;
  final int conflicts;
  final String message;
}

class AppSession {
  const AppSession({
    required this.userId,
    required this.displayName,
    required this.orgId,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String orgId;
  final String role;
  bool get isAdmin => role == 'admin';
}

typedef StatusList = List<CustomerStatus>;
