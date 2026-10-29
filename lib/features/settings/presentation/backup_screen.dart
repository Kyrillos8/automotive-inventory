import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';

final backupListProvider = FutureProvider.autoDispose<List<BackupInfo>>(
  (ref) => ref.watch(backupServiceProvider).listBackups(),
);

/// S22 — Backup & restore.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    final b = await runAction(context, () => ref.read(backupServiceProvider).createBackup());
    ref.invalidate(backupListProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    if (b != null) {
      final share = await confirm(context, 'تم إنشاء النسخة',
          'النسخة محفوظة داخل التطبيق. لحمايتها من فقدان الجهاز، صدّرها الآن إلى Google Drive أو الكمبيوتر أو واتساب.',
          ok: 'تصدير الآن');
      if (share && mounted) await runAction(context, () => ref.read(backupServiceProvider).export(b));
    }
  }

  Future<void> _restore(File f) async {
    final svc = ref.read(backupServiceProvider);
    final v = await runAction(context, () => svc.validate(f));
    if (v == null || !mounted) return;
    final ok = await confirm(
      context,
      'استعادة نسخة احتياطية',
      'النسخة سليمة وتحتوي على ${v.products} منتج و${v.sales} فاتورة.\n\n'
          '⚠️ سيتم استبدال كل البيانات الحالية بالكامل بمحتوى هذه النسخة.\n'
          'سيتم أخذ نسخة أمان من بياناتك الحالية تلقائيًا قبل الاستعادة.',
      ok: 'استبدال البيانات',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final safety = await runAction(context, () => svc.restore(f));
    if (!mounted) return;
    setState(() => _busy = false);
    if (safety == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('تمت الاستعادة'),
        content: Text('يجب إعادة فتح التطبيق الآن لتحميل البيانات المستعادة.\nنسخة الأمان: ${safety.name}'),
        actions: [FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('إغلاق التطبيق'))],
      ),
    );
  }

  Future<void> _pickAndRestore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null || !mounted) return;
    await _restore(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(backupListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.backup),
                label: const Text('نسخة احتياطية الآن'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickAndRestore,
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('استعادة من ملف'),
              ),
            ),
          ]),
        ),
        if (_busy) const LinearProgressIndicator(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('النسخ أدناه محفوظة داخل الجهاز. صدّرها خارج الجهاز بانتظام.', style: TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(backupListProvider)),
            data: (items) => items.isEmpty
                ? const EmptyView(icon: Icons.backup_outlined, title: 'لا توجد نسخ احتياطية بعد')
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final b = items[i];
                      return ListTile(
                        leading: const Icon(Icons.storage),
                        title: Text(b.name, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                        subtitle: Text('${Fmt.dateTime(b.modified)} • ${(b.bytes / 1024).toStringAsFixed(1)} KB'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            final svc = ref.read(backupServiceProvider);
                            switch (v) {
                              case 'export':
                                await runAction(context, () => svc.export(b));
                              case 'restore':
                                await _restore(b.file);
                              case 'delete':
                                if (await confirm(context, 'حذف النسخة', 'حذف ${b.name}؟', destructive: true)) {
                                  await svc.deleteBackup(b);
                                  ref.invalidate(backupListProvider);
                                }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'export', child: Text('تصدير / مشاركة')),
                            PopupMenuItem(value: 'restore', child: Text('استعادة هذه النسخة')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
