import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';
import '../../core/utils/money.dart';
import '../inventory/inventory_service.dart';

abstract final class PoStatus {
  static const draft = 'draft';
  static const ordered = 'ordered';
  static const partial = 'partial';
  static const received = 'received';
  static const cancelled = 'cancelled';
  static String label(String s) => switch (s) {
        draft => 'مسودة',
        ordered => 'تم الطلب',
        partial => 'استلام جزئي',
        received => 'مستلم بالكامل',
        cancelled => 'ملغي',
        _ => s,
      };
}

class PoLineInput {
  final int? id;
  final int productId;
  final String productName;
  int orderedQuantity;
  int unitCost;
  PoLineInput({this.id, required this.productId, required this.productName, required this.orderedQuantity, required this.unitCost});
  int get lineTotal => Money(unitCost).timesQty(Qty(orderedQuantity)).minor;
}

class ReceiptLineInput {
  final int? purchaseOrderLineId;
  final int productId;
  final String productName;
  int acceptedQuantity;
  int rejectedQuantity;
  int unitCost;
  /// For PO receipts: remaining quantity to receive (display/validation).
  final int? remaining;
  ReceiptLineInput({
    this.purchaseOrderLineId,
    required this.productId,
    required this.productName,
    this.acceptedQuantity = 0,
    this.rejectedQuantity = 0,
    required this.unitCost,
    this.remaining,
  });
}

class SupplierInput {
  int? id;
  String name = '';
  String? contactName;
  String? phone;
  String? email;
  String? address;
  String? notes;
}

class PurchasingService {
  PurchasingService(this.db, this.inventory);
  final AppDatabase db;
  final InventoryService inventory;

  // ---------------------------------------------------------------- suppliers
  Future<int> saveSupplier(SupplierInput s) async {
    if (s.name.trim().isEmpty) throw const BusinessException('اسم المورد مطلوب');
    final c = SuppliersCompanion(
      name: Value(s.name.trim()),
      contactName: Value(_n(s.contactName)),
      phone: Value(_n(s.phone)),
      email: Value(_n(s.email)),
      address: Value(_n(s.address)),
      notes: Value(_n(s.notes)),
      updatedAt: Value(DateTime.now()),
    );
    if (s.id == null) {
      final id = await db.into(db.suppliers).insert(c);
      await db.logActivity('create', 'supplier', 'إضافة مورد: ${s.name.trim()}', entityId: id);
      return id;
    }
    await (db.update(db.suppliers)..where((t) => t.id.equals(s.id!))).write(c);
    return s.id!;
  }

  Future<void> setSupplierActive(int id, bool active) =>
      (db.update(db.suppliers)..where((t) => t.id.equals(id))).write(SuppliersCompanion(isActive: Value(active)));

  // ---------------------------------------------------------- purchase orders
  Future<int> savePurchaseOrder({
    int? id,
    required int supplierId,
    required DateTime orderDate,
    DateTime? expectedDate,
    required List<PoLineInput> lines,
    String? notes,
    bool markOrdered = false,
  }) {
    if (lines.isEmpty) throw const BusinessException('أضف منتجًا واحدًا على الأقل');
    for (final l in lines) {
      if (l.orderedQuantity <= 0) throw BusinessException('كمية غير صحيحة للمنتج ${l.productName}');
      if (l.unitCost < 0) throw BusinessException('تكلفة غير صحيحة للمنتج ${l.productName}');
    }
    return db.transaction(() async {
      final subtotal = lines.fold<int>(0, (a, l) => a + l.lineTotal);
      int poId;
      if (id == null) {
        final number = await db.nextDocNumber('purchase_order');
        poId = await db.into(db.purchaseOrders).insert(PurchaseOrdersCompanion.insert(
              orderNumber: number,
              supplierId: supplierId,
              orderDate: orderDate,
              expectedDate: Value(expectedDate),
              status: Value(markOrdered ? PoStatus.ordered : PoStatus.draft),
              subtotal: Value(subtotal),
              grandTotal: Value(subtotal),
              notes: Value(_n(notes)),
            ));
        await db.logActivity('create', 'purchase_order', 'أمر شراء $number', entityId: poId);
      } else {
        poId = id;
        final po = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(id))).getSingle();
        if (po.status != PoStatus.draft) throw const BusinessException('لا يمكن تعديل أمر شراء بعد إرساله');
        await (db.update(db.purchaseOrders)..where((t) => t.id.equals(id))).write(PurchaseOrdersCompanion(
              supplierId: Value(supplierId),
              orderDate: Value(orderDate),
              expectedDate: Value(expectedDate),
              status: Value(markOrdered ? PoStatus.ordered : PoStatus.draft),
              subtotal: Value(subtotal),
              grandTotal: Value(subtotal),
              notes: Value(_n(notes)),
            ));
        await (db.delete(db.purchaseOrderLines)..where((t) => t.purchaseOrderId.equals(id))).go();
      }
      for (final l in lines) {
        await db.into(db.purchaseOrderLines).insert(PurchaseOrderLinesCompanion.insert(
              purchaseOrderId: poId,
              productId: l.productId,
              orderedQuantity: l.orderedQuantity,
              unitCost: l.unitCost,
              lineTotal: l.lineTotal,
            ));
      }
      return poId;
    });
  }

  Future<void> setPoStatus(int poId, String status) async {
    await db.transaction(() async {
      final po = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(poId))).getSingle();
      if (status == PoStatus.cancelled && (po.status == PoStatus.received || po.status == PoStatus.cancelled)) {
        throw const BusinessException('لا يمكن إلغاء هذا الأمر');
      }
      if (status == PoStatus.ordered && po.status != PoStatus.draft) {
        throw const BusinessException('الأمر ليس مسودة');
      }
      await (db.update(db.purchaseOrders)..where((t) => t.id.equals(poId)))
          .write(PurchaseOrdersCompanion(status: Value(status)));
      await db.logActivity('status', 'purchase_order', '${po.orderNumber}: ${PoStatus.label(status)}', entityId: poId);
    });
  }

  /// Lines of a PO with remaining quantity, ready for a receipt form.
  Future<List<ReceiptLineInput>> receiptLinesForPo(int poId) async {
    final rows = await db.customSelect('''
      SELECT l.*, p.name_ar FROM purchase_order_lines l JOIN products p ON p.id = l.product_id
      WHERE l.purchase_order_id = ? ORDER BY l.id
    ''', variables: [Variable.withInt(poId)]).get();
    return [
      for (final r in rows)
        if (r.read<int>('ordered_quantity') > r.read<int>('received_quantity'))
          ReceiptLineInput(
            purchaseOrderLineId: r.read<int>('id'),
            productId: r.read<int>('product_id'),
            productName: r.read<String>('name_ar'),
            unitCost: r.read<int>('unit_cost'),
            acceptedQuantity: r.read<int>('ordered_quantity') - r.read<int>('received_quantity'),
            remaining: r.read<int>('ordered_quantity') - r.read<int>('received_quantity'),
          ),
    ];
  }

  // ------------------------------------------------------------ goods receipts
  /// Creates and posts a goods receipt atomically. Only accepted quantities
  /// enter stock. Linked PO lines/status are updated in the same transaction.
  Future<int> postGoodsReceipt({
    int? purchaseOrderId,
    required int supplierId,
    required DateTime receivedAt,
    required List<ReceiptLineInput> lines,
    String? notes,
  }) {
    final active = lines.where((l) => l.acceptedQuantity > 0 || l.rejectedQuantity > 0).toList();
    if (active.isEmpty) throw const BusinessException('أدخل كمية مستلمة لمنتج واحد على الأقل');
    return db.transaction(() async {
      if (purchaseOrderId != null) {
        final po = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(purchaseOrderId))).getSingle();
        if (po.status == PoStatus.cancelled || po.status == PoStatus.received) {
          throw const BusinessException('هذا الأمر ملغي أو مستلم بالكامل');
        }
      }
      final number = await db.nextDocNumber('goods_receipt');
      var total = 0;
      for (final l in active) {
        if (l.acceptedQuantity < 0 || l.rejectedQuantity < 0) throw const BusinessException('الكميات لا يمكن أن تكون سالبة');
        total += Money(l.unitCost).timesQty(Qty(l.acceptedQuantity)).minor;
      }
      final grId = await db.into(db.goodsReceipts).insert(GoodsReceiptsCompanion.insert(
            receiptNumber: number,
            purchaseOrderId: Value(purchaseOrderId),
            supplierId: supplierId,
            receivedAt: receivedAt,
            status: const Value('posted'),
            total: Value(total),
            notes: Value(_n(notes)),
          ));
      final reqs = <MovementRequest>[];
      for (final l in active) {
        if (l.purchaseOrderLineId != null) {
          final pol = await (db.select(db.purchaseOrderLines)..where((t) => t.id.equals(l.purchaseOrderLineId!))).getSingle();
          final remaining = pol.orderedQuantity - pol.receivedQuantity;
          if (l.acceptedQuantity > remaining) {
            throw BusinessException('الكمية المقبولة للمنتج ${l.productName} أكبر من المتبقي في أمر الشراء');
          }
          await (db.update(db.purchaseOrderLines)..where((t) => t.id.equals(pol.id)))
              .write(PurchaseOrderLinesCompanion(receivedQuantity: Value(pol.receivedQuantity + l.acceptedQuantity)));
        }
        await db.into(db.goodsReceiptLines).insert(GoodsReceiptLinesCompanion.insert(
              goodsReceiptId: grId,
              purchaseOrderLineId: Value(l.purchaseOrderLineId),
              productId: l.productId,
              receivedQuantity: l.acceptedQuantity,
              rejectedQuantity: Value(l.rejectedQuantity),
              unitCost: l.unitCost,
            ));
        if (l.acceptedQuantity > 0) {
          reqs.add(MovementRequest(
              productId: l.productId, type: MovementType.purchase, quantityDelta: l.acceptedQuantity, unitCost: l.unitCost));
        }
      }
      await inventory.apply(reqs, sourceType: 'goods_receipt', sourceId: grId, occurredAt: receivedAt);
      if (purchaseOrderId != null) {
        final pls = await (db.select(db.purchaseOrderLines)..where((t) => t.purchaseOrderId.equals(purchaseOrderId))).get();
        final full = pls.every((x) => x.receivedQuantity >= x.orderedQuantity);
        final any = pls.any((x) => x.receivedQuantity > 0);
        await (db.update(db.purchaseOrders)..where((t) => t.id.equals(purchaseOrderId))).write(PurchaseOrdersCompanion(
              status: Value(full ? PoStatus.received : (any ? PoStatus.partial : PoStatus.ordered)),
            ));
      }
      await db.logActivity('post', 'goods_receipt', 'استلام بضاعة $number', entityId: grId);
      return grId;
    });
  }

  // ---------------------------------------------------------- supplier returns
  Future<int> postSupplierReturn({
    required int supplierId,
    int? goodsReceiptId,
    required List<ReceiptLineInput> lines,
    String? notes,
  }) {
    final active = lines.where((l) => l.acceptedQuantity > 0).toList();
    if (active.isEmpty) throw const BusinessException('أدخل كمية مرتجعة');
    return db.transaction(() async {
      final number = await db.nextDocNumber('supplier_return');
      final total = active.fold<int>(0, (a, l) => a + Money(l.unitCost).timesQty(Qty(l.acceptedQuantity)).minor);
      final id = await db.into(db.supplierReturns).insert(SupplierReturnsCompanion.insert(
            returnNumber: number,
            supplierId: supplierId,
            goodsReceiptId: Value(goodsReceiptId),
            returnDate: DateTime.now(),
            total: total,
            notes: Value(_n(notes)),
          ));
      for (final l in active) {
        await db.into(db.supplierReturnLines).insert(SupplierReturnLinesCompanion.insert(
            supplierReturnId: id, productId: l.productId, quantity: l.acceptedQuantity, unitCost: l.unitCost));
      }
      await inventory.apply([
        for (final l in active)
          MovementRequest(productId: l.productId, type: MovementType.supplierReturn, quantityDelta: -l.acceptedQuantity)
      ], sourceType: 'supplier_return', sourceId: id);
      await db.logActivity('post', 'supplier_return', 'مرتجع لمورد $number', entityId: id);
      return id;
    });
  }

  /// Historical purchase costs for a product (newest first).
  Future<List<QueryRow>> costHistory(int productId) => db.customSelect('''
      SELECT g.receipt_number, g.received_at, s.name AS supplier, l.received_quantity, l.unit_cost
      FROM goods_receipt_lines l JOIN goods_receipts g ON g.id = l.goods_receipt_id JOIN suppliers s ON s.id = g.supplier_id
      WHERE l.product_id = ? AND g.status = 'posted' ORDER BY g.received_at DESC, g.id DESC LIMIT 100
    ''', variables: [Variable.withInt(productId)]).get();

  static String? _n(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

final purchasingServiceProvider = Provider<PurchasingService>(
  (ref) => PurchasingService(ref.watch(databaseProvider), ref.watch(inventoryServiceProvider)),
);
