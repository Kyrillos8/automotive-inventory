import 'money.dart';

/// Normalizes text for search keys only. Stored display values are never changed.
///
/// Rules:
/// - Arabic diacritics (tashkeel) and tatweel removed.
/// - أ إ آ ٱ -> ا ; ى -> ي ; ة -> ه ; ؤ -> و ; ئ -> ي.
/// - Arabic-Indic digits -> Western digits; Arabic decimal separator -> '.'.
/// - Lowercased; whitespace collapsed.
String normalizeForSearch(String input) {
  var s = normalizeDigits(input);
  s = s.replaceAll(RegExp('[ً-ٰٟۖ-ۭ]'), '');
  s = s.replaceAll('ـ', '');
  s = s
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('٫', '.')
      .replaceAll('،', ',');
  s = s.toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Splits a query into normalized terms.
List<String> searchTerms(String query) =>
    normalizeForSearch(query).split(' ').where((t) => t.isNotEmpty).toList();
