import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../product_providers.dart';
import '../product_repository.dart';

/// THE reusable product search component. Used by the catalog, inventory,
/// sales invoices, purchase orders, receipts, stock forms and stocktaking.
class ProductSearchView extends ConsumerStatefulWidget {
  const ProductSearchView({
    super.key,
    required this.onTap,
    this.initialQuery = const ProductQuery(),
    this.showCost = false,
    this.trailingBuilder,
    this.autofocus = false,
  });
  final void Function(ProductListItem) onTap;
  final ProductQuery initialQuery;
  final bool showCost;
  final Widget Function(ProductListItem)? trailingBuilder;
  final bool autofocus;

  @override
  ConsumerState<ProductSearchView> createState() => _ProductSearchViewState();
}

class _ProductSearchViewState extends ConsumerState<ProductSearchView> {
  late ProductQuery _q = widget.initialQuery;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<ProductListItem> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _text.text = _q.text;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_loading && _hasMore) _load(more: true);
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(productRepositoryProvider);
      final q = ProductQuery(
        text: _q.text,
        productTypeId: _q.productTypeId,
        brandId: _q.brandId,
        categoryId: _q.categoryId,
        tagIds: _q.tagIds,
        tagsMatchAll: _q.tagsMatchAll,
        makeId: _q.makeId,
        modelId: _q.modelId,
        engineFilter: _q.engineFilter,
        stockStatus: _q.stockStatus,
        includeArchived: _q.includeArchived,
        sort: _q.sort,
        limit: 50,
        offset: more ? _items.length : 0,
      );
      final r = await repo.search(q);
      if (gen != _gen || !mounted) return;
      setState(() {
        _items = more ? [..._items, ...r] : r;
        _hasMore = r.length == 50;
        _loading = false;
      });
    } catch (e) {
      if (gen != _gen || !mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onText(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _q = _q.copyWith(text: v);
      _load();
    });
  }

  Future<void> _openFilters() async {
    final r = await showModalBottomSheet<ProductQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductFilterSheet(initial: _q),
    );
    if (r != null) {
      setState(() => _q = r);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogVersionProvider, (_, __) => _load());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: widget.autofocus,
              onChanged: _onText,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم، الكود، T.C، المقاس، السيارة، الوسم...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _text.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _text.clear();
                          _onText('');
                        }),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Badge(
            isLabelVisible: _q.hasFilters,
            child: IconButton.filledTonal(onPressed: _openFilters, icon: const Icon(Icons.filter_list)),
          ),
        ]),
      ),
      if (_q.hasFilters) _ActiveFilters(q: _q, onClear: () {
        setState(() => _q = ProductQuery(text: _q.text, sort: _q.sort));
        _load();
      }),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: _q.text.isEmpty && !_q.hasFilters ? 'لا توجد منتجات بعد' : 'لا توجد نتائج مطابقة',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (c, i) {
          if (i >= _items.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          final p = _items[i];
          return ProductTile(p, showCost: widget.showCost, onTap: () => widget.onTap(p), trailing: widget.trailingBuilder?.call(p));
        },
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile(this.p, {super.key, this.onTap, this.showCost = false, this.trailing});
  final ProductListItem p;
  final VoidCallback? onTap;
  final bool showCost;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = TextStyle(color: t.colorScheme.outline, fontSize: 12);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nameAr, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (p.nameEn != null) Text(p.nameEn!, style: muted, textDirection: TextDirection.ltr),
                ]),
              ),
              if (!p.isActive)
                const Padding(padding: EdgeInsetsDirectional.only(end: 6), child: Chip(label: Text('مؤرشف'), visualDensity: VisualDensity.compact)),
              StockBadge(quantity: p.quantity, status: p.stockStatus, unit: p.unitName),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 2, children: [
              Text(p.typeName, style: muted),
              if (p.brandName != null) Text(p.brandName!, style: muted),
              Text(p.sku, style: muted, textDirection: TextDirection.ltr),
              if (p.tcCode != null) Text('T.C ${p.tcCode}', style: muted, textDirection: TextDirection.ltr),
            ]),
            if (p.specSummary.isNotEmpty) Text(p.specSummary, style: const TextStyle(fontSize: 13)),
            if (p.vehicles != null)
              Text('🚗 ${p.vehicles}', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Wrap(spacing: 12, children: [
                  Text('جملة: ${Fmt.money(p.wholesalePrice)}', style: const TextStyle(fontSize: 12)),
                  Text('قطاعي: ${Fmt.money(p.retailPrice)}', style: const TextStyle(fontSize: 12)),
                  if (showCost) Text('متوسط التكلفة: ${Fmt.money(p.avgCost)}', style: muted),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
            if (p.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: TagChips(p.tags)),
          ]),
        ),
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.q, required this.onClear});
  final ProductQuery q;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          const Icon(Icons.filter_alt, size: 16),
          const SizedBox(width: 4),
          const Expanded(child: Text('تصفية مفعّلة', style: TextStyle(fontSize: 12))),
          TextButton(onPressed: onClear, child: const Text('مسح التصفية')),
        ]),
      );
}

/// Bottom sheet with every product filter.
class ProductFilterSheet extends ConsumerStatefulWidget {
  const ProductFilterSheet({super.key, required this.initial});
  final ProductQuery initial;
  @override
  ConsumerState<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends ConsumerState<ProductFilterSheet> {
  late int? typeId = widget.initial.productTypeId;
  late int? brandId = widget.initial.brandId;
  late Set<int> tagIds = {...widget.initial.tagIds};
  late bool matchAll = widget.initial.tagsMatchAll;
  late int? makeId = widget.initial.makeId;
  late int? modelId = widget.initial.modelId;
  late final engine = TextEditingController(text: widget.initial.engineFilter ?? '');
  late String? stock = widget.initial.stockStatus;
  late bool archived = widget.initial.includeArchived;
  late String sort = widget.initial.sort;

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(productTypesProvider).valueOrNull ?? [];
    final brands = ref.watch(brandsProvider).valueOrNull ?? [];
    final tags = ref.watch(activeTagsProvider).valueOrNull ?? [];
    final makes = ref.watch(makesProvider).valueOrNull ?? [];
    final List<VehicleModel> models = makeId == null ? const [] : (ref.watch(modelsProvider(makeId!)).valueOrNull ?? const []);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text('تصفية وترتيب', style: Theme.of(context).textTheme.titleLarge),
        const SectionTitle('نوع المنتج'),
        Wrap(spacing: 6, children: [
          ChoiceChip(label: const Text('الكل'), selected: typeId == null, onSelected: (_) => setState(() => typeId = null)),
          for (final t in types)
            ChoiceChip(label: Text(t.nameAr), selected: typeId == t.id, onSelected: (_) => setState(() => typeId = t.id)),
        ]),
        if (brands.isNotEmpty) ...[
          const SectionTitle('الماركة'),
          DropdownButtonFormField<int?>(
            value: brandId,
            items: [
              const DropdownMenuItem(value: null, child: Text('الكل')),
              for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.nameAr)),
            ],
            onChanged: (v) => setState(() => brandId = v),
          ),
        ],
        const SectionTitle('السيارة'),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              value: makeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الماركة'),
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                for (final m in makes) DropdownMenuItem(value: m.id, child: Text(m.nameAr)),
              ],
              onChanged: (v) => setState(() {
                makeId = v;
                modelId = null;
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int?>(
              value: modelId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الموديل'),
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                for (final m in models) DropdownMenuItem(value: m.id, child: Text(m.nameAr)),
              ],
              onChanged: makeId == null ? null : (v) => setState(() => modelId = v),
            ),
          ),
        ]),
        if (makeId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(controller: engine, decoration: const InputDecoration(labelText: 'سعة أو كود المحرك (اختياري)')),
          ),
        if (tags.isNotEmpty) ...[
          SectionTitle('الوسوم (${tagIds.length})'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final t in tags)
              FilterChip(
                label: Text(t.name),
                selected: tagIds.contains(t.id),
                onSelected: (s) => setState(() => s ? tagIds.add(t.id) : tagIds.remove(t.id)),
              ),
          ]),
          if (tagIds.length > 1)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('يطابق كل الوسوم المختارة'),
              subtitle: Text(matchAll ? 'المنتج يجب أن يحمل جميع الوسوم' : 'المنتج يحمل أيًا من الوسوم'),
              value: matchAll,
              onChanged: (v) => setState(() => matchAll = v),
            ),
        ],
        const SectionTitle('حالة المخزون'),
        Wrap(spacing: 6, children: [
          for (final e in const {null: 'الكل', 'in': 'متوفر', 'low': 'منخفض', 'out': 'نفد'}.entries)
            ChoiceChip(label: Text(e.value), selected: stock == e.key, onSelected: (_) => setState(() => stock = e.key)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إظهار المنتجات المؤرشفة'),
          value: archived,
          onChanged: (v) => setState(() => archived = v),
        ),
        const SectionTitle('الترتيب'),
        Wrap(spacing: 6, children: [
          for (final e in const {'name': 'الاسم', 'sku': 'الكود', 'stock': 'الأكثر كمية', 'stock_asc': 'الأقل كمية', 'recent': 'الأحدث'}.entries)
            ChoiceChip(label: Text(e.value), selected: sort == e.key, onSelected: (_) => setState(() => sort = e.key)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, ProductQuery(text: widget.initial.text)),
              child: const Text('مسح الكل'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                ProductQuery(
                  text: widget.initial.text,
                  productTypeId: typeId,
                  brandId: brandId,
                  tagIds: tagIds,
                  tagsMatchAll: matchAll,
                  makeId: makeId,
                  modelId: modelId,
                  engineFilter: engine.text.trim().isEmpty ? null : engine.text.trim(),
                  stockStatus: stock,
                  includeArchived: archived,
                  sort: sort,
                ),
              ),
              child: const Text('تطبيق'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Opens the unified search as a picker and returns the chosen product.
Future<ProductListItem?> pickProduct(BuildContext context, {String title = 'اختر منتجًا'}) {
  return Navigator.of(context).push<ProductListItem>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (c) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ProductSearchView(autofocus: true, onTap: (p) => Navigator.pop(c, p)),
    ),
  ));
}
