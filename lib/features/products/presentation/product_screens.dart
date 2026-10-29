import 'package:drift/drift.dart' show OrderingTerm, QueryRow, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/inventory_service.dart';
import '../../inventory/presentation/stock_screens.dart';
import '../../inventory/stock_documents_service.dart';
import '../../purchasing/purchasing_service.dart';
import '../product_providers.dart';
import '../product_repository.dart';
import 'pickers.dart';
import 'product_form_screen.dart';
import 'product_search_view.dart';

/// S03 — Product list.
class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات'), actions: [
        IconButton(
          tooltip: 'الوسوم',
          icon: const Icon(Icons.sell_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagsScreen())),
        ),
        IconButton(
          tooltip: 'السيارات',
          icon: const Icon(Icons.directions_car_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VehiclesScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_product',
        onPressed: () => openProductForm(context),
        icon: const Icon(Icons.add),
        label: const Text('منتج جديد'),
      ),
      body: ProductSearchView(onTap: (p) => openProductDetails(context, p.id)),
    );
  }
}

Future<void> openProductForm(BuildContext context, {int? id}) async {
  final newId = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => ProductFormScreen(productId: id)));
  if (newId != null && id == null && context.mounted) {
    await openProductDetails(context, newId);
  }
}

Future<void> openProductDetails(BuildContext context, int id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: id)));

class _Details {
  final ProductListItem item;
  final Product product;
  final List<CompatView> compat;
  final List<ProductSpec> specs;
  final List<StockMovement> moves;
  final List<QueryRow> costs;
  final List<QueryRow> sales;
  final bool hasOpening;
  _Details(this.item, this.product, this.compat, this.specs, this.moves, this.costs, this.sales, this.hasOpening);
}

/// S05 — Product details.
class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final int productId;
  @override
  ConsumerState<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  int _v = 0;

  Future<_Details> _load() async {
    final db = ref.read(databaseProvider);
    final repo = ref.read(productRepositoryProvider);
    final id = widget.productId;
    final item = await repo.item(id);
    if (item == null) throw Exception('المنتج غير موجود');
    final product = await (db.select(db.products)..where((t) => t.id.equals(id))).getSingle();
    final moves = await (db.select(db.stockMovements)
          ..where((t) => t.productId.equals(id))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(20))
        .get();
    final opening = await (db.select(db.stockMovements)
          ..where((t) => t.productId.equals(id) & t.movementType.equals(MovementType.opening)))
        .get();
    final sales = await db.customSelect('''
      SELECT s.invoice_number, s.invoice_date, l.quantity, l.unit_price, l.price_type, COALESCE(c.name,'عميل نقدي') AS cname
      FROM sale_lines l JOIN sales s ON s.id = l.sale_id LEFT JOIN customers c ON c.id = s.customer_id
      WHERE l.product_id = ? AND s.status = 'posted' ORDER BY s.id DESC LIMIT 20
    ''', variables: [Variable.withInt(id)]).get();
    return _Details(
      item,
      product,
      await repo.compatibilityOf(id),
      await (db.select(db.productSpecs)..where((t) => t.productId.equals(id))).get(),
      moves,
      await ref.read(purchasingServiceProvider).costHistory(id),
      sales,
      opening.isNotEmpty,
    );
  }

  void _refresh() => setState(() => _v++);

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogVersionProvider, (_, __) => _refresh());
    return FutureLoader<_Details>(
      reloadKey: _v,
      load: _load,
      builder: (context, d, reload) {
        final p = d.product;
        final i = d.item;
        return Scaffold(
          appBar: AppBar(title: Text(p.nameAr), actions: [
            IconButton(icon: const Icon(Icons.edit), tooltip: 'تعديل', onPressed: () => openProductForm(context, id: p.id)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'archive':
                  case 'activate':
                    final ok = await confirm(context, v == 'archive' ? 'أرشفة المنتج' : 'إعادة التفعيل',
                        v == 'archive' ? 'لن يظهر المنتج في البحث، ويبقى سجله ورصيده كما هو.' : 'سيظهر المنتج مجددًا في البحث.');
                    if (!ok || !context.mounted) return;
                    await runAction(context, () => ref.read(productRepositoryProvider).setActive(p.id, v == 'activate'));
                    if (context.mounted) bumpCatalog(ref);
                  case 'history':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => StockHistoryScreen(productId: p.id, name: p.nameAr)));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'history', child: Text('سجل حركة المخزون')),
                PopupMenuItem(value: p.isActive ? 'archive' : 'activate', child: Text(p.isActive ? 'أرشفة' : 'إعادة تفعيل')),
              ],
            ),
          ]),
          body: RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('المخزون الحالي', style: Theme.of(context).textTheme.titleMedium)),
                      StockBadge(quantity: i.quantity, status: i.stockStatus, unit: i.unitName),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      if (!d.hasOpening)
                        ActionChip(
                          avatar: const Icon(Icons.flag_outlined, size: 18),
                          label: const Text('رصيد افتتاحي'),
                          onPressed: () => _stockDoc(StockDocKind.opening, i),
                        ),
                      ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('إضافة'), onPressed: () => _stockDoc(StockDocKind.receipt, i)),
                      ActionChip(avatar: const Icon(Icons.remove, size: 18), label: const Text('صرف'), onPressed: () => _stockDoc(StockDocKind.issue, i)),
                      ActionChip(avatar: const Icon(Icons.tune, size: 18), label: const Text('تسوية'), onPressed: () => _stockDoc(StockDocKind.adjustment, i)),
                    ]),
                    if (!p.isActive) const Padding(padding: EdgeInsets.only(top: 8), child: Text('⚠️ هذا المنتج مؤرشف')),
                  ]),
                ),
              ),
              _section('البيانات الأساسية', [
                InfoRow('الاسم بالإنجليزية', p.nameEn, ltr: true),
                InfoRow('النوع', i.typeName),
                InfoRow('الماركة', i.brandName),
                InfoRow('الكود الداخلي', p.internalSku, ltr: true),
                InfoRow('الباركود', p.barcode, ltr: true),
                InfoRow('كود T.C', p.tcCode, ltr: true),
                InfoRow('بلد المنشأ', p.countryOfOrigin),
                InfoRow('الوصف', p.description),
              ]),
              _section('المواصفات', [
                InfoRow('القطر', p.diameterMm == null ? null : '${formatMm(p.diameterMm!)} مم'),
                InfoRow('المقاس', p.sizeDesignation),
                InfoRow('أبعاد الشنبر', p.ringDimensions, ltr: true),
                InfoRow('سعة المحرك', p.engineCapacity),
                InfoRow('السلندرات', p.cylinders?.toString()),
                InfoRow('كود المحرك', p.engineCode, ltr: true),
                InfoRow('قطر البنز', p.pinDiameterMm == null ? null : '${formatMm(p.pinDiameterMm!)} مم'),
                InfoRow('ارتفاع الضغط', p.compressionHeightMm == null ? null : '${formatMm(p.compressionHeightMm!)} مم'),
                for (final s in d.specs) InfoRow(s.specKey, s.textValue),
                InfoRow('ملاحظات الملصق', p.labelNotes),
              ]),
              _section('الأسعار', [
                InfoRow('تكلفة الشراء الافتراضية', Fmt.money(p.purchasePrice)),
                InfoRow('متوسط التكلفة الفعلي', Fmt.money(i.avgCost)),
                InfoRow('سعر الجملة', Fmt.money(p.wholesalePrice)),
                InfoRow('سعر القطاعي', Fmt.money(p.retailPrice)),
                InfoRow('حد إعادة الطلب', p.minimumStock == 0 ? null : Fmt.qty(p.minimumStock)),
                InfoRow('الحد الأقصى', p.maximumStock == null ? null : Fmt.qty(p.maximumStock!)),
              ]),
              _section('السيارات المتوافقة (${d.compat.length})', [
                if (d.compat.isEmpty) const Text('لا توجد سيارات مرتبطة'),
                for (final c in d.compat)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(c.status == 'confirmed' ? Icons.verified : Icons.help_outline,
                        color: c.status == 'confirmed' ? Colors.green : Colors.orange),
                    title: Text(c.label),
                    subtitle: c.notes == null ? null : Text(c.notes!),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off),
                      tooltip: 'إزالة التوافق',
                      onPressed: () async {
                        final ok = await confirm(context, 'إزالة التوافق', 'إزالة ${c.label} من هذا المنتج؟ لن يُحذف المنتج.');
                        if (!ok || !context.mounted) return;
                        await runAction(context, () => ref.read(productRepositoryProvider).removeCompatibility(c.id));
                        if (context.mounted) bumpCatalog(ref);
                      },
                    ),
                  ),
              ]),
              _section('الوسوم', [i.tags.isEmpty ? const Text('لا توجد وسوم') : TagChips(i.tags, max: 100)]),
              _section('آخر حركات المخزون', [
                if (d.moves.isEmpty) const Text('لا توجد حركات'),
                for (final m in d.moves)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(MovementType.label(m.movementType)),
                    subtitle: Text(Fmt.dateTime(m.occurredAt)),
                    trailing: Text('${m.quantityDelta > 0 ? '+' : ''}${Fmt.qty(m.quantityDelta)} ← ${Fmt.qty(m.balanceAfter)}',
                        textDirection: TextDirection.ltr),
                  ),
              ]),
              _section('سجل أسعار الشراء', [
                if (d.costs.isEmpty) const Text('لا توجد مشتريات'),
                for (final r in d.costs)
                  InfoRow('${Fmt.date(r.read<DateTime>('received_at'))} • ${r.read<String>('supplier')}',
                      '${Fmt.qty(r.read<int>('received_quantity'))} × ${Fmt.money(r.read<int>('unit_cost'))}'),
              ]),
              _section('آخر المبيعات', [
                if (d.sales.isEmpty) const Text('لا توجد مبيعات'),
                for (final r in d.sales)
                  InfoRow('${r.read<String>('invoice_number')} • ${r.read<String>('cname')}',
                      '${Fmt.qty(r.read<int>('quantity'))} × ${Fmt.money(r.read<int>('unit_price'))}'),
              ]),
              if (p.notes != null) _section('ملاحظات', [Text(p.notes!)]),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _stockDoc(String kind, ProductListItem i) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => StockDocFormScreen(kind: kind, initialProduct: i)));
    if (ok == true && mounted) bumpCatalog(ref);
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            ...children,
          ]),
        ),
      );
}

/// S06 — Tag management.
class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});
  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(productRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الوسوم')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_tag',
        onPressed: () async {
          final n = await promptText(context, 'وسم جديد', label: 'اسم الوسم');
          if (n != null && context.mounted) await runAction(context, () => repo.createTag(n), success: 'تمت الإضافة');
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في الوسوم'),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TagWithCount>>(
            stream: repo.watchTagsWithCounts(filter: _filter),
            builder: (c, s) {
              if (s.hasError) return ErrorView(error: s.error!);
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final list = s.data!;
              if (list.isEmpty) return const EmptyView(icon: Icons.sell_outlined, title: 'لا توجد وسوم');
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final t = list[i];
                  return ListTile(
                    leading: Icon(Icons.sell, color: t.tag.isActive ? null : Colors.grey),
                    title: Text(t.tag.name, style: TextStyle(color: t.tag.isActive ? null : Colors.grey)),
                    subtitle: Text('${t.count} منتج${t.tag.isActive ? '' : ' • مؤرشف'}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text('منتجات: ${t.tag.name}')),
                          body: ProductSearchView(
                            initialQuery: ProductQuery(tagIds: {t.tag.id}, includeArchived: true),
                            onTap: (p) => openProductDetails(context, p.id),
                          ),
                        ),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'rename':
                            final n = await promptText(context, 'إعادة تسمية', initial: t.tag.name);
                            if (n != null && context.mounted) {
                              await runAction(context, () => repo.renameTag(t.tag.id, n), success: 'تم التعديل');
                              if (context.mounted) bumpCatalog(ref);
                            }
                          case 'archive':
                            await repo.setTagActive(t.tag.id, !t.tag.isActive);
                          case 'delete':
                            if (await confirm(context, 'حذف الوسم', 'حذف "${t.tag.name}"؟', destructive: true) && context.mounted) {
                              await runAction(context, () => repo.deleteTag(t.tag.id), success: 'تم الحذف');
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                        PopupMenuItem(value: 'archive', child: Text(t.tag.isActive ? 'أرشفة' : 'إعادة تفعيل')),
                        if (t.count == 0) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// S07/S08 — Vehicle makes & models; browse compatible products per model.
class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final makes = ref.watch(makesProvider);
    final repo = ref.read(productRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('توافق السيارات')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_make',
        onPressed: () async {
          final r = await askVehicleNames(context, 'ماركة سيارة جديدة');
          if (r != null && context.mounted) await runAction(context, () => repo.addMake(r.$1, r.$2));
        },
        icon: const Icon(Icons.add),
        label: const Text('ماركة'),
      ),
      body: makes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (list) => list.isEmpty
            ? const EmptyView(icon: Icons.directions_car, title: 'لا توجد ماركات', message: 'أضف ماركات السيارات وموديلاتها لربطها بالمنتجات.')
            : ListView(children: [
                for (final m in list)
                  ExpansionTile(
                    leading: const Icon(Icons.directions_car),
                    title: Text(m.nameEn == null ? m.nameAr : '${m.nameAr} (${m.nameEn})'),
                    children: [_ModelsList(make: m)],
                  ),
              ]),
      ),
    );
  }
}

class _ModelsList extends ConsumerWidget {
  const _ModelsList({required this.make});
  final VehicleMake make;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(modelsProvider(make.id)).valueOrNull ?? [];
    final repo = ref.read(productRepositoryProvider);
    return Column(children: [
      for (final md in models)
        ListTile(
          contentPadding: const EdgeInsetsDirectional.only(start: 56, end: 8),
          title: Text(md.nameEn == null ? md.nameAr : '${md.nameAr} (${md.nameEn})'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text('${make.nameAr} ${md.nameAr}')),
                body: ProductSearchView(
                  initialQuery: ProductQuery(makeId: make.id, modelId: md.id),
                  onTap: (p) => openProductDetails(context, p.id),
                ),
              ),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final r = await askVehicleNames(context, 'تعديل الموديل');
              if (r != null && context.mounted) {
                await runAction(context, () => repo.renameModel(md.id, r.$1, r.$2));
                if (context.mounted) bumpCatalog(ref);
              }
            },
          ),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text('تعديل الماركة'),
          onPressed: () async {
            final r = await askVehicleNames(context, 'تعديل الماركة');
            if (r != null && context.mounted) {
              await runAction(context, () => repo.renameMake(make.id, r.$1, r.$2));
              if (context.mounted) bumpCatalog(ref);
            }
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('موديل'),
          onPressed: () async {
            final r = await askVehicleNames(context, 'موديل جديد لـ ${make.nameAr}');
            if (r != null && context.mounted) await runAction(context, () => repo.addModel(make.id, r.$1, r.$2));
          },
        ),
      ]),
    ]);
  }
}
