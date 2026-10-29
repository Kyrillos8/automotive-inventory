import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/presentation/product_screens.dart';
import '../../products/presentation/product_search_view.dart';
import '../../products/product_providers.dart';
import '../../products/product_repository.dart';
import '../inventory_service.dart';
import '../stock_documents_service.dart';

/// S09 — Inventory overview.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(String kind) async {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StockDocFormScreen(kind: kind)));
      if (ok == true) bumpCatalog(ref);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المخزون'), actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'count':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StocktakingListScreen()));
              case 'reconcile':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReconcileScreen()));
              default:
                open(v);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: StockDocKind.opening, child: Text('رصيد افتتاحي')),
            PopupMenuItem(value: StockDocKind.receipt, child: Text('إضافة مخزون')),
            PopupMenuItem(value: StockDocKind.issue, child: Text('صرف مخزون')),
            PopupMenuItem(value: StockDocKind.damage, child: Text('تالف / إعدام')),
            PopupMenuItem(value: StockDocKind.adjustment, child: Text('تسوية مخزون')),
            PopupMenuItem(value: 'count', child: Text('جرد المخزون')),
            PopupMenuItem(value: 'reconcile', child: Text('مطابقة الأرصدة مع الحركات')),
          ],
        ),
      ]),
      body: Column(children: [
        const _ValuationBar(),
        Expanded(
          child: ProductSearchView(
            showCost: true,
            onTap: (p) => _quickActions(context, ref, p),
          ),
        ),
      ]),
    );
  }

  void _quickActions(BuildContext context, WidgetRef ref, ProductListItem p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(p.nameAr, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('المتاح: ${Fmt.qty(p.quantity)} ${p.unitName}')),
          for (final k in [StockDocKind.receipt, StockDocKind.issue, StockDocKind.adjustment, StockDocKind.damage])
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(StockDocKind.label(k)),
              onTap: () async {
                Navigator.pop(c);
                final ok = await Navigator.push<bool>(
                    context, MaterialPageRoute(builder: (_) => StockDocFormScreen(kind: k, initialProduct: p)));
                if (ok == true) bumpCatalog(ref);
              },
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('سجل الحركة'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => StockHistoryScreen(productId: p.id, name: p.nameAr)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('تفاصيل المنتج'),
            onTap: () {
              Navigator.pop(c);
              openProductDetails(context, p.id);
            },
          ),
        ]),
      ),
    );
  }
}

class _ValuationBar extends ConsumerWidget {
  const _ValuationBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogVersionProvider);
    final db = ref.read(databaseProvider);
    return FutureBuilder(
      future: db.customSelect('''SELECT COALESCE(SUM(CASE WHEN quantity_on_hand > 0 THEN quantity_on_hand ELSE 0 END),0) AS units,
          CAST(ROUND(COALESCE(SUM(CASE WHEN quantity_on_hand > 0 THEN quantity_on_hand * avg_cost / 1000.0 ELSE 0 END),0)) AS INTEGER) AS val
          FROM stock_balances''').getSingle(),
      builder: (c, s) {
        if (!s.hasData) return const SizedBox(height: 4);
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('إجمالي الوحدات: ${Fmt.qty(s.data!.read<int>('units'))}   •   قيمة المخزون: ${Fmt.money(s.data!.read<int>('val'))}'),
        );
      },
    );
  }
}

class _DocLine {
  final ProductListItem product;
  final qty = TextEditingController();
  final cost = TextEditingController();
  _DocLine(this.product);
}

/// S10 — Stock transaction form (opening / receipt / issue / damage / adjustment).
class StockDocFormScreen extends ConsumerStatefulWidget {
  const StockDocFormScreen({super.key, required this.kind, this.initialProduct});
  final String kind;
  final ProductListItem? initialProduct;
  @override
  ConsumerState<StockDocFormScreen> createState() => _StockDocFormScreenState();
}

class _StockDocFormScreenState extends ConsumerState<StockDocFormScreen> {
  final _form = GlobalKey<FormState>();
  final _lines = <_DocLine>[];
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  bool get _withCost => widget.kind == StockDocKind.opening || widget.kind == StockDocKind.receipt;
  bool get _isAdj => widget.kind == StockDocKind.adjustment;

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) _add(widget.initialProduct!);
    _reason.text = switch (widget.kind) {
      StockDocKind.opening => 'رصيد افتتاحي',
      _ => '',
    };
  }

  void _add(ProductListItem p) {
    if (_lines.any((l) => l.product.id == p.id)) return;
    final l = _DocLine(p);
    if (_withCost) l.cost.text = Money(p.avgCost > 0 ? p.avgCost : p.purchasePrice).toPlain();
    setState(() => _lines.add(l));
  }

  Future<void> _post() async {
    if (_lines.isEmpty) {
      showSnack(context, 'أضف منتجًا', error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    final summary = _lines.map((l) {
      final q = parseQty(l.qty.text);
      return _isAdj ? '${l.product.nameAr}: ${Fmt.qty(l.product.quantity)} ← ${Fmt.qty(q)} (فرق ${Fmt.qty(q - l.product.quantity)})' : '${l.product.nameAr}: ${Fmt.qty(q)}';
    }).join('\n');
    final ok = await confirm(context, 'ترحيل ${StockDocKind.label(widget.kind)}', '$summary\n\nلا يمكن تعديل المستند بعد الترحيل.', ok: 'ترحيل');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await runAction(
      context,
      () => ref.read(stockDocumentsServiceProvider).post(
            kind: widget.kind,
            reason: _reason.text,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            lines: [
              for (final l in _lines)
                StockDocLine(l.product.id, parseQty(l.qty.text), unitCost: _withCost && l.cost.text.trim().isNotEmpty ? parseMoney(l.cost.text) : null),
            ],
          ),
      success: 'تم الترحيل',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(StockDocKind.label(widget.kind))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(l.product.nameAr, style: const TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.remove(l))),
                  ]),
                  Text('الرصيد المسجل: ${Fmt.qty(l.product.quantity)} ${l.product.unitName}'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: QtyField(
                        controller: l.qty,
                        label: _isAdj ? 'الكمية الفعلية' : 'الكمية',
                        allowZero: _isAdj,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_withCost) ...[const SizedBox(width: 8), Expanded(child: MoneyField(controller: l.cost, label: 'تكلفة الوحدة'))],
                  ]),
                  if (_isAdj && l.qty.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('الفرق: ${Fmt.qty(parseQty(l.qty.text) - l.product.quantity)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة منتج'),
            onPressed: () async {
              final p = await pickProduct(context);
              if (p != null) _add(p);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'السبب *'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'السبب مطلوب' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _busy ? null : _post, icon: const Icon(Icons.check), label: const Text('ترحيل')),
        ]),
      ),
    );
  }
}

/// Stock movement ledger for one product.
class StockHistoryScreen extends ConsumerWidget {
  const StockHistoryScreen({super.key, required this.productId, required this.name});
  final int productId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text('حركة: $name')),
      body: FutureLoader<List<StockMovement>>(
        load: () => (db.select(db.stockMovements)
              ..where((t) => t.productId.equals(productId))
              ..orderBy([(t) => OrderingTerm.desc(t.id)]))
            .get(),
        builder: (c, list, _) => list.isEmpty
            ? const EmptyView(icon: Icons.history, title: 'لا توجد حركات')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final m = list[i];
                  final up = m.quantityDelta > 0;
                  return ListTile(
                    leading: Icon(up ? Icons.arrow_downward : Icons.arrow_upward, color: up ? Colors.green : Colors.red),
                    title: Text(MovementType.label(m.movementType)),
                    subtitle: Text([Fmt.dateTime(m.occurredAt), if (m.reason != null) m.reason!, if (m.unitCost != null) 'تكلفة ${Fmt.money(m.unitCost!)}'].join(' • ')),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${up ? '+' : ''}${Fmt.qty(m.quantityDelta)}', style: TextStyle(fontWeight: FontWeight.bold, color: up ? Colors.green : Colors.red)),
                      Text('الرصيد ${Fmt.qty(m.balanceAfter)}', style: const TextStyle(fontSize: 11)),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

/// S11 — Stocktaking sessions.
class StocktakingListScreen extends ConsumerStatefulWidget {
  const StocktakingListScreen({super.key});
  @override
  ConsumerState<StocktakingListScreen> createState() => _StocktakingListScreenState();
}

class _StocktakingListScreenState extends ConsumerState<StocktakingListScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('جرد المخزون')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_count',
        icon: const Icon(Icons.add),
        label: const Text('جرد جديد'),
        onPressed: () async {
          final scope = await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(title: const Text('نطاق الجرد'), children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(c, 'all'), child: const Text('كل المنتجات النشطة')),
              SimpleDialogOption(onPressed: () => Navigator.pop(c, 'pick'), child: const Text('اختيار منتجات محددة')),
            ]),
          );
          if (scope == null || !context.mounted) return;
          List<int>? ids;
          if (scope == 'pick') {
            ids = [];
            while (true) {
              final p = await pickProduct(context, title: 'أضف منتجًا للجرد (${ids.length}) — اضغط رجوع للانتهاء');
              if (p == null) break;
              if (!ids.contains(p.id)) ids.add(p.id);
              if (!context.mounted) return;
            }
            if (ids.isEmpty) return;
          }
          if (!context.mounted) return;
          final id = await runAction(context, () => ref.read(stockDocumentsServiceProvider).startCount(productIds: ids));
          if (id != null && context.mounted) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => StocktakingDetailScreen(countId: id)));
            setState(() => _v++);
          }
        },
      ),
      body: FutureLoader<List<StockCount>>(
        reloadKey: _v,
        load: () => (db.select(db.stockCounts)..orderBy([(t) => OrderingTerm.desc(t.id)])).get(),
        builder: (c, list, _) => list.isEmpty
            ? const EmptyView(icon: Icons.fact_check_outlined, title: 'لا توجد عمليات جرد')
            : ListView(children: [
                for (final s in list)
                  ListTile(
                    leading: Icon(s.status == 'posted' ? Icons.check_circle : (s.status == 'draft' ? Icons.edit_note : Icons.cancel)),
                    title: Text(s.countNumber, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                    subtitle: Text('${Fmt.dateTime(s.startedAt)} • ${switch (s.status) { 'draft' => 'مسودة', 'posted' => 'مُرحّل', _ => 'ملغي' }}'),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => StocktakingDetailScreen(countId: s.id)));
                      setState(() => _v++);
                    },
                  ),
              ]),
      ),
    );
  }
}

class _CountRow {
  final StockCountLine line;
  final String name;
  final String sku;
  final TextEditingController ctrl;
  _CountRow(this.line, this.name, this.sku) : ctrl = TextEditingController(text: line.countedQuantity == null ? '' : Qty(line.countedQuantity!).toPlain());
}

class StocktakingDetailScreen extends ConsumerStatefulWidget {
  const StocktakingDetailScreen({super.key, required this.countId});
  final int countId;
  @override
  ConsumerState<StocktakingDetailScreen> createState() => _StocktakingDetailScreenState();
}

class _StocktakingDetailScreenState extends ConsumerState<StocktakingDetailScreen> {
  StockCount? _count;
  List<_CountRow> _rows = [];
  bool _onlyDiff = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final c = await (db.select(db.stockCounts)..where((t) => t.id.equals(widget.countId))).getSingle();
    final rows = await db.customSelect('''
      SELECT l.*, p.name_ar, p.internal_sku FROM stock_count_lines l JOIN products p ON p.id = l.product_id
      WHERE l.stock_count_id = ? ORDER BY p.name_ar''', variables: [Variable.withInt(widget.countId)]).get();
    if (!mounted) return;
    setState(() {
      _count = c;
      _rows = [for (final r in rows) _CountRow(db.stockCountLines.map(r.data), r.read<String>('name_ar'), r.read<String>('internal_sku'))];
    });
  }

  Future<void> _save(_CountRow r) async {
    final t = r.ctrl.text.trim();
    final q = t.isEmpty ? null : Qty.tryParse(t);
    if (t.isNotEmpty && (q == null || q.isNegative)) {
      showSnack(context, 'كمية غير صحيحة', error: true);
      return;
    }
    await runAction(context, () => ref.read(stockDocumentsServiceProvider).setCounted(r.line.id, q?.milli));
  }

  @override
  Widget build(BuildContext context) {
    final c = _count;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final draft = c.status == 'draft';
    int? counted(_CountRow r) => r.ctrl.text.trim().isEmpty ? null : Qty.tryParse(r.ctrl.text)?.milli;
    final countedN = _rows.where((r) => counted(r) != null).length;
    final diffs = _rows.where((r) => counted(r) != null && counted(r) != r.line.expectedQuantity).length;
    final shown = _rows.where((r) {
      if (_onlyDiff && (counted(r) == null || counted(r) == r.line.expectedQuantity)) return false;
      if (_filter.isNotEmpty && !r.name.contains(_filter) && !r.sku.toLowerCase().contains(_filter.toLowerCase())) return false;
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text('جرد ${c.countNumber}'), actions: [
        if (draft)
          IconButton(
            tooltip: 'إلغاء الجرد',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'إلغاء الجرد', 'لن تُرحّل أي تسويات.', destructive: true) || !context.mounted) return;
              await runAction(context, () => ref.read(stockDocumentsServiceProvider).cancelCount(c.id));
              _load();
            },
          ),
      ]),
      bottomNavigationBar: draft
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text('مراجعة وترحيل ($diffs فروق)'),
                  onPressed: () async {
                    for (final r in _rows) {
                      await ref.read(stockDocumentsServiceProvider).setCounted(r.line.id, counted(r));
                    }
                    if (!context.mounted) return;
                    final ok = await confirm(context, 'ترحيل الجرد',
                        'تم عد $countedN من ${_rows.length} منتج.\nسيتم ترحيل $diffs تسوية (الفرق = الفعلي − المتوقع وقت بدء الجرد).\nالمنتجات غير المعدودة لن تتغير.',
                        ok: 'ترحيل');
                    if (!ok || !context.mounted) return;
                    await runAction(context, () => ref.read(stockDocumentsServiceProvider).postCount(c.id), success: 'تم ترحيل الجرد');
                    if (context.mounted) bumpCatalog(ref);
                    _load();
                  },
                ),
              ),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث'),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('الفروق فقط'), selected: _onlyDiff, onSelected: (v) => setState(() => _onlyDiff = v)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('تم العد: $countedN / ${_rows.length} • فروق: $diffs • ${switch (c.status) { 'draft' => 'مسودة — يمكنك الحفظ والعودة لاحقًا', 'posted' => 'مُرحّل', _ => 'ملغي' }}'),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (ctx, i) {
              final r = shown[i];
              final cq = counted(r);
              final v = cq == null ? null : cq - r.line.expectedQuantity;
              return ListTile(
                title: Text(r.name),
                subtitle: Text('المتوقع: ${Fmt.qty(r.line.expectedQuantity)}${v == null ? '' : ' • الفرق: ${v > 0 ? '+' : ''}${Fmt.qty(v)}'}',
                    style: TextStyle(color: v == null || v == 0 ? null : Colors.red.shade700)),
                trailing: SizedBox(
                  width: 90,
                  child: TextField(
                    controller: r.ctrl,
                    enabled: draft,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'العدد'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(r),
                    onTapOutside: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (draft) _save(r);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Verifies stored balances == SUM(movements).
class ReconcileScreen extends ConsumerStatefulWidget {
  const ReconcileScreen({super.key});
  @override
  ConsumerState<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends ConsumerState<ReconcileScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    final inv = ref.read(inventoryServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('مطابقة المخزون')),
      body: FutureLoader<List<ReconciliationIssue>>(
        reloadKey: _v,
        load: inv.reconcile,
        builder: (c, issues, _) => issues.isEmpty
            ? const EmptyView(icon: Icons.verified, title: 'كل الأرصدة مطابقة لسجل الحركات ✔')
            : ListView(children: [
                ListTile(title: Text('${issues.length} منتج غير مطابق')),
                for (final i in issues)
                  ListTile(title: Text(i.name), subtitle: Text('المسجل ${Fmt.qty(i.stored)} • من الحركات ${Fmt.qty(i.ledger)}')),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () async {
                      await runAction(context, inv.rebuildBalancesFromLedger, success: 'تمت إعادة بناء الأرصدة من الحركات');
                      setState(() => _v++);
                    },
                    child: const Text('إعادة بناء الأرصدة من سجل الحركات'),
                  ),
                ),
              ]),
      ),
    );
  }
}
