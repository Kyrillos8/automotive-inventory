import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/errors/business_exception.dart';
import '../../core/utils/search_normalizer.dart';

// ---------------------------------------------------------------------------
// Input / output models
// ---------------------------------------------------------------------------

class CompatInput {
  final int vehicleModelId;
  final int? yearFrom;
  final int? yearTo;
  final String engineCapacity;
  final String engineCode;
  final String status; // confirmed | needs_verification
  final String? notes;
  // Display only
  final String label;
  CompatInput({
    required this.vehicleModelId,
    required this.label,
    this.yearFrom,
    this.yearTo,
    this.engineCapacity = '',
    this.engineCode = '',
    this.status = 'confirmed',
    this.notes,
  });
  String get key => '$vehicleModelId|$engineCapacity|$engineCode';
}

class SpecInput {
  final String key;
  final String value;
  SpecInput(this.key, this.value);
}

class ProductInput {
  int? id;
  String internalSku = '';
  String? barcode;
  String? tcCode;
  String nameAr = '';
  String? nameEn;
  String? description;
  int? productTypeId;
  int? brandId;
  int? categoryId;
  String? countryOfOrigin;
  int? baseUnitId;
  int purchasePrice = 0;
  int wholesalePrice = 0;
  int retailPrice = 0;
  int minimumStock = 0;
  int? maximumStock;
  String? notes;
  double? diameterMm;
  String? sizeDesignation;
  String? ringDimensions;
  String? engineCapacity;
  int? cylinders;
  String? engineCode;
  double? pinDiameterMm;
  double? compressionHeightMm;
  String? labelNotes;
  List<int> tagIds = [];
  List<CompatInput> compat = [];
  List<SpecInput> specs = [];
}

class ProductQuery {
  final String text;
  final int? productTypeId;
  final int? brandId;
  final int? categoryId;
  final Set<int> tagIds;
  final bool tagsMatchAll;
  final int? makeId;
  final int? modelId;
  final String? engineFilter; // engine code or capacity
  final String? stockStatus; // in | low | out
  final bool includeArchived;
  final String sort; // name | stock | sku | recent
  final int limit;
  final int offset;
  final int? productId;
  const ProductQuery({
    this.productId,
    this.text = '',
    this.productTypeId,
    this.brandId,
    this.categoryId,
    this.tagIds = const {},
    this.tagsMatchAll = false,
    this.makeId,
    this.modelId,
    this.engineFilter,
    this.stockStatus,
    this.includeArchived = false,
    this.sort = 'name',
    this.limit = 50,
    this.offset = 0,
  });

  ProductQuery copyWith({
    String? text,
    int? Function()? productTypeId,
    int? Function()? brandId,
    int? Function()? categoryId,
    Set<int>? tagIds,
    bool? tagsMatchAll,
    int? Function()? makeId,
    int? Function()? modelId,
    String? Function()? engineFilter,
    String? Function()? stockStatus,
    bool? includeArchived,
    String? sort,
    int? limit,
  }) =>
      ProductQuery(
        text: text ?? this.text,
        productTypeId: productTypeId != null ? productTypeId() : this.productTypeId,
        brandId: brandId != null ? brandId() : this.brandId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        tagIds: tagIds ?? this.tagIds,
        tagsMatchAll: tagsMatchAll ?? this.tagsMatchAll,
        makeId: makeId != null ? makeId() : this.makeId,
        modelId: modelId != null ? modelId() : this.modelId,
        engineFilter: engineFilter != null ? engineFilter() : this.engineFilter,
        stockStatus: stockStatus != null ? stockStatus() : this.stockStatus,
        includeArchived: includeArchived ?? this.includeArchived,
        sort: sort ?? this.sort,
        limit: limit ?? this.limit,
      );

  bool get hasFilters =>
      productTypeId != null ||
      brandId != null ||
      categoryId != null ||
      tagIds.isNotEmpty ||
      makeId != null ||
      modelId != null ||
      (engineFilter?.isNotEmpty ?? false) ||
      stockStatus != null ||
      includeArchived;
}

class ProductListItem {
  final int id;
  final String sku;
  final String nameAr;
  final String? nameEn;
  final String? tcCode;
  final String? barcode;
  final String typeName;
  final String typeKind;
  final String? brandName;
  final double? diameterMm;
  final String? sizeDesignation;
  final String? ringDimensions;
  final String? engineCapacity;
  final int quantity;
  final int avgCost;
  final int purchasePrice;
  final int wholesalePrice;
  final int retailPrice;
  final int minimumStock;
  final bool isActive;
  final List<String> tags;
  final String? vehicles;
  final String unitName;
  ProductListItem({
    required this.id,
    required this.sku,
    required this.nameAr,
    required this.nameEn,
    required this.tcCode,
    required this.barcode,
    required this.typeName,
    required this.typeKind,
    required this.brandName,
    required this.diameterMm,
    required this.sizeDesignation,
    required this.ringDimensions,
    required this.engineCapacity,
    required this.quantity,
    required this.avgCost,
    required this.purchasePrice,
    required this.wholesalePrice,
    required this.retailPrice,
    required this.minimumStock,
    required this.isActive,
    required this.tags,
    required this.vehicles,
    required this.unitName,
  });

  String get stockStatus => quantity <= 0 ? 'out' : (minimumStock > 0 && quantity < minimumStock ? 'low' : 'in');

  String get specSummary {
    final parts = <String>[];
    if (diameterMm != null) parts.add('Ø ${formatMm(diameterMm!)}');
    if (ringDimensions?.isNotEmpty ?? false) parts.add(ringDimensions!);
    if (sizeDesignation?.isNotEmpty ?? false) parts.add('مقاس $sizeDesignation');
    if (engineCapacity?.isNotEmpty ?? false) parts.add('سعة $engineCapacity');
    return parts.join(' • ');
  }
}

String formatMm(double v) => v.toStringAsFixed(2);

class CompatView {
  final int id;
  final int modelId;
  final String makeName;
  final String modelName;
  final int? yearFrom;
  final int? yearTo;
  final String engineCapacity;
  final String engineCode;
  final String status;
  final String? notes;
  CompatView(this.id, this.modelId, this.makeName, this.modelName, this.yearFrom, this.yearTo, this.engineCapacity,
      this.engineCode, this.status, this.notes);
  String get label {
    final b = StringBuffer('$makeName $modelName');
    if (yearFrom != null || yearTo != null) b.write(' (${yearFrom ?? ''}-${yearTo ?? ''})');
    if (engineCapacity.isNotEmpty) b.write(' • $engineCapacity');
    if (engineCode.isNotEmpty) b.write(' • $engineCode');
    return b.toString();
  }
}

class TagWithCount {
  final Tag tag;
  final int count;
  TagWithCount(this.tag, this.count);
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class ProductRepository {
  ProductRepository(this.db);
  final AppDatabase db;

  // ---------- lookups
  Stream<List<ProductType>> watchTypes() =>
      (db.select(db.productTypes)..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();
  Stream<List<Brand>> watchBrands() =>
      (db.select(db.brands)..orderBy([(t) => OrderingTerm(expression: t.nameAr)])).watch();
  Stream<List<Category>> watchCategories() =>
      (db.select(db.categories)..orderBy([(t) => OrderingTerm(expression: t.nameAr)])).watch();
  Stream<List<UnitOfMeasure>> watchUnits() =>
      (db.select(db.units)..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();
  Stream<List<Tag>> watchActiveTags() => (db.select(db.tags)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();
  Stream<List<VehicleMake>> watchMakes() =>
      (db.select(db.vehicleMakes)..orderBy([(t) => OrderingTerm(expression: t.nameAr)])).watch();
  Stream<List<VehicleModel>> watchModels(int makeId) => (db.select(db.vehicleModels)
        ..where((t) => t.makeId.equals(makeId))
        ..orderBy([(t) => OrderingTerm(expression: t.nameAr)]))
      .watch();

  Future<int> addProductType(String nameAr, String? nameEn, String kind) async {
    if (nameAr.trim().isEmpty) throw const BusinessException('الاسم مطلوب');
    return db.into(db.productTypes).insert(
        ProductTypesCompanion.insert(nameAr: nameAr.trim(), nameEn: Value(_n(nameEn)), kind: Value(kind)));
  }

  Future<int> addBrand(String nameAr, String? nameEn) async {
    final name = nameAr.trim();
    if (name.isEmpty) throw const BusinessException('الاسم مطلوب');
    final all = await db.select(db.brands).get();
    for (final b in all) {
      if (normalizeForSearch(b.nameAr) == normalizeForSearch(name)) return b.id;
    }
    return db.into(db.brands).insert(BrandsCompanion.insert(nameAr: name, nameEn: Value(_n(nameEn))));
  }

  Future<int> addCategory(String nameAr) async {
    if (nameAr.trim().isEmpty) throw const BusinessException('الاسم مطلوب');
    return db.into(db.categories).insert(CategoriesCompanion.insert(nameAr: nameAr.trim()));
  }

  Future<int> addUnit(String nameAr) async {
    if (nameAr.trim().isEmpty) throw const BusinessException('الاسم مطلوب');
    return db.into(db.units).insert(UnitsCompanion.insert(nameAr: nameAr.trim()));
  }

  // ---------- tags
  Future<Tag> createTag(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const BusinessException('اسم الوسم مطلوب');
    final norm = normalizeForSearch(clean);
    final existing = await (db.select(db.tags)..where((t) => t.normalizedName.equals(norm))).getSingleOrNull();
    if (existing != null) {
      if (!existing.isActive) {
        await (db.update(db.tags)..where((t) => t.id.equals(existing.id)))
            .write(const TagsCompanion(isActive: Value(true)));
      }
      return (db.select(db.tags)..where((t) => t.id.equals(existing.id))).getSingle();
    }
    final id = await db.into(db.tags).insert(TagsCompanion.insert(name: clean, normalizedName: norm));
    return (db.select(db.tags)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameTag(int id, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) throw const BusinessException('اسم الوسم مطلوب');
    final norm = normalizeForSearch(clean);
    await db.transaction(() async {
      final dup = await (db.select(db.tags)..where((t) => t.normalizedName.equals(norm) & t.id.equals(id).not()))
          .getSingleOrNull();
      if (dup != null) throw BusinessException('يوجد وسم بنفس الاسم: ${dup.name}');
      await (db.update(db.tags)..where((t) => t.id.equals(id)))
          .write(TagsCompanion(name: Value(clean), normalizedName: Value(norm), updatedAt: Value(DateTime.now())));
      final pids = await _productIdsWhere('SELECT product_id AS id FROM product_tags WHERE tag_id = ?', [id]);
      for (final p in pids) {
        await rebuildSearchText(p);
      }
    });
  }

  Future<void> setTagActive(int id, bool active) =>
      (db.update(db.tags)..where((t) => t.id.equals(id))).write(TagsCompanion(isActive: Value(active)));

  /// Deletes a tag only if no product uses it.
  Future<void> deleteTag(int id) async {
    await db.transaction(() async {
      final used = await db.customSelect('SELECT COUNT(*) AS c FROM product_tags WHERE tag_id = ?',
          variables: [Variable.withInt(id)]).getSingle();
      if (used.read<int>('c') > 0) throw const BusinessException('لا يمكن حذف وسم مرتبط بمنتجات — يمكنك أرشفته');
      await (db.delete(db.tags)..where((t) => t.id.equals(id))).go();
    });
  }

  Stream<List<TagWithCount>> watchTagsWithCounts({String filter = ''}) {
    final f = normalizeForSearch(filter);
    return db
        .customSelect(
          'SELECT t.*, (SELECT COUNT(*) FROM product_tags pt WHERE pt.tag_id = t.id) AS cnt FROM tags t '
          "WHERE t.normalized_name LIKE ? ESCAPE '\\' ORDER BY t.is_active DESC, t.name",
          variables: [Variable.withString('%${_esc(f)}%')],
          readsFrom: {db.tags, db.productTags},
        )
        .watch()
        .map((rows) => [for (final r in rows) TagWithCount(db.tags.map(r.data), r.read<int>('cnt'))]);
  }

  // ---------- vehicles
  Future<int> addMake(String nameAr, String? nameEn) async {
    if (nameAr.trim().isEmpty) throw const BusinessException('اسم الماركة مطلوب');
    final norm = normalizeForSearch(nameAr);
    for (final m in await db.select(db.vehicleMakes).get()) {
      if (normalizeForSearch(m.nameAr) == norm) throw BusinessException('الماركة موجودة بالفعل: ${m.nameAr}');
    }
    return db.into(db.vehicleMakes).insert(VehicleMakesCompanion.insert(nameAr: nameAr.trim(), nameEn: Value(_n(nameEn))));
  }

  Future<int> addModel(int makeId, String nameAr, String? nameEn) async {
    if (nameAr.trim().isEmpty) throw const BusinessException('اسم الموديل مطلوب');
    final norm = normalizeForSearch(nameAr);
    final models = await (db.select(db.vehicleModels)..where((t) => t.makeId.equals(makeId))).get();
    for (final m in models) {
      if (normalizeForSearch(m.nameAr) == norm) throw BusinessException('الموديل موجود بالفعل: ${m.nameAr}');
    }
    return db
        .into(db.vehicleModels)
        .insert(VehicleModelsCompanion.insert(makeId: makeId, nameAr: nameAr.trim(), nameEn: Value(_n(nameEn))));
  }

  Future<void> renameMake(int id, String nameAr, String? nameEn) async {
    await db.transaction(() async {
      await (db.update(db.vehicleMakes)..where((t) => t.id.equals(id)))
          .write(VehicleMakesCompanion(nameAr: Value(nameAr.trim()), nameEn: Value(_n(nameEn))));
      final pids = await _productIdsWhere(
          'SELECT DISTINCT c.product_id AS id FROM vehicle_compatibilities c JOIN vehicle_models m ON m.id = c.vehicle_model_id WHERE m.make_id = ?',
          [id]);
      for (final p in pids) {
        await rebuildSearchText(p);
      }
    });
  }

  Future<void> renameModel(int id, String nameAr, String? nameEn) async {
    await db.transaction(() async {
      await (db.update(db.vehicleModels)..where((t) => t.id.equals(id)))
          .write(VehicleModelsCompanion(nameAr: Value(nameAr.trim()), nameEn: Value(_n(nameEn))));
      final pids = await _productIdsWhere(
          'SELECT DISTINCT product_id AS id FROM vehicle_compatibilities WHERE vehicle_model_id = ?', [id]);
      for (final p in pids) {
        await rebuildSearchText(p);
      }
    });
  }

  Future<List<CompatView>> compatibilityOf(int productId) async {
    final rows = await db.customSelect('''
      SELECT c.*, m.name_ar AS model_ar, mk.name_ar AS make_ar
      FROM vehicle_compatibilities c
      JOIN vehicle_models m ON m.id = c.vehicle_model_id
      JOIN vehicle_makes mk ON mk.id = m.make_id
      WHERE c.product_id = ? ORDER BY mk.name_ar, m.name_ar
    ''', variables: [Variable.withInt(productId)]).get();
    return [
      for (final r in rows)
        CompatView(
          r.read<int>('id'),
          r.read<int>('vehicle_model_id'),
          r.read<String>('make_ar'),
          r.read<String>('model_ar'),
          r.readNullable<int>('year_from'),
          r.readNullable<int>('year_to'),
          r.read<String>('engine_capacity'),
          r.read<String>('engine_code'),
          r.read<String>('status'),
          r.readNullable<String>('notes'),
        ),
    ];
  }

  Future<void> removeCompatibility(int compatId) async {
    await db.transaction(() async {
      final c = await (db.select(db.vehicleCompatibilities)..where((t) => t.id.equals(compatId))).getSingle();
      await (db.delete(db.vehicleCompatibilities)..where((t) => t.id.equals(compatId))).go();
      await rebuildSearchText(c.productId);
    });
  }

  // ---------- products
  Future<String> suggestSku() async {
    final row = await (db.select(db.docSequences)..where((t) => t.docType.equals('sku'))).getSingle();
    return '${row.prefix}${row.nextValue.toString().padLeft(5, '0')}';
  }

  Future<int> saveProduct(ProductInput p) async {
    if (p.nameAr.trim().isEmpty) throw const BusinessException('اسم المنتج بالعربية مطلوب');
    if (p.productTypeId == null) throw const BusinessException('نوع المنتج مطلوب');
    if (p.baseUnitId == null) throw const BusinessException('وحدة المخزون مطلوبة');
    if (p.purchasePrice < 0 || p.wholesalePrice < 0 || p.retailPrice < 0) {
      throw const BusinessException('الأسعار لا يمكن أن تكون سالبة');
    }
    return db.transaction(() async {
      var sku = p.internalSku.trim();
      if (sku.isEmpty) {
        sku = await db.nextDocNumber('sku');
      }
      final dup = await (db.select(db.products)
            ..where((t) => t.internalSku.equals(sku) & (p.id == null ? const Constant(true) : t.id.equals(p.id!).not())))
          .getSingleOrNull();
      if (dup != null) throw BusinessException('الكود الداخلي $sku مستخدم لمنتج آخر: ${dup.nameAr}');

      final comp = ProductsCompanion(
        internalSku: Value(sku),
        barcode: Value(_n(p.barcode)),
        tcCode: Value(_n(p.tcCode)),
        nameAr: Value(p.nameAr.trim()),
        nameEn: Value(_n(p.nameEn)),
        description: Value(_n(p.description)),
        productTypeId: Value(p.productTypeId!),
        brandId: Value(p.brandId),
        categoryId: Value(p.categoryId),
        countryOfOrigin: Value(_n(p.countryOfOrigin)),
        baseUnitId: Value(p.baseUnitId!),
        purchasePrice: Value(p.purchasePrice),
        wholesalePrice: Value(p.wholesalePrice),
        retailPrice: Value(p.retailPrice),
        minimumStock: Value(p.minimumStock),
        maximumStock: Value(p.maximumStock),
        notes: Value(_n(p.notes)),
        diameterMm: Value(p.diameterMm),
        sizeDesignation: Value(_n(p.sizeDesignation)),
        ringDimensions: Value(_n(p.ringDimensions)),
        engineCapacity: Value(_n(p.engineCapacity)),
        cylinders: Value(p.cylinders),
        engineCode: Value(_n(p.engineCode)),
        pinDiameterMm: Value(p.pinDiameterMm),
        compressionHeightMm: Value(p.compressionHeightMm),
        labelNotes: Value(_n(p.labelNotes)),
        updatedAt: Value(DateTime.now()),
      );
      int id;
      if (p.id == null) {
        id = await db.into(db.products).insert(comp);
        await db.into(db.stockBalances).insert(StockBalancesCompanion.insert(productId: Value(id)));
        await db.logActivity('create', 'product', 'إضافة منتج: ${p.nameAr.trim()} ($sku)', entityId: id);
      } else {
        id = p.id!;
        await (db.update(db.products)..where((t) => t.id.equals(id))).write(comp);
        await db.logActivity('update', 'product', 'تعديل منتج: ${p.nameAr.trim()} ($sku)', entityId: id);
      }

      // Tags: replace set.
      await (db.delete(db.productTags)..where((t) => t.productId.equals(id))).go();
      for (final tid in p.tagIds.toSet()) {
        await db.into(db.productTags).insert(ProductTagsCompanion.insert(productId: id, tagId: tid));
      }
      // Compatibility: replace set (dedup by key).
      await (db.delete(db.vehicleCompatibilities)..where((t) => t.productId.equals(id))).go();
      final seen = <String>{};
      for (final c in p.compat) {
        if (!seen.add(c.key)) continue;
        await db.into(db.vehicleCompatibilities).insert(VehicleCompatibilitiesCompanion.insert(
              productId: id,
              vehicleModelId: c.vehicleModelId,
              yearFrom: Value(c.yearFrom),
              yearTo: Value(c.yearTo),
              engineCapacity: Value(c.engineCapacity.trim()),
              engineCode: Value(c.engineCode.trim()),
              status: Value(c.status),
              notes: Value(_n(c.notes)),
            ));
      }
      // Extra specs.
      await (db.delete(db.productSpecs)..where((t) => t.productId.equals(id))).go();
      for (final s in p.specs) {
        if (s.key.trim().isEmpty || s.value.trim().isEmpty) continue;
        await db.into(db.productSpecs).insert(ProductSpecsCompanion.insert(
              productId: id,
              specKey: s.key.trim(),
              textValue: s.value.trim(),
              numericValue: Value(double.tryParse(s.value.trim())),
            ));
      }
      await rebuildSearchText(id);
      return id;
    });
  }

  Future<ProductInput> loadInput(int id) async {
    final p = await (db.select(db.products)..where((t) => t.id.equals(id))).getSingle();
    final tags = await (db.select(db.productTags)..where((t) => t.productId.equals(id))).get();
    final specs = await (db.select(db.productSpecs)..where((t) => t.productId.equals(id))).get();
    final compat = await compatibilityOf(id);
    return ProductInput()
      ..id = p.id
      ..internalSku = p.internalSku
      ..barcode = p.barcode
      ..tcCode = p.tcCode
      ..nameAr = p.nameAr
      ..nameEn = p.nameEn
      ..description = p.description
      ..productTypeId = p.productTypeId
      ..brandId = p.brandId
      ..categoryId = p.categoryId
      ..countryOfOrigin = p.countryOfOrigin
      ..baseUnitId = p.baseUnitId
      ..purchasePrice = p.purchasePrice
      ..wholesalePrice = p.wholesalePrice
      ..retailPrice = p.retailPrice
      ..minimumStock = p.minimumStock
      ..maximumStock = p.maximumStock
      ..notes = p.notes
      ..diameterMm = p.diameterMm
      ..sizeDesignation = p.sizeDesignation
      ..ringDimensions = p.ringDimensions
      ..engineCapacity = p.engineCapacity
      ..cylinders = p.cylinders
      ..engineCode = p.engineCode
      ..pinDiameterMm = p.pinDiameterMm
      ..compressionHeightMm = p.compressionHeightMm
      ..labelNotes = p.labelNotes
      ..tagIds = tags.map((t) => t.tagId).toList()
      ..specs = specs.map((s) => SpecInput(s.specKey, s.textValue)).toList()
      ..compat = [
        for (final c in compat)
          CompatInput(
            vehicleModelId: c.modelId,
            label: '${c.makeName} ${c.modelName}',
            yearFrom: c.yearFrom,
            yearTo: c.yearTo,
            engineCapacity: c.engineCapacity,
            engineCode: c.engineCode,
            status: c.status,
            notes: c.notes,
          )
      ];
  }

  Future<void> setActive(int id, bool active) async {
    await db.transaction(() async {
      await (db.update(db.products)..where((t) => t.id.equals(id)))
          .write(ProductsCompanion(isActive: Value(active), updatedAt: Value(DateTime.now())));
      await db.logActivity(active ? 'reactivate' : 'archive', 'product', active ? 'إعادة تفعيل منتج' : 'أرشفة منتج',
          entityId: id);
    });
  }

  /// Rebuilds the normalized search key from every searchable field.
  Future<void> rebuildSearchText(int productId) async {
    final r = await db.customSelect('''
      SELECT p.*, pt.name_ar AS type_ar, pt.name_en AS type_en, b.name_ar AS brand_ar, b.name_en AS brand_en,
             c.name_ar AS cat_ar, c.name_en AS cat_en,
             (SELECT GROUP_CONCAT(t.name, ' ') FROM product_tags x JOIN tags t ON t.id = x.tag_id WHERE x.product_id = p.id) AS tag_names,
             (SELECT GROUP_CONCAT(mk.name_ar || ' ' || COALESCE(mk.name_en,'') || ' ' || m.name_ar || ' ' || COALESCE(m.name_en,'') || ' ' || vc.engine_code || ' ' || vc.engine_capacity, ' ')
                FROM vehicle_compatibilities vc JOIN vehicle_models m ON m.id = vc.vehicle_model_id JOIN vehicle_makes mk ON mk.id = m.make_id
                WHERE vc.product_id = p.id) AS vehicles,
             (SELECT GROUP_CONCAT(s.spec_key || ' ' || s.text_value, ' ') FROM product_specs s WHERE s.product_id = p.id) AS specs
      FROM products p
      JOIN product_types pt ON pt.id = p.product_type_id
      LEFT JOIN brands b ON b.id = p.brand_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.id = ?
    ''', variables: [Variable.withInt(productId)]).getSingle();
    String? s(String k) => r.readNullable<String>(k);
    final dia = r.readNullable<double>('diameter_mm');
    final cyl = r.readNullable<int>('cylinders');
    final parts = <String?>[
      s('name_ar'), s('name_en'), s('internal_sku'), s('barcode'), s('tc_code'),
      s('type_ar'), s('type_en'), s('brand_ar'), s('brand_en'), s('cat_ar'), s('cat_en'),
      s('country_of_origin'), s('description'), s('engine_code'), s('engine_capacity'),
      s('size_designation'), s('ring_dimensions'), s('label_notes'),
      if (dia != null) '${formatMm(dia)} ${_trimNum(dia)}',
      if (cyl != null) '${cyl}cyl ${cyl}cly',
      s('tag_names'), s('vehicles'), s('specs'),
    ];
    final text = normalizeForSearch(parts.whereType<String>().where((e) => e.trim().isNotEmpty).join(' | '));
    await (db.update(db.products)..where((t) => t.id.equals(productId)))
        .write(ProductsCompanion(searchText: Value(text)));
  }

  Future<void> rebuildAllSearchText() async {
    final ids = await _productIdsWhere('SELECT id FROM products', []);
    await db.transaction(() async {
      for (final id in ids) {
        await rebuildSearchText(id);
      }
    });
  }

  // ---------- search
  /// Unified product search. All text terms must appear somewhere in the
  /// product's searchable data (name, codes, specs, tags, vehicles, ...).
  /// Exact SKU / barcode / T.C matches are ranked first.
  Future<List<ProductListItem>> search(ProductQuery q) async {
    final where = <String>[];
    final vars = <Variable>[];
    if (!q.includeArchived) where.add('p.is_active = 1');
    if (q.productId != null) {
      where.add('p.id = ?');
      vars.add(Variable.withInt(q.productId!));
    }
    final terms = searchTerms(q.text);
    for (final t in terms) {
      where.add("p.search_text LIKE ? ESCAPE '\\'");
      vars.add(Variable.withString('%${_esc(t)}%'));
    }
    if (q.productTypeId != null) {
      where.add('p.product_type_id = ?');
      vars.add(Variable.withInt(q.productTypeId!));
    }
    if (q.brandId != null) {
      where.add('p.brand_id = ?');
      vars.add(Variable.withInt(q.brandId!));
    }
    if (q.categoryId != null) {
      where.add('p.category_id = ?');
      vars.add(Variable.withInt(q.categoryId!));
    }
    if (q.tagIds.isNotEmpty) {
      final ph = List.filled(q.tagIds.length, '?').join(',');
      if (q.tagsMatchAll) {
        where.add('(SELECT COUNT(DISTINCT tag_id) FROM product_tags x WHERE x.product_id = p.id AND x.tag_id IN ($ph)) = ?');
        vars.addAll(q.tagIds.map(Variable.withInt));
        vars.add(Variable.withInt(q.tagIds.length));
      } else {
        where.add('EXISTS (SELECT 1 FROM product_tags x WHERE x.product_id = p.id AND x.tag_id IN ($ph))');
        vars.addAll(q.tagIds.map(Variable.withInt));
      }
    }
    if (q.modelId != null || q.makeId != null) {
      final sub = StringBuffer(
          'EXISTS (SELECT 1 FROM vehicle_compatibilities vc JOIN vehicle_models vm ON vm.id = vc.vehicle_model_id WHERE vc.product_id = p.id');
      if (q.modelId != null) {
        sub.write(' AND vc.vehicle_model_id = ?');
        vars.add(Variable.withInt(q.modelId!));
      } else {
        sub.write(' AND vm.make_id = ?');
        vars.add(Variable.withInt(q.makeId!));
      }
      if (q.engineFilter?.trim().isNotEmpty ?? false) {
        sub.write(" AND (vc.engine_code LIKE ? OR vc.engine_capacity LIKE ? OR vc.engine_code = '' AND vc.engine_capacity = '')");
        final e = '%${q.engineFilter!.trim()}%';
        vars.add(Variable.withString(e));
        vars.add(Variable.withString(e));
      }
      sub.write(')');
      where.add(sub.toString());
    }
    switch (q.stockStatus) {
      case 'out':
        where.add('COALESCE(sb.quantity_on_hand,0) <= 0');
      case 'low':
        where.add('COALESCE(sb.quantity_on_hand,0) > 0 AND p.minimum_stock > 0 AND sb.quantity_on_hand < p.minimum_stock');
      case 'in':
        where.add('COALESCE(sb.quantity_on_hand,0) > 0');
    }
    final exact = normalizeForSearch(q.text);
    final orderBy = switch (q.sort) {
      'stock' => 'qty DESC',
      'stock_asc' => 'qty ASC',
      'sku' => 'p.internal_sku',
      'recent' => 'p.id DESC',
      _ => 'p.name_ar',
    };
    final rankVars = <Variable>[Variable.withString(exact), Variable.withString(exact), Variable.withString(exact)];
    final sql = '''
      SELECT p.id, p.internal_sku, p.name_ar, p.name_en, p.tc_code, p.barcode, p.diameter_mm, p.size_designation,
             p.ring_dimensions, p.engine_capacity, p.purchase_price, p.wholesale_price, p.retail_price,
             p.minimum_stock, p.is_active,
             pt.name_ar AS type_name, pt.kind AS type_kind, b.name_ar AS brand_name, u.name_ar AS unit_name,
             COALESCE(sb.quantity_on_hand, 0) AS qty, COALESCE(sb.avg_cost, 0) AS avg_cost,
             (SELECT GROUP_CONCAT(t.name, '|') FROM product_tags x JOIN tags t ON t.id = x.tag_id WHERE x.product_id = p.id) AS tags,
             (SELECT GROUP_CONCAT(mk.name_ar || ' ' || m.name_ar, '، ') FROM vehicle_compatibilities vc
                JOIN vehicle_models m ON m.id = vc.vehicle_model_id JOIN vehicle_makes mk ON mk.id = m.make_id
                WHERE vc.product_id = p.id) AS vehicles,
             CASE WHEN LOWER(p.internal_sku) = ? OR LOWER(COALESCE(p.barcode,'')) = ? OR LOWER(COALESCE(p.tc_code,'')) = ? THEN 0 ELSE 1 END AS rnk
      FROM products p
      JOIN product_types pt ON pt.id = p.product_type_id
      JOIN units u ON u.id = p.base_unit_id
      LEFT JOIN brands b ON b.id = p.brand_id
      LEFT JOIN stock_balances sb ON sb.product_id = p.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY rnk, $orderBy
      LIMIT ? OFFSET ?
    ''';
    final rows = await db.customSelect(sql, variables: [
      ...rankVars,
      ...vars,
      Variable.withInt(q.limit),
      Variable.withInt(q.offset),
    ]).get();
    return rows.map(_mapItem).toList();
  }

  ProductListItem _mapItem(QueryRow r) => ProductListItem(
        id: r.read<int>('id'),
        sku: r.read<String>('internal_sku'),
        nameAr: r.read<String>('name_ar'),
        nameEn: r.readNullable<String>('name_en'),
        tcCode: r.readNullable<String>('tc_code'),
        barcode: r.readNullable<String>('barcode'),
        typeName: r.read<String>('type_name'),
        typeKind: r.read<String>('type_kind'),
        brandName: r.readNullable<String>('brand_name'),
        diameterMm: r.readNullable<double>('diameter_mm'),
        sizeDesignation: r.readNullable<String>('size_designation'),
        ringDimensions: r.readNullable<String>('ring_dimensions'),
        engineCapacity: r.readNullable<String>('engine_capacity'),
        quantity: r.read<int>('qty'),
        avgCost: r.read<int>('avg_cost'),
        purchasePrice: r.read<int>('purchase_price'),
        wholesalePrice: r.read<int>('wholesale_price'),
        retailPrice: r.read<int>('retail_price'),
        minimumStock: r.read<int>('minimum_stock'),
        isActive: r.read<bool>('is_active'),
        tags: (r.readNullable<String>('tags') ?? '').split('|').where((e) => e.isNotEmpty).toList(),
        vehicles: r.readNullable<String>('vehicles'),
        unitName: r.read<String>('unit_name'),
      );

  Future<ProductListItem?> item(int id) async {
    final r = await search(ProductQuery(includeArchived: true, productId: id, limit: 1));
    return r.isEmpty ? null : r.first;
  }

  Future<List<int>> _productIdsWhere(String sql, List<int> args) async {
    final rows = await db.customSelect(sql, variables: args.map(Variable.withInt).toList()).get();
    return rows.map((r) => r.read<int>('id')).toList();
  }

  static String? _n(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  static String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
  static String _trimNum(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

final productRepositoryProvider = Provider<ProductRepository>((ref) => ProductRepository(ref.watch(databaseProvider)));
