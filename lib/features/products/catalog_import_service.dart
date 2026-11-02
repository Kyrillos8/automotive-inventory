import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';
import 'product_repository.dart';

/// One catalog row from an import file (format "auto-parts-catalog" v1).
///
/// Prices are whole Egyptian pounds as written in the owner's price books;
/// they are stored as piastres. Missing values stay missing (0 / null) and are
/// never invented.
class CatalogItem {
  final String key; // becomes the internal SKU (used to skip duplicates on re-import)
  final String kind; // ring | piston
  final String? brand;
  final String make; // car make from the page title (rings)
  final String model;
  final String size;
  final String dim;
  final String code;
  final int? purchase;
  final int? wholesale;
  final int? retail;
  final String notes;
  final bool needsReview;
  final String reviewNote;
  final String source;

  CatalogItem.fromJson(Map<String, dynamic> j)
      : key = (j['key'] ?? '').toString().trim(),
        kind = (j['kind'] ?? '').toString(),
        brand = _str(j['brand']),
        make = (j['make'] ?? '').toString().trim(),
        model = (j['model'] ?? '').toString().trim(),
        size = (j['size'] ?? '').toString().trim(),
        dim = (j['dim'] ?? '').toString().trim(),
        code = (j['code'] ?? '').toString().trim(),
        purchase = _int(j['purchase']),
        wholesale = _int(j['wholesale']),
        retail = _int(j['retail']),
        notes = (j['notes'] ?? '').toString().trim(),
        needsReview = j['needsReview'] == true,
        reviewNote = (j['reviewNote'] ?? '').toString().trim(),
        source = (j['source'] ?? '').toString().trim();

  static String? _str(Object? v) => (v == null || v.toString().trim().isEmpty) ? null : v.toString().trim();
  static int? _int(Object? v) => v is int ? v : (v is num ? v.round() : int.tryParse('${v ?? ''}'));

  String get typeWord => kind == 'piston' ? 'بستم' : 'شنبر';

  /// Arabic display name; never adds information that is not in the row.
  String get displayName {
    final parts = <String>[typeWord];
    if (brand != null) parts.add(brand!);
    if (make.isNotEmpty && !model.startsWith(make)) parts.add(make);
    if (model.isNotEmpty) {
      parts.add(model);
    } else if (size.isNotEmpty) {
      parts.add('مقاس $size');
    }
    return parts.join(' ');
  }
}

class CatalogPreview {
  final List<CatalogItem> items;
  final int rings;
  final int pistons;
  final int flagged;
  final int alreadyExisting;
  CatalogPreview(this.items, this.rings, this.pistons, this.flagged, this.alreadyExisting);
}

class CatalogImportResult {
  final int created;
  final int skipped;
  final int flagged;
  CatalogImportResult(this.created, this.skipped, this.flagged);
}

class CatalogImportService {
  CatalogImportService(this.db, this.products);
  final AppDatabase db;
  final ProductRepository products;

  Future<CatalogPreview> preview(String jsonText) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const BusinessException('الملف ليس ملف كتالوج صالح');
    }
    if (decoded is! Map || decoded['format'] != 'auto-parts-catalog' || decoded['items'] is! List) {
      throw const BusinessException('الملف ليس ملف كتالوج صالح');
    }
    if ((decoded['version'] ?? 0) != 1) throw const BusinessException('إصدار ملف الكتالوج غير مدعوم');
    final items = <CatalogItem>[];
    for (final raw in decoded['items'] as List) {
      if (raw is! Map) continue;
      final it = CatalogItem.fromJson(Map<String, dynamic>.from(raw));
      if (it.key.isEmpty || (it.kind != 'ring' && it.kind != 'piston')) continue;
      items.add(it);
    }
    if (items.isEmpty) throw const BusinessException('الملف لا يحتوي على منتجات');
    final existing = (await db.select(db.products).get()).map((p) => p.internalSku).toSet();
    return CatalogPreview(
      items,
      items.where((i) => i.kind == 'ring').length,
      items.where((i) => i.kind == 'piston').length,
      items.where((i) => i.needsReview).length,
      items.where((i) => existing.contains(i.key)).length,
    );
  }

  /// Creates every product whose key is not already used as a SKU. Existing
  /// products are never modified. Runs in one transaction (all or nothing).
  Future<CatalogImportResult> import(CatalogPreview p) {
    return db.transaction(() async {
      final types = await db.select(db.productTypes).get();
      int typeFor(String kind) {
        final want = kind == 'piston' ? 'piston' : 'ring';
        final t = types.where((t) => t.kind == want).firstOrNull;
        if (t == null) throw BusinessException('نوع المنتج "$want" غير موجود');
        return t.id;
      }

      final unitsList = await db.select(db.units).get();
      Future<int> unitFor(String kind) async {
        final name = kind == 'ring' ? 'طقم' : 'قطعة';
        final u = unitsList.where((u) => u.nameAr == name).firstOrNull;
        return u?.id ?? await products.addUnit(name);
      }

      final existing = (await db.select(db.products).get()).map((x) => x.internalSku).toSet();
      final tagCache = <String, int>{};
      Future<int> tag(String name) async =>
          tagCache[name] ??= (await products.createTag(name)).id;
      final brandCache = <String, int>{};

      var created = 0, skipped = 0, flagged = 0;
      for (final it in p.items) {
        if (existing.contains(it.key)) {
          skipped++;
          continue;
        }
        final tags = <int>[await tag(it.kind == 'piston' ? 'بساتم' : 'شنابر')];
        if (it.make.isNotEmpty) tags.add(await tag(it.make));
        if (it.brand != null) tags.add(await tag(it.brand!));
        int? brandId;
        if (it.brand != null) brandId = brandCache[it.brand!] ??= await products.addBrand(it.brand!, it.brand);

        final diameter = double.tryParse(it.size);
        final labelParts = <String>[
          if (it.notes.isNotEmpty) it.notes,
          if (diameter == null && it.size.isNotEmpty) 'المقاس كما في الدفتر: ${it.size}',
        ];
        final input = ProductInput()
          ..internalSku = it.key
          ..nameAr = it.displayName
          ..productTypeId = typeFor(it.kind)
          ..baseUnitId = await unitFor(it.kind)
          ..brandId = brandId
          ..tcCode = it.code.isEmpty ? null : it.code
          ..diameterMm = diameter
          ..ringDimensions = it.dim.isEmpty ? null : it.dim
          ..purchasePrice = (it.purchase ?? 0) * 100
          ..wholesalePrice = (it.wholesale ?? 0) * 100
          ..retailPrice = (it.retail ?? 0) * 100
          ..labelNotes = labelParts.isEmpty ? null : labelParts.join(' — ')
          ..notes = it.source.isEmpty ? null : 'مستورد من دفتر الأسعار (صورة: ${it.source})'
          ..needsReview = it.needsReview
          ..reviewNote = it.reviewNote.isEmpty ? null : it.reviewNote
          ..tagIds = tags;
        await products.saveProduct(input);
        created++;
        if (it.needsReview) flagged++;
      }
      await db.logActivity('import', 'product', 'استيراد كتالوج: $created منتج جديد، $skipped موجود مسبقًا');
      return CatalogImportResult(created, skipped, flagged);
    });
  }
}

final catalogImportServiceProvider = Provider<CatalogImportService>(
  (ref) => CatalogImportService(ref.watch(databaseProvider), ref.watch(productRepositoryProvider)),
);
