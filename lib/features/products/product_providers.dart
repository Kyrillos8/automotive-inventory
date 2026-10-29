import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import 'product_repository.dart';

final productTypesProvider = StreamProvider<List<ProductType>>((ref) => ref.watch(productRepositoryProvider).watchTypes());
final brandsProvider = StreamProvider<List<Brand>>((ref) => ref.watch(productRepositoryProvider).watchBrands());
final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(productRepositoryProvider).watchCategories());
final unitsProvider = StreamProvider<List<UnitOfMeasure>>((ref) => ref.watch(productRepositoryProvider).watchUnits());
final activeTagsProvider = StreamProvider<List<Tag>>((ref) => ref.watch(productRepositoryProvider).watchActiveTags());
final makesProvider = StreamProvider<List<VehicleMake>>((ref) => ref.watch(productRepositoryProvider).watchMakes());
final modelsProvider =
    StreamProvider.family<List<VehicleModel>, int>((ref, makeId) => ref.watch(productRepositoryProvider).watchModels(makeId));

/// Bumped after any product/stock change so open lists refresh.
final catalogVersionProvider = StateProvider<int>((ref) => 0);

void bumpCatalog(WidgetRef ref) => ref.read(catalogVersionProvider.notifier).state++;
