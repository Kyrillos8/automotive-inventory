import '../../core/utils/money.dart';

abstract final class PricingMode {
  static const wholesale = 'wholesale';
  static const retail = 'retail';
  static String label(String m) => m == wholesale ? 'جملة' : 'قطاعي';
  static String forCustomerType(String? customerType) => customerType == 'wholesale' ? wholesale : retail;
}

abstract final class PriceType {
  static const wholesale = 'wholesale';
  static const retail = 'retail';
  static const manual = 'manual';
  static String label(String t) => switch (t) {
        wholesale => 'جملة',
        retail => 'قطاعي',
        _ => 'سعر يدوي',
      };
}

class DraftLine {
  final int productId;
  final String name;
  final String sku;
  final int wholesalePrice;
  final int retailPrice;
  final int available; // milli
  int quantity; // milli
  int unitPrice; // minor
  String priceType;
  int discount; // minor, per line

  DraftLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.wholesalePrice,
    required this.retailPrice,
    required this.available,
    required this.quantity,
    required this.unitPrice,
    required this.priceType,
    this.discount = 0,
  });

  int priceFor(String mode) => mode == PricingMode.wholesale ? wholesalePrice : retailPrice;
  int get gross => Money(unitPrice).timesQty(Qty(quantity)).minor;
  int get lineTotal => gross - discount;
  bool get isManual => priceType == PriceType.manual;
  bool get exceedsStock => quantity > available;
}

/// In-memory invoice being built. Pure logic — no database access — so the
/// pricing rules are unit-tested directly.
class InvoiceDraft {
  int? saleId;
  int? customerId; // null = walk-in retail customer
  String? customerName;
  String? customerType;
  String pricingMode;
  final List<DraftLine> lines = [];
  int invoiceDiscount = 0;
  String? notes;

  InvoiceDraft({this.customerId, this.customerName, this.customerType})
      : pricingMode = PricingMode.forCustomerType(customerType);

  /// Changing customer resets the default mode from the new customer type.
  /// Returns true if the mode changed.
  bool setCustomer(int? id, String? name, String? type, {bool resetOverrides = false}) {
    customerId = id;
    customerName = name;
    customerType = type;
    final m = PricingMode.forCustomerType(type);
    if (m == pricingMode) return false;
    setPricingMode(m, resetOverrides: resetOverrides);
    return true;
  }

  bool get hasManualOverrides => lines.any((l) => l.isManual);

  /// Applies the mode's default price to every non-manual line. Manual prices
  /// are kept unless [resetOverrides] is true. Never silently discards overrides.
  void setPricingMode(String mode, {required bool resetOverrides}) {
    pricingMode = mode;
    for (final l in lines) {
      if (l.isManual && !resetOverrides) continue;
      l.unitPrice = l.priceFor(mode);
      l.priceType = mode;
    }
  }

  void addProduct({
    required int productId,
    required String name,
    required String sku,
    required int wholesalePrice,
    required int retailPrice,
    required int available,
    int quantity = 1000,
  }) {
    for (final l in lines) {
      if (l.productId == productId) {
        l.quantity += quantity;
        return;
      }
    }
    lines.add(DraftLine(
      productId: productId,
      name: name,
      sku: sku,
      wholesalePrice: wholesalePrice,
      retailPrice: retailPrice,
      available: available,
      quantity: quantity,
      unitPrice: pricingMode == PricingMode.wholesale ? wholesalePrice : retailPrice,
      priceType: pricingMode,
    ));
  }

  /// Sets a line price; marks it manual unless it equals the current default.
  void setLinePrice(DraftLine l, int price) {
    l.unitPrice = price;
    l.priceType = price == l.priceFor(pricingMode) ? pricingMode : PriceType.manual;
  }

  void resetLinePrice(DraftLine l) {
    l.unitPrice = l.priceFor(pricingMode);
    l.priceType = pricingMode;
  }

  int get subtotal => lines.fold(0, (a, l) => a + l.gross);
  int get lineDiscounts => lines.fold(0, (a, l) => a + l.discount);
  int get discountTotal => lineDiscounts + invoiceDiscount;
  int get taxTotal => 0; // Taxes disabled until configured.
  int get grandTotal => subtotal - discountTotal + taxTotal;

  List<String> validate() {
    final errors = <String>[];
    if (lines.isEmpty) errors.add('أضف منتجًا واحدًا على الأقل');
    for (final l in lines) {
      if (l.quantity <= 0) errors.add('كمية غير صحيحة: ${l.name}');
      if (l.unitPrice < 0) errors.add('سعر غير صحيح: ${l.name}');
      if (l.discount < 0 || l.discount > l.gross) errors.add('خصم غير صحيح: ${l.name}');
    }
    if (invoiceDiscount < 0 || grandTotal < 0) errors.add('خصم الفاتورة أكبر من الإجمالي');
    return errors;
  }
}
