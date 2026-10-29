import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';

abstract final class CustomerType {
  static const wholesale = 'wholesale';
  static const retail = 'retail';
  static String label(String t) => t == wholesale ? 'جملة' : 'قطاعي';
}

class CustomerInput {
  int? id;
  String name = '';
  String? phone;
  String? email;
  String? address;
  String customerType = CustomerType.retail;
  String? notes;
}

class CustomerBalance {
  final Customer customer;
  final int totalSales; // posted, net of returns
  final int totalPayments;
  final int totalRefunds;
  CustomerBalance(this.customer, this.totalSales, this.totalPayments, this.totalRefunds);
  /// Positive = customer owes; negative = customer credit.
  int get outstanding => totalSales + totalRefunds - totalPayments;
}

class CustomerRepository {
  CustomerRepository(this.db);
  final AppDatabase db;

  Future<int> save(CustomerInput c) async {
    if (c.name.trim().isEmpty) throw const BusinessException('اسم العميل مطلوب');
    final comp = CustomersCompanion(
      name: Value(c.name.trim()),
      phone: Value(_n(c.phone)),
      email: Value(_n(c.email)),
      address: Value(_n(c.address)),
      customerType: Value(c.customerType),
      notes: Value(_n(c.notes)),
      updatedAt: Value(DateTime.now()),
    );
    if (c.id == null) {
      final id = await db.into(db.customers).insert(comp);
      await db.logActivity('create', 'customer', 'إضافة عميل: ${c.name.trim()}', entityId: id);
      return id;
    }
    // Changing type affects future default pricing only; posted invoices are untouched.
    await (db.update(db.customers)..where((t) => t.id.equals(c.id!))).write(comp);
    return c.id!;
  }

  Future<void> setActive(int id, bool active) =>
      (db.update(db.customers)..where((t) => t.id.equals(id))).write(CustomersCompanion(isActive: Value(active)));

  Future<List<CustomerBalance>> balances({String text = '', bool includeArchived = false, int? id}) async {
    final where = <String>[];
    final vars = <Variable>[];
    if (!includeArchived) where.add('c.is_active = 1');
    if (id != null) {
      where.add('c.id = ?');
      vars.add(Variable.withInt(id));
    }
    if (text.trim().isNotEmpty) {
      where.add("(c.name LIKE ? OR COALESCE(c.phone,'') LIKE ?)");
      vars.add(Variable.withString('%${text.trim()}%'));
      vars.add(Variable.withString('%${text.trim()}%'));
    }
    final rows = await db.customSelect('''
      SELECT c.*,
        COALESCE((SELECT SUM(s.grand_total) FROM sales s WHERE s.customer_id = c.id AND s.status = 'posted'), 0)
          - COALESCE((SELECT SUM(r.return_total) FROM sales_returns r JOIN sales s ON s.id = r.sale_id WHERE s.customer_id = c.id), 0) AS total_sales,
        COALESCE((SELECT SUM(p.amount) FROM sale_payments p JOIN sales s ON s.id = p.sale_id WHERE s.customer_id = c.id), 0) AS total_paid,
        COALESCE((SELECT SUM(r.refund_amount) FROM sales_returns r JOIN sales s ON s.id = r.sale_id WHERE s.customer_id = c.id), 0) AS total_refunds
      FROM customers c
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY c.name
    ''', variables: vars).get();
    return [
      for (final r in rows)
        CustomerBalance(db.customers.map(r.data), r.read<int>('total_sales'), r.read<int>('total_paid'),
            r.read<int>('total_refunds'))
    ];
  }

  Future<List<Customer>> searchCustomers(String text) {
    final q = db.select(db.customers)..where((t) => t.isActive.equals(true));
    if (text.trim().isNotEmpty) {
      q.where((t) => t.name.like('%${text.trim()}%') | t.phone.like('%${text.trim()}%'));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.name)]);
    q.limit(50);
    return q.get();
  }

  static String? _n(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) => CustomerRepository(ref.watch(databaseProvider)));
