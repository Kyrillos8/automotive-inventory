import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../catalog_import_service.dart';
import '../product_providers.dart';
import 'product_search_view.dart';

/// Imports a catalog file (prepared from the owner's price books) into the
/// product list. Existing products are never changed; re-importing skips them.
class CatalogImportScreen extends ConsumerStatefulWidget {
  const CatalogImportScreen({super.key});
  @override
  ConsumerState<CatalogImportScreen> createState() => _CatalogImportScreenState();
}

class _CatalogImportScreenState extends ConsumerState<CatalogImportScreen> {
  CatalogPreview? _preview;
  String? _fileName;
  bool _busy = false;
  CatalogImportResult? _result;

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null || !mounted) return;
    setState(() => _busy = true);
    final preview = await runAction(context, () async {
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      return ref.read(catalogImportServiceProvider).preview(utf8.decode(bytes));
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _preview = preview;
      _fileName = f.name;
      _result = null;
    });
  }

  Future<void> _import() async {
    final p = _preview!;
    final ok = await confirm(
      context,
      'استيراد الكتالوج',
      'سيتم إضافة ${p.items.length - p.alreadyExisting} منتج جديد.\n'
          '${p.alreadyExisting > 0 ? 'سيتم تخطي ${p.alreadyExisting} منتج موجود مسبقًا (بدون تعديل).\n' : ''}'
          'لن تتغير أي كميات في المخزون.',
      ok: 'استيراد',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await runAction(context, () => ref.read(catalogImportServiceProvider).import(p));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r;
      if (r != null) _preview = null;
    });
    if (r != null) bumpCatalog(ref);
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد كتالوج')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'اختر ملف الكتالوج (catalog_import.json). المنتجات الموجودة لن تتغير، '
          'والمنتجات غير المؤكدة ستظهر في قائمة "تحتاج مراجعة" (أيقونة الجرس).',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.file_open),
          label: const Text('اختيار ملف'),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (p != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                InfoRow('الملف', _fileName),
                InfoRow('شنابر', '${p.rings}'),
                InfoRow('بساتم', '${p.pistons}'),
                InfoRow('تحتاج مراجعة', '${p.flagged}'),
                InfoRow('موجود مسبقًا (سيتم تخطيه)', '${p.alreadyExisting}'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || p.items.length == p.alreadyExisting ? null : _import,
            icon: const Icon(Icons.download_done),
            label: Text('استيراد ${p.items.length - p.alreadyExisting} منتج'),
          ),
        ],
        if (r != null) ...[
          const SizedBox(height: 16),
          EmptyView(
            icon: Icons.task_alt,
            title: 'تم استيراد ${r.created} منتج',
            message: '${r.skipped > 0 ? 'تم تخطي ${r.skipped} موجود مسبقًا. ' : ''}'
                '${r.flagged} منتج يحتاج مراجعة.',
            action: r.flagged > 0
                ? FilledButton.icon(
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('فتح قائمة المراجعة'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewInboxScreen())),
                  )
                : null,
          ),
        ],
      ]),
    );
  }
}
