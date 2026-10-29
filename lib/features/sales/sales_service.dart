import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';
import '../inventory/inventory_service.dart';
import 'invoice_draft.dart';

abstract final class SaleStatus {
  static const draft = 'draft';
  static const posted = 'posted';
  static const voided = 'void';
}

abstract final class PaymentStatus {
  static const unpaid = 'unpaid';
  static const partial = 'partial';
  static const paid = 'paid';
  static String label(String s) => switch (s) {
        unpaid => 'غير مدفوعة',
        partial => 'مدفوعة جزئيًا',
        paid => 'مدفوعة',
        _ => s,
      };
}

abstract final class PaymentMethod {
  static const all = ['cash', 'bank', 'other'];
  static String label(String m) => switch (m) {
        'cash' => 'نقدي',
        'bank' => 'تحويل بنكي',
        _ => 'أخرى',
      };
}

class SaleSummary {
  final Sale sale;
  final String customerName;
  final String? customerType;
  final int paid;
  final int returned;
  final int refunded;
  SaleSummary(this.sale, this.customerName, this.customerType, this.paid, this.returned, this.refunded);

  /// Amount the customer owes for this invoice (negative = customer credit).
  int get due => sale.grandTotal - returned + refunded;
  int get outstanding => due - paid;
  String get paymentStatus {
    if (sale.status != SaleStatus.posted) return '';
    if (outstanding <= 0) return PaymentStatus.paid;
    if (paid > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }
}

class ReturnLineInput {
  final int saleLineId;
  final int quantity; // milli
  final int damagedQuantity; // milli, part of quantity not restocked
  ReturnLineInput(this.saleLineId, this.quantity, this.damagedQuantity);
}

class ReturnableLine {
  final SaleLine line;
  final String productName;
  final int returnedSoFar;
  ReturnableLine(this.line, this.productName, this.returnedSoFar);
  int get returnable => line.quantity - returnedSoFar;
  /// Net unit value after line discount, used for return value.
  int valueFor(int qty) => line.quantity == 0 ? 0 : ((line.lineTotal * qty) / line.quantity).round();
}

class SalesService {
  SalesService(this.db, this.inventory);
  final AppDatabase db;
  final InventoryService inventory;

  // ---------------------------------------------------------------- drafts
  Future<int> saveDraft(InvoiceDraft d) {
    final errs = d.validate();
    if (errs.isNotEmpty) throw BusinessException(errs.first);
    return _guard(d, () => db.transaction(() => _writeDraft(d)));
  }

  /// If a transaction that assigned a new id rolls back, forget that id.
  Future<T> _guard<T>(InvoiceDraft d, Future<T> Function() body) async {
    final wasNew = d.saleId == null;
    try {
      return await body();
    } catch (_) {
      if (wasNew) d.saleId = null;
      rethrow;
    }
  }

  Future<int> _writeDraft(InvoiceDraft d) async {
    final comp = SalesCompanion(
      customerId: Value(d.customerId),
      pricingMode: Value(d.pricingMode),
      subtotal: Value(d.subtotal),
      discountTotal: Value(d.discountTotal),
      taxTotal: Value(d.taxTotal),
      grandTotal: Value(d.grandTotal),
      notes: Value(d.notes),
      updatedAt: Value(DateTime.now()),
    );
    int id;
    if (d.saleId == null) {
      final number = await db.nextDocNumber('sale');
      id = await db.into(db.sales).insert(comp.copyWith(
            invoiceNumber: Value(number),
            invoiceDate: Value(DateTime.now()),
            status: const Value(SaleStatus.draft),
          ));
      d.saleId = id;
    } else {
      id = d.saleId!;
      final s = await (db.select(db.sales)..where((t) => t.id.equals(id))).getSingle();
      if (s.status != SaleStatus.draft) throw const BusinessException('لا يمكن تعديل فاتورة مُرحّلة');
      await (db.update(db.sales)..where((t) => t.id.equals(id))).write(comp);
      await (db.delete(db.saleLines)..where((t) => t.saleId.equals(id))).go();
    }
    // Invoice-level discount is spread proportionally? No: stored separately in
    // discountTotal; line discounts are stored on lines.
    for (final l in d.lines) {
      await db.into(db.saleLines).insert(SaleLinesCompanion.insert(
            saleId: id,
            productId: l.productId,
            quantity: l.quantity,
            unitPrice: l.unitPrice,
            priceType: l.priceType,
            discountAmount: Value(l.discount),
            lineTotal: l.lineTotal,
          ));
    }
    return id;
  }

  Future<InvoiceDraft> loadDraft(int saleId) async {
    final s = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
    Customer? c;
    if (s.customerId != null) {
      c = await (db.select(db.customers)..where((t) => t.id.equals(s.customerId!))).getSingle();
    }
    final d = InvoiceDraft(customerId: c?.id, customerName: c?.name, customerType: c?.customerType)
      ..saleId = s.id
      ..pricingMode = s.pricingMode
      ..notes = s.notes;
    final rows = await db.customSelect('''
      SELECT l.*, p.name_ar, p.internal_sku, p.wholesale_price, p.retail_price, COALESCE(b.quantity_on_hand,0) AS avail
      FROM sale_lines l JOIN products p ON p.id = l.product_id LEFT JOIN stock_balances b ON b.product_id = p.id
      WHERE l.sale_id = ? ORDER BY l.id
    ''', variables: [Variable.withInt(saleId)]).get();
    var lineDisc = 0;
    for (final r in rows) {
      final disc = r.read<int>('discount_amount');
      lineDisc += disc;
      d.lines.add(DraftLine(
        productId: r.read<int>('product_id'),
        name: r.read<String>('name_ar'),
        sku: r.read<String>('internal_sku'),
        wholesalePrice: r.read<int>('wholesale_price'),
        retailPrice: r.read<int>('retail_price'),
        available: r.read<int>('avail'),
        quantity: r.read<int>('quantity'),
        unitPrice: r.read<int>('unit_price'),
        priceType: r.read<String>('price_type'),
        discount: disc,
      ));
    }
    d.invoiceDiscount = s.discountTotal - lineDisc;
    return d;
  }

  Future<void> deleteDraft(int saleId) async {
    await db.transaction(() async {
      final s = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
      if (s.status != SaleStatus.draft) throw const BusinessException('لا يمكن حذف فاتورة مُرحّلة');
      await (db.delete(db.saleLines)..where((t) => t.saleId.equals(saleId))).go();
      await (db.delete(db.sales)..where((t) => t.id.equals(saleId))).go();
    });
  }

  // ---------------------------------------------------------------- posting
  /// Saves and posts the invoice in ONE transaction: stock is deducted exactly
  /// once; a second call fails because the status is no longer draft.
  Future<int> post(InvoiceDraft d, {int initialPayment = 0, String paymentMethod = 'cash'}) {
    final errs = d.validate();
    if (errs.isNotEmpty) throw BusinessException(errs.first);
    if (initialPayment < 0) throw const BusinessException('مبلغ الدفع غير صحيح');
    if (initialPayment > d.grandTotal) throw const BusinessException('المبلغ المدفوع أكبر من إجمالي الفاتورة');
    return _guard(d, () => db.transaction(() async {
      final id = await _writeDraft(d);
      final s = await (db.select(db.sales)..where((t) => t.id.equals(id))).getSingle();
      if (s.status != SaleStatus.draft) throw const BusinessException('تم ترحيل هذه الفاتورة من قبل');
      final lines = await (db.select(db.saleLines)..where((t) => t.saleId.equals(id))).get();
      // Aggregate per product so stock check is correct for duplicate lines.
      final results = await inventory.apply([
        for (final l in lines) MovementRequest(productId: l.productId, type: MovementType.sale, quantityDelta: -l.quantity)
      ], sourceType: 'sale', sourceId: id, occurredAt: s.invoiceDate);
      var cogs = 0;
      for (var i = 0; i < lines.length; i++) {
        final cost = results[i].unitCost;
        await (db.update(db.saleLines)..where((t) => t.id.equals(lines[i].id)))
            .write(SaleLinesCompanion(unitCostAtSale: Value(cost)));
        cogs += ((cost * lines[i].quantity) / 1000).round();
      }
      await (db.update(db.sales)..where((t) => t.id.equals(id))).write(SalesCompanion(
            status: const Value(SaleStatus.posted),
            postedAt: Value(DateTime.now()),
            cogsTotal: Value(cogs),
          ));
      if (initialPayment > 0) {
        await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
              saleId: id,
              paymentDate: DateTime.now(),
              amount: initialPayment,
              paymentMethod: paymentMethod,
            ));
      }
      await db.logActivity('post', 'sale', 'ترحيل فاتورة ${s.invoiceNumber}', entityId: id);
      return id;
    }));
  }

  /// Voids a posted invoice that has no payments or returns, restoring stock.
  Future<void> voidSale(int saleId, String reason) {
    if (reason.trim().isEmpty) throw const BusinessException('سبب الإلغاء مطلوب');
    return db.transaction(() async {
      final sum = await summary(saleId);
      if (sum.sale.status != SaleStatus.posted) throw const BusinessException('الفاتورة ليست مُرحّلة');
      if (sum.paid != 0 || sum.returned != 0) {
        throw const BusinessException('لا يمكن إلغاء فاتورة عليها مدفوعات أو مرتجعات — استخدم المرتجع');
      }
      final lines = await (db.select(db.saleLines)..where((t) => t.saleId.equals(saleId))).get();
      await inventory.apply([
        for (final l in lines)
          MovementRequest(
              productId: l.productId,
              type: MovementType.saleReturn,
              quantityDelta: l.quantity,
              unitCost: l.unitCostAtSale,
              reason: 'إلغاء فاتورة: ${reason.trim()}')
      ], sourceType: 'sale_void', sourceId: saleId);
      await (db.update(db.sales)..where((t) => t.id.equals(saleId))).write(SalesCompanion(
            status: const Value(SaleStatus.voided),
            notes: Value('${sum.sale.notes ?? ''}\nإلغاء: ${reason.trim()}'.trim()),
          ));
      await db.logActivity('void', 'sale', 'إلغاء فاتورة ${sum.sale.invoiceNumber}', entityId: saleId);
    });
  }

  // ---------------------------------------------------------------- payments
  Future<SaleSummary> summary(int saleId) async {
    final list = await summaries(saleId: saleId);
    if (list.isEmpty) throw const BusinessException('الفاتورة غير موجودة');
    return list.first;
  }

  Future<List<SaleSummary>> summaries({
    int? saleId,
    int? customerId,
    String? status,
    DateTime? from,
    DateTime? to,
    String text = '',
    int limit = 100,
  }) async {
    final where = <String>[];
    final vars = <Variable>[];
    if (saleId != null) {
      where.add('s.id = ?');
      vars.add(Variable.withInt(saleId));
    }
    if (customerId != null) {
      where.add('s.customer_id = ?');
      vars.add(Variable.withInt(customerId));
    }
    if (status != null) {
      where.add('s.status = ?');
      vars.add(Variable.withString(status));
    }
    if (from != null) {
      where.add('s.invoice_date >= ?');
      vars.add(Variable.withDateTime(from));
    }
    if (to != null) {
      where.add('s.invoice_date < ?');
      vars.add(Variable.withDateTime(to));
    }
    if (text.trim().isNotEmpty) {
      where.add("(s.invoice_number LIKE ? OR COALESCE(c.name,'') LIKE ?)");
      vars.add(Variable.withString('%${text.trim()}%'));
      vars.add(Variable.withString('%${text.trim()}%'));
    }
    final rows = await db.customSelect('''
      SELECT s.*, c.name AS cname, c.customer_type AS ctype,
        COALESCE((SELECT SUM(amount) FROM sale_payments p WHERE p.sale_id = s.id), 0) AS paid,
        COALESCE((SELECT SUM(return_total) FROM sales_returns r WHERE r.sale_id = s.id), 0) AS returned,
        COALESCE((SELECT SUM(refund_amount) FROM sales_returns r WHERE r.sale_id = s.id), 0) AS refunded
      FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.id DESC LIMIT ?
    ''', variables: [...vars, Variable.withInt(limit)], readsFrom: {db.sales, db.salePayments, db.salesReturns, db.customers}).get();
    return [
      for (final r in rows)
        SaleSummary(
          db.sales.map(r.data),
          r.readNullable<String>('cname') ?? 'عميل نقدي (قطاعي)',
          r.readNullable<String>('ctype'),
          r.read<int>('paid'),
          r.read<int>('returned'),
          r.read<int>('refunded'),
        )
    ];
  }

  Future<int> addPayment(int saleId, int amount, String method, {String? reference, String? notes, DateTime? date}) {
    if (amount <= 0) throw const BusinessException('المبلغ يجب أن يكون أكبر من صفر');
    return db.transaction(() async {
      final s = await summary(saleId);
      if (s.sale.status != SaleStatus.posted) throw const BusinessException('لا يمكن الدفع على فاتورة غير مُرحّلة');
      if (amount > s.outstanding) {
        throw const BusinessException('المبلغ أكبر من المتبقي على الفاتورة (الدفعات المقدمة غير مدعومة)');
      }
      final id = await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
            saleId: saleId,
            paymentDate: date ?? DateTime.now(),
            amount: amount,
            paymentMethod: method,
            reference: Value(reference),
            notes: Value(notes),
          ));
      await db.logActivity('payment', 'sale', 'دفعة على ${s.sale.invoiceNumber}', entityId: saleId);
      return id;
    });
  }

  /// Reverses a payment with an auditable negative entry; original is kept.
  Future<void> reversePayment(int paymentId, String reason) {
    if (reason.trim().isEmpty) throw const BusinessException('سبب العكس مطلوب');
    return db.transaction(() async {
      final p = await (db.select(db.salePayments)..where((t) => t.id.equals(paymentId))).getSingle();
      if (p.amount <= 0) throw const BusinessException('لا يمكن عكس قيد عكسي');
      final already = await (db.select(db.salePayments)..where((t) => t.reversesPaymentId.equals(paymentId))).get();
      if (already.isNotEmpty) throw const BusinessException('تم عكس هذه الدفعة من قبل');
      await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
            saleId: p.saleId,
            paymentDate: DateTime.now(),
            amount: -p.amount,
            paymentMethod: p.paymentMethod,
            reversesPaymentId: Value(paymentId),
            notes: Value('عكس دفعة: ${reason.trim()}'),
          ));
      await db.logActivity('reverse_payment', 'sale', 'عكس دفعة رقم $paymentId', entityId: p.saleId);
    });
  }

  // ---------------------------------------------------------------- returns
  Future<List<ReturnableLine>> returnableLines(int saleId) async {
    final rows = await db.customSelect('''
      SELECT l.*, p.name_ar AS pname,
        COALESCE((SELECT SUM(rl.quantity) FROM sales_return_lines rl WHERE rl.sale_line_id = l.id), 0) AS returned
      FROM sale_lines l JOIN products p ON p.id = l.product_id WHERE l.sale_id = ? ORDER BY l.id
    ''', variables: [Variable.withInt(saleId)]).get();
    return [
      for (final r in rows) ReturnableLine(db.saleLines.map(r.data), r.read<String>('pname'), r.read<int>('returned'))
    ];
  }

  /// Posts a return. [refundAmount] is cash paid back now (cannot exceed what
  /// the customer has overpaid after the return); any remaining overpayment
  /// stays as customer credit on the invoice.
  Future<int> postReturn(int saleId, List<ReturnLineInput> input,
      {int refundAmount = 0, String refundMethod = 'cash', String? notes}) {
    final active = input.where((l) => l.quantity > 0).toList();
    if (active.isEmpty) throw const BusinessException('أدخل كمية مرتجعة');
    return db.transaction(() async {
      final s = await summary(saleId);
      if (s.sale.status != SaleStatus.posted) throw const BusinessException('المرتجع متاح للفواتير المُرحّلة فقط');
      final lines = {for (final l in await returnableLines(saleId)) l.line.id: l};
      var total = 0;
      var costTotal = 0;
      final reqs = <MovementRequest>[];
      final values = <int, int>{};
      for (final i in active) {
        final rl = lines[i.saleLineId];
        if (rl == null) throw const BusinessException('سطر غير موجود في الفاتورة');
        if (i.quantity > rl.returnable) {
          throw BusinessException('الكمية المرتجعة للمنتج ${rl.productName} أكبر من المتاح للإرجاع');
        }
        if (i.damagedQuantity < 0 || i.damagedQuantity > i.quantity) {
          throw BusinessException('كمية التالف غير صحيحة للمنتج ${rl.productName}');
        }
        final v = rl.valueFor(i.quantity);
        values[i.saleLineId] = v;
        total += v;
        final restock = i.quantity - i.damagedQuantity;
        if (restock > 0) {
          costTotal += ((rl.line.unitCostAtSale * restock) / 1000).round();
          reqs.add(MovementRequest(
              productId: rl.line.productId,
              type: MovementType.saleReturn,
              quantityDelta: restock,
              unitCost: rl.line.unitCostAtSale));
        }
      }
      // Overpayment available for refund after this return.
      final overpaid = -(s.outstanding - total);
      if (refundAmount < 0 || refundAmount > (overpaid < 0 ? 0 : overpaid)) {
        throw const BusinessException('مبلغ الاسترداد أكبر من المبلغ المستحق للعميل');
      }
      final number = await db.nextDocNumber('sales_return');
      final rid = await db.into(db.salesReturns).insert(SalesReturnsCompanion.insert(
            returnNumber: number,
            saleId: saleId,
            returnDate: DateTime.now(),
            returnTotal: total,
            costTotal: Value(costTotal),
            refundAmount: Value(refundAmount),
            refundMethod: Value(refundAmount > 0 ? refundMethod : null),
            notes: Value(notes),
          ));
      for (final i in active) {
        final rl = lines[i.saleLineId]!;
        await db.into(db.salesReturnLines).insert(SalesReturnLinesCompanion.insert(
              salesReturnId: rid,
              saleLineId: i.saleLineId,
              quantity: i.quantity,
              unitPrice: rl.line.unitPrice,
              restockQuantity: i.quantity - i.damagedQuantity,
              damagedQuantity: i.damagedQuantity,
              lineTotal: values[i.saleLineId]!,
            ));
      }
      await inventory.apply(reqs, sourceType: 'sales_return', sourceId: rid);
      await db.logActivity('post', 'sales_return', 'مرتجع $number على ${s.sale.invoiceNumber}', entityId: rid);
      return rid;
    });
  }
}

final salesServiceProvider = Provider<SalesService>(
  (ref) => SalesService(ref.watch(databaseProvider), ref.watch(inventoryServiceProvider)),
);
