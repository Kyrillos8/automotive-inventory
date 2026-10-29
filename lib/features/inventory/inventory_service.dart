import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';

abstract final class MovementType {
  static const opening = 'opening';
  static const purchase = 'purchase';
  static const sale = 'sale';
  static const saleReturn = 'sale_return';
  static const receipt = 'receipt';
  static const issue = 'issue';
  static const damage = 'damage';
  static const supplierReturn = 'supplier_return';
  static const adjustment = 'adjustment';

  static String label(String t) => switch (t) {
        opening => 'رصيد افتتاحي',
        purchase => 'استلام مشتريات',
        sale => 'بيع',
        saleReturn => 'مرتجع مبيعات',
        receipt => 'إضافة يدوية',
        issue => 'صرف يدوي',
        damage => 'تالف / إعدام',
        supplierReturn => 'مرتجع لمورد',
        adjustment => 'تسوية جرد',
        _ => t,
      };
}

class MovementRequest {
  final int productId;
  final String type;
  /// Milli-units; positive increases stock, negative decreases.
  final int quantityDelta;
  /// For increases: unit cost (minor). Null = use current average cost.
  final int? unitCost;
  final String? reason;
  MovementRequest({required this.productId, required this.type, required this.quantityDelta, this.unitCost, this.reason});
}

class MovementResult {
  final int productId;
  final int quantityDelta;
  /// Unit cost applied (for decreases: average cost at the time; COGS basis).
  final int unitCost;
  MovementResult(this.productId, this.quantityDelta, this.unitCost);
}

/// The ONLY component allowed to change stock. Must be called inside a
/// database transaction owned by the posting document.
class InventoryService {
  InventoryService(this.db);
  final AppDatabase db;

  Future<bool> _allowNegative() async {
    final r = await (db.select(db.appSettings)..where((t) => t.key.equals('allow_negative_stock'))).getSingleOrNull();
    return r?.value == '1';
  }

  Future<StockBalance> balanceOf(int productId) async {
    final b = await (db.select(db.stockBalances)..where((t) => t.productId.equals(productId))).getSingleOrNull();
    if (b != null) return b;
    await db.into(db.stockBalances).insert(StockBalancesCompanion.insert(productId: Value(productId)));
    return (db.select(db.stockBalances)..where((t) => t.productId.equals(productId))).getSingle();
  }

  /// Applies movements atomically; throws [BusinessException] (rolling back
  /// the caller's transaction) if any would make stock negative.
  Future<List<MovementResult>> apply(
    List<MovementRequest> reqs, {
    required String sourceType,
    int? sourceId,
    DateTime? occurredAt,
  }) async {
    // Nested drift transactions become savepoints, so this joins the caller's transaction.
    return db.transaction(() => _apply(reqs, sourceType, sourceId, occurredAt));
  }

  Future<List<MovementResult>> _apply(
      List<MovementRequest> reqs, String sourceType, int? sourceId, DateTime? occurredAt) async {
    final allowNeg = await _allowNegative();
    final when = occurredAt ?? DateTime.now();
    final results = <MovementResult>[];
    for (final r in reqs) {
      if (r.quantityDelta == 0) continue;
      final bal = await balanceOf(r.productId);
      final newQty = bal.quantityOnHand + r.quantityDelta;
      if (newQty < 0 && !allowNeg) {
        final p = await (db.select(db.products)..where((t) => t.id.equals(r.productId))).getSingle();
        throw BusinessException(
            'الكمية غير كافية للمنتج "${p.nameAr}": المتاح ${_fmt(bal.quantityOnHand)} والمطلوب ${_fmt(-r.quantityDelta)}');
      }
      int applied;
      int newAvg = bal.avgCost;
      if (r.quantityDelta > 0) {
        applied = r.unitCost ?? bal.avgCost;
        final oldQty = bal.quantityOnHand < 0 ? 0 : bal.quantityOnHand;
        final totalQty = oldQty + r.quantityDelta;
        if (totalQty > 0) {
          // Moving weighted average (rounded to nearest piastre).
          newAvg = ((oldQty * bal.avgCost + r.quantityDelta * applied) / totalQty).round();
        }
      } else {
        applied = r.unitCost ?? bal.avgCost;
      }
      await (db.update(db.stockBalances)..where((t) => t.productId.equals(r.productId))).write(StockBalancesCompanion(
        quantityOnHand: Value(newQty),
        avgCost: Value(newAvg),
        updatedAt: Value(DateTime.now()),
      ));
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: r.productId,
            movementType: r.type,
            quantityDelta: r.quantityDelta,
            unitCost: Value(applied),
            balanceAfter: newQty,
            sourceType: sourceType,
            sourceId: Value(sourceId),
            reason: Value(r.reason),
            occurredAt: when,
          ));
      results.add(MovementResult(r.productId, r.quantityDelta, applied));
    }
    return results;
  }

  static String _fmt(int milli) {
    if (milli % 1000 == 0) return '${milli ~/ 1000}';
    return (milli / 1000).toStringAsFixed(3);
  }

  /// Products whose stored balance differs from the sum of their movements.
  Future<List<ReconciliationIssue>> reconcile() async {
    final rows = await db.customSelect('''
      SELECT p.id AS pid, p.name_ar AS name,
             COALESCE(b.quantity_on_hand, 0) AS stored,
             COALESCE((SELECT SUM(m.quantity_delta) FROM stock_movements m WHERE m.product_id = p.id), 0) AS ledger
      FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id
    ''').get();
    return [
      for (final r in rows)
        if (r.read<int>('stored') != r.read<int>('ledger'))
          ReconciliationIssue(r.read<int>('pid'), r.read<String>('name'), r.read<int>('stored'), r.read<int>('ledger')),
    ];
  }

  /// Rewrites stored balances from the ledger (used after restore or if reconcile finds issues).
  Future<void> rebuildBalancesFromLedger() async {
    await db.transaction(() async {
      await db.customStatement('''
        UPDATE stock_balances SET quantity_on_hand =
          COALESCE((SELECT SUM(m.quantity_delta) FROM stock_movements m WHERE m.product_id = stock_balances.product_id), 0)
      ''');
    });
  }
}

class ReconciliationIssue {
  final int productId;
  final String name;
  final int stored;
  final int ledger;
  ReconciliationIssue(this.productId, this.name, this.stored, this.ledger);
}

final inventoryServiceProvider = Provider<InventoryService>((ref) => InventoryService(ref.watch(databaseProvider)));
