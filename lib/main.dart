import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/backup/backup_service.dart';
import 'core/database/app_database.dart';
import 'core/database/providers.dart';
import 'core/security/pin_service.dart';
import 'core/widgets/common.dart';
import 'features/inventory/inventory_service.dart';
import 'features/products/product_repository.dart';
import 'features/settings/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');

  final db = AppDatabase();
  final settingsRepo = SettingsRepository(db);
  final settings = await settingsRepo.load();
  Fmt.currency = settings.currency;

  // After a restore: verify the ledger and rebuild derived data.
  if (await BackupService.consumeRestoreMarker()) {
    final inv = InventoryService(db);
    if ((await inv.reconcile()).isNotEmpty) await inv.rebuildBalancesFromLedger();
    await ProductRepository(db).rebuildAllSearchText();
    await db.logActivity('restore', 'database', 'تمت استعادة نسخة احتياطية والتحقق من الأرصدة');
  }

  final locked = await PinService(settingsRepo).isEnabled();

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      initialSetupDoneProvider.overrideWithValue(settings.setupComplete),
      startLockedProvider.overrideWithValue(locked),
    ],
    child: const AutoPartsApp(),
  ));
}
