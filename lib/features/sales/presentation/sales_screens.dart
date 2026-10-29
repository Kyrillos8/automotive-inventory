import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../customers/customer_repository.dart';
import '../../customers/presentation/customer_screens.dart';
import '../../products/presentation/product_search_view.dart';
import '../../products/product_providers.dart';
import '../invoice_draft.dart';
import '../sales_service.dart';

/// Sales tab: invoice list.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  String _q = '';
  String? _status;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogVersionProvider, (_, __) => setState(() => _v++));
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات'), actions: [
        IconButton(
          tooltip: 'العملاء',
          icon: const Icon(Icons.people_outline),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_invoice',
        icon: const Icon(Icons.add),
        label: const Text('فاتورة بيع'),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()));
          setState(() => _v++);
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'رقم الفاتورة أو اسم العميل'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            for (final e in const {null: 'الكل', SaleStatus.draft: 'مسودات', SaleStatus.posted: 'مُرحّلة', SaleStatus.voided: 'ملغاة'}.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
              ),
          ]),
        ),
        Expanded(
          child: FutureLoader<List<SaleSummary>>(
            reloadKey: '$_q|$_status|$_v',
            load: () => ref.read(salesServiceProvider).summaries(text: _q, status: _status, limit: 300),
            builder: (c, list, reload) => list.isEmpty
                ? const EmptyView(icon: Icons.receipt_long, title: 'لا توجد فواتير')
                : RefreshIndicator(
                    onRefresh: () async => reload(),
                    child: ListView(children: [for (final s in list) SaleSummaryTile(s, onChanged: () => setState(() => _v++))]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class SaleSummaryTile extends StatelessWidget {
  const SaleSummaryTile(this.s, {super.key, required this.onChanged});
  final SaleSummary s;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final st = s.sale.status;
    final (label, color) = switch (st) {
      SaleStatus.draft => ('مسودة', Colors.grey),
      SaleStatus.voided => ('ملغاة', Colors.grey),
      _ => switch (s.paymentStatus) {
          PaymentStatus.paid => ('مدفوعة', Colors.green),
          PaymentStatus.partial => ('جزئي', Colors.orange),
          _ => ('غير مدفوعة', Colors.red),
        },
    };
    return Card(
      child: ListTile(
        title: Text('${s.sale.invoiceNumber} • ${s.customerName}'),
        subtitle: Text('${Fmt.dateTime(s.sale.invoiceDate)} • ${PricingMode.label(s.sale.pricingMode)}'
            '${st == SaleStatus.posted && s.outstanding > 0 ? ' • متبقي ${Fmt.money(s.outstanding)}' : ''}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.money(s.sale.grandTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ]),
        onTap: () async {
          if (st == SaleStatus.draft) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceBuilderScreen(saleId: s.sale.id)));
          } else {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(saleId: s.sale.id)));
          }
          onChanged();
        },
      ),
    );
  }
}

// ======================================================= invoice builder

/// S16 — Sales invoice builder.
class InvoiceBuilderScreen extends ConsumerStatefulWidget {
  const InvoiceBuilderScreen({super.key, this.saleId, this.initialCustomer});
  final int? saleId;
  final Customer? initialCustomer;
  @override
  ConsumerState<InvoiceBuilderScreen> createState() => _InvoiceBuilderScreenState();
}

class _InvoiceBuilderScreenState extends ConsumerState<InvoiceBuilderScreen> {
  InvoiceDraft? _d;
  bool _busy = false;
  final _discount = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.saleId != null) {
      ref.read(salesServiceProvider).loadDraft(widget.saleId!).then((d) {
        if (!mounted) return;
        setState(() {
          _d = d;
          if (d.invoiceDiscount > 0) _discount.text = Money(d.invoiceDiscount).toPlain();
        });
      });
    } else {
      final c = widget.initialCustomer;
      _d = InvoiceDraft(customerId: c?.id, customerName: c?.name, customerType: c?.customerType);
    }
  }

  Future<void> _chooseCustomer() async {
    final d = _d!;
    final c = await Navigator.push<Object>(context, MaterialPageRoute(builder: (_) => const _CustomerPicker()));
    if (c == null || !mounted) return;
    final customer = c is Customer ? c : null; // 'walkin' sentinel
    final newMode = PricingMode.forCustomerType(customer?.customerType);
    var reset = false;
    if (newMode != d.pricingMode && d.hasManualOverrides) {
      final r = await _askResetOverrides();
      if (r == null) return;
      reset = r;
    }
    setState(() => d.setCustomer(customer?.id, customer?.name, customer?.customerType, resetOverrides: reset));
  }

  /// Returns true = reset manual prices, false = keep them, null = cancel.
  Future<bool?> _askResetOverrides() => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('أسعار معدلة يدويًا'),
          content: const Text('بعض الأسطر لها أسعار عدّلتها يدويًا. هل تريد الاحتفاظ بها أم إعادتها لأسعار نوع التسعير الجديد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('إعادة ضبط الأسعار')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('الاحتفاظ بالأسعار اليدوية')),
          ],
        ),
      );

  Future<void> _changeMode(String mode) async {
    final d = _d!;
    if (mode == d.pricingMode) return;
    var reset = false;
    if (d.hasManualOverrides) {
      final r = await _askResetOverrides();
      if (r == null) return;
      reset = r;
    }
    setState(() => d.setPricingMode(mode, resetOverrides: reset));
  }

  Future<void> _addProducts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (c) => Scaffold(
          appBar: AppBar(title: const Text('إضافة أصناف'), actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text('تم', style: TextStyle(color: Theme.of(c).colorScheme.onPrimary))),
          ]),
          body: ProductSearchView(
            autofocus: true,
            onTap: (p) {
              setState(() => _d!.addProduct(
                    productId: p.id,
                    name: p.nameAr,
                    sku: p.sku,
                    wholesalePrice: p.wholesalePrice,
                    retailPrice: p.retailPrice,
                    available: p.quantity,
                  ));
              ScaffoldMessenger.of(c)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('أُضيف: ${p.nameAr}'), duration: const Duration(milliseconds: 900)));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editPrice(DraftLine l) async {
    final ctrl = TextEditingController(text: Money(l.unitPrice).toPlain());
    final r = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('سعر ${l.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('جملة: ${Fmt.money(l.wholesalePrice)} • قطاعي: ${Fmt.money(l.retailPrice)}'),
          const SizedBox(height: 10),
          MoneyField(controller: ctrl, label: 'سعر الوحدة'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, -1), child: const Text('السعر الافتراضي')),
          FilledButton(
            onPressed: () {
              final m = Money.tryParse(ctrl.text);
              if (m == null || m.isNegative) return;
              Navigator.pop(c, m.minor);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (r == null) return;
    setState(() => r == -1 ? _d!.resetLinePrice(l) : _d!.setLinePrice(l, r));
  }

  Future<void> _editQty(DraftLine l) async {
    final ctrl = TextEditingController(text: Qty(l.quantity).toPlain());
    final disc = TextEditingController(text: l.discount == 0 ? '' : Money(l.discount).toPlain());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المتاح: ${Fmt.qty(l.available)}'),
          const SizedBox(height: 8),
          QtyField(controller: ctrl, label: 'الكمية'),
          const SizedBox(height: 8),
          MoneyField(controller: disc, label: 'خصم على السطر'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final q = Qty.tryParse(ctrl.text);
    if (q == null || q.milli <= 0) return;
    setState(() {
      l.quantity = q.milli;
      l.discount = parseMoney(disc.text);
    });
  }

  Future<void> _saveDraft() async {
    _d!.invoiceDiscount = parseMoney(_discount.text);
    setState(() => _busy = true);
    final id = await runAction(context, () => ref.read(salesServiceProvider).saveDraft(_d!), success: 'تم حفظ المسودة');
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) Navigator.pop(context);
  }

  Future<void> _post() async {
    final d = _d!..invoiceDiscount = parseMoney(_discount.text);
    final errs = d.validate();
    if (errs.isNotEmpty) {
      showSnack(context, errs.first, error: true);
      return;
    }
    final short = d.lines.where((l) => l.exceedsStock).toList();
    if (short.isNotEmpty) {
      showSnack(context, 'الكمية غير كافية: ${short.map((l) => l.name).join('، ')}', error: true);
      return;
    }
    final pay = await showDialog<(int, String)>(context: context, builder: (_) => _PaymentDialog(total: d.grandTotal));
    if (pay == null || !mounted) return;
    setState(() => _busy = true);
    final id = await runAction(
      context,
      () => ref.read(salesServiceProvider).post(d, initialPayment: pay.$1, paymentMethod: pay.$2),
      success: 'تم ترحيل الفاتورة',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      bumpCatalog(ref);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(saleId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    d.invoiceDiscount = parseMoney(_discount.text);
    return Scaffold(
      appBar: AppBar(title: Text(d.saleId == null ? 'فاتورة بيع جديدة' : 'تعديل مسودة'), actions: [
        if (d.saleId != null)
          IconButton(
            tooltip: 'حذف المسودة',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'حذف المسودة', 'حذف هذه المسودة نهائيًا؟', destructive: true) || !context.mounted) return;
              final r = await runAction(context, () async {
                await ref.read(salesServiceProvider).deleteDraft(d.saleId!);
                return true;
              });
              if (r == true && context.mounted) Navigator.pop(context);
            },
          ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), children: [
        Card(
          child: ListTile(
            leading: Icon(d.customerId == null ? Icons.person_outline : Icons.person),
            title: Text(d.customerName ?? 'عميل نقدي (قطاعي)'),
            subtitle: Text(d.customerId == null ? 'بدون حساب' : 'عميل ${CustomerType.label(d.customerType ?? 'retail')}'),
            trailing: const Icon(Icons.swap_horiz),
            onTap: _chooseCustomer,
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          const Text('التسعير: '),
          const SizedBox(width: 8),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: PricingMode.wholesale, label: Text('جملة')),
                ButtonSegment(value: PricingMode.retail, label: Text('قطاعي')),
              ],
              selected: {d.pricingMode},
              onSelectionChanged: (s) => _changeMode(s.first),
            ),
          ),
        ]),
        if (d.pricingMode != PricingMode.forCustomerType(d.customerType))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('⚠️ نوع التسعير مختلف عن نوع العميل', style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(onPressed: _addProducts, icon: const Icon(Icons.search), label: const Text('بحث وإضافة أصناف')),
        const SizedBox(height: 8),
        if (d.lines.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لم تُضف أصناف بعد'))),
        for (final l in d.lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => d.lines.remove(l))),
                ]),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: l.quantity > 1000 ? () => setState(() => l.quantity -= 1000) : null,
                  ),
                  InkWell(
                    onTap: () => _editQty(l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(Fmt.qty(l.quantity), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => l.quantity += 1000)),
                  const Spacer(),
                  InkWell(
                    onTap: () => _editPrice(l),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Row(children: [
                        if (l.isManual)
                          Container(
                            margin: const EdgeInsetsDirectional.only(end: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            color: Colors.amber.shade100,
                            child: const Text('يدوي', style: TextStyle(fontSize: 11)),
                          ),
                        Text('× ${Fmt.money(l.unitPrice)}'),
                        const Icon(Icons.edit, size: 14),
                      ]),
                      Text(Fmt.money(l.lineTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (l.discount > 0) Text('خصم ${Fmt.money(l.discount)}', style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                ]),
                Text(
                  'المتاح: ${Fmt.qty(l.available)}${l.exceedsStock ? ' — الكمية غير كافية!' : ''}',
                  style: TextStyle(fontSize: 12, color: l.exceedsStock ? Colors.red : Theme.of(context).colorScheme.outline),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        MoneyField(controller: _discount, label: 'خصم إضافي على الفاتورة', onChanged: (_) => setState(() {})),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('الإجمالي قبل الخصم: ${Fmt.money(d.subtotal)}', style: const TextStyle(fontSize: 12))),
              if (d.discountTotal > 0) Text('الخصم: ${Fmt.money(d.discountTotal)}', style: const TextStyle(fontSize: 12)),
            ]),
            Row(children: [
              Expanded(child: Text('الصافي: ${Fmt.money(d.grandTotal)}', style: Theme.of(context).textTheme.titleLarge)),
              OutlinedButton(onPressed: _busy || d.lines.isEmpty ? null : _saveDraft, child: const Text('مسودة')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy || d.lines.isEmpty ? null : _post, child: const Text('ترحيل')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total, this.forInvoice = true});
  final int total;
  final bool forInvoice;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final amount = TextEditingController(text: Money(widget.total).toPlain());
  String method = 'cash';
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('الدفع'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.forInvoice ? 'إجمالي الفاتورة' : 'المتبقي'}: ${Fmt.money(widget.total)}'),
        const SizedBox(height: 10),
        MoneyField(controller: amount, label: 'المبلغ المدفوع الآن'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: method,
          decoration: const InputDecoration(labelText: 'طريقة الدفع'),
          items: [for (final m in PaymentMethod.all) DropdownMenuItem(value: m, child: Text(PaymentMethod.label(m)))],
          onChanged: (v) => setState(() => method = v ?? 'cash'),
        ),
        const SizedBox(height: 6),
        if (widget.forInvoice) const Text('اترك المبلغ 0 لتسجيل الفاتورة آجلة.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final m = amount.text.trim().isEmpty ? Money.zero : Money.tryParse(amount.text);
            if (m == null || m.isNegative || m.minor > widget.total) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ غير صحيح')));
              return;
            }
            Navigator.pop(context, (m.minor, method));
          },
          child: Text(widget.forInvoice ? 'ترحيل الفاتورة' : 'تسجيل الدفعة'),
        ),
      ],
    );
  }
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار العميل')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('عميل نقدي (قطاعي)'),
          onTap: () => Navigator.pop(context, 'walkin'),
        ),
        ListTile(
          leading: const Icon(Icons.person_add),
          title: const Text('عميل جديد'),
          onTap: () async {
            final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const CustomerFormScreen()));
            if (id == null || !context.mounted) return;
            final db = ref.read(databaseProvider);
            final c = await (db.select(db.customers)..where((t) => t.id.equals(id))).getSingle();
            if (context.mounted) Navigator.pop(context, c);
          },
        ),
        const Divider(),
        Expanded(
          child: FutureLoader<List<Customer>>(
            reloadKey: '$_q|$_v',
            load: () => ref.read(customerRepositoryProvider).searchCustomers(_q),
            builder: (c, list, _) => ListView(children: [
              for (final cu in list)
                ListTile(
                  leading: CircleAvatar(child: Text(cu.customerType == CustomerType.wholesale ? 'ج' : 'ق')),
                  title: Text(cu.name),
                  subtitle: Text('${CustomerType.label(cu.customerType)}${cu.phone == null ? '' : ' • ${cu.phone}'}'),
                  onTap: () => Navigator.pop(context, cu),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ======================================================= invoice details

class _InvoiceData {
  final SaleSummary s;
  final List<ReturnableLine> lines;
  final List<SalePayment> payments;
  final List<SalesReturn> returns;
  _InvoiceData(this.s, this.lines, this.payments, this.returns);
}

/// S17 — Invoice details, payments, returns, void.
class InvoiceDetailsScreen extends ConsumerStatefulWidget {
  const InvoiceDetailsScreen({super.key, required this.saleId});
  final int saleId;
  @override
  ConsumerState<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends ConsumerState<InvoiceDetailsScreen> {
  int _v = 0;

  Future<_InvoiceData> _load() async {
    final svc = ref.read(salesServiceProvider);
    final db = ref.read(databaseProvider);
    return _InvoiceData(
      await svc.summary(widget.saleId),
      await svc.returnableLines(widget.saleId),
      await (db.select(db.salePayments)..where((t) => t.saleId.equals(widget.saleId))).get(),
      await (db.select(db.salesReturns)..where((t) => t.saleId.equals(widget.saleId))).get(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(salesServiceProvider);
    return FutureLoader<_InvoiceData>(
      reloadKey: _v,
      load: _load,
      builder: (context, d, _) {
        final s = d.s;
        final posted = s.sale.status == SaleStatus.posted;
        final reversed = d.payments.where((p) => p.reversesPaymentId != null).map((p) => p.reversesPaymentId).toSet();
        return Scaffold(
          appBar: AppBar(title: Text(s.sale.invoiceNumber), actions: [
            if (posted)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'void') {
                    final reason = await promptText(context, 'إلغاء الفاتورة', label: 'سبب الإلغاء');
                    if (reason == null || !context.mounted) return;
                    if (!await confirm(context, 'تأكيد الإلغاء', 'سيتم إرجاع الكميات للمخزون وتعليم الفاتورة كملغاة.', destructive: true)) return;
                    if (!context.mounted) return;
                    await runAction(context, () => svc.voidSale(s.sale.id, reason), success: 'تم الإلغاء');
                    bumpCatalog(ref);
                    setState(() => _v++);
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'void', child: Text('إلغاء الفاتورة'))],
              ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  InfoRow('العميل', s.customerName),
                  InfoRow('التاريخ', Fmt.dateTime(s.sale.invoiceDate)),
                  InfoRow('نوع التسعير', PricingMode.label(s.sale.pricingMode)),
                  InfoRow('الحالة', s.sale.status == SaleStatus.voided ? 'ملغاة' : (posted ? PaymentStatus.label(s.paymentStatus) : 'مسودة')),
                  InfoRow('ملاحظات', s.sale.notes),
                ]),
              ),
            ),
            const SectionTitle('الأصناف'),
            for (final l in d.lines)
              ListTile(
                dense: true,
                title: Text(l.productName),
                subtitle: Text('${Fmt.qty(l.line.quantity)} × ${Fmt.money(l.line.unitPrice)} (${PriceType.label(l.line.priceType)})'
                    '${l.line.discountAmount > 0 ? ' • خصم ${Fmt.money(l.line.discountAmount)}' : ''}'
                    '${l.returnedSoFar > 0 ? ' • مرتجع ${Fmt.qty(l.returnedSoFar)}' : ''}'),
                trailing: Text(Fmt.money(l.line.lineTotal)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  InfoRow('الإجمالي قبل الخصم', Fmt.money(s.sale.subtotal)),
                  if (s.sale.discountTotal > 0) InfoRow('الخصم', Fmt.money(s.sale.discountTotal)),
                  InfoRow('صافي الفاتورة', Fmt.money(s.sale.grandTotal)),
                  if (s.returned > 0) InfoRow('مرتجعات', Fmt.money(s.returned)),
                  if (s.refunded > 0) InfoRow('مبالغ مستردة نقدًا', Fmt.money(s.refunded)),
                  InfoRow('المدفوع', Fmt.money(s.paid)),
                  InfoRow(s.outstanding >= 0 ? 'المتبقي' : 'رصيد دائن للعميل', Fmt.money(s.outstanding.abs())),
                ]),
              ),
            ),
            if (posted)
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.payments),
                    label: const Text('تسجيل دفعة'),
                    onPressed: s.outstanding <= 0
                        ? null
                        : () async {
                            final r = await showDialog<(int, String)>(context: context, builder: (_) => _PaymentDialog(total: s.outstanding, forInvoice: false));
                            if (r == null || r.$1 <= 0 || !context.mounted) return;
                            await runAction(context, () => svc.addPayment(s.sale.id, r.$1, r.$2), success: 'تم تسجيل الدفعة');
                            setState(() => _v++);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.assignment_return),
                    label: const Text('مرتجع'),
                    onPressed: d.lines.every((l) => l.returnable <= 0)
                        ? null
                        : () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => SalesReturnScreen(saleId: s.sale.id)));
                            setState(() => _v++);
                          },
                  ),
                ),
              ]),
            const SectionTitle('المدفوعات'),
            if (d.payments.isEmpty) const Text('لا توجد مدفوعات'),
            for (final p in d.payments)
              ListTile(
                dense: true,
                leading: Icon(p.amount < 0 ? Icons.undo : Icons.payments_outlined),
                title: Text('${Fmt.money(p.amount)} • ${PaymentMethod.label(p.paymentMethod)}'),
                subtitle: Text('${Fmt.dateTime(p.paymentDate)}${p.notes == null ? '' : ' • ${p.notes}'}'),
                trailing: p.amount > 0 && !reversed.contains(p.id)
                    ? TextButton(
                        onPressed: () async {
                          final reason = await promptText(context, 'عكس الدفعة', label: 'السبب');
                          if (reason == null || !context.mounted) return;
                          await runAction(context, () => svc.reversePayment(p.id, reason), success: 'تم عكس الدفعة');
                          setState(() => _v++);
                        },
                        child: const Text('عكس'),
                      )
                    : (reversed.contains(p.id) ? const Text('معكوسة') : null),
              ),
            if (d.returns.isNotEmpty) ...[
              const SectionTitle('المرتجعات'),
              for (final r in d.returns)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.assignment_return),
                  title: Text('${r.returnNumber} • ${Fmt.money(r.returnTotal)}'),
                  subtitle: Text('${Fmt.dateTime(r.returnDate)}${r.refundAmount > 0 ? ' • مسترد ${Fmt.money(r.refundAmount)}' : ''}'),
                ),
            ],
          ]),
        );
      },
    );
  }
}

// ======================================================= returns

/// S18 — Sales return.
class SalesReturnScreen extends ConsumerStatefulWidget {
  const SalesReturnScreen({super.key, required this.saleId});
  final int saleId;
  @override
  ConsumerState<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _RetCtrl {
  final ReturnableLine l;
  final qty = TextEditingController();
  final damaged = TextEditingController();
  _RetCtrl(this.l);
}

class _SalesReturnScreenState extends ConsumerState<SalesReturnScreen> {
  List<_RetCtrl>? _rows;
  SaleSummary? _s;
  final _refund = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(salesServiceProvider);
    Future.wait([svc.returnableLines(widget.saleId), svc.summary(widget.saleId)]).then((r) {
      if (!mounted) return;
      setState(() {
        _rows = [for (final l in r[0] as List<ReturnableLine>) if (l.returnable > 0) _RetCtrl(l)];
        _s = r[1] as SaleSummary;
      });
    });
  }

  int get _value => _rows!.fold(0, (a, r) => a + r.l.valueFor(parseQty(r.qty.text)));

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final s = _s;
    if (rows == null || s == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final value = _value;
    final overpaid = -(s.outstanding - value);
    final maxRefund = overpaid > 0 ? overpaid : 0;
    return Scaffold(
      appBar: AppBar(title: Text('مرتجع على ${s.sale.invoiceNumber}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final r in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.l.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('مباع ${Fmt.qty(r.l.line.quantity)} بسعر ${Fmt.money(r.l.line.unitPrice)} • متاح للإرجاع ${Fmt.qty(r.l.returnable)}'),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: QtyField(controller: r.qty, label: 'الكمية المرتجعة', required: false, allowZero: true, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: QtyField(controller: r.damaged, label: 'منها تالف (لا يعود للمخزون)', required: false, allowZero: true, onChanged: (_) => setState(() {}))),
                ]),
              ]),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              InfoRow('قيمة المرتجع', Fmt.money(value)),
              InfoRow('المتبقي على الفاتورة حاليًا', Fmt.money(s.outstanding)),
              InfoRow('يمكن رده نقدًا', Fmt.money(maxRefund)),
            ]),
          ),
        ),
        if (maxRefund > 0) ...[
          MoneyField(controller: _refund, label: 'المبلغ المسترد نقدًا الآن'),
          const SizedBox(height: 4),
          const Text('أي مبلغ لا يُرد نقدًا يبقى رصيدًا دائنًا للعميل.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(labelText: 'طريقة الرد'),
            items: [for (final m in PaymentMethod.all) DropdownMenuItem(value: m, child: Text(PaymentMethod.label(m)))],
            onChanged: (v) => setState(() => _method = v ?? 'cash'),
          ),
        ] else
          const Text('قيمة المرتجع ستُخصم من المتبقي على الفاتورة.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'سبب الإرجاع / ملاحظات')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || value <= 0
              ? null
              : () async {
                  if (!await confirm(context, 'ترحيل المرتجع', 'قيمة المرتجع ${Fmt.money(value)}. لا يمكن التراجع بعد الترحيل.', ok: 'ترحيل')) return;
                  if (!context.mounted) return;
                  setState(() => _busy = true);
                  final id = await runAction(
                    context,
                    () => ref.read(salesServiceProvider).postReturn(
                          widget.saleId,
                          [for (final r in rows) ReturnLineInput(r.l.line.id, parseQty(r.qty.text), parseQty(r.damaged.text))],
                          refundAmount: parseMoney(_refund.text),
                          refundMethod: _method,
                          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      ]),
    );
  }
}
