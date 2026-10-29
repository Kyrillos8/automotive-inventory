import 'package:intl/intl.dart';

/// Decimal-safe money: stored as integer minor units (piastres, 1 EGP = 100).
/// Never store formatted strings or doubles as authoritative values.
class Money implements Comparable<Money> {
  final int minor;
  const Money(this.minor);
  static const zero = Money(0);

  factory Money.fromMajor(num major) => Money((major * 100).round());

  /// Parses user input such as "300", "300.5", "٣٠٠٫٥٠", "1,250.75".
  static Money? tryParse(String input) {
    final s = normalizeDigits(input).replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (m == null) return null;
    final whole = int.parse(m.group(2)!);
    final frac = (m.group(3) ?? '').padRight(2, '0');
    final v = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
    return Money(m.group(1) == '-' ? -v : v);
  }

  Money operator +(Money o) => Money(minor + o.minor);
  Money operator -(Money o) => Money(minor - o.minor);
  Money operator -() => Money(-minor);

  /// Multiply by a quantity expressed in milli-units (see [Qty]); rounds half away from zero.
  Money timesQty(Qty q) {
    final p = minor * q.milli;
    final r = (p.abs() + 500) ~/ 1000;
    return Money(p < 0 ? -r : r);
  }

  bool get isNegative => minor < 0;
  double get asDouble => minor / 100.0;

  String format({String currency = 'ج.م'}) {
    final f = NumberFormat('#,##0.00', 'en');
    return '${f.format(minor / 100)} $currency';
  }

  /// Plain value for editing fields / CSV, e.g. "300.00".
  String toPlain() {
    final neg = minor < 0 ? '-' : '';
    final a = minor.abs();
    return '$neg${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);
  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;
  @override
  int get hashCode => minor.hashCode;
  @override
  String toString() => toPlain();
}

/// Quantity stored as integer milli-units (3 decimal places) to support
/// fractional units while staying exact.
class Qty implements Comparable<Qty> {
  final int milli;
  const Qty(this.milli);
  static const zero = Qty(0);
  factory Qty.units(num n) => Qty((n * 1000).round());

  static Qty? tryParse(String input) {
    final s = normalizeDigits(input).replaceAll('٫', '.').trim();
    final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,3}))?$').firstMatch(s);
    if (m == null) return null;
    final v = int.parse(m.group(2)!) * 1000 + int.parse((m.group(3) ?? '').padRight(3, '0'));
    return Qty(m.group(1) == '-' ? -v : v);
  }

  Qty operator +(Qty o) => Qty(milli + o.milli);
  Qty operator -(Qty o) => Qty(milli - o.milli);
  bool get isNegative => milli < 0;

  String toPlain() {
    final neg = milli < 0 ? '-' : '';
    final a = milli.abs();
    final frac = a % 1000;
    if (frac == 0) return '$neg${a ~/ 1000}';
    return '$neg${a ~/ 1000}.${frac.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '')}';
  }

  @override
  int compareTo(Qty other) => milli.compareTo(other.milli);
  @override
  bool operator ==(Object other) => other is Qty && other.milli == milli;
  @override
  int get hashCode => milli.hashCode;
  @override
  String toString() => toPlain();
}

const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
const _easternIndic = '۰۱۲۳۴۵۶۷۸۹';

/// Converts Arabic-Indic and Persian digits to Western digits.
String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    var i = _arabicIndic.indexOf(c);
    if (i < 0) i = _easternIndic.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}
