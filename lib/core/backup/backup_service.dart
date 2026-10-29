import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqlite3/sqlite3.dart' as s3;

import '../database/app_database.dart';
import '../database/providers.dart';
import '../errors/business_exception.dart';

class BackupInfo {
  final File file;
  final DateTime modified;
  final int bytes;
  BackupInfo(this.file, this.modified, this.bytes);
  String get name => p.basename(file.path);
}

class BackupValidation {
  final int schemaVersion;
  final int products;
  final int sales;
  BackupValidation(this.schemaVersion, this.products, this.sales);
}

/// Full-database backups.
///
/// Format: a complete SQLite snapshot made with `VACUUM INTO` (consistent even
/// while the app is running). The schema version is SQLite's `user_version`;
/// the file name also carries it. Restore policy: FULL REPLACEMENT of all local
/// data, after validation, confirmation and an automatic safety backup.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static const formatVersion = 1;
  static const _requiredTables = ['products', 'stock_movements', 'stock_balances', 'sales', 'app_settings'];
  static const restoreMarker = 'restore_pending';

  Future<Directory> backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<BackupInfo> createBackup({String label = 'backup'}) async {
    final dir = await backupDir();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final target = p.join(dir.path, '${label}_v${formatVersion}_s${_db.schemaVersion}_$ts.sqlite');
    final tmpFile = File('$target.part');
    if (await tmpFile.exists()) await tmpFile.delete();
    await _db.customStatement('VACUUM INTO ?', [tmpFile.path]);
    // Rename only after completion: an interrupted backup never looks valid.
    final done = await tmpFile.rename(target);
    await _db.logActivity('backup', 'database', 'إنشاء نسخة احتياطية ${p.basename(target)}');
    final st = await done.stat();
    return BackupInfo(done, st.modified, st.size);
  }

  Future<List<BackupInfo>> listBackups() async {
    final dir = await backupDir();
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.sqlite')).cast<File>().toList();
    final infos = <BackupInfo>[];
    for (final f in files) {
      final s = await f.stat();
      infos.add(BackupInfo(f, s.modified, s.size));
    }
    infos.sort((a, b) => b.modified.compareTo(a.modified));
    return infos;
  }

  /// Opens the system share sheet so the user can save the file to Drive,
  /// Files, USB, WhatsApp, etc.
  Future<void> export(BackupInfo b) async {
    await Share.shareXFiles([XFile(b.file.path)], subject: 'نسخة احتياطية - ${b.name}');
  }

  Future<void> deleteBackup(BackupInfo b) => b.file.delete();

  /// Validates a candidate backup file without touching live data.
  Future<BackupValidation> validate(File f) async {
    final raf = await f.open();
    final header = await raf.read(16);
    await raf.close();
    if (String.fromCharCodes(header.take(15)) != 'SQLite format 3') {
      throw const BusinessException('الملف ليس نسخة احتياطية صالحة');
    }
    final d = s3.sqlite3.open(f.path, mode: s3.OpenMode.readOnly);
    try {
      final ic = d.select('PRAGMA integrity_check').first.values.first.toString();
      if (ic != 'ok') throw BusinessException('النسخة الاحتياطية تالفة: $ic');
      final ver = d.select('PRAGMA user_version').first.values.first as int;
      if (ver > _db.schemaVersion) {
        throw const BusinessException('هذه النسخة من إصدار أحدث من التطبيق — حدّث التطبيق أولًا');
      }
      if (ver < 1) throw const BusinessException('النسخة لا تحتوي على رقم إصدار صالح');
      final tables = d.select("SELECT name FROM sqlite_master WHERE type='table'").map((r) => r['name'] as String).toSet();
      for (final t in _requiredTables) {
        if (!tables.contains(t)) throw BusinessException('النسخة ناقصة (الجدول $t غير موجود)');
      }
      final products = d.select('SELECT COUNT(*) AS c FROM products').first['c'] as int;
      final sales = d.select('SELECT COUNT(*) AS c FROM sales').first['c'] as int;
      return BackupValidation(ver, products, sales);
    } finally {
      d.dispose();
    }
  }

  /// Replaces ALL local data with [source]. Caller must have confirmed with
  /// the user. A safety backup of the current data is taken first. The app
  /// must restart afterwards (balances are re-verified on next launch).
  Future<BackupInfo> restore(File source) async {
    await validate(source);
    final safety = await createBackup(label: 'before_restore');
    final staged = File('${source.path}.staged');
    await source.copy(staged.path);
    await _db.close();
    final live = await databaseFile();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('${live.path}$suffix');
      if (await f.exists()) await f.delete();
    }
    await staged.copy(live.path);
    await staged.delete();
    final docs = await getApplicationDocumentsDirectory();
    await File(p.join(docs.path, restoreMarker)).writeAsString(DateTime.now().toIso8601String());
    return safety;
  }

  /// Called at startup: if a restore just happened, report it (and delete the marker).
  static Future<bool> consumeRestoreMarker() async {
    final docs = await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, restoreMarker));
    if (await f.exists()) {
      await f.delete();
      return true;
    }
    return false;
  }
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));
