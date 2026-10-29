import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';
import 'inventory_service.dart';

/// kind of manual stock document.
abstract final class StockDocKind {
  static const opening = 'opening';
  static const receipt = 'receipt';
  static const issue = 'issue';
  static const damage = 'damage';
  static const adjustment = 'adjustment';

  static String label(String k) => switch (k) {
        opening => 'رصيد افتتاحي',
        receipt => 'إضافة مخزون',
        issue => 'صرف مخزون',
        damage => 'تالف / إعدام',
        adjustment => 'تسوية مخزون',
        _ => k,
      };
}

class StockDocLine {
  final int productId;
  /// For opening/receipt: quantity to add. For issue/damage: quantity to remove.
  /// For adjustment: the PHYSICAL quantity counted.
  final int quantity;
  final int? unitCost;
  StockDocLine(this.productId, this.quantity, {this.unitCost});
}

class StockDocumentsService {
  StockDocumentsService(this.db, this.inventory);
  final AppDatabase db;
  final InventoryService inventory;

  /// Creates and posts a manual stock document in one atomic transaction.
  Future<int> post({
    required String kind,
    required List<StockDocLine> lines,
    required String reason,
    String? notes,
    DateTime? date,
  }) async {
    if (lines.isEmpty) throw const BusinessException('أضف منتجًا واحدًا على الأقل');
    if (reason.trim().isEmpty) throw const BusinessException('السبب مطلوب');
    final when = date ?? DateTime.now();
    return db.transaction(() async {
      final number = await db.nextDocNumber('stock_adjustment');
      final docId = await db.into(db.stockAdjustments).insert(StockAdjustmentsCompanion.insert(
            adjustmentNumber: number,
            kind: kind,
            reason: reason.trim(),
            notes: Value(notes),
            occurredAt: when,
            status: const Value('posted'),
            postedAt: Value(DateTime.now()),
          ));
      final reqs = <MovementRequest>[];
      for (final l in lines) {
        if (l.quantity < 0) throw const BusinessException('الكمية لا يمكن أن تكون سالبة');
        final bal = await inventory.balanceOf(l.productId);
        int delta;
        String type;
        switch (kind) {
          case StockDocKind.opening:
            final exists = await (db.select(db.stockMovements)
                  ..where((t) => t.productId.equals(l.productId) & t.movementType.equals(MovementType.opening)))
                .getSingleOrNull();
            if (exists != null) throw const BusinessException('تم تسجيل الرصيد الافتتاحي لهذا المنتج من قبل');
            if (l.quantity == 0) throw const BusinessException('الكمية يجب أن تكون أكبر من صفر');
            delta = l.quantity;
            type = MovementType.opening;
          case StockDocKind.receipt:
            if (l.quantity == 0) throw const BusinessException('الكمية يجب أن تكون أكبر من صفر');
            delta = l.quantity;
            type = MovementType.receipt;
          case StockDocKind.issue:
          case StockDocKind.damage:
            if (l.quantity == 0) throw const BusinessException('الكمية يجب أن تكون أكبر من صفر');
            delta = -l.quantity;
            type = kind == StockDocKind.issue ? MovementType.issue : MovementType.damage;
          case StockDocKind.adjustment:
            delta = l.quantity - bal.quantityOnHand;
            type = MovementType.adjustment;
          default:
            throw BusinessException('نوع مستند غير معروف: $kind');
        }
        await db.into(db.stockAdjustmentLines).insert(StockAdjustmentLinesCompanion.insert(
              adjustmentId: docId,
              productId: l.productId,
              quantityDelta: delta,
              unitCost: Value(l.unitCost),
              quantityBefore: Value(bal.quantityOnHand),
              quantityAfter: Value(bal.quantityOnHand + delta),
            ));
        reqs.add(MovementRequest(
          productId: l.productId,
          type: type,
          quantityDelta: delta,
          unitCost: delta > 0 ? l.unitCost : null,
          reason: reason.trim(),
        ));
      }
      await inventory.apply(reqs, sourceType: 'stock_adjustment', sourceId: docId, occurredAt: when);
      await db.logActivity('post', 'stock_adjustment', '${StockDocKind.label(kind)} $number', entityId: docId);
      return docId;
    });
  }

  // ------------------------------------------------------------------ counts

  /// Starts a stock count. Expected quantities are snapshotted now.
  /// [productIds] null = all active products.
  Future<int> startCount({List<int>? productIds, String? notes}) {
    return db.transaction(() async {
      final number = await db.nextDocNumber('stock_count');
      final countId = await db.into(db.stockCounts).insert(StockCountsCompanion.insert(
            countNumber: number,
            startedAt: DateTime.now(),
            notes: Value(notes),
          ));
      final ids = productIds ??
          (await (db.select(db.products)..where((t) => t.isActive.equals(true))).get()).map((p) => p.id).toList();
      final maxMove = await db.customSelect('SELECT COALESCE(MAX(id),0) AS m FROM stock_movements').getSingle();
      final snap = maxMove.read<int>('m');
      for (final pid in ids) {
        final bal = await inventory.balanceOf(pid);
        await db.into(db.stockCountLines).insert(StockCountLinesCompanion.insert(
              stockCountId: countId,
              productId: pid,
              expectedQuantity: bal.quantityOnHand,
              snapshotMovementId: Value(snap),
            ));
      }
      await db.logActivity('create', 'stock_count', 'بدء جرد $number', entityId: countId);
      return countId;
    });
  }

  Future<void> setCounted(int lineId, int? counted) async {
    final line = await (db.select(db.stockCountLines)..where((t) => t.id.equals(lineId))).getSingle();
    final count = await (db.select(db.stockCounts)..where((t) => t.id.equals(line.stockCountId))).getSingle();
    if (count.status != 'draft') throw const BusinessException('لا يمكن تعديل جرد مُرحّل');
    await (db.update(db.stockCountLines)..where((t) => t.id.equals(lineId)))
        .write(StockCountLinesCompanion(countedQuantity: Value(counted)));
  }

  /// Posts variances for counted lines.
  ///
  /// Policy for movements during the count: the physical count reflects stock at
  /// count time, so the adjustment is (counted − expected). Sales/receipts posted
  /// after the snapshot are preserved, not overwritten.
  Future<void> postCount(int countId) {
    return db.transaction(() async {
      final count = await (db.select(db.stockCounts)..where((t) => t.id.equals(countId))).getSingle();
      if (count.status != 'draft') throw const BusinessException('تم ترحيل هذا الجرد من قبل');
      final lines = await (db.select(db.stockCountLines)
            ..where((t) => t.stockCountId.equals(countId) & t.countedQuantity.isNotNull()))
          .get();
      final variances = lines.where((l) => l.countedQuantity! != l.expectedQuantity).toList();
      int? adjId;
      if (variances.isNotEmpty) {
        final number = await db.nextDocNumber('stock_adjustment');
        adjId = await db.into(db.stockAdjustments).insert(StockAdjustmentsCompanion.insert(
              adjustmentNumber: number,
              kind: StockDocKind.adjustment,
              reason: 'تسوية جرد ${count.countNumber}',
              occurredAt: DateTime.now(),
              status: const Value('posted'),
              postedAt: Value(DateTime.now()),
            ));
        final reqs = <MovementRequest>[];
        for (final l in variances) {
          final delta = l.countedQuantity! - l.expectedQuantity;
          final bal = await inventory.balanceOf(l.productId);
          await db.into(db.stockAdjustmentLines).insert(StockAdjustmentLinesCompanion.insert(
                adjustmentId: adjId,
                productId: l.productId,
                quantityDelta: delta,
                quantityBefore: Value(bal.quantityOnHand),
                quantityAfter: Value(bal.quantityOnHand + delta),
              ));
          reqs.add(MovementRequest(
              productId: l.productId, type: MovementType.adjustment, quantityDelta: delta, reason: 'جرد ${count.countNumber}'));
        }
        await inventory.apply(reqs, sourceType: 'stock_count', sourceId: countId);
      }
      await (db.update(db.stockCounts)..where((t) => t.id.equals(countId))).write(StockCountsCompanion(
            status: const Value('posted'),
            completedAt: Value(DateTime.now()),
            adjustmentId: Value(adjId),
          ));
      await db.logActivity('post', 'stock_count', 'ترحيل جرد ${count.countNumber} (${variances.length} فروق)',
          entityId: countId);
    });
  }

  Future<void> cancelCount(int countId) async {
    await db.transaction(() async {
      final c = await (db.select(db.stockCounts)..where((t) => t.id.equals(countId))).getSingle();
      if (c.status != 'draft') throw const BusinessException('لا يمكن إلغاء جرد مُرحّل');
      await (db.update(db.stockCounts)..where((t) => t.id.equals(countId)))
          .write(const StockCountsCompanion(status: Value('cancelled')));
    });
  }
}

final stockDocumentsServiceProvider = Provider<StockDocumentsService>(
  (ref) => StockDocumentsService(ref.watch(databaseProvider), ref.watch(inventoryServiceProvider)),
);
