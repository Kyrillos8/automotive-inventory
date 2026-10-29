import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/inventory_service.dart';
import '../../inventory/presentation/stock_screens.dart';
import '../../inventory/stock_documents_service.dart';
import '../../products/presentation/product_screens.dart';
import '../../products/presentation/product_search_view.dart';
import '../../products/product_providers.dart';
import '../../products/product_repository.dart';
import '../../purchasing/presentation/purchasing_screens.dart';
import '../../reports/reports_service.dart';
import '../../sales/presentation/sales_screens.dart';
import '../../settings/settings_repository.dart';

class _DashData {
  final DashboardMetrics m;
  final List<ProductListItem> low;
  final List<StockMovement> moves;
  final Map<int, String> names;
  _DashData(this.m, this.low, this.moves, this.names);
}

/// S02 — Dashboard. Every number comes from the local database.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _v = 0;

  Future<_DashData> _load() async {
    final db = ref.read(databaseProvider);
    final n = DateTime.now();
    final from = DateTime(n.year, n.month, 1);
    final to = DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
    final m = await ref.read(reportsServiceProvider).dashboard(from, to);
    final low = [
      ...await ref.read(productRepositoryProvider).search(const ProductQuery(stockStatus: 'out', limit: 5)),
      ...await ref.read(productRepositoryProvider).search(const ProductQuery(stockStatus: 'low', limit: 5)),
    ];
    final moves = await (db.select(db.stockMovements)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(8))
        .get();
    final ids = moves.map((e) => e.productId).toSet();
    final products = ids.isEmpty ? <Product>[] : await (db.select(db.products)..where((t) => t.id.isIn(ids))).get();
    return _DashData(m, low, moves, {for (final p in products) p.id: p.nameAr});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogVersionProvider, (_, __) => setState(() => _v++));
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(settings?.businessName.isNotEmpty == true ? settings!.businessName : 'الرئيسية')),
      body: FutureLoader<_DashData>(
        reloadKey: _v,
        load: _load,
        builder: (context, d, reload) {
          final m = d.m;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _v++),
            child: ListView(padding: const EdgeInsets.all(8), children: [
              _shortcuts(context),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.9,
                children: [
                  _Metric('مبيعات اليوم', Fmt.money(m.todaySales), Icons.today, Colors.blue),
                  _Metric('مبيعات الشهر', Fmt.money(m.periodSales), Icons.calendar_month, Colors.indigo),
                  _Metric('جملة (الشهر)', Fmt.money(m.wholesaleSales), Icons.store, Colors.teal),
                  _Metric('قطاعي (الشهر)', Fmt.money(m.retailSales), Icons.person, Colors.cyan),
                  _Metric('مستحقات العملاء', Fmt.money(m.receivables), Icons.account_balance_wallet, Colors.red),
                  _Metric('قيمة المخزون', Fmt.money(m.inventoryValue), Icons.inventory, Colors.brown),
                  _Metric('المنتجات النشطة', '${m.activeProducts}', Icons.settings_input_component, Colors.blueGrey),
                  _Metric('إجمالي الوحدات', Fmt.qty(m.totalUnits), Icons.widgets, Colors.green),
                  _Metric('منخفض المخزون', '${m.lowStock}', Icons.warning_amber, Colors.orange),
                  _Metric('نفد المخزون', '${m.outOfStock}', Icons.remove_shopping_cart, Colors.deepOrange),
                  _Metric('أوامر شراء معلقة', '${m.pendingPos}', Icons.local_shipping, Colors.purple),
                ],
              ),
              if (d.low.isNotEmpty) ...[
                const SectionTitle('تنبيهات المخزون'),
                for (final p in d.low)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.warning, color: p.stockStatus == 'out' ? Colors.red : Colors.orange),
                    title: Text(p.nameAr),
                    subtitle: Text('الحد الأدنى ${Fmt.qty(p.minimumStock)}'),
                    trailing: StockBadge(quantity: p.quantity, status: p.stockStatus),
                    onTap: () => openProductDetails(context, p.id),
                  ),
              ],
              const SectionTitle('آخر حركات المخزون'),
              if (d.moves.isEmpty) const EmptyView(icon: Icons.swap_vert, title: 'لا توجد حركات بعد'),
              for (final mv in d.moves)
                ListTile(
                  dense: true,
                  title: Text(d.names[mv.productId] ?? ''),
                  subtitle: Text('${MovementType.label(mv.movementType)} • ${Fmt.dateTime(mv.occurredAt)}'),
                  trailing: Text('${mv.quantityDelta > 0 ? '+' : ''}${Fmt.qty(mv.quantityDelta)}', textDirection: TextDirection.ltr),
                ),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }

  Widget _shortcuts(BuildContext context) {
    Future<void> go(Widget w) async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
      if (mounted) setState(() => _v++);
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      ActionChip(avatar: const Icon(Icons.add_box_outlined), label: const Text('إضافة منتج'), onPressed: () async {
        await openProductForm(context);
        if (mounted) setState(() => _v++);
      }),
      ActionChip(avatar: const Icon(Icons.receipt_long), label: const Text('إنشاء فاتورة بيع'), onPressed: () => go(const InvoiceBuilderScreen())),
      ActionChip(avatar: const Icon(Icons.local_shipping_outlined), label: const Text('تسجيل مشتريات'), onPressed: () => go(const PurchasesScreen())),
      ActionChip(avatar: const Icon(Icons.inventory_2_outlined), label: const Text('إضافة مخزون'), onPressed: () => go(const StockDocFormScreen(kind: StockDocKind.receipt))),
      ActionChip(avatar: const Icon(Icons.fact_check_outlined), label: const Text('إجراء جرد'), onPressed: () => go(const StocktakingListScreen())),
      ActionChip(avatar: const Icon(Icons.bar_chart), label: const Text('عرض التقارير'), onPressed: () => context.push('/more/reports')),
      ActionChip(avatar: const Icon(Icons.search), label: const Text('بحث سريع'), onPressed: () async {
        final p = await pickProduct(context, title: 'بحث عن منتج');
        if (p != null && context.mounted) openProductDetails(context, p.id);
      }),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      );
}
