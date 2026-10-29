import 'package:automotive_inventory/core/utils/money.dart';
import 'package:automotive_inventory/features/sales/invoice_draft.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDraft _draft(String? type) {
  final d = InvoiceDraft(customerId: type == null ? null : 1, customerType: type);
  d.addProduct(
    productId: 1,
    name: 'شنبر TR2',
    sku: 'P-1',
    wholesalePrice: Money.fromMajor(300).minor,
    retailPrice: Money.fromMajor(350).minor,
    available: Qty.units(20).milli,
    quantity: Qty.units(2).milli,
  );
  return d;
}

void main() {
  test('Test F: wholesale customer gets wholesale price, total 600', () {
    final d = _draft('wholesale');
    expect(d.pricingMode, PricingMode.wholesale);
    expect(d.lines.single.unitPrice, Money.fromMajor(300).minor);
    expect(d.grandTotal, Money.fromMajor(600).minor);
  });

  test('Test G: retail customer gets retail price, total 700', () {
    final d = _draft('retail');
    expect(d.lines.single.unitPrice, Money.fromMajor(350).minor);
    expect(d.grandTotal, Money.fromMajor(700).minor);
  });

  test('walk-in defaults to retail', () {
    expect(_draft(null).pricingMode, PricingMode.retail);
  });

  test('Test H: mode switch updates defaults but never silently drops manual prices', () {
    final d = _draft('wholesale');
    d.addProduct(productId: 2, name: 'بستم', sku: 'P-2', wholesalePrice: 10000, retailPrice: 12000, available: 5000);
    d.setPricingMode(PricingMode.retail, resetOverrides: false);
    expect(d.lines[0].unitPrice, Money.fromMajor(350).minor);
    expect(d.lines[1].unitPrice, 12000);

    d.setLinePrice(d.lines[0], Money.fromMajor(320).minor);
    expect(d.lines[0].isManual, isTrue);
    expect(d.hasManualOverrides, isTrue);

    d.setPricingMode(PricingMode.wholesale, resetOverrides: false);
    expect(d.lines[0].unitPrice, Money.fromMajor(320).minor, reason: 'manual price preserved');
    expect(d.lines[1].unitPrice, 10000);

    d.setPricingMode(PricingMode.retail, resetOverrides: true);
    expect(d.lines[0].unitPrice, Money.fromMajor(350).minor);
    expect(d.lines[0].isManual, isFalse);
  });

  test('setting a price equal to the default is not marked manual', () {
    final d = _draft('retail');
    d.setLinePrice(d.lines.single, Money.fromMajor(350).minor);
    expect(d.lines.single.isManual, isFalse);
  });

  test('discounts and validation', () {
    final d = _draft('retail');
    d.lines.single.discount = Money.fromMajor(50).minor;
    d.invoiceDiscount = Money.fromMajor(10).minor;
    expect(d.grandTotal, Money.fromMajor(640).minor);
    expect(d.validate(), isEmpty);
    d.invoiceDiscount = Money.fromMajor(1000).minor;
    expect(d.validate(), isNotEmpty);
  });

  test('adding the same product merges quantity', () {
    final d = _draft('retail');
    d.addProduct(productId: 1, name: 'x', sku: 'P-1', wholesalePrice: 1, retailPrice: 1, available: 0, quantity: 1000);
    expect(d.lines, hasLength(1));
    expect(d.lines.single.quantity, 3000);
  });
}
