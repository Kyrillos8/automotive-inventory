import 'package:automotive_inventory/core/utils/search_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alef forms and diacritics are unified', () {
    expect(normalizeForSearch('إلنترا'), normalizeForSearch('النترا'));
    expect(normalizeForSearch('شَنَابِر'), 'شنابر');
    expect(normalizeForSearch('هيونـــداي'), 'هيونداي');
  });

  test('ta marbuta / alef maqsura', () {
    expect(normalizeForSearch('مقاسة'), normalizeForSearch('مقاسه'));
    expect(normalizeForSearch('كورى'), normalizeForSearch('كوري'));
  });

  test('digits and case', () {
    expect(normalizeForSearch('٧٨٫٠٠'), '78.00');
    expect(normalizeForSearch('Hyundai  ELANTRA '), 'hyundai elantra');
    expect(normalizeForSearch('TR2'), 'tr2');
  });

  test('terms split', () {
    expect(searchTerms('Hyundai ٧٨ 0.50'), ['hyundai', '78', '0.50']);
  });

  test('manufacturer codes kept intact', () {
    expect(normalizeForSearch('01680'), '01680');
    expect(normalizeForSearch('1.20 - 1.20 - 2.00'), '1.20 - 1.20 - 2.00');
  });
}
