import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../models/models.dart';
import 'repository.dart';

const sampleOrgId = 'b0000000-0000-4000-8000-000000000001';
const sampleTaroId = 'c0000000-0000-4000-8000-000000000001';
const sampleHanakoId = 'c0000000-0000-4000-8000-000000000002';

const statusActiveId = 'a0000000-0000-4000-8000-000000000001';
const statusNegoId = 'a0000000-0000-4000-8000-000000000002';
const statusProspectId = 'a0000000-0000-4000-8000-000000000003';
const statusLostId = 'a0000000-0000-4000-8000-000000000004';

List<CustomerStatus> defaultStatuses() => const [
  CustomerStatus(id: statusActiveId, label: '契約中', colorHex: '#1A73E8', shape: 'check', sortOrder: 0, isDefault: true, hidden: false),
  CustomerStatus(id: statusNegoId, label: '商談中', colorHex: '#F9AB00', shape: 'diamond', sortOrder: 1, isDefault: true, hidden: false),
  CustomerStatus(id: statusProspectId, label: '見込み', colorHex: '#12B5CB', shape: 'ring', sortOrder: 2, isDefault: true, hidden: false),
  CustomerStatus(id: statusLostId, label: '解約・失注', colorHex: '#5F6368', shape: 'cross', sortOrder: 3, isDefault: true, hidden: false),
];

Customer _sample({
  required String id,
  required String name,
  required String phone,
  required String address,
  required String memo,
  required String statusId,
  required DateTime contractDate,
  required int price,
  required double lat,
  required double lng,
  String format = 'template',
}) {
  return Customer(
    id: id,
    orgId: sampleOrgId,
    ownerId: sampleTaroId,
    ownerName: '山田 太郎',
    name: name,
    phone: phone,
    address: address,
    memo: memo,
    lat: lat,
    lng: lng,
    locationSource: 'manual',
    statusId: statusId,
    version: 1,
    updatedAt: DateTime(2026, 11, 1, 9),
    contractId: 'k$id',
    contractDate: contractDate,
    unitPrice: price,
    contractFormat: format,
    pendingSync: false,
    sharedWithMe: false,
    updatedByName: '山田 太郎',
    baseVersion: 1,
  );
}

List<Customer> sampleCustomers() => [
  _sample(
    id: 'd0000000-0000-4000-8000-000000000001',
    name: '（サンプル）青葉工務店',
    phone: '090-0000-1101',
    address: '東京都架空区みどり町1-2-3',
    memo: '次回は屋根材の見積を持参。担当の佐藤さんは午前が都合よい。',
    statusId: statusActiveId,
    contractDate: DateTime(2026, 4, 1),
    price: 240000,
    lat: 35.6895,
    lng: 139.7700,
  ),
  _sample(
    id: 'd0000000-0000-4000-8000-000000000002',
    name: '（サンプル）さくら歯科',
    phone: '090-0000-1102',
    address: '東京都架空区さくら台4-5-6',
    memo: '院長は火曜午後が空いている。',
    statusId: statusActiveId,
    contractDate: DateTime(2026, 7, 15),
    price: 85000,
    lat: 35.6920,
    lng: 139.7780,
  ),
  _sample(
    id: 'd0000000-0000-4000-8000-000000000003',
    name: '（サンプル）海風ベーカリー',
    phone: '090-0000-1103',
    address: '東京都架空区港南2-8-1',
    memo: '店舗改装のあと再提案。',
    statusId: statusNegoId,
    contractDate: DateTime(2026, 9, 20),
    price: 32000,
    lat: 35.6805,
    lng: 139.7810,
    format: 'handwritten',
  ),
  _sample(
    id: 'd0000000-0000-4000-8000-000000000004',
    name: '（サンプル）北斗運送',
    phone: '090-0000-1104',
    address: '東京都架空区北原7-1-9',
    memo: '車両5台。来期予算の確認が必要。',
    statusId: statusProspectId,
    contractDate: DateTime(2026, 10, 2),
    price: 150000,
    lat: 35.6860,
    lng: 139.7600,
  ),
  _sample(
    id: 'd0000000-0000-4000-8000-000000000005',
    name: '（サンプル）ひなた薬局',
    phone: '090-0000-1105',
    address: '東京都架空区日向1-9-2',
    memo: '解約理由は価格。半年後に再訪。',
    statusId: statusLostId,
    contractDate: DateTime(2025, 12, 1),
    price: 45000,
    lat: 35.6760,
    lng: 139.7680,
  ),
  _sample(
    id: 'd0000000-0000-4000-8000-000000000006',
    name: '（サンプル）星野不動産',
    phone: '090-0000-1106',
    address: '東京都架空区星ケ丘5-3-8',
    memo: '管理物件が3棟。理事長はメール希望。',
    statusId: statusNegoId,
    contractDate: DateTime(2026, 8, 8),
    price: 380000,
    lat: 35.6740,
    lng: 139.7850,
    format: 'handwritten',
  ),
];

class SampleRepository implements AppRepository {
  SampleRepository({DateTime Function()? clock, String Function()? ids})
    : _clock = clock ?? DateTime.now,
      _ids = ids ?? _fallbackId;

  final DateTime Function() _clock;
  final String Function() _ids;
  final List<Customer> _customers = sampleCustomers();
  final List<CustomerStatus> _statuses = defaultStatuses();
  PriceTierConfig _tiers = PriceTierConfig.defaults;
  final List<CustomerShare> _shares = [
    const CustomerShare(
      customerId: 'd0000000-0000-4000-8000-000000000002',
      userId: sampleHanakoId,
      userName: '佐藤 花子',
      role: 'viewer',
    ),
    const CustomerShare(
      customerId: 'd0000000-0000-4000-8000-000000000003',
      userId: sampleHanakoId,
      userName: '佐藤 花子',
      role: 'editor',
    ),
  ];
  final List<SyncConflict> _conflicts = [];
  final Map<String, String> _images = {};

  static var _seq = 0;
  static String _fallbackId() => 'local-${++_seq}';

  @override
  bool get sampleMode => true;

  @override
  bool get isOnline => _online;

  bool _online = true;

  @override
  void setConnectivity(bool online) => _online = online;

  @override
  AppSession? get session => const AppSession(
    userId: sampleTaroId,
    displayName: '山田 太郎',
    orgId: sampleOrgId,
    role: 'admin',
  );

  @override
  Future<void> init() async {}

  @override
  Future<String?> signIn(String email, String password) async => 'サンプルモードではログインしません';

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String orgName,
  }) async => 'サンプルモードでは登録しません';

  @override
  Future<void> signOut() async {}

  @override
  Future<List<Customer>> loadCustomers() async => _customers.where((customer) => customer.version > 0).toList();

  @override
  Future<Customer> saveCustomer(Customer customer, {bool creating = false, bool appendContract = false}) async {
    final now = _clock();
    final saved = customer.copyWith(
      updatedAt: now,
      updatedByName: session!.displayName,
      pendingSync: false,
      version: creating ? 1 : customer.version + 1,
      baseVersion: creating ? 1 : customer.version + 1,
      contractId: customer.contractId ?? _ids(),
    );
    final index = _customers.indexWhere((item) => item.id == customer.id);
    if (index >= 0) {
      _customers[index] = saved;
    } else {
      _customers.add(saved);
    }
    return saved;
  }

  @override
  Future<void> archiveCustomer(String id) async {
    _customers.removeWhere((customer) => customer.id == id);
    _shares.removeWhere((share) => share.customerId == id);
  }

  @override
  Future<List<CustomerStatus>> loadStatuses() async {
    final copy = [..._statuses]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return copy;
  }

  @override
  Future<String?> saveStatus(CustomerStatus status, {bool creating = false}) async {
    final message = validateStatusEdit(_statuses, status);
    if (message != null) return message;
    if (creating) {
      _statuses.add(status);
    } else {
      final index = _statuses.indexWhere((item) => item.id == status.id);
      if (index < 0) return 'ステータスが見つかりません';
      final current = _statuses[index];
      if (current.isDefault && (current.label != status.label || current.colorHex != status.colorHex || current.shape != status.shape)) {
        if (session?.isAdmin != true) return '初期ステータスの名前と色の変更は管理者のみです';
      }
      _statuses[index] = status;
    }
    return null;
  }

  @override
  Future<String?> deleteStatus(String id, {String? moveToStatusId}) async {
    final status = _statuses.cast<CustomerStatus?>().firstWhere((item) => item!.id == id, orElse: () => null);
    if (status == null) return 'ステータスが見つかりません';
    if (status.isDefault) return '初期ステータスは削除できません。非表示にしてください';
    final used = _customers.where((customer) => customer.statusId == id).toList();
    if (used.isNotEmpty) {
      if (moveToStatusId == null || moveToStatusId == id) return '使用中です。移し替え先を選んでください';
      for (var i = 0; i < _customers.length; i++) {
        if (_customers[i].statusId == id) {
          _customers[i] = _customers[i].copyWith(statusId: moveToStatusId);
        }
      }
    }
    _statuses.removeWhere((item) => item.id == id);
    return null;
  }

  @override
  Future<void> reorderStatuses(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final index = _statuses.indexWhere((status) => status.id == orderedIds[i]);
      if (index >= 0) _statuses[index] = _statuses[index].copyWith(sortOrder: i);
    }
  }

  @override
  Future<PriceTierConfig> loadPriceTiers() async => _tiers;

  @override
  Future<String?> savePriceTiers(PriceTierConfig config) async {
    final message = config.validate();
    if (message != null) return message;
    _tiers = PriceTierConfig(List<int>.from(config.boundaries), personal: true);
    return null;
  }

  @override
  Future<List<OrgMember>> loadMembers() async => const [
    OrgMember(id: sampleTaroId, displayName: '山田 太郎', role: 'admin', active: true),
    OrgMember(id: sampleHanakoId, displayName: '佐藤 花子', role: 'member', active: true),
  ];

  @override
  Future<List<CustomerShare>> loadShares(String customerId) async =>
    _shares.where((share) => share.customerId == customerId).toList();

  @override
  Future<String?> invite({
    required String customerId,
    required String userId,
    required String role,
    DateTime? expiresAt,
  }) async {
    final customer = _customers.cast<Customer?>().firstWhere((item) => item!.id == customerId, orElse: () => null);
    if (customer == null) return '顧客が見つかりません';
    if (customer.ownerId != session!.userId && session!.role != 'admin') return '共有できるのは担当者か管理者です';
    if (userId == session!.userId) return '自分自身は招待できません';
    _shares.removeWhere((share) => share.customerId == customerId && share.userId == userId);
    final members = await loadMembers();
    final member = members.cast<OrgMember?>().firstWhere((item) => item!.id == userId, orElse: () => null);
    if (member == null || !member.active) return '同じ会社の有効な社員を選んでください';
    _shares.add(CustomerShare(customerId: customerId, userId: userId, userName: member.displayName, role: role, expiresAt: expiresAt));
    return null;
  }

  @override
  Future<String?> revokeShare(String customerId, String userId) async {
    _shares.removeWhere((share) => share.customerId == customerId && share.userId == userId);
    return null;
  }

  @override
  Future<List<SyncConflict>> loadConflicts() async => List<SyncConflict>.from(_conflicts);

  @override
  Future<void> resolveConflict({required SyncConflict conflict, required bool useDevice}) async {
    _conflicts.removeWhere((item) => item.id == conflict.id);
    if (!useDevice) return;
    final index = _customers.indexWhere((customer) => customer.id == conflict.customerId);
    if (index < 0) return;
    final current = _customers[index];
    _customers[index] = switch (conflict.field) {
      'memo' => current.copyWith(memo: conflict.deviceValue),
      'name' => current.copyWith(name: conflict.deviceValue),
      'phone' => current.copyWith(phone: conflict.deviceValue),
      'address' => current.copyWith(address: conflict.deviceValue),
      _ => current,
    };
  }

  @override
  Future<SyncReport> sync() async => const SyncReport(pushed: 0, conflicts: 0, message: 'サンプルデータは端末内だけです');

  @override
  Future<void> saveLocalImage(String customerId, String path) async {
    _images[customerId] = path;
    final index = _customers.indexWhere((customer) => customer.id == customerId);
    if (index >= 0) _customers[index] = _customers[index].copyWith(imageLocalPath: path);
  }
}
