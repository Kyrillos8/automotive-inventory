import 'package:automotive_inventory/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('parses western, arabic-indic and grouped input', () {
      expect(Money.tryParse('300'), const Money(30000));
      expect(Money.tryParse('300.5'), const Money(30050));
      expect(Money.tryParse('٣٥٠٫٧٥'), const Money(35075));
      expect(Money.tryParse('1,250.75'), const Money(125075));
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.234'), isNull);
    });

    test('price x quantity is exact (Test F/G totals)', () {
      expect(Money.fromMajor(300).timesQty(Qty.units(2)), Money.fromMajor(600));
      expect(Money.fromMajor(350).timesQty(Qty.units(2)), Money.fromMajor(700));
    });

    test('fractional quantity rounds half away from zero', () {
      // 0.10 EGP * 0.005 = 0.0005 EGP -> rounds to 0
      expect(const Money(10).timesQty(const Qty(5)), Money.zero);
      // 1.01 EGP * 1.5 = 1.515 -> 1.52
      expect(const Money(101).timesQty(const Qty(1500)), const Money(152));
    });

    test('partial payment balance (Test I)', () {
      expect(Money.fromMajor(600) - Money.fromMajor(400), Money.fromMajor(200));
    });

    test('formatting is separate from value', () {
      expect(const Money(125075).toPlain(), '1250.75');
      expect(const Money(-5).toPlain(), '-0.05');
    });
  });

  group('Qty', () {
    test('parse and print', () {
      expect(Qty.tryParse('20'), Qty.units(20));
      expect(Qty.tryParse('١٫٥'), const Qty(1500));
      expect(const Qty(1500).toPlain(), '1.5');
      expect(Qty.units(18).toPlain(), '18');
    });
  });
}
