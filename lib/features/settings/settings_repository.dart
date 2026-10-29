import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';

abstract final class SettingKeys {
  static const setupComplete = 'setup_complete';
  static const businessName = 'business_name';
  static const currency = 'currency';
  static const allowNegativeStock = 'allow_negative_stock';
}

class BusinessSettings {
  final bool setupComplete;
  final String businessName;
  final String currency;
  final bool allowNegativeStock;

  const BusinessSettings({
    required this.setupComplete,
    required this.businessName,
    required this.currency,
    required this.allowNegativeStock,
  });
}

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value, updatedAt: Value(DateTime.now())),
        );
  }

  Future<BusinessSettings> load() async {
    final rows = await _db.select(_db.appSettings).get();
    final m = {for (final r in rows) r.key: r.value};
    return BusinessSettings(
      setupComplete: m[SettingKeys.setupComplete] == '1',
      businessName: m[SettingKeys.businessName] ?? '',
      currency: m[SettingKeys.currency] ?? 'ج.م',
      allowNegativeStock: m[SettingKeys.allowNegativeStock] == '1',
    );
  }

  Future<void> completeSetup({required String businessName, required String currency}) async {
    await _db.transaction(() async {
      await set(SettingKeys.businessName, businessName.trim());
      await set(SettingKeys.currency, currency.trim().isEmpty ? 'ج.م' : currency.trim());
      await set(SettingKeys.allowNegativeStock, '0');
      await set(SettingKeys.setupComplete, '1');
      await _db.logActivity('setup', 'settings', 'إتمام الإعداد الأولي: ${businessName.trim()}');
    });
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

class SettingsController extends AsyncNotifier<BusinessSettings> {
  @override
  Future<BusinessSettings> build() => ref.read(settingsRepositoryProvider).load();

  Future<void> completeSetup(String name, String currency) async {
    await ref.read(settingsRepositoryProvider).completeSetup(businessName: name, currency: currency);
    state = AsyncData(await ref.read(settingsRepositoryProvider).load());
  }

  Future<void> updateBusiness(String name, String currency) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.set(SettingKeys.businessName, name.trim());
    await repo.set(SettingKeys.currency, currency.trim());
    state = AsyncData(await repo.load());
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, BusinessSettings>(SettingsController.new);
