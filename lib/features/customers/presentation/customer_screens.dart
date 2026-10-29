import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../sales/presentation/sales_screens.dart';
import '../../sales/sales_service.dart';
import '../customer_repository.dart';

/// S15 — Customers with balances.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _q = '';
  bool _archived = false;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء'), actions: [
        IconButton(
          tooltip: 'إظهار المؤرشفين',
          icon: Icon(_archived ? Icons.inventory : Icons.inventory_2_outlined),
          onPressed: () => setState(() => _archived = !_archived),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_customer',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormScreen()));
          setState(() => _v++);
        },
        child: const Icon(Icons.person_add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الهاتف'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: FutureLoader<List<CustomerBalance>>(
            reloadKey: '$_q|$_archived|$_v',
            load: () => ref.read(customerRepositoryProvider).balances(text: _q, includeArchived: _archived),
            builder: (c, list, _) => list.isEmpty
                ? const EmptyView(icon: Icons.people_outline, title: 'لا يوجد عملاء')
                : ListView(children: [
                    for (final b in list)
                      ListTile(
                        leading: CircleAvatar(child: Text(b.customer.customerType == CustomerType.wholesale ? 'ج' : 'ق')),
                        title: Text(b.customer.name),
                        subtitle: Text('${CustomerType.label(b.customer.customerType)}${b.customer.phone == null ? '' : ' • ${b.customer.phone}'}'
                            '${b.customer.isActive ? '' : ' • مؤرشف'}'),
                        trailing: b.outstanding == 0
                            ? null
                            : Text(
                                b.outstanding > 0 ? 'عليه ${Fmt.money(b.outstanding)}' : 'له ${Fmt.money(-b.outstanding)}',
                                style: TextStyle(color: b.outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold),
                              ),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customerId: b.customer.id)));
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

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customer});
  final Customer? customer;
  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.customer?.name);
  late final phone = TextEditingController(text: widget.customer?.phone);
  late final email = TextEditingController(text: widget.customer?.email);
  late final address = TextEditingController(text: widget.customer?.address);
  late final notes = TextEditingController(text: widget.customer?.notes);
  late String type = widget.customer?.customerType ?? CustomerType.retail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customer == null ? 'عميل جديد' : 'تعديل عميل')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل *'), validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: CustomerType.wholesale, label: Text('عميل جملة')),
              ButtonSegment(value: CustomerType.retail, label: Text('عميل قطاعي')),
            ],
            selected: {type},
            onSelectionChanged: (s) => setState(() => type = s.first),
          ),
          if (widget.customer != null && widget.customer!.customerType != type)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('تغيير النوع يؤثر على تسعير الفواتير الجديدة فقط، ولا يغيّر الفواتير السابقة أو الأرصدة.', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 12),
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف'), keyboardType: TextInputType.phone, textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextFormField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني'), textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextFormField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
          const SizedBox(height: 10),
          TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 2),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final c = CustomerInput()
                ..id = widget.customer?.id
                ..name = name.text
                ..phone = phone.text
                ..email = email.text
                ..address = address.text
                ..notes = notes.text
                ..customerType = type;
              final id = await runAction(context, () => ref.read(customerRepositoryProvider).save(c), success: 'تم الحفظ');
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
            child: const Text('حفظ'),
          ),
        ]),
      ),
    );
  }
}

class CustomerDetailsScreen extends ConsumerStatefulWidget {
  const CustomerDetailsScreen({super.key, required this.customerId});
  final int customerId;
  @override
  ConsumerState<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends ConsumerState<CustomerDetailsScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    return FutureLoader<(CustomerBalance, List<SaleSummary>)>(
      reloadKey: _v,
      load: () async => (
        (await ref.read(customerRepositoryProvider).balances(id: widget.customerId, includeArchived: true)).first,
        await ref.read(salesServiceProvider).summaries(customerId: widget.customerId, limit: 500),
      ),
      builder: (context, d, _) {
        final b = d.$1;
        final c = b.customer;
        final posted = d.$2.where((s) => s.sale.status == SaleStatus.posted).toList();
        return Scaffold(
          appBar: AppBar(title: Text(c.name), actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: c)));
                setState(() => _v++);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (_) async {
                await ref.read(customerRepositoryProvider).setActive(c.id, !c.isActive);
                setState(() => _v++);
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'a', child: Text(c.isActive ? 'أرشفة' : 'إعادة تفعيل'))],
            ),
          ]),
          floatingActionButton: c.isActive
              ? FloatingActionButton.extended(
                  heroTag: 'cust_invoice',
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('فاتورة جديدة'),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceBuilderScreen(initialCustomer: c)));
                    setState(() => _v++);
                  },
                )
              : null,
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  InfoRow('النوع', CustomerType.label(c.customerType)),
                  InfoRow('الهاتف', c.phone, ltr: true),
                  InfoRow('البريد', c.email, ltr: true),
                  InfoRow('العنوان', c.address),
                  InfoRow('ملاحظات', c.notes),
                  const Divider(),
                  InfoRow('صافي المبيعات المرحّلة', Fmt.money(b.totalSales)),
                  InfoRow('إجمالي المدفوعات', Fmt.money(b.totalPayments)),
                  if (b.totalRefunds != 0) InfoRow('مبالغ مستردة للعميل', Fmt.money(b.totalRefunds)),
                  InfoRow(b.outstanding >= 0 ? 'المستحق على العميل' : 'رصيد دائن للعميل', Fmt.money(b.outstanding.abs())),
                ]),
              ),
            ),
            SectionTitle('الفواتير (${posted.length})'),
            if (d.$2.isEmpty) const Text('لا توجد فواتير'),
            for (final s in d.$2) SaleSummaryTile(s, onChanged: () => setState(() => _v++)),
          ]),
        );
      },
    );
  }
}
