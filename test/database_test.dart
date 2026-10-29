// Requires a native SQLite library on the host running `flutter test`.
import 'package:automotive_inventory/core/database/app_database.dart';
import 'package:automotive_inventory/core/errors/business_exception.dart';
import 'package:automotive_inventory/core/utils/money.dart';
import 'package:automotive_inventory/features/inventory/inventory_service.dart';
import 'package:automotive_inventory/features/inventory/stock_documents_service.dart';
import 'package:automotive_inventory/features/products/product_repository.dart';
import 'package:automotive_inventory/features/purchasing/purchasing_service.dart';
import 'package:automotive_inventory/features/sales/invoice_draft.dart';
import 'package:automotive_inventory/features/sales/sales_service.dart';
import 'package:automotive_inventory/features/settings/settings_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

int u(num n) => Qty.units(n).milli;
int egp(num n) => Money.fromMajor(n).minor;

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late InventoryService inv;
  late StockDocumentsService docs;
  late SalesService sales;
  late PurchasingService purchasing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    products = ProductRepository(db);
    inv = InventoryService(db);
    docs = StockDocumentsService(db, inv);
    sales = SalesService(db, inv);
    purchasing = PurchasingService(db, inv);
  });
  tearDown(() => db.close());

  Future<int> qty(int pid) async => (await inv.balanceOf(pid)).quantityOnHand;

  /// Test A product.
  Future<int> createRing({List<CompatInput> compat = const []}) async {
    final types = await products.watchTypes().first;
    final unitsList = await products.watchUnits().first;
    final brand = await products.addBrand('TR2', 'TR2');
    final tags = [for (final t in ['شنابر', 'هيونداي', 'كوري']) (await products.createTag(t)).id];
    final make = await products.addMake('هيونداي', 'Hyundai');
    final elantra = await products.addModel(make, 'إلنترا', 'Elantra');
    final p = ProductInput()
      ..nameAr = 'شنبر هيونداي إلنترا'
      ..nameEn = 'Piston ring Hyundai Elantra'
      ..productTypeId = types.firstWhere((t) => t.kind == 'ring').id
      ..baseUnitId = unitsList.first.id
      ..brandId = brand
      ..tcCode = '01680'
      ..diameterMm = 78.0
      ..ringDimensions = '1.20 - 1.20 - 2.00'
      ..countryOfOrigin = 'كوريا'
      ..purchasePrice = egp(250)
      ..wholesalePrice = egp(300)
      ..retailPrice = egp(350)
      ..tagIds = tags
      ..compat = [CompatInput(vehicleModelId: elantra, label: 'Hyundai Elantra'), ...compat];
    return products.saveProduct(p);
  }

  test('setup persists settings', () async {
    final repo = SettingsRepository(db);
    await repo.completeSetup(businessName: 'مخزن', currency: 'ج.م');
    expect((await repo.load()).setupComplete, isTrue);
  });

  test('Test A/B/C/D: product, compatibility, search, tags', () async {
    final make = await products.addMake('بيجو', 'Peugeot');
    final m301 = await products.addModel(make, '301', null);
    final id = await createRing(compat: [CompatInput(vehicleModelId: m301, label: 'Peugeot 301')]);

    Future<bool> found(String q) async => (await products.search(ProductQuery(text: q))).any((p) => p.id == id);
    for (final q in ['شنبر', 'Piston ring', '01680', 'كوري', 'هيونداي إلنترا', 'النترا', 'Hyundai Elantra', '78', '1.20', 'TR2', 'Peugeot 301', '٠١٦٨٠']) {
      expect(await found(q), isTrue, reason: 'query "$q"');
    }
    expect(await found('Hyundai 99'), isFalse);
    expect((await products.search(ProductQuery(text: '01680'))).first.id, id, reason: 'exact code ranks first');

    // Vehicle filter + removing one compatibility keeps the product and the other link.
    expect((await products.search(ProductQuery(makeId: make, modelId: m301))).map((e) => e.id), contains(id));
    final compat = await products.compatibilityOf(id);
    expect(compat, hasLength(2));
    await products.removeCompatibility(compat.firstWhere((c) => c.modelId == m301).id);
    expect(await products.compatibilityOf(id), hasLength(1));
    expect((await products.search(ProductQuery(makeId: make, modelId: m301))).map((e) => e.id), isNot(contains(id)));
    expect(await products.item(id), isNotNull);

    // Tags: any / all, rename.
    final tags = await products.watchActiveTags().first;
    final korean = tags.firstWhere((t) => t.name == 'كوري');
    final other = await products.createTag('بساتم');
    expect((await products.search(ProductQuery(tagIds: {korean.id, other.id}))).map((e) => e.id), contains(id));
    expect((await products.search(ProductQuery(tagIds: {korean.id, other.id}, tagsMatchAll: true))), isEmpty);
    await products.renameTag(korean.id, 'كوري الصنع');
    expect((await products.item(id))!.tags, contains('كوري الصنع'));
    expect(await found('الصنع'), isTrue);
    // Duplicate tag via normalization returns the existing tag.
    expect((await products.createTag('شَنَابِر')).id, tags.firstWhere((t) => t.name == 'شنابر').id);
  });

  test('Test E: opening stock once only', () async {
    final id = await createRing();
    await docs.post(kind: StockDocKind.opening, lines: [StockDocLine(id, u(20), unitCost: egp(250))], reason: 'رصيد افتتاحي');
    expect(await qty(id), u(20));
    final moves = await (db.select(db.stockMovements)..where((t) => t.productId.equals(id))).get();
    expect(moves.single.movementType, MovementType.opening);
    await expectLater(() => docs.post(kind: StockDocKind.opening, lines: [StockDocLine(id, u(5))], reason: 'x'),
        throwsA(isA<BusinessException>()));
    expect(await qty(id), u(20));
  });

  test('Test F/I + negative stock + double post protection', () async {
    final id = await createRing();
    await docs.post(kind: StockDocKind.opening, lines: [StockDocLine(id, u(20), unitCost: egp(250))], reason: 'opening');
    final cust = await db.into(db.customers).insert(CustomersCompanion.insert(name: 'تاجر جملة', customerType: const Value('wholesale')));
    final p = (await products.item(id))!;
    final d = InvoiceDraft(customerId: cust, customerType: 'wholesale')
      ..addProduct(productId: id, name: p.nameAr, sku: p.sku, wholesalePrice: p.wholesalePrice, retailPrice: p.retailPrice, available: p.quantity, quantity: u(2));
    expect(d.grandTotal, egp(600));
    final saleId = await sales.post(d);
    expect(await qty(id), u(18));
    // Posting the same invoice again must not deduct twice.
    await expectLater(sales.post(d), throwsA(isA<BusinessException>()));
    expect(await qty(id), u(18));

    final sale = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
    expect(sale.cogsTotal, egp(500));

    await sales.addPayment(saleId, egp(400), 'cash');
    final s = await sales.summary(saleId);
    expect(s.outstanding, egp(200));
    expect(s.paymentStatus, PaymentStatus.partial);
    await expectLater(() => sales.addPayment(saleId, egp(300), 'cash'), throwsA(isA<BusinessException>()));

    // Insufficient stock is rejected and nothing changes.
    final big = InvoiceDraft()
      ..addProduct(productId: id, name: 'x', sku: 'x', wholesalePrice: 1, retailPrice: 1, available: 0, quantity: u(100));
    await expectLater(sales.post(big), throwsA(isA<BusinessException>()));
    expect(await qty(id), u(18));
    expect(big.saleId, isNull);
  });

  test('Test J: purchase order and partial receipts', () async {
    final id = await createRing();
    final sup = await purchasing.saveSupplier(SupplierInput()..name = 'مورد');
    final po = await purchasing.savePurchaseOrder(
      supplierId: sup,
      orderDate: DateTime.now(),
      markOrdered: true,
      lines: [PoLineInput(productId: id, productName: 'x', orderedQuantity: u(10), unitCost: egp(240))],
    );
    expect(await qty(id), 0);
    var lines = await purchasing.receiptLinesForPo(po);
    await purchasing.postGoodsReceipt(
        purchaseOrderId: po, supplierId: sup, receivedAt: DateTime.now(), lines: [lines.single..acceptedQuantity = u(6)]);
    expect(await qty(id), u(6));
    var order = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(po))).getSingle();
    expect(order.status, PoStatus.partial);

    lines = await purchasing.receiptLinesForPo(po);
    expect(lines.single.remaining, u(4));
    await purchasing.postGoodsReceipt(purchaseOrderId: po, supplierId: sup, receivedAt: DateTime.now(), lines: lines);
    expect(await qty(id), u(10));
    order = await (db.select(db.purchaseOrders)..where((t) => t.id.equals(po))).getSingle();
    expect(order.status, PoStatus.received);
    expect((await inv.balanceOf(id)).avgCost, egp(240));
  });

  test('Test K + O: returns, damaged goods, reconciliation', () async {
    final id = await createRing();
    await docs.post(kind: StockDocKind.opening, lines: [StockDocLine(id, u(20), unitCost: egp(250))], reason: 'opening');
    final d = InvoiceDraft()
      ..addProduct(productId: id, name: 'x', sku: 'x', wholesalePrice: egp(300), retailPrice: egp(350), available: u(20), quantity: u(3));
    final saleId = await sales.post(d, initialPayment: egp(1050));
    expect(await qty(id), u(17));
    final line = (await sales.returnableLines(saleId)).single;

    // 2 returned, 1 of them damaged → only 1 back in stock. Refund the full value.
    await sales.postReturn(saleId, [ReturnLineInput(line.line.id, u(2), u(1))], refundAmount: egp(700));
    expect(await qty(id), u(18));
    final s = await sales.summary(saleId);
    expect(s.returned, egp(700));
    expect(s.outstanding, 0);
    final ret = await (db.select(db.salesReturns)..where((t) => t.saleId.equals(saleId))).getSingle();
    expect(ret.saleId, saleId);

    // Cannot exceed remaining returnable (1 left).
    await expectLater(() => sales.postReturn(saleId, [ReturnLineInput(line.line.id, u(2), 0)]), throwsA(isA<BusinessException>()));

    // Adjustment + stocktake, then ledger must equal balances.
    await docs.post(kind: StockDocKind.adjustment, lines: [StockDocLine(id, u(15))], reason: 'جرد');
    expect(await qty(id), u(15));
    final count = await docs.startCount(productIds: [id]);
    final cl = await (db.select(db.stockCountLines)..where((t) => t.stockCountId.equals(count))).getSingle();
    await docs.setCounted(cl.id, u(14));
    await docs.postCount(count);
    expect(await qty(id), u(14));
    await expectLater(docs.postCount(count), throwsA(isA<BusinessException>()));
    expect(await inv.reconcile(), isEmpty);
  });

  test('void sale restores stock', () async {
    final id = await createRing();
    await docs.post(kind: StockDocKind.opening, lines: [StockDocLine(id, u(5), unitCost: egp(250))], reason: 'o');
    final d = InvoiceDraft()..addProduct(productId: id, name: 'x', sku: 'x', wholesalePrice: 1, retailPrice: 1, available: u(5), quantity: u(2));
    final sid = await sales.post(d);
    await sales.voidSale(sid, 'خطأ');
    expect(await qty(id), u(5));
    expect(await inv.reconcile(), isEmpty);
  });

  test('foreign keys enabled and integrity ok', () async {
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.data.values.first, 1);
    expect(await db.integrityCheck(), 'ok');
  });
}
