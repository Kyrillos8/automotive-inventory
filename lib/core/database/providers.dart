import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Overridden in main() with the opened database instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});
