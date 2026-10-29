import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables.dart';

part 'app_database.g.dart';

const kDatabaseName = 'auto_parts_inventory';

/// Location of the live database file (private app storage).
Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, '$kDatabaseName.sqlite'));
}

QueryExecutor _openConnection() => LazyDatabase(() async {
      if (Platform.isAndroid) {
        await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      }
      return NativeDatabase.createInBackground(await databaseFile());
    });

@DriftDatabase(tables: [
  AppSettings,
  ActivityLogs,
  DocSequences,
  ProductTypes,
  Brands,
  Categories,
  Units,
  Products,
  ProductSpecs,
  Tags,
  ProductTags,
  VehicleMakes,
  VehicleModels,
  VehicleCompatibilities,
  StockBalances,
  StockMovements,
  StockAdjustments,
  StockAdjustmentLines,
  StockCounts,
  StockCountLines,
  Suppliers,
  PurchaseOrders,
  PurchaseOrderLines,
  GoodsReceipts,
  GoodsReceiptLines,
  SupplierReturns,
  SupplierReturnLines,
  Customers,
  Sales,
  SaleLines,
  SalePayments,
  SalesReturns,
  SalesReturnLines,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Bump on every schema change and add a step in [migration].
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
          await _seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          // Add steps like: if (from < 2) { await m.addColumn(...); }
          // Never drop/recreate tables that hold business data.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    const stmts = [
      'CREATE INDEX IF NOT EXISTS idx_products_tc ON products(tc_code)',
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
      'CREATE INDEX IF NOT EXISTS idx_products_type ON products(product_type_id)',
      'CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand_id)',
      'CREATE INDEX IF NOT EXISTS idx_products_diameter ON products(diameter_mm)',
      'CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active)',
      'CREATE INDEX IF NOT EXISTS idx_product_tags_tag ON product_tags(tag_id, product_id)',
      'CREATE INDEX IF NOT EXISTS idx_compat_model ON vehicle_compatibilities(vehicle_model_id)',
      'CREATE INDEX IF NOT EXISTS idx_compat_product ON vehicle_compatibilities(product_id)',
      'CREATE INDEX IF NOT EXISTS idx_models_make ON vehicle_models(make_id)',
      'CREATE INDEX IF NOT EXISTS idx_moves_product ON stock_movements(product_id, id)',
      'CREATE INDEX IF NOT EXISTS idx_moves_source ON stock_movements(source_type, source_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(invoice_date)',
      'CREATE INDEX IF NOT EXISTS idx_sale_lines_sale ON sale_lines(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_sale_lines_product ON sale_lines(product_id)',
      'CREATE INDEX IF NOT EXISTS idx_payments_sale ON sale_payments(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_returns_sale ON sales_returns(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id)',
      'CREATE INDEX IF NOT EXISTS idx_gr_supplier ON goods_receipts(supplier_id)',
      'CREATE INDEX IF NOT EXISTS idx_grl_product ON goods_receipt_lines(product_id)',
      // At most one posted opening-stock line per product (duplicate protection).
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_opening_per_product ON stock_movements(product_id) WHERE movement_type = 'opening'",
    ];
    for (final s in stmts) {
      await customStatement(s);
    }
  }

  Future<void> _seedDefaults() async {
    const seqs = {
      'sale': 'INV-',
      'purchase_order': 'PO-',
      'goods_receipt': 'GR-',
      'sales_return': 'SR-',
      'supplier_return': 'PR-',
      'stock_adjustment': 'ADJ-',
      'stock_count': 'CNT-',
      'sku': 'P-',
    };
    for (final e in seqs.entries) {
      await into(docSequences).insert(
        DocSequencesCompanion.insert(docType: e.key, prefix: e.value),
        mode: InsertMode.insertOrIgnore,
      );
    }
    // Default configuration lists (editable/extendable by the admin).
    await into(productTypes).insert(ProductTypesCompanion.insert(nameAr: 'شنابر', nameEn: const Value('Piston rings'), kind: const Value('ring')));
    await into(productTypes).insert(ProductTypesCompanion.insert(nameAr: 'بساتم', nameEn: const Value('Pistons'), kind: const Value('piston')));
    await into(productTypes).insert(ProductTypesCompanion.insert(nameAr: 'قطع غيار موتور أخرى', nameEn: const Value('Other engine parts')));
    for (final u in const [['قطعة', 'Piece'], ['طقم', 'Set'], ['زوج', 'Pair'], ['علبة', 'Box']]) {
      await into(units).insert(UnitsCompanion.insert(nameAr: u[0], nameEn: Value(u[1])));
    }
  }

  /// Reserves the next number for [docType]. Call inside the transaction that
  /// creates the document.
  Future<String> nextDocNumber(String docType) async {
    final row = await (select(docSequences)..where((t) => t.docType.equals(docType))).getSingle();
    await (update(docSequences)..where((t) => t.docType.equals(docType)))
        .write(DocSequencesCompanion(nextValue: Value(row.nextValue + 1)));
    return '${row.prefix}${row.nextValue.toString().padLeft(6, '0')}';
  }

  Future<void> logActivity(String action, String entity, String description, {int? entityId}) {
    return into(activityLogs).insert(ActivityLogsCompanion.insert(
      actionType: action,
      entityType: entity,
      entityId: Value(entityId),
      description: description,
    ));
  }

  Future<String> integrityCheck() async {
    final r = await customSelect('PRAGMA integrity_check').getSingle();
    return r.data.values.first.toString();
  }
}
