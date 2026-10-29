import 'package:drift/drift.dart';

// Conventions:
// - Money columns are INTEGER minor units (piastres).
// - Quantity columns are INTEGER milli-units (1 unit = 1000).
// - Posted documents are immutable; corrections use new documents.

// ---------------------------------------------------------------------------
// Application support
// ---------------------------------------------------------------------------

@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ActivityLogEntry')
class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()();
  TextColumn get entityType => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get description => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('DocSequence')
class DocSequences extends Table {
  TextColumn get docType => text()();
  TextColumn get prefix => text()();
  IntColumn get nextValue => integer().withDefault(const Constant(1))();
  @override
  Set<Column> get primaryKey => {docType};
}

// ---------------------------------------------------------------------------
// Master data
// ---------------------------------------------------------------------------

/// kind: 'ring' | 'piston' | 'other' — controls which spec fields are shown.
@DataClassName('ProductType')
class ProductTypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('other'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Brand')
class Brands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
}

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
}

@DataClassName('UnitOfMeasure')
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get internalSku => text().unique()();
  TextColumn get barcode => text().nullable()();
  TextColumn get tcCode => text().nullable()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get productTypeId => integer().references(ProductTypes, #id)();
  IntColumn get brandId => integer().nullable().references(Brands, #id)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get countryOfOrigin => text().nullable()();
  IntColumn get baseUnitId => integer().references(Units, #id)();
  IntColumn get purchasePrice => integer().withDefault(const Constant(0))();
  IntColumn get wholesalePrice => integer().withDefault(const Constant(0))();
  IntColumn get retailPrice => integer().withDefault(const Constant(0))();
  IntColumn get minimumStock => integer().withDefault(const Constant(0))();
  IntColumn get maximumStock => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  // Structured, searchable specifications (rings & pistons).
  RealColumn get diameterMm => real().nullable()();
  TextColumn get sizeDesignation => text().nullable()(); // STD, 0.25, 0.50 ...
  TextColumn get ringDimensions => text().nullable()(); // "1.20 - 1.20 - 2.00"
  TextColumn get engineCapacity => text().nullable()();
  IntColumn get cylinders => integer().nullable()();
  TextColumn get engineCode => text().nullable()();
  RealColumn get pinDiameterMm => real().nullable()();
  RealColumn get compressionHeightMm => real().nullable()();
  TextColumn get labelNotes => text().nullable()();
  /// Normalized concatenation of every searchable field (maintained by ProductRepository).
  TextColumn get searchText => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Extra manufacturer-specific attributes (key/value).
@DataClassName('ProductSpec')
class ProductSpecs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get specKey => text()();
  TextColumn get textValue => text()();
  RealColumn get numericValue => real().nullable()();
}

@DataClassName('Tag')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text().unique()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductTag')
class ProductTags extends Table {
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(Tags, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {productId, tagId};
}

@DataClassName('VehicleMake')
class VehicleMakes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('VehicleModel')
class VehicleModels extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get makeId => integer().references(VehicleMakes, #id)();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// status: 'confirmed' | 'needs_verification'.
/// engineCapacity/engineCode use '' (not NULL) so the unique key works.
@DataClassName('VehicleCompatibility')
class VehicleCompatibilities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get vehicleModelId => integer().references(VehicleModels, #id)();
  IntColumn get yearFrom => integer().nullable()();
  IntColumn get yearTo => integer().nullable()();
  TextColumn get engineCapacity => text().withDefault(const Constant(''))();
  TextColumn get engineCode => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('confirmed'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  List<Set<Column>> get uniqueKeys => [
        {productId, vehicleModelId, engineCapacity, engineCode},
      ];
}

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------

/// One row per product (single warehouse). Projection of stock_movements.
@DataClassName('StockBalance')
class StockBalances extends Table {
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantityOnHand => integer().withDefault(const Constant(0))();
  /// Moving weighted-average unit cost (minor units).
  IntColumn get avgCost => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {productId};
}

@DataClassName('StockMovement')
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get movementType => text()();
  IntColumn get quantityDelta => integer()();
  IntColumn get unitCost => integer().nullable()();
  IntColumn get balanceAfter => integer()();
  TextColumn get sourceType => text()();
  IntColumn get sourceId => integer().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Manual stock documents. kind: opening | receipt | issue | damage | adjustment.
@DataClassName('StockAdjustment')
class StockAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get adjustmentNumber => text().unique()();
  TextColumn get kind => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get reason => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get postedAt => dateTime().nullable()();
}

@DataClassName('StockAdjustmentLine')
class StockAdjustmentLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get adjustmentId => integer().references(StockAdjustments, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantityDelta => integer()();
  IntColumn get unitCost => integer().nullable()();
  IntColumn get quantityBefore => integer().nullable()();
  IntColumn get quantityAfter => integer().nullable()();
}

@DataClassName('StockCount')
class StockCounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get countNumber => text().unique()();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft|posted|cancelled
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get adjustmentId => integer().nullable().references(StockAdjustments, #id)();
}

@DataClassName('StockCountLine')
class StockCountLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get stockCountId => integer().references(StockCounts, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get expectedQuantity => integer()();
  /// Id of the last stock movement when the expectation was captured.
  IntColumn get snapshotMovementId => integer().withDefault(const Constant(0))();
  IntColumn get countedQuantity => integer().nullable()();
  @override
  List<Set<Column>> get uniqueKeys => [
        {stockCountId, productId},
      ];
}

// ---------------------------------------------------------------------------
// Purchasing
// ---------------------------------------------------------------------------

@DataClassName('Supplier')
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get contactName => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// status: draft | ordered | partial | received | cancelled
@DataClassName('PurchaseOrder')
class PurchaseOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNumber => text().unique()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  DateTimeColumn get orderDate => dateTime()();
  DateTimeColumn get expectedDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discountTotal => integer().withDefault(const Constant(0))();
  IntColumn get taxTotal => integer().withDefault(const Constant(0))();
  IntColumn get grandTotal => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseOrderLine')
class PurchaseOrderLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseOrderId => integer().references(PurchaseOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get orderedQuantity => integer()();
  IntColumn get receivedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get unitCost => integer()();
  IntColumn get lineTotal => integer()();
}

/// status: draft | posted
@DataClassName('GoodsReceipt')
class GoodsReceipts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get receiptNumber => text().unique()();
  IntColumn get purchaseOrderId => integer().nullable().references(PurchaseOrders, #id)();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('GoodsReceiptLine')
class GoodsReceiptLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goodsReceiptId => integer().references(GoodsReceipts, #id)();
  IntColumn get purchaseOrderLineId => integer().nullable().references(PurchaseOrderLines, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get receivedQuantity => integer()(); // accepted
  IntColumn get rejectedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get unitCost => integer()();
}

@DataClassName('SupplierReturn')
class SupplierReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().unique()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get goodsReceiptId => integer().nullable().references(GoodsReceipts, #id)();
  DateTimeColumn get returnDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  IntColumn get total => integer()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('SupplierReturnLine')
class SupplierReturnLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierReturnId => integer().references(SupplierReturns, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitCost => integer()();
}

// ---------------------------------------------------------------------------
// Sales & finance
// ---------------------------------------------------------------------------

/// customerType: 'wholesale' | 'retail'
@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get customerType => text().withDefault(const Constant('retail'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// status: draft | posted | void. Payment status is derived from amounts.
/// pricingMode: wholesale | retail
@DataClassName('Sale')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().unique()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  DateTimeColumn get invoiceDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get pricingMode => text()();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discountTotal => integer().withDefault(const Constant(0))();
  IntColumn get taxTotal => integer().withDefault(const Constant(0))();
  IntColumn get grandTotal => integer().withDefault(const Constant(0))();
  IntColumn get cogsTotal => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get postedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// priceType: wholesale | retail | manual
@DataClassName('SaleLine')
class SaleLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  TextColumn get priceType => text()();
  IntColumn get unitCostAtSale => integer().withDefault(const Constant(0))();
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  IntColumn get taxAmount => integer().withDefault(const Constant(0))();
  IntColumn get lineTotal => integer()();
}

/// Negative amounts are reversals and reference the reversed payment.
@DataClassName('SalePayment')
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  DateTimeColumn get paymentDate => dateTime()();
  IntColumn get amount => integer()();
  TextColumn get paymentMethod => text()(); // cash | bank | other
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get reversesPaymentId => integer().nullable().references(SalePayments, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// settlement: 'refund' (cash paid out) | 'credit' (kept as customer credit) | 'reduce_due'
@DataClassName('SalesReturn')
class SalesReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().unique()();
  IntColumn get saleId => integer().references(Sales, #id)();
  DateTimeColumn get returnDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  IntColumn get returnTotal => integer()();
  IntColumn get costTotal => integer().withDefault(const Constant(0))();
  IntColumn get refundAmount => integer().withDefault(const Constant(0))();
  TextColumn get refundMethod => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SalesReturnLine')
class SalesReturnLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get salesReturnId => integer().references(SalesReturns, #id)();
  IntColumn get saleLineId => integer().references(SaleLines, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get restockQuantity => integer()();
  IntColumn get damagedQuantity => integer()();
  IntColumn get lineTotal => integer()();
}
