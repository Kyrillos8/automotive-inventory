import 'package:drift/drift.dart' show OrderingTerm, QueryRow, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/presentation/product_search_view.dart';
import '../../products/product_providers.dart';
import '../purchasing_service.dart';

// ============================================================== suppliers

/// S12 — Suppliers.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String _q = '';
  bool _archived = false;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الموردون'), actions: [
        IconButton(
          tooltip: 'المؤرشفون',
          icon: Icon(_archived ? Icons.inventory : Icons.inventory_2_outlined),
          onPressed: () => setState(() => _archived = !_archived),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_supplier',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierFormScreen()));
          setState(() => _v++);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الهاتف'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: FutureLoader<List<Supplier>>(
            reloadKey: '$_q|$_archived|$_v',
            load: () {
              final s = db.select(db.suppliers)..where((t) => t.isActive.equals(!_archived));
              if (_q.isNotEmpty) s.where((t) => t.name.like('%$_q%') | t.phone.like('%$_q%'));
              s.orderBy([(t) => OrderingTerm(expression: t.name)]);
              return s.get();
            },
            builder: (c, list, _) => list.isEmpty
                ? const EmptyView(icon: Icons.factory_outlined, title: 'لا يوجد موردون')
                : ListView(children: [
                    for (final s in list)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.factory)),
                        title: Text(s.name),
                        subtitle: Text([s.contactName, s.phone].whereType<String>().join(' • ')),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierDetailsScreen(supplierId: s.id)));
                          setState(() => _v++);
                        },
                      ),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key, this.supplier});
  final Supplier? supplier;
  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.supplier?.name);
  late final contact = TextEditingController(text: widget.supplier?.contactName);
  late final phone = TextEditingController(text: widget.supplier?.phone);
  late final email = TextEditingController(text: widget.supplier?.email);
  late final address = TextEditingController(text: widget.supplier?.address);
  late final notes = TextEditingController(text: widget.supplier?.notes);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier == null ? 'مورد جديد' : 'تعديل مورد')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم المورد *'), validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null),
          const SizedBox(height: 10),
          TextFormField(controller: contact, decoration: const InputDecoration(labelText: 'اسم المسؤول')),
          const SizedBox(height: 10),
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف'), keyboardType: TextInputType.phone, textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextFormField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني'), keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextFormField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
          const SizedBox(height: 10),
          TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 2),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final s = SupplierInput()
                ..id = widget.supplier?.id
                ..name = name.text
                ..contactName = contact.text
                ..phone = phone.text
                ..email = email.text
                ..address = address.text
                ..notes = notes.text;
              final id = await runAction(context, () => ref.read(purchasingServiceProvider).saveSupplier(s), success: 'تم الحفظ');
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
            child: const Text('حفظ'),
          ),
        ]),
      ),
    );
  }
}

class SupplierDetailsScreen extends ConsumerStatefulWidget {
  const SupplierDetailsScreen({super.key, required this.supplierId});
  final int supplierId;
  @override
  ConsumerState<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends ConsumerState<SupplierDetailsScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return FutureLoader<(Supplier, List<PurchaseOrder>, List<GoodsReceipt>)>(
      reloadKey: _v,
      load: () async => (
        await (db.select(db.suppliers)..where((t) => t.id.equals(widget.supplierId))).getSingle(),
        await (db.select(db.purchaseOrders)
              ..where((t) => t.supplierId.equals(widget.supplierId))
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .get(),
        await (db.select(db.goodsReceipts)
              ..where((t) => t.supplierId.equals(widget.supplierId))
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .get(),
      ),
      builder: (context, d, reload) {
        final s = d.$1;
        final total = d.$3.fold<int>(0, (a, g) => a + g.total);
        return Scaffold(
          appBar: AppBar(title: Text(s.name), actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierFormScreen(supplier: s)));
                setState(() => _v++);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'archive') {
                  await ref.read(purchasingServiceProvider).setSupplierActive(s.id, !s.isActive);
                  setState(() => _v++);
                } else if (v == 'return') {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierReturnFormScreen(supplierId: s.id)));
                  setState(() => _v++);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'return', child: Text('مرتجع للمورد')),
                PopupMenuItem(value: 'archive', child: Text(s.isActive ? 'أرشفة' : 'إعادة تفعيل')),
              ],
            ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  InfoRow('المسؤول', s.contactName),
                  InfoRow('الهاتف', s.phone, ltr: true),
                  InfoRow('البريد', s.email, ltr: true),
                  InfoRow('العنوان', s.address),
                  InfoRow('ملاحظات', s.notes),
                  InfoRow('إجمالي المشتريات المستلمة', Fmt.money(total)),
                ]),
              ),
            ),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.note_add),
                  label: const Text('أمر شراء'),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => PoFormScreen(supplierId: s.id)));
                    setState(() => _v++);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.move_to_inbox),
                  label: const Text('استلام مباشر'),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptFormScreen(supplierId: s.id)));
                    setState(() => _v++);
                  },
                ),
              ),
            ]),
            const SectionTitle('أوامر الشراء'),
            if (d.$2.isEmpty) const Text('لا توجد أوامر'),
            for (final o in d.$2) _poTile(context, o, () => setState(() => _v++)),
            const SectionTitle('الاستلامات'),
            if (d.$3.isEmpty) const Text('لا توجد استلامات'),
            for (final g in d.$3)
              ListTile(
                dense: true,
                title: Text(g.receiptNumber, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                subtitle: Text(Fmt.dateTime(g.receivedAt)),
                trailing: Text(Fmt.money(g.total)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptDetailsScreen(receiptId: g.id))),
              ),
          ]),
        );
      },
    );
  }
}

Widget _poTile(BuildContext context, PurchaseOrder o, VoidCallback changed) => Card(
      child: ListTile(
        title: Text(o.orderNumber, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
        subtitle: Text('${Fmt.date(o.orderDate)} • ${PoStatus.label(o.status)}'),
        trailing: Text(Fmt.money(o.grandTotal)),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => PoDetailsScreen(poId: o.id)));
          changed();
        },
      ),
    );

// ============================================================== purchases hub

/// Purchases: purchase orders and goods receipts.
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});
  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المشتريات'),
          actions: [
            IconButton(
              tooltip: 'الموردون',
              icon: const Icon(Icons.factory_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersScreen())),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'أوامر الشراء'), Tab(text: 'الاستلامات')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new_purchase',
          icon: const Icon(Icons.add),
          label: const Text('جديد'),
          onPressed: () async {
            final kind = await showModalBottomSheet<String>(
              context: context,
              builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(leading: const Icon(Icons.note_add), title: const Text('أمر شراء'), onTap: () => Navigator.pop(c, 'po')),
                  ListTile(leading: const Icon(Icons.move_to_inbox), title: const Text('استلام بضاعة مباشر (بدون أمر)'), onTap: () => Navigator.pop(c, 'gr')),
                  ListTile(leading: const Icon(Icons.assignment_return), title: const Text('مرتجع لمورد'), onTap: () => Navigator.pop(c, 'ret')),
                ]),
              ),
            );
            if (kind == null || !context.mounted) return;
            final sid = await pickSupplier(context, ref);
            if (sid == null || !context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => switch (kind) {
                  'po' => PoFormScreen(supplierId: sid),
                  'gr' => ReceiptFormScreen(supplierId: sid),
                  _ => SupplierReturnFormScreen(supplierId: sid),
                },
              ),
            );
            setState(() => _v++);
          },
        ),
        body: TabBarView(children: [
          FutureLoader<List<PurchaseOrder>>(
            reloadKey: _v,
            load: () => (db.select(db.purchaseOrders)..orderBy([(t) => OrderingTerm.desc(t.id)])..limit(200)).get(),
            builder: (c, list, _) => list.isEmpty
                ? const EmptyView(icon: Icons.note_add_outlined, title: 'لا توجد أوامر شراء')
                : ListView(children: [for (final o in list) _poTile(context, o, () => setState(() => _v++))]),
          ),
          FutureLoader<List<QueryRow>>(
            reloadKey: _v,
            load: () => db.customSelect('''SELECT g.*, s.name AS sname FROM goods_receipts g JOIN suppliers s ON s.id = g.supplier_id
                ORDER BY g.id DESC LIMIT 200''').get(),
            builder: (c, list, _) => list.isEmpty
                ? const EmptyView(icon: Icons.move_to_inbox, title: 'لا توجد استلامات')
                : ListView(children: [
                    for (final r in list)
                      ListTile(
                        title: Text('${r.read<String>('receipt_number')} • ${r.read<String>('sname')}'),
                        subtitle: Text(Fmt.dateTime(r.read<DateTime>('received_at'))),
                        trailing: Text(Fmt.money(r.read<int>('total'))),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptDetailsScreen(receiptId: r.read<int>('id')))),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

Future<int?> pickSupplier(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final list = await (db.select(db.suppliers)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .get();
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(title: const Text('اختر المورد'), children: [
      for (final s in list) SimpleDialogOption(onPressed: () => Navigator.pop(c, s.id), child: Text(s.name)),
      SimpleDialogOption(
        onPressed: () async {
          final id = await Navigator.push<int>(c, MaterialPageRoute(builder: (_) => const SupplierFormScreen()));
          if (c.mounted) Navigator.pop(c, id);
        },
        child: const Text('+ مورد جديد', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ]),
  );
}

// ============================================================== PO form

class _PoLineCtrl {
  final int productId;
  final String name;
  final qty = TextEditingController();
  final cost = TextEditingController();
  _PoLineCtrl(this.productId, this.name);
}

/// S13 — Purchase order form. Never changes stock.
class PoFormScreen extends ConsumerStatefulWidget {
  const PoFormScreen({super.key, required this.supplierId, this.poId});
  final int supplierId;
  final int? poId;
  @override
  ConsumerState<PoFormScreen> createState() => _PoFormScreenState();
}

class _PoFormScreenState extends ConsumerState<PoFormScreen> {
  final _form = GlobalKey<FormState>();
  final _lines = <_PoLineCtrl>[];
  final _notes = TextEditingController();
  DateTime? _expected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.poId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    final db = ref.read(databaseProvider);
    final po = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(widget.poId!))).getSingle();
    final rows = await db.customSelect(
        'SELECT l.*, p.name_ar FROM purchase_order_lines l JOIN products p ON p.id = l.product_id WHERE purchase_order_id = ?',
        variables: [Variable.withInt(widget.poId!)]).get();
    setState(() {
      _notes.text = po.notes ?? '';
      _expected = po.expectedDate;
      for (final r in rows) {
        final l = _PoLineCtrl(r.read<int>('product_id'), r.read<String>('name_ar'));
        l.qty.text = Qty(r.read<int>('ordered_quantity')).toPlain();
        l.cost.text = Money(r.read<int>('unit_cost')).toPlain();
        _lines.add(l);
      }
    });
  }

  int get _total => _lines.fold(0, (a, l) => a + Money(parseMoney(l.cost.text)).timesQty(Qty(parseQty(l.qty.text))).minor);

  Future<void> _save(bool ordered) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final id = await runAction(
      context,
      () => ref.read(purchasingServiceProvider).savePurchaseOrder(
            id: widget.poId,
            supplierId: widget.supplierId,
            orderDate: DateTime.now(),
            expectedDate: _expected,
            notes: _notes.text,
            markOrdered: ordered,
            lines: [
              for (final l in _lines)
                PoLineInput(productId: l.productId, productName: l.name, orderedQuantity: parseQty(l.qty.text), unitCost: parseMoney(l.cost.text)),
            ],
          ),
      success: 'تم الحفظ',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.poId == null ? 'أمر شراء جديد' : 'تعديل أمر الشراء')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: Text('الإجمالي: ${Fmt.money(_total)}', style: const TextStyle(fontWeight: FontWeight.bold))),
            OutlinedButton(onPressed: _busy ? null : () => _save(false), child: const Text('حفظ مسودة')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : () => _save(true), child: const Text('إرسال الطلب')),
          ]),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_expected == null ? 'تاريخ التسليم المتوقع (اختياري)' : 'التسليم المتوقع: ${Fmt.date(_expected!)}'),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _expected ?? DateTime.now());
              if (d != null) setState(() => _expected = d);
            },
          ),
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.remove(l))),
                  ]),
                  Row(children: [
                    Expanded(child: QtyField(controller: l.qty, label: 'الكمية', onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 8),
                    Expanded(child: MoneyField(controller: l.cost, label: 'تكلفة الوحدة', required: true, onChanged: (_) => setState(() {}))),
                  ]),
                ]),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة منتج'),
            onPressed: () async {
              final p = await pickProduct(context);
              if (p == null || _lines.any((x) => x.productId == p.id)) return;
              final l = _PoLineCtrl(p.id, p.nameAr)..cost.text = Money(p.purchasePrice).toPlain();
              setState(() => _lines.add(l));
            },
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
        ]),
      ),
    );
  }
}

class PoDetailsScreen extends ConsumerStatefulWidget {
  const PoDetailsScreen({super.key, required this.poId});
  final int poId;
  @override
  ConsumerState<PoDetailsScreen> createState() => _PoDetailsScreenState();
}

class _PoDetailsScreenState extends ConsumerState<PoDetailsScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    final svc = ref.read(purchasingServiceProvider);
    return FutureLoader<(PurchaseOrder, Supplier, List<QueryRow>)>(
      reloadKey: _v,
      load: () async {
        final po = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(widget.poId))).getSingle();
        final s = await (db.select(db.suppliers)..where((t) => t.id.equals(po.supplierId))).getSingle();
        final lines = await db.customSelect(
            'SELECT l.*, p.name_ar FROM purchase_order_lines l JOIN products p ON p.id = l.product_id WHERE purchase_order_id = ? ORDER BY l.id',
            variables: [Variable.withInt(widget.poId)]).get();
        return (po, s, lines);
      },
      builder: (context, d, _) {
        final (po, s, lines) = d;
        final canReceive = po.status == PoStatus.ordered || po.status == PoStatus.partial;
        return Scaffold(
          appBar: AppBar(title: Text(po.orderNumber), actions: [
            if (po.status == PoStatus.draft)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PoFormScreen(supplierId: po.supplierId, poId: po.id)));
                  setState(() => _v++);
                },
              ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  InfoRow('المورد', s.name),
                  InfoRow('الحالة', PoStatus.label(po.status)),
                  InfoRow('تاريخ الطلب', Fmt.date(po.orderDate)),
                  InfoRow('التسليم المتوقع', po.expectedDate == null ? null : Fmt.date(po.expectedDate!)),
                  InfoRow('الإجمالي', Fmt.money(po.grandTotal)),
                  InfoRow('ملاحظات', po.notes),
                ]),
              ),
            ),
            const SectionTitle('الأصناف'),
            for (final r in lines)
              ListTile(
                title: Text(r.read<String>('name_ar')),
                subtitle: Text('مطلوب ${Fmt.qty(r.read<int>('ordered_quantity'))} • مستلم ${Fmt.qty(r.read<int>('received_quantity'))}'),
                trailing: Text('${Fmt.money(r.read<int>('unit_cost'))}'),
              ),
            const SizedBox(height: 16),
            if (po.status == PoStatus.draft)
              FilledButton(
                onPressed: () async {
                  await runAction(context, () => svc.setPoStatus(po.id, PoStatus.ordered), success: 'تم إرسال الطلب');
                  setState(() => _v++);
                },
                child: const Text('تأكيد الطلب (إرسال للمورد)'),
              ),
            if (canReceive)
              FilledButton.icon(
                icon: const Icon(Icons.move_to_inbox),
                label: const Text('استلام بضاعة'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptFormScreen(supplierId: po.supplierId, poId: po.id)));
                  setState(() => _v++);
                },
              ),
            if (po.status != PoStatus.received && po.status != PoStatus.cancelled)
              TextButton(
                onPressed: () async {
                  if (!await confirm(context, 'إلغاء الأمر', 'إلغاء أمر الشراء؟ الكميات المستلمة سابقًا تبقى في المخزون.', destructive: true)) return;
                  if (!context.mounted) return;
                  await runAction(context, () => svc.setPoStatus(po.id, PoStatus.cancelled));
                  setState(() => _v++);
                },
                child: const Text('إلغاء الأمر'),
              ),
          ]),
        );
      },
    );
  }
}

// ============================================================== receipts

class _RcLine {
  final ReceiptLineInput input;
  final accepted = TextEditingController();
  final rejected = TextEditingController();
  final cost = TextEditingController();
  _RcLine(this.input) {
    accepted.text = input.acceptedQuantity == 0 ? '' : Qty(input.acceptedQuantity).toPlain();
    cost.text = Money(input.unitCost).toPlain();
  }
}

/// S14 — Goods receipt (linked to a PO, or direct).
class ReceiptFormScreen extends ConsumerStatefulWidget {
  const ReceiptFormScreen({super.key, required this.supplierId, this.poId});
  final int supplierId;
  final int? poId;
  @override
  ConsumerState<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends ConsumerState<ReceiptFormScreen> {
  final _form = GlobalKey<FormState>();
  final _lines = <_RcLine>[];
  final _notes = TextEditingController();
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.poId != null) {
      ref.read(purchasingServiceProvider).receiptLinesForPo(widget.poId!).then((l) {
        if (mounted) {
          setState(() {
            _lines.addAll(l.map(_RcLine.new));
            _loaded = true;
          });
        }
      });
    } else {
      _loaded = true;
    }
  }

  Future<void> _post() async {
    if (!_form.currentState!.validate()) return;
    final lines = [
      for (final l in _lines)
        ReceiptLineInput(
          purchaseOrderLineId: l.input.purchaseOrderLineId,
          productId: l.input.productId,
          productName: l.input.productName,
          acceptedQuantity: parseQty(l.accepted.text),
          rejectedQuantity: parseQty(l.rejected.text),
          unitCost: parseMoney(l.cost.text),
        ),
    ];
    final ok = await confirm(context, 'ترحيل الاستلام', 'ستُضاف الكميات المقبولة فقط إلى المخزون. لا يمكن تعديل الاستلام بعد الترحيل.', ok: 'ترحيل');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final id = await runAction(
      context,
      () => ref.read(purchasingServiceProvider).postGoodsReceipt(
            purchaseOrderId: widget.poId,
            supplierId: widget.supplierId,
            receivedAt: DateTime.now(),
            lines: lines,
            notes: _notes.text,
          ),
      success: 'تم ترحيل الاستلام',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      bumpCatalog(ref);
      Navigator.pop(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(widget.poId == null ? 'استلام مباشر' : 'استلام من أمر شراء')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(onPressed: _busy ? null : _post, icon: const Icon(Icons.check), label: const Text('ترحيل الاستلام')),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_lines.isEmpty && widget.poId != null) const EmptyView(icon: Icons.done_all, title: 'لا توجد كميات متبقية للاستلام'),
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(l.input.productName, style: const TextStyle(fontWeight: FontWeight.bold))),
                    if (widget.poId == null) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.remove(l))),
                  ]),
                  if (l.input.remaining != null) Text('المتبقي من الأمر: ${Fmt.qty(l.input.remaining!)}'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: QtyField(controller: l.accepted, label: 'مقبول', allowZero: true, required: false)),
                    const SizedBox(width: 6),
                    Expanded(child: QtyField(controller: l.rejected, label: 'مرفوض/تالف', allowZero: true, required: false)),
                    const SizedBox(width: 6),
                    Expanded(child: MoneyField(controller: l.cost, label: 'التكلفة', required: true)),
                  ]),
                ]),
              ),
            ),
          if (widget.poId == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
              onPressed: () async {
                final p = await pickProduct(context);
                if (p == null || _lines.any((x) => x.input.productId == p.id)) return;
                setState(() => _lines.add(_RcLine(ReceiptLineInput(productId: p.id, productName: p.nameAr, unitCost: p.purchasePrice))));
              },
            ),
          const SizedBox(height: 10),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
        ]),
      ),
    );
  }
}

class ReceiptDetailsScreen extends ConsumerWidget {
  const ReceiptDetailsScreen({super.key, required this.receiptId});
  final int receiptId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الاستلام')),
      body: FutureLoader<(GoodsReceipt, List<QueryRow>)>(
        load: () async => (
          await (db.select(db.goodsReceipts)..where((t) => t.id.equals(receiptId))).getSingle(),
          await db.customSelect(
              'SELECT l.*, p.name_ar FROM goods_receipt_lines l JOIN products p ON p.id = l.product_id WHERE goods_receipt_id = ?',
              variables: [Variable.withInt(receiptId)]).get(),
        ),
        builder: (c, d, _) => ListView(padding: const EdgeInsets.all(12), children: [
          InfoRow('الرقم', d.$1.receiptNumber, ltr: true),
          InfoRow('التاريخ', Fmt.dateTime(d.$1.receivedAt)),
          InfoRow('الإجمالي', Fmt.money(d.$1.total)),
          InfoRow('ملاحظات', d.$1.notes),
          const Divider(),
          for (final r in d.$2)
            ListTile(
              title: Text(r.read<String>('name_ar')),
              subtitle: Text('مقبول ${Fmt.qty(r.read<int>('received_quantity'))} • مرفوض ${Fmt.qty(r.read<int>('rejected_quantity'))}'),
              trailing: Text(Fmt.money(r.read<int>('unit_cost'))),
            ),
        ]),
      ),
    );
  }
}

class SupplierReturnFormScreen extends ConsumerStatefulWidget {
  const SupplierReturnFormScreen({super.key, required this.supplierId});
  final int supplierId;
  @override
  ConsumerState<SupplierReturnFormScreen> createState() => _SupplierReturnFormScreenState();
}

class _SupplierReturnFormScreenState extends ConsumerState<SupplierReturnFormScreen> {
  final _form = GlobalKey<FormState>();
  final _lines = <_RcLine>[];
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مرتجع لمورد')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    if (!await confirm(context, 'ترحيل المرتجع', 'ستُخصم الكميات من المخزون.', ok: 'ترحيل') || !context.mounted) return;
                    setState(() => _busy = true);
                    final id = await runAction(
                      context,
                      () => ref.read(purchasingServiceProvider).postSupplierReturn(
                            supplierId: widget.supplierId,
                            notes: _notes.text,
                            lines: [
                              for (final l in _lines)
                                ReceiptLineInput(
                                    productId: l.input.productId,
                                    productName: l.input.productName,
                                    acceptedQuantity: parseQty(l.accepted.text),
                                    unitCost: parseMoney(l.cost.text)),
                            ],
                          ),
                      success: 'تم ترحيل المرتجع',
                    );
                    if (!context.mounted) return;
                    setState(() => _busy = false);
                    if (id != null) {
                      bumpCatalog(ref);
                      Navigator.pop(context);
                    }
                  },
            child: const Text('ترحيل المرتجع'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: Text(l.input.productName, style: const TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.remove(l))),
                  ]),
                  Row(children: [
                    Expanded(child: QtyField(controller: l.accepted, label: 'الكمية المرتجعة')),
                    const SizedBox(width: 8),
                    Expanded(child: MoneyField(controller: l.cost, label: 'قيمة الوحدة', required: true)),
                  ]),
                ]),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة منتج'),
            onPressed: () async {
              final p = await pickProduct(context);
              if (p == null || _lines.any((x) => x.input.productId == p.id)) return;
              setState(() => _lines.add(_RcLine(ReceiptLineInput(productId: p.id, productName: p.nameAr, unitCost: p.avgCost))));
            },
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'السبب / ملاحظات')),
        ]),
      ),
    );
  }
}
