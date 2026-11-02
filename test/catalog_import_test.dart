// Uses synthetic sample rows only — real catalog data is never committed (public repo).
import 'dart:convert';

import 'package:automotive_inventory/core/database/app_database.dart';
import 'package:automotive_inventory/core/errors/business_exception.dart';
import 'package:automotive_inventory/features/products/catalog_import_service.dart';
import 'package:automotive_inventory/features/products/product_repository.dart';
import 'package:automotive_inventory/features/sales/invoice_draft.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String sample() => jsonEncode({
      'format': 'auto-parts-catalog',
      'version': 1,
      'items': [
        {'key': 'R-0001', 'kind': 'ring', 'make': 'ماركة', 'model': 'موديل أ', 'size': '70', 'dim': '1+1+2', 'code': '111',
         'purchase': 100, 'wholesale': 100, 'retail': 120, 'notes': 'زيت قطعة واحدة', 'needsReview': false},
        {'key': 'R-0002', 'kind': 'ring', 'make': 'ماركة', 'model': '', 'size': '71.5(؟)', 'dim': '1+1+2',
         'retail': 130, 'needsReview': true, 'reviewNote': 'لا يوجد سعر جملة'},
        {'key': 'TR2-001', 'kind': 'piston', 'brand': 'TR2', 'model': 'موديل ب', 'size': '75.00', 'retail': 500, 'needsReview': false},
      ],
    });

void main() {
  late AppDatabase db;
  late ProductRepository repo;
  late CatalogImportService svc;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProductRepository(db);
    svc = CatalogImportService(db, repo);
  });
  tearDown(() => db.close());

  test('imports rows exactly, flags review items, and is idempotent', () async {
    final p = await svc.preview(sample());
    expect(p.rings, 2);
    expect(p.pistons, 1);
    expect(p.flagged, 1);
    final r = await svc.import(p);
    expect(r.created, 3);
    expect(r.flagged, 1);

    final a = await (db.select(db.products)..where((t) => t.internalSku.equals('R-0001'))).getSingle();
    expect(a.nameAr, 'شنبر ماركة موديل أ');
    expect(a.purchasePrice, 10000);
    expect(a.wholesalePrice, 10000);
    expect(a.retailPrice, 12000);
    expect(a.diameterMm, 70);
    expect(a.tcCode, '111');
    expect(a.needsReview, isFalse);

    final b = await (db.select(db.products)..where((t) => t.internalSku.equals('R-0002'))).getSingle();
    expect(b.nameAr, 'شنبر ماركة مقاس 71.5(؟)');
    expect(b.diameterMm, isNull, reason: 'unclear size is not converted to a number');
    expect(b.labelNotes, contains('71.5(؟)'));
    expect(b.wholesalePrice, 0, reason: 'missing prices are not invented');
    expect(b.needsReview, isTrue);
    expect(b.reviewNote, 'لا يوجد سعر جملة');

    final c = await (db.select(db.products)..where((t) => t.internalSku.equals('TR2-001'))).getSingle();
    expect(c.nameAr, 'بستم TR2 موديل ب');

    expect(await repo.watchReviewCount().first, 1);
    expect((await repo.search(const ProductQuery(needsReviewOnly: true))).single.sku, 'R-0002');
    expect((await repo.search(const ProductQuery(text: 'TR2 75'))).single.sku, 'TR2-001');

    await repo.markReviewed(b.id);
    expect(await repo.watchReviewCount().first, 0);

    // Re-import: nothing duplicated, nothing modified.
    final again = await svc.import(await svc.preview(sample()));
    expect(again.created, 0);
    expect(again.skipped, 3);
    expect((await db.select(db.products).get()).length, 3);
  });

  test('rejects files that are not catalogs', () async {
    await expectLater(svc.preview('{"x":1}'), throwsA(isA<BusinessException>()));
    await expectLater(svc.preview('not json'), throwsA(isA<BusinessException>()));
  });

  test('zero-price line cannot be posted', () {
    final d = InvoiceDraft()
      ..addProduct(productId: 1, name: 'x', sku: 'x', wholesalePrice: 0, retailPrice: 0, available: 5000);
    expect(d.validate().join(), contains('سعر البيع صفر'));
  });
}
