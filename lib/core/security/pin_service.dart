import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_repository.dart';

/// Optional app PIN. Stored as salted, iterated SHA-256 — never plaintext.
/// Limitation: local-only protection; anyone with a rooted device and the
/// database file could bypass it. Keep regular backups off the device.
class PinService {
  PinService(this.settings);
  final SettingsRepository settings;

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';

  Future<bool> isEnabled() async => (await settings.get(_hashKey))?.isNotEmpty ?? false;

  static String hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) throw ArgumentError('الرقم السري من 4 إلى 8 أرقام');
    final rnd = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await settings.set(_saltKey, salt);
    await settings.set(_hashKey, hash(pin, salt));
  }

  Future<void> disable() async {
    await settings.set(_hashKey, '');
    await settings.set(_saltKey, '');
  }

  Future<bool> verify(String pin) async {
    final h = await settings.get(_hashKey);
    final s = await settings.get(_saltKey);
    if (h == null || h.isEmpty || s == null) return true;
    return hash(pin, s) == h;
  }
}

final pinServiceProvider = Provider<PinService>((ref) => PinService(ref.watch(settingsRepositoryProvider)));
