import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../product_providers.dart';
import '../product_repository.dart';
import 'pickers.dart';

/// S04 — Add / edit product. Stock is NOT edited here (use opening stock or
/// stock documents).
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final int? productId;
  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  ProductInput? _p;
  bool _saving = false;

  final _c = <String, TextEditingController>{};
  TextEditingController c(String k) => _c.putIfAbsent(k, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(productRepositoryProvider);
    ProductInput p;
    if (widget.productId != null) {
      p = await repo.loadInput(widget.productId!);
    } else {
      p = ProductInput();
      final types = await repo.watchTypes().first;
      final units = await repo.watchUnits().first;
      p.productTypeId = types.isEmpty ? null : types.first.id;
      p.baseUnitId = units.isEmpty ? null : units.first.id;
      p.internalSku = await repo.suggestSku();
    }
    c('sku').text = p.internalSku;
    c('barcode').text = p.barcode ?? '';
    c('tc').text = p.tcCode ?? '';
    c('nameAr').text = p.nameAr;
    c('nameEn').text = p.nameEn ?? '';
    c('desc').text = p.description ?? '';
    c('country').text = p.countryOfOrigin ?? '';
    c('purchase').text = p.id == null ? '' : Money(p.purchasePrice).toPlain();
    c('wholesale').text = p.id == null ? '' : Money(p.wholesalePrice).toPlain();
    c('retail').text = p.id == null ? '' : Money(p.retailPrice).toPlain();
    c('min').text = p.minimumStock == 0 ? '' : Qty(p.minimumStock).toPlain();
    c('max').text = p.maximumStock == null ? '' : Qty(p.maximumStock!).toPlain();
    c('notes').text = p.notes ?? '';
    c('diameter').text = p.diameterMm == null ? '' : formatMm(p.diameterMm!);
    c('size').text = p.sizeDesignation ?? '';
    c('ring').text = p.ringDimensions ?? '';
    c('capacity').text = p.engineCapacity ?? '';
    c('cyl').text = p.cylinders?.toString() ?? '';
    c('engine').text = p.engineCode ?? '';
    c('pin').text = p.pinDiameterMm == null ? '' : formatMm(p.pinDiameterMm!);
    c('comp').text = p.compressionHeightMm == null ? '' : formatMm(p.compressionHeightMm!);
    c('label').text = p.labelNotes ?? '';
    if (mounted) setState(() => _p = p);
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  double? _dbl(String k) {
    final t = normalizeDigits(c(k).text).replaceAll('٫', '.').trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _save() async {
    final p = _p!;
    if (!_form.currentState!.validate()) {
      showSnackError('راجع الحقول المطلوبة');
      return;
    }
    p
      ..internalSku = c('sku').text
      ..barcode = c('barcode').text
      ..tcCode = c('tc').text
      ..nameAr = c('nameAr').text
      ..nameEn = c('nameEn').text
      ..description = c('desc').text
      ..countryOfOrigin = c('country').text
      ..purchasePrice = parseMoney(c('purchase').text)
      ..wholesalePrice = parseMoney(c('wholesale').text)
      ..retailPrice = parseMoney(c('retail').text)
      ..minimumStock = parseQty(c('min').text)
      ..maximumStock = c('max').text.trim().isEmpty ? null : parseQty(c('max').text)
      ..notes = c('notes').text
      ..diameterMm = _dbl('diameter')
      ..sizeDesignation = c('size').text
      ..ringDimensions = c('ring').text
      ..engineCapacity = c('capacity').text
      ..cylinders = int.tryParse(normalizeDigits(c('cyl').text).trim())
      ..engineCode = c('engine').text
      ..pinDiameterMm = _dbl('pin')
      ..compressionHeightMm = _dbl('comp')
      ..labelNotes = c('label').text;
    if (p.retailPrice > 0 && p.wholesalePrice > p.retailPrice) {
      final ok = await confirm(context, 'تنبيه', 'سعر الجملة أعلى من سعر القطاعي. هل تريد الحفظ؟', ok: 'حفظ');
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final id = await runAction(context, () => ref.read(productRepositoryProvider).saveProduct(p));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id != null) {
      bumpCatalog(ref);
      Navigator.pop(context, id);
    }
  }

  void showSnackError(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Theme.of(context).colorScheme.error));

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId == null ? 'إضافة منتج' : 'تعديل منتج'),
        actions: [
          TextButton.icon(
            onPressed: p == null || _saving ? null : _save,
            icon: Icon(Icons.save, color: Theme.of(context).colorScheme.onPrimary),
            label: Text('حفظ', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
          ),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : Form(key: _form, child: _fields(p)),
    );
  }

  Widget _fields(ProductInput p) {
    final types = ref.watch(productTypesProvider).valueOrNull ?? [];
    final brands = ref.watch(brandsProvider).valueOrNull ?? [];
    final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
    final units = ref.watch(unitsProvider).valueOrNull ?? [];
    final tags = ref.watch(activeTagsProvider).valueOrNull ?? [];
    final kind = types.where((t) => t.id == p.productTypeId).map((t) => t.kind).firstOrNull ?? 'other';
    const gap = SizedBox(height: 10);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 80), children: [
      const SectionTitle('١. البيانات الأساسية'),
      TextFormField(
        controller: c('nameAr'),
        decoration: const InputDecoration(labelText: 'اسم المنتج بالعربية *'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
      ),
      gap,
      TextFormField(controller: c('nameEn'), decoration: const InputDecoration(labelText: 'الاسم بالإنجليزية'), textDirection: TextDirection.ltr),
      gap,
      Row(children: [
        Expanded(child: TextFormField(controller: c('sku'), decoration: const InputDecoration(labelText: 'الكود الداخلي (SKU)', helperText: 'يُولد تلقائيًا إن تُرك فارغًا'), textDirection: TextDirection.ltr)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: c('barcode'), decoration: const InputDecoration(labelText: 'الباركود'), textDirection: TextDirection.ltr)),
      ]),
      gap,
      TextFormField(controller: c('desc'), decoration: const InputDecoration(labelText: 'الوصف'), maxLines: 2),

      const SectionTitle('٢. النوع والتصنيف'),
      _dropdownWithAdd<int>(
        label: 'نوع المنتج *',
        value: p.productTypeId,
        items: {for (final t in types) t.id: t.nameAr},
        onChanged: (v) => setState(() => p.productTypeId = v),
        onAdd: () async {
          final id = await showAddTypeDialog(context, ref);
          if (id != null) setState(() => p.productTypeId = id);
        },
      ),
      gap,
      _dropdownWithAdd<int>(
        label: 'التصنيف',
        value: p.categoryId,
        nullable: true,
        items: {for (final x in cats) x.id: x.nameAr},
        onChanged: (v) => setState(() => p.categoryId = v),
        onAdd: () async {
          final n = await promptText(context, 'تصنيف جديد', label: 'الاسم');
          if (n == null || !mounted) return;
          final id = await runAction(context, () => ref.read(productRepositoryProvider).addCategory(n));
          if (id != null) setState(() => p.categoryId = id);
        },
      ),

      const SectionTitle('٣. بيانات الشركة المصنعة والملصق'),
      _dropdownWithAdd<int>(
        label: 'الماركة / المصنع',
        value: p.brandId,
        nullable: true,
        items: {for (final b in brands) b.id: b.nameAr},
        onChanged: (v) => setState(() => p.brandId = v),
        onAdd: () async {
          final n = await promptText(context, 'ماركة جديدة', label: 'الاسم (مثال: TR2)');
          if (n == null || !mounted) return;
          final id = await runAction(context, () => ref.read(productRepositoryProvider).addBrand(n, null));
          if (id != null) setState(() => p.brandId = id);
        },
      ),
      gap,
      Row(children: [
        Expanded(child: TextFormField(controller: c('tc'), decoration: const InputDecoration(labelText: 'كود T.C'), textDirection: TextDirection.ltr)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: c('country'), decoration: const InputDecoration(labelText: 'بلد المنشأ'))),
      ]),

      const SectionTitle('٤. المواصفات الفنية'),
      if (kind == 'ring' || kind == 'piston') ...[
        Row(children: [
          Expanded(child: _numField('diameter', 'القطر (مم)')),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: c('size'), decoration: const InputDecoration(labelText: 'المقاس', hintText: 'STD / 0.25 / 0.50'), textDirection: TextDirection.ltr)),
        ]),
        gap,
        if (kind == 'ring') ...[
          TextFormField(controller: c('ring'), decoration: const InputDecoration(labelText: 'أبعاد الشنبر / السماكات', hintText: '1.20 - 1.20 - 2.00'), textDirection: TextDirection.ltr),
          gap,
        ],
        if (kind == 'piston') ...[
          Row(children: [
            Expanded(child: _numField('pin', 'قطر البنز (مم)')),
            const SizedBox(width: 8),
            Expanded(child: _numField('comp', 'ارتفاع الضغط (مم)')),
          ]),
          gap,
        ],
      ],
      Row(children: [
        Expanded(child: TextFormField(controller: c('capacity'), decoration: const InputDecoration(labelText: 'سعة المحرك'), textDirection: TextDirection.ltr)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(controller: c('cyl'), decoration: const InputDecoration(labelText: 'عدد السلندرات'), keyboardType: TextInputType.number)),
      ]),
      gap,
      TextFormField(controller: c('engine'), decoration: const InputDecoration(labelText: 'كود المحرك'), textDirection: TextDirection.ltr),
      gap,
      TextFormField(controller: c('label'), decoration: const InputDecoration(labelText: 'ملاحظات من الملصق'), maxLines: 2),
      const SizedBox(height: 6),
      Text('مواصفات إضافية', style: Theme.of(context).textTheme.labelLarge),
      for (var i = 0; i < p.specs.length; i++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${p.specs[i].key}: ${p.specs[i].value}'),
          trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => p.specs.removeAt(i))),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('إضافة مواصفة'),
          onPressed: () async {
            final s = await showSpecDialog(context);
            if (s != null) setState(() => p.specs.add(s));
          },
        ),
      ),

      const SectionTitle('٥. السيارات المتوافقة'),
      for (var i = 0; i < p.compat.length; i++)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            leading: Icon(p.compat[i].status == 'confirmed' ? Icons.verified : Icons.help_outline,
                color: p.compat[i].status == 'confirmed' ? Colors.green : Colors.orange),
            title: Text(p.compat[i].label),
            subtitle: Text([
              if (p.compat[i].yearFrom != null || p.compat[i].yearTo != null) '${p.compat[i].yearFrom ?? ''}-${p.compat[i].yearTo ?? ''}',
              if (p.compat[i].engineCapacity.isNotEmpty) 'سعة ${p.compat[i].engineCapacity}',
              if (p.compat[i].engineCode.isNotEmpty) p.compat[i].engineCode,
              p.compat[i].status == 'confirmed' ? 'مؤكد' : 'يحتاج تحقق',
            ].join(' • ')),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => p.compat.removeAt(i))),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.directions_car),
          label: const Text('ربط بسيارة'),
          onPressed: () async {
            final r = await showCompatDialog(context, ref);
            if (r == null) return;
            if (p.compat.any((x) => x.key == r.key)) {
              showSnackError('هذا التوافق مضاف بالفعل');
              return;
            }
            setState(() => p.compat.add(r));
          },
        ),
      ),

      const SectionTitle('٦. الأسعار'),
      MoneyField(controller: c('purchase'), label: 'تكلفة الشراء الافتراضية'),
      gap,
      Row(children: [
        Expanded(child: MoneyField(controller: c('wholesale'), label: 'سعر الجملة')),
        const SizedBox(width: 8),
        Expanded(child: MoneyField(controller: c('retail'), label: 'سعر القطاعي')),
      ]),

      const SectionTitle('٧. إعدادات المخزون'),
      _dropdownWithAdd<int>(
        label: 'وحدة المخزون *',
        value: p.baseUnitId,
        items: {for (final u in units) u.id: u.nameAr},
        onChanged: (v) => setState(() => p.baseUnitId = v),
        onAdd: () async {
          final n = await promptText(context, 'وحدة جديدة', label: 'الاسم');
          if (n == null || !mounted) return;
          final id = await runAction(context, () => ref.read(productRepositoryProvider).addUnit(n));
          if (id != null) setState(() => p.baseUnitId = id);
        },
      ),
      gap,
      Row(children: [
        Expanded(child: QtyField(controller: c('min'), label: 'حد إعادة الطلب', required: false, allowZero: true)),
        const SizedBox(width: 8),
        Expanded(child: QtyField(controller: c('max'), label: 'الحد الأقصى', required: false, allowZero: true)),
      ]),
      if (widget.productId == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('الكمية الافتتاحية تُسجل بعد الحفظ من شاشة المنتج ← "رصيد افتتاحي".', style: TextStyle(fontSize: 12)),
        ),

      const SectionTitle('٨. الوسوم'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final id in p.tagIds)
          InputChip(
            label: Text(tags.where((t) => t.id == id).map((t) => t.name).firstOrNull ?? '…'),
            onDeleted: () => setState(() => p.tagIds.remove(id)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('إضافة وسم'),
          onPressed: () async {
            final r = await showTagSelector(context, ref, selected: p.tagIds.toSet());
            if (r != null) setState(() => p.tagIds = r.toList());
          },
        ),
      ]),

      const SectionTitle('٩. ملاحظات'),
      TextFormField(controller: c('notes'), decoration: const InputDecoration(labelText: 'ملاحظات داخلية'), maxLines: 3),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('حفظ المنتج')),
    ]);
  }

  Widget _numField(String k, String label) => TextFormField(
        controller: c(k),
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          return double.tryParse(normalizeDigits(v).replaceAll('٫', '.').trim()) == null ? 'رقم غير صحيح' : null;
        },
      );

  Widget _dropdownWithAdd<T>({
    required String label,
    required T? value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
    required VoidCallback onAdd,
    bool nullable = false,
  }) {
    final v = items.containsKey(value) ? value : null;
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<T?>(
          value: v,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (nullable) DropdownMenuItem<T?>(value: null, child: const Text('—')),
            for (final e in items.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
          validator: (x) => (!nullable && x == null) ? 'مطلوب' : null,
        ),
      ),
      IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline), tooltip: 'إضافة جديد'),
    ]);
  }
}
