import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/database/providers.dart';
import '../../core/utils/money.dart';
import '../inventory/inventory_service.dart';

enum ColKind { text, money, qty, number }

class ReportColumn {
  final String title;
  final ColKind kind;
  const ReportColumn(this.title, [this.kind = ColKind.text]);
}

class ReportTable {
  final String title;
  final List<ReportColumn> columns;
  final List<List<Object?>> rows;
  final String? note;
  ReportTable(this.title, this.columns, this.rows, {this.note});

  String cell(int r, int c) => formatCell(rows[r][c], columns[c].kind);

  static String formatCell(Object? v, ColKind k) {
    if (v == null) return '';
    switch (k) {
      case ColKind.money:
        return Money((v as num).toInt()).toPlain();
      case ColKind.qty:
        return Qty((v as num).toInt()).toPlain();
      case ColKind.number:
      case ColKind.text:
        if (v is DateTime) return DateFormat('yyyy-MM-dd HH:mm', 'en').format(v);
        return '$v';
    }
  }

  /// Sums for money/qty columns.
  List<String> totals() => [
        for (var c = 0; c < columns.length; c++)
          (columns[c].kind == ColKind.money || columns[c].kind == ColKind.qty)
              ? formatCell(rows.fold<int>(0, (a, r) => a + ((r[c] as num?)?.toInt() ?? 0)), columns[c].kind)
              : (c == 0 ? 'الإجمالي' : ''),
      ];

  /// UTF-8 with BOM so Excel shows Arabic correctly.
  String toCsv() {
    String esc(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
    final b = StringBuffer();
    b.writeln(columns.map((c) => esc(c.title)).join(','));
    for (var r = 0; r < rows.length; r++) {
      b.writeln([for (var c = 0; c < columns.length; c++) esc(cell(r, c))].join(','));
    }
    return b.toString();
  }

  Future<File> writeCsv() async {
    final dir = await getTemporaryDirectory();
    final safe = title.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
    final ts = DateFormat('yyyyMMdd_HHmm', 'en').format(DateTime.now());
    final f = File(p.join(dir.path, '${safe}_$ts.csv'));
    await f.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv())]);
    return f;
  }
}

class ReportDef {
  final String id;
  final String group;
  final String title;
  final bool usesDates;
  final Future<ReportTable> Function(ReportsService s, DateTime from, DateTime to) build;
  const ReportDef(this.id, this.group, this.title, this.usesDates, this.build);
}

class DashboardMetrics {
  final int activeProducts;
  final int totalUnits;
  final int inventoryValue;
  final int lowStock;
  final int outOfStock;
  final int todaySales;
  final int periodSales;
  final int wholesaleSales;
  final int retailSales;
  final int receivables;
  final int pendingPos;
  DashboardMetrics({
    required this.activeProducts,
    required this.totalUnits,
    required this.inventoryValue,
    required this.lowStock,
    required this.outOfStock,
    required this.todaySales,
    required this.periodSales,
    required this.wholesaleSales,
    required this.retailSales,
    required this.receivables,
    required this.pendingPos,
  });
}

class ReportsService {
  ReportsService(this.db);
  final AppDatabase db;

  Future<List<QueryRow>> _q(String sql, [List<Object> args = const []]) => db.customSelect(sql, variables: [
        for (final a in args)
          if (a is int)
            Variable.withInt(a)
          else if (a is DateTime)
            Variable.withDateTime(a)
          else
            Variable.withString('$a')
      ]).get();

  Future<int> _int(String sql, [List<Object> args = const []]) async {
    final r = await _q(sql, args);
    final v = r.first.data.values.first;
    return v == null ? 0 : (v as num).round();
  }

  static const _netSalesSql = '''
    COALESCE((SELECT SUM(grand_total) FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ?),0)
  - COALESCE((SELECT SUM(r.return_total) FROM sales_returns r WHERE r.return_date >= ? AND r.return_date < ?),0)
  ''';

  Future<DashboardMetrics> dashboard(DateTime from, DateTime to) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return DashboardMetrics(
      activeProducts: await _int('SELECT COUNT(*) FROM products WHERE is_active = 1'),
      totalUnits: await _int('SELECT COALESCE(SUM(quantity_on_hand),0) FROM stock_balances WHERE quantity_on_hand > 0'),
      inventoryValue: await _int(
          'SELECT COALESCE(SUM(quantity_on_hand * avg_cost / 1000.0),0) FROM stock_balances WHERE quantity_on_hand > 0'),
      lowStock: await _int('''SELECT COUNT(*) FROM products p JOIN stock_balances b ON b.product_id = p.id
          WHERE p.is_active = 1 AND b.quantity_on_hand > 0 AND p.minimum_stock > 0 AND b.quantity_on_hand < p.minimum_stock'''),
      outOfStock: await _int('''SELECT COUNT(*) FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id
          WHERE p.is_active = 1 AND COALESCE(b.quantity_on_hand,0) <= 0'''),
      todaySales: await _int('SELECT $_netSalesSql', [today, tomorrow, today, tomorrow]),
      periodSales: await _int('SELECT $_netSalesSql', [from, to, from, to]),
      wholesaleSales: await _int(
          "SELECT COALESCE(SUM(grand_total),0) FROM sales WHERE status='posted' AND pricing_mode='wholesale' AND invoice_date >= ? AND invoice_date < ?",
          [from, to]),
      retailSales: await _int(
          "SELECT COALESCE(SUM(grand_total),0) FROM sales WHERE status='posted' AND pricing_mode='retail' AND invoice_date >= ? AND invoice_date < ?",
          [from, to]),
      receivables: await _int('SELECT COALESCE(SUM(CASE WHEN o > 0 THEN o ELSE 0 END),0) FROM ($_outstandingSql)'),
      pendingPos: await _int("SELECT COUNT(*) FROM purchase_orders WHERE status IN ('ordered','partial')"),
    );
  }

  static const _outstandingSql = '''
    SELECT s.id, s.invoice_number, s.invoice_date, s.customer_id, s.grand_total,
      COALESCE((SELECT SUM(amount) FROM sale_payments x WHERE x.sale_id = s.id),0) AS paid,
      s.grand_total - COALESCE((SELECT SUM(return_total) FROM sales_returns r WHERE r.sale_id = s.id),0)
        + COALESCE((SELECT SUM(refund_amount) FROM sales_returns r WHERE r.sale_id = s.id),0)
        - COALESCE((SELECT SUM(amount) FROM sale_payments x WHERE x.sale_id = s.id),0) AS o
    FROM sales s WHERE s.status = 'posted'
  ''';

  Future<ReportTable> _table(String title, List<ReportColumn> cols, String sql,
      [List<Object> args = const [], String? note]) async {
    final rows = await _q(sql, args);
    return ReportTable(title, cols, [for (final r in rows) r.data.values.toList()], note: note);
  }

  // ------------------------------------------------------------------ catalog
  static final List<ReportDef> all = [
    // Inventory
    ReportDef('stock', 'المخزون', 'المخزون الحالي حسب المنتج', false, (s, f, t) => s._table(
        'المخزون الحالي',
        const [ReportColumn('الكود'), ReportColumn('المنتج'), ReportColumn('T.C'), ReportColumn('الكمية', ColKind.qty),
          ReportColumn('متوسط التكلفة', ColKind.money), ReportColumn('القيمة', ColKind.money)],
        '''SELECT p.internal_sku, p.name_ar, p.tc_code, COALESCE(b.quantity_on_hand,0), COALESCE(b.avg_cost,0),
             CAST(ROUND(COALESCE(b.quantity_on_hand,0) * COALESCE(b.avg_cost,0) / 1000.0) AS INTEGER)
           FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 ORDER BY p.name_ar''')),
    ReportDef('stock_type', 'المخزون', 'المخزون حسب نوع المنتج', false, (s, f, t) => s._table(
        'المخزون حسب النوع',
        const [ReportColumn('النوع'), ReportColumn('عدد المنتجات', ColKind.number), ReportColumn('الكمية', ColKind.qty), ReportColumn('القيمة', ColKind.money)],
        '''SELECT pt.name_ar, COUNT(p.id), COALESCE(SUM(b.quantity_on_hand),0),
             CAST(ROUND(COALESCE(SUM(b.quantity_on_hand * b.avg_cost / 1000.0),0)) AS INTEGER)
           FROM product_types pt LEFT JOIN products p ON p.product_type_id = pt.id AND p.is_active = 1
           LEFT JOIN stock_balances b ON b.product_id = p.id GROUP BY pt.id ORDER BY pt.name_ar''')),
    ReportDef('stock_brand', 'المخزون', 'المخزون حسب الماركة', false, (s, f, t) => s._table(
        'المخزون حسب الماركة',
        const [ReportColumn('الماركة'), ReportColumn('عدد المنتجات', ColKind.number), ReportColumn('الكمية', ColKind.qty), ReportColumn('القيمة', ColKind.money)],
        '''SELECT COALESCE(br.name_ar,'بدون ماركة'), COUNT(p.id), COALESCE(SUM(b.quantity_on_hand),0),
             CAST(ROUND(COALESCE(SUM(b.quantity_on_hand * b.avg_cost / 1000.0),0)) AS INTEGER)
           FROM products p LEFT JOIN brands br ON br.id = p.brand_id LEFT JOIN stock_balances b ON b.product_id = p.id
           WHERE p.is_active = 1 GROUP BY p.brand_id ORDER BY 1''')),
    ReportDef('stock_tag', 'المخزون', 'المخزون حسب الوسم', false, (s, f, t) => s._table(
        'المخزون حسب الوسم',
        const [ReportColumn('الوسم'), ReportColumn('عدد المنتجات', ColKind.number), ReportColumn('الكمية', ColKind.qty)],
        '''SELECT tg.name, COUNT(p.id), COALESCE(SUM(b.quantity_on_hand),0)
           FROM tags tg JOIN product_tags x ON x.tag_id = tg.id JOIN products p ON p.id = x.product_id AND p.is_active = 1
           LEFT JOIN stock_balances b ON b.product_id = p.id GROUP BY tg.id ORDER BY tg.name''',
        const [], 'المنتج الذي يحمل أكثر من وسم يظهر تحت كل وسم.')),
    ReportDef('stock_vehicle', 'المخزون', 'المخزون حسب السيارة', false, (s, f, t) => s._table(
        'المخزون حسب السيارة',
        const [ReportColumn('الماركة'), ReportColumn('الموديل'), ReportColumn('عدد المنتجات', ColKind.number), ReportColumn('الكمية', ColKind.qty)],
        '''SELECT mk.name_ar, m.name_ar, COUNT(DISTINCT p.id), COALESCE(SUM(b.quantity_on_hand),0)
           FROM vehicle_compatibilities vc JOIN vehicle_models m ON m.id = vc.vehicle_model_id JOIN vehicle_makes mk ON mk.id = m.make_id
           JOIN products p ON p.id = vc.product_id AND p.is_active = 1 LEFT JOIN stock_balances b ON b.product_id = p.id
           GROUP BY m.id ORDER BY mk.name_ar, m.name_ar''')),
    ReportDef('low', 'المخزون', 'منتجات منخفضة المخزون', false, (s, f, t) => s._table(
        'منخفض المخزون',
        const [ReportColumn('الكود'), ReportColumn('المنتج'), ReportColumn('المتاح', ColKind.qty), ReportColumn('الحد الأدنى', ColKind.qty),
          ReportColumn('كمية مقترحة للطلب', ColKind.qty)],
        '''SELECT p.internal_sku, p.name_ar, b.quantity_on_hand, p.minimum_stock,
             COALESCE(p.maximum_stock, p.minimum_stock * 2) - b.quantity_on_hand
           FROM products p JOIN stock_balances b ON b.product_id = p.id
           WHERE p.is_active = 1 AND b.quantity_on_hand > 0 AND p.minimum_stock > 0 AND b.quantity_on_hand < p.minimum_stock
           ORDER BY p.name_ar''',
        const [], 'الكمية المقترحة = الحد الأقصى (أو ضعف الحد الأدنى إن لم يُحدد) − المتاح.')),
    ReportDef('out', 'المخزون', 'منتجات نفدت', false, (s, f, t) => s._table(
        'نفد من المخزون',
        const [ReportColumn('الكود'), ReportColumn('المنتج'), ReportColumn('T.C'), ReportColumn('الحد الأدنى', ColKind.qty)],
        '''SELECT p.internal_sku, p.name_ar, p.tc_code, p.minimum_stock FROM products p
           LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active = 1 AND COALESCE(b.quantity_on_hand,0) <= 0
           ORDER BY p.name_ar''')),
    ReportDef('movements', 'المخزون', 'حركة المخزون', true, (s, f, t) => s._q('''
        SELECT m.occurred_at, p.name_ar, m.movement_type, m.quantity_delta, m.balance_after, m.unit_cost, m.reason
        FROM stock_movements m JOIN products p ON p.id = m.product_id
        WHERE m.occurred_at >= ? AND m.occurred_at < ? ORDER BY m.id DESC LIMIT 5000''', [f, t]).then((rows) => ReportTable(
          'حركة المخزون',
          const [ReportColumn('التاريخ'), ReportColumn('المنتج'), ReportColumn('النوع'), ReportColumn('الكمية', ColKind.qty),
            ReportColumn('الرصيد بعد', ColKind.qty), ReportColumn('التكلفة', ColKind.money), ReportColumn('السبب')],
          [
            for (final r in rows)
              [r.read<DateTime>('occurred_at'), r.read<String>('name_ar'), MovementType.label(r.read<String>('movement_type')),
                r.read<int>('quantity_delta'), r.read<int>('balance_after'), r.readNullable<int>('unit_cost'), r.readNullable<String>('reason')]
          ],
        ))),
    ReportDef('adjustments', 'المخزون', 'تسويات وحركات يدوية', true, (s, f, t) => s._table(
        'التسويات والحركات اليدوية',
        const [ReportColumn('رقم المستند'), ReportColumn('النوع'), ReportColumn('المنتج'), ReportColumn('قبل', ColKind.qty),
          ReportColumn('الفرق', ColKind.qty), ReportColumn('بعد', ColKind.qty), ReportColumn('السبب')],
        '''SELECT a.adjustment_number, a.kind, p.name_ar, l.quantity_before, l.quantity_delta, l.quantity_after, a.reason
           FROM stock_adjustment_lines l JOIN stock_adjustments a ON a.id = l.adjustment_id JOIN products p ON p.id = l.product_id
           WHERE a.occurred_at >= ? AND a.occurred_at < ? ORDER BY a.id DESC''', [f, t])),
    ReportDef('count_diff', 'المخزون', 'فروق الجرد', true, (s, f, t) => s._table(
        'فروق الجرد',
        const [ReportColumn('رقم الجرد'), ReportColumn('المنتج'), ReportColumn('المتوقع', ColKind.qty), ReportColumn('الفعلي', ColKind.qty),
          ReportColumn('الفرق', ColKind.qty)],
        '''SELECT c.count_number, p.name_ar, l.expected_quantity, l.counted_quantity, l.counted_quantity - l.expected_quantity
           FROM stock_count_lines l JOIN stock_counts c ON c.id = l.stock_count_id JOIN products p ON p.id = l.product_id
           WHERE c.status = 'posted' AND l.counted_quantity IS NOT NULL AND l.counted_quantity <> l.expected_quantity
             AND c.started_at >= ? AND c.started_at < ? ORDER BY c.id DESC''', [f, t])),
    // Sales
    ReportDef('sales_day', 'المبيعات', 'المبيعات اليومية', true, (s, f, t) => s._table(
        'المبيعات حسب اليوم',
        const [ReportColumn('اليوم'), ReportColumn('عدد الفواتير', ColKind.number), ReportColumn('المبيعات', ColKind.money),
          ReportColumn('الخصومات', ColKind.money), ReportColumn('تكلفة البضاعة', ColKind.money), ReportColumn('مجمل الربح', ColKind.money)],
        '''SELECT date(invoice_date, 'unixepoch', 'localtime') AS d, COUNT(*), SUM(grand_total), SUM(discount_total), SUM(cogs_total),
             SUM(grand_total) - SUM(cogs_total)
           FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ? GROUP BY d ORDER BY d DESC''', [f, t],
        'قبل خصم المرتجعات — راجع تقرير مجمل الربح للصافي.')),
    ReportDef('sales_month', 'المبيعات', 'المبيعات الشهرية', true, (s, f, t) => s._table(
        'المبيعات حسب الشهر',
        const [ReportColumn('الشهر'), ReportColumn('عدد الفواتير', ColKind.number), ReportColumn('المبيعات', ColKind.money),
          ReportColumn('تكلفة البضاعة', ColKind.money), ReportColumn('مجمل الربح', ColKind.money)],
        '''SELECT strftime('%Y-%m', invoice_date, 'unixepoch', 'localtime') AS m, COUNT(*), SUM(grand_total), SUM(cogs_total),
             SUM(grand_total) - SUM(cogs_total)
           FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ? GROUP BY m ORDER BY m DESC''', [f, t])),
    ReportDef('sales_customer', 'المبيعات', 'المبيعات حسب العميل', true, (s, f, t) => s._table(
        'المبيعات حسب العميل',
        const [ReportColumn('العميل'), ReportColumn('النوع'), ReportColumn('عدد الفواتير', ColKind.number), ReportColumn('المبيعات', ColKind.money)],
        '''SELECT COALESCE(c.name, 'عميل نقدي'), CASE c.customer_type WHEN 'wholesale' THEN 'جملة' ELSE 'قطاعي' END,
             COUNT(*), SUM(s.grand_total)
           FROM sales s LEFT JOIN customers c ON c.id = s.customer_id
           WHERE s.status='posted' AND s.invoice_date >= ? AND s.invoice_date < ? GROUP BY s.customer_id ORDER BY 4 DESC''', [f, t])),
    ReportDef('sales_product', 'المبيعات', 'المبيعات حسب المنتج', true, (s, f, t) => s._table(
        'المبيعات حسب المنتج',
        const [ReportColumn('الكود'), ReportColumn('المنتج'), ReportColumn('الكمية', ColKind.qty), ReportColumn('الإيراد', ColKind.money),
          ReportColumn('التكلفة', ColKind.money), ReportColumn('مجمل الربح', ColKind.money)],
        '''SELECT p.internal_sku, p.name_ar, SUM(l.quantity), SUM(l.line_total),
             CAST(ROUND(SUM(l.unit_cost_at_sale * l.quantity / 1000.0)) AS INTEGER),
             SUM(l.line_total) - CAST(ROUND(SUM(l.unit_cost_at_sale * l.quantity / 1000.0)) AS INTEGER)
           FROM sale_lines l JOIN sales s ON s.id = l.sale_id JOIN products p ON p.id = l.product_id
           WHERE s.status='posted' AND s.invoice_date >= ? AND s.invoice_date < ? GROUP BY p.id ORDER BY 4 DESC''', [f, t],
        'الإيراد قبل خصم الفاتورة العام والمرتجعات.')),
    ReportDef('sales_type', 'المبيعات', 'المبيعات حسب نوع المنتج', true, (s, f, t) => s._table(
        'المبيعات حسب النوع',
        const [ReportColumn('النوع'), ReportColumn('الكمية', ColKind.qty), ReportColumn('الإيراد', ColKind.money)],
        '''SELECT pt.name_ar, SUM(l.quantity), SUM(l.line_total)
           FROM sale_lines l JOIN sales s ON s.id = l.sale_id JOIN products p ON p.id = l.product_id JOIN product_types pt ON pt.id = p.product_type_id
           WHERE s.status='posted' AND s.invoice_date >= ? AND s.invoice_date < ? GROUP BY pt.id ORDER BY 3 DESC''', [f, t])),
    ReportDef('sales_mode', 'المبيعات', 'مبيعات الجملة والقطاعي', true, (s, f, t) => s._table(
        'الجملة / القطاعي',
        const [ReportColumn('نوع التسعير'), ReportColumn('عدد الفواتير', ColKind.number), ReportColumn('المبيعات', ColKind.money)],
        '''SELECT CASE pricing_mode WHEN 'wholesale' THEN 'جملة' ELSE 'قطاعي' END, COUNT(*), SUM(grand_total)
           FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ? GROUP BY pricing_mode''', [f, t])),
    ReportDef('sales_paystatus', 'المبيعات', 'المبيعات حسب حالة الدفع', true, (s, f, t) => s._table(
        'حالة الدفع',
        const [ReportColumn('الحالة'), ReportColumn('عدد الفواتير', ColKind.number), ReportColumn('الإجمالي', ColKind.money), ReportColumn('المتبقي', ColKind.money)],
        '''SELECT CASE WHEN o <= 0 THEN 'مدفوعة' WHEN paid > 0 THEN 'مدفوعة جزئيًا' ELSE 'غير مدفوعة' END AS st,
             COUNT(*), SUM(grand_total), SUM(CASE WHEN o > 0 THEN o ELSE 0 END)
           FROM ($_outstandingSql) WHERE invoice_date >= ? AND invoice_date < ? GROUP BY st''', [f, t])),
    ReportDef('returns', 'المبيعات', 'مرتجعات المبيعات', true, (s, f, t) => s._table(
        'مرتجعات المبيعات',
        const [ReportColumn('رقم المرتجع'), ReportColumn('الفاتورة'), ReportColumn('التاريخ'), ReportColumn('القيمة', ColKind.money),
          ReportColumn('مسترد نقدًا', ColKind.money)],
        '''SELECT r.return_number, s.invoice_number, date(r.return_date,'unixepoch','localtime'), r.return_total, r.refund_amount
           FROM sales_returns r JOIN sales s ON s.id = r.sale_id WHERE r.return_date >= ? AND r.return_date < ? ORDER BY r.id DESC''', [f, t])),
    ReportDef('discounts', 'المبيعات', 'الخصومات', true, (s, f, t) => s._table(
        'الخصومات',
        const [ReportColumn('الفاتورة'), ReportColumn('التاريخ'), ReportColumn('الإجمالي قبل الخصم', ColKind.money), ReportColumn('الخصم', ColKind.money)],
        '''SELECT invoice_number, date(invoice_date,'unixepoch','localtime'), subtotal, discount_total FROM sales
           WHERE status='posted' AND discount_total > 0 AND invoice_date >= ? AND invoice_date < ? ORDER BY id DESC''', [f, t])),
    ReportDef('gross_profit', 'المالية', 'مجمل الربح', true, (s, f, t) => s.grossProfit(f, t)),
    // Purchasing
    ReportDef('pur_supplier', 'المشتريات', 'المشتريات حسب المورد', true, (s, f, t) => s._table(
        'المشتريات حسب المورد',
        const [ReportColumn('المورد'), ReportColumn('عدد الاستلامات', ColKind.number), ReportColumn('القيمة', ColKind.money)],
        '''SELECT sp.name, COUNT(*), SUM(g.total) FROM goods_receipts g JOIN suppliers sp ON sp.id = g.supplier_id
           WHERE g.status='posted' AND g.received_at >= ? AND g.received_at < ? GROUP BY sp.id ORDER BY 3 DESC''', [f, t])),
    ReportDef('pur_date', 'المشتريات', 'المشتريات حسب التاريخ', true, (s, f, t) => s._table(
        'المشتريات حسب التاريخ',
        const [ReportColumn('رقم الاستلام'), ReportColumn('التاريخ'), ReportColumn('المورد'), ReportColumn('القيمة', ColKind.money)],
        '''SELECT g.receipt_number, date(g.received_at,'unixepoch','localtime'), sp.name, g.total FROM goods_receipts g
           JOIN suppliers sp ON sp.id = g.supplier_id WHERE g.status='posted' AND g.received_at >= ? AND g.received_at < ?
           ORDER BY g.id DESC''', [f, t])),
    ReportDef('pur_cost', 'المشتريات', 'سجل تكلفة الشراء', true, (s, f, t) => s._table(
        'سجل تكلفة الشراء',
        const [ReportColumn('المنتج'), ReportColumn('المورد'), ReportColumn('التاريخ'), ReportColumn('الكمية', ColKind.qty), ReportColumn('تكلفة الوحدة', ColKind.money)],
        '''SELECT p.name_ar, sp.name, date(g.received_at,'unixepoch','localtime'), l.received_quantity, l.unit_cost
           FROM goods_receipt_lines l JOIN goods_receipts g ON g.id = l.goods_receipt_id JOIN suppliers sp ON sp.id = g.supplier_id
           JOIN products p ON p.id = l.product_id WHERE g.received_at >= ? AND g.received_at < ? ORDER BY p.name_ar, g.received_at DESC''', [f, t])),
    ReportDef('pur_pending', 'المشتريات', 'أوامر شراء معلقة', false, (s, f, t) => s._table(
        'أوامر الشراء المعلقة',
        const [ReportColumn('رقم الأمر'), ReportColumn('المورد'), ReportColumn('الحالة'), ReportColumn('الإجمالي', ColKind.money)],
        '''SELECT o.order_number, sp.name, CASE o.status WHEN 'ordered' THEN 'تم الطلب' WHEN 'partial' THEN 'استلام جزئي' ELSE 'مسودة' END, o.grand_total
           FROM purchase_orders o JOIN suppliers sp ON sp.id = o.supplier_id WHERE o.status IN ('draft','ordered','partial') ORDER BY o.id DESC''')),
    ReportDef('pur_partial', 'المشتريات', 'الاستلامات الجزئية', false, (s, f, t) => s._table(
        'الاستلامات الجزئية',
        const [ReportColumn('رقم الأمر'), ReportColumn('المنتج'), ReportColumn('المطلوب', ColKind.qty), ReportColumn('المستلم', ColKind.qty),
          ReportColumn('المتبقي', ColKind.qty)],
        '''SELECT o.order_number, p.name_ar, l.ordered_quantity, l.received_quantity, l.ordered_quantity - l.received_quantity
           FROM purchase_order_lines l JOIN purchase_orders o ON o.id = l.purchase_order_id JOIN products p ON p.id = l.product_id
           WHERE o.status = 'partial' AND l.received_quantity < l.ordered_quantity ORDER BY o.id DESC''')),
    ReportDef('sup_returns', 'المشتريات', 'مرتجعات الموردين', true, (s, f, t) => s._table(
        'مرتجعات الموردين',
        const [ReportColumn('رقم المرتجع'), ReportColumn('المورد'), ReportColumn('التاريخ'), ReportColumn('القيمة', ColKind.money)],
        '''SELECT r.return_number, sp.name, date(r.return_date,'unixepoch','localtime'), r.total FROM supplier_returns r
           JOIN suppliers sp ON sp.id = r.supplier_id WHERE r.return_date >= ? AND r.return_date < ? ORDER BY r.id DESC''', [f, t])),
    // Finance
    ReportDef('balances', 'المالية', 'أرصدة العملاء المستحقة', false, (s, f, t) => s._table(
        'أرصدة العملاء',
        const [ReportColumn('العميل'), ReportColumn('عدد الفواتير المفتوحة', ColKind.number), ReportColumn('المستحق', ColKind.money)],
        '''SELECT COALESCE(c.name,'عميل نقدي'), SUM(CASE WHEN o > 0 THEN 1 ELSE 0 END), SUM(o)
           FROM ($_outstandingSql) x LEFT JOIN customers c ON c.id = x.customer_id GROUP BY x.customer_id HAVING SUM(o) <> 0 ORDER BY 3 DESC''',
        const [], 'القيمة السالبة تعني رصيدًا دائنًا للعميل.')),
    ReportDef('payments', 'المالية', 'المدفوعات المستلمة', true, (s, f, t) => s._table(
        'المدفوعات المستلمة',
        const [ReportColumn('التاريخ'), ReportColumn('الفاتورة'), ReportColumn('العميل'), ReportColumn('الطريقة'), ReportColumn('المبلغ', ColKind.money)],
        '''SELECT date(p.payment_date,'unixepoch','localtime'), s.invoice_number, COALESCE(c.name,'عميل نقدي'),
             CASE p.payment_method WHEN 'cash' THEN 'نقدي' WHEN 'bank' THEN 'تحويل بنكي' ELSE 'أخرى' END, p.amount
           FROM sale_payments p JOIN sales s ON s.id = p.sale_id LEFT JOIN customers c ON c.id = s.customer_id
           WHERE p.payment_date >= ? AND p.payment_date < ? ORDER BY p.id DESC''', [f, t],
        'هذا هو النقد المحصّل فعليًا، وهو يختلف عن إيراد المبيعات.')),
    ReportDef('unpaid', 'المالية', 'فواتير غير مدفوعة', false, (s, f, t) => s._table(
        'الفواتير غير المدفوعة',
        const [ReportColumn('الفاتورة'), ReportColumn('التاريخ'), ReportColumn('العميل'), ReportColumn('المتبقي', ColKind.money)],
        '''SELECT x.invoice_number, date(x.invoice_date,'unixepoch','localtime'), COALESCE(c.name,'عميل نقدي'), x.o
           FROM ($_outstandingSql) x LEFT JOIN customers c ON c.id = x.customer_id WHERE x.o > 0 AND x.paid = 0 ORDER BY x.invoice_date''')),
    ReportDef('partial_paid', 'المالية', 'فواتير مدفوعة جزئيًا', false, (s, f, t) => s._table(
        'الفواتير المدفوعة جزئيًا',
        const [ReportColumn('الفاتورة'), ReportColumn('العميل'), ReportColumn('الإجمالي', ColKind.money), ReportColumn('المدفوع', ColKind.money),
          ReportColumn('المتبقي', ColKind.money)],
        '''SELECT x.invoice_number, COALESCE(c.name,'عميل نقدي'), x.grand_total, x.paid, x.o
           FROM ($_outstandingSql) x LEFT JOIN customers c ON c.id = x.customer_id WHERE x.o > 0 AND x.paid > 0 ORDER BY x.invoice_date''')),
  ];

  Future<ReportTable> grossProfit(DateTime f, DateTime t) async {
    final sales = await _int("SELECT COALESCE(SUM(grand_total),0) FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ?", [f, t]);
    final cogs = await _int("SELECT COALESCE(SUM(cogs_total),0) FROM sales WHERE status='posted' AND invoice_date >= ? AND invoice_date < ?", [f, t]);
    final ret = await _int('SELECT COALESCE(SUM(return_total),0) FROM sales_returns WHERE return_date >= ? AND return_date < ?', [f, t]);
    final retCost = await _int('SELECT COALESCE(SUM(cost_total),0) FROM sales_returns WHERE return_date >= ? AND return_date < ?', [f, t]);
    final cash = await _int('SELECT COALESCE(SUM(amount),0) FROM sale_payments WHERE payment_date >= ? AND payment_date < ?', [f, t]);
    final netRev = sales - ret;
    final netCogs = cogs - retCost;
    return ReportTable('مجمل الربح', const [ReportColumn('البند'), ReportColumn('المبلغ', ColKind.money)], [
      ['إجمالي المبيعات المرحّلة', sales],
      ['(−) مرتجعات المبيعات', -ret],
      ['= صافي إيراد المبيعات', netRev],
      ['تكلفة البضاعة المباعة', netCogs],
      ['= مجمل الربح', netRev - netCogs],
      ['للمقارنة: النقد المحصّل في الفترة', cash],
    ], note: 'مجمل الربح = صافي الإيراد − تكلفة البضاعة (متوسط مرجح متحرك). لا يُحسب صافي الربح لأن المصروفات غير مسجلة. '
        'تكلفة الأصناف المرتجعة التالفة تبقى ضمن التكلفة كخسارة.');
  }
}

final reportsServiceProvider = Provider<ReportsService>((ref) => ReportsService(ref.watch(databaseProvider)));
