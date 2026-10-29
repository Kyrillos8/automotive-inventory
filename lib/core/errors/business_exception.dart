/// A rule violation that should be shown to the user (Arabic message).
class BusinessException implements Exception {
  final String message;
  const BusinessException(this.message);
  @override
  String toString() => message;
}
