import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/customers/presentation/customer_screens.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/inventory/presentation/stock_screens.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/products/presentation/product_screens.dart';
import '../features/purchasing/presentation/purchasing_screens.dart';
import '../features/reports/presentation/report_screens.dart';
import '../features/sales/presentation/sales_screens.dart';
import '../features/settings/presentation/backup_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/setup/presentation/setup_screen.dart';

/// Overridden in main() with whether initial setup was already completed.
final initialSetupDoneProvider = Provider<bool>((ref) => false);

final routerProvider = Provider<GoRouter>((ref) {
  final setupDone = ref.watch(initialSetupDoneProvider);
  return GoRouter(
    initialLocation: setupDone ? '/' : '/setup',
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/products', builder: (_, __) => const ProductListScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/sales', builder: (_, __) => const SalesScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (_, __) => const MoreScreen(), routes: [
              GoRoute(path: 'purchases', builder: (_, __) => const PurchasesScreen()),
              GoRoute(path: 'customers', builder: (_, __) => const CustomersScreen()),
              GoRoute(path: 'suppliers', builder: (_, __) => const SuppliersScreen()),
              GoRoute(path: 'vehicles', builder: (_, __) => const VehiclesScreen()),
              GoRoute(path: 'tags', builder: (_, __) => const TagsScreen()),
              GoRoute(path: 'stocktaking', builder: (_, __) => const StocktakingListScreen()),
              GoRoute(path: 'reports', builder: (_, __) => const ReportsScreen()),
              GoRoute(path: 'activity', builder: (_, __) => const ActivityScreen()),
              GoRoute(path: 'settings', builder: (_, __) => const SettingsScreen()),
              GoRoute(path: 'backup', builder: (_, __) => const BackupScreen()),
            ]),
          ]),
        ],
      ),
    ],
  );
});

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.settings_input_component_outlined), selectedIcon: Icon(Icons.settings_input_component), label: 'المنتجات'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'المخزون'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'المبيعات'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'المزيد'),
        ],
      ),
    );
  }
}
