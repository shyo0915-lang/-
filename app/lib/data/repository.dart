import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../models/models.dart';

abstract class AppRepository {
  bool get sampleMode;
  AppSession? get session;

  Future<void> init();
  Future<String?> signIn(String email, String password);
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String orgName,
  });
  Future<void> signOut();

  Future<List<Customer>> loadCustomers();
  Future<Customer> saveCustomer(Customer customer, {bool creating = false, bool appendContract = false});
  Future<void> archiveCustomer(String id);
  Future<List<CustomerStatus>> loadStatuses();
  Future<String?> saveStatus(CustomerStatus status, {bool creating = false});
  Future<String?> deleteStatus(String id, {String? moveToStatusId});
  Future<void> reorderStatuses(List<String> orderedIds);
  Future<PriceTierConfig> loadPriceTiers();
  Future<String?> savePriceTiers(PriceTierConfig config);
  Future<List<OrgMember>> loadMembers();
  Future<List<CustomerShare>> loadShares(String customerId);
  Future<String?> invite({
    required String customerId,
    required String userId,
    required String role,
    DateTime? expiresAt,
  });
  Future<String?> revokeShare(String customerId, String userId);
  Future<List<SyncConflict>> loadConflicts();
  Future<void> resolveConflict({required SyncConflict conflict, required bool useDevice});
  Future<SyncReport> sync();
  Future<void> saveLocalImage(String customerId, String path);
  bool get isOnline;
  void setConnectivity(bool online);
}
