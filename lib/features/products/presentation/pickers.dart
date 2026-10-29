import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/search_normalizer.dart';
import '../../../core/widgets/common.dart';
import '../product_providers.dart';
import '../product_repository.dart';

Future<int?> showAddTypeDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  var kind = 'other';
  final r = await showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('نوع منتج جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: kind,
            decoration: const InputDecoration(labelText: 'نموذج المواصفات'),
            items: const [
              DropdownMenuItem(value: 'ring', child: Text('مثل الشنابر')),
              DropdownMenuItem(value: 'piston', child: Text('مثل البساتم')),
              DropdownMenuItem(value: 'other', child: Text('عام')),
            ],
            onChanged: (v) => setS(() => kind = v ?? 'other'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final id = await runAction(c, () => ref.read(productRepositoryProvider).addProductType(name.text, null, kind));
              if (id != null && c.mounted) Navigator.pop(c, id);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
  return r;
}

Future<SpecInput?> showSpecDialog(BuildContext context) async {
  final k = TextEditingController();
  final v = TextEditingController();
  return showDialog<SpecInput>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('مواصفة إضافية'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: k, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المواصفة')),
        const SizedBox(height: 8),
        TextField(controller: v, decoration: const InputDecoration(labelText: 'القيمة')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (k.text.trim().isEmpty || v.text.trim().isEmpty) return;
            Navigator.pop(c, SpecInput(k.text.trim(), v.text.trim()));
          },
          child: const Text('إضافة'),
        ),
      ],
    ),
  );
}

/// Multi-select tag picker with inline creation.
Future<Set<int>?> showTagSelector(BuildContext context, WidgetRef ref, {required Set<int> selected}) {
  return Navigator.of(context).push<Set<int>>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TagSelector(selected: selected),
  ));
}

class _TagSelector extends ConsumerStatefulWidget {
  const _TagSelector({required this.selected});
  final Set<int> selected;
  @override
  ConsumerState<_TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends ConsumerState<_TagSelector> {
  late final Set<int> _sel = {...widget.selected};
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(activeTagsProvider).valueOrNull ?? [];
    final nq = normalizeForSearch(_q.text);
    final shown = tags.where((t) => nq.isEmpty || t.normalizedName.contains(nq)).toList();
    final exact = tags.any((t) => t.normalizedName == nq);
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار الوسوم'), actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _sel),
          child: Text('تم (${_sel.length})', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث أو اكتب وسمًا جديدًا'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (nq.isNotEmpty && !exact)
          ListTile(
            leading: const Icon(Icons.add_circle, color: Colors.green),
            title: Text('إنشاء الوسم "${_q.text.trim()}"'),
            onTap: () async {
              final t = await runAction(context, () => ref.read(productRepositoryProvider).createTag(_q.text));
              if (t != null) {
                setState(() {
                  _sel.add(t.id);
                  _q.clear();
                });
              }
            },
          ),
        Expanded(
          child: ListView(children: [
            for (final t in shown)
              CheckboxListTile(
                value: _sel.contains(t.id),
                title: Text(t.name),
                onChanged: (v) => setState(() => v == true ? _sel.add(t.id) : _sel.remove(t.id)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Vehicle compatibility entry, with inline creation of makes and models.
Future<CompatInput?> showCompatDialog(BuildContext context, WidgetRef ref) {
  return Navigator.of(context).push<CompatInput>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _CompatForm(),
  ));
}

class _CompatForm extends ConsumerStatefulWidget {
  const _CompatForm();
  @override
  ConsumerState<_CompatForm> createState() => _CompatFormState();
}

class _CompatFormState extends ConsumerState<_CompatForm> {
  int? makeId;
  int? modelId;
  final yearFrom = TextEditingController();
  final yearTo = TextEditingController();
  final capacity = TextEditingController();
  final engine = TextEditingController();
  final notes = TextEditingController();
  String status = 'confirmed';

  @override
  Widget build(BuildContext context) {
    final makes = ref.watch(makesProvider).valueOrNull ?? [];
    final List<VehicleModel> models = makeId == null ? const [] : (ref.watch(modelsProvider(makeId!)).valueOrNull ?? const []);
    final repo = ref.read(productRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ربط بسيارة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: makes.any((m) => m.id == makeId) ? makeId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ماركة السيارة *'),
              items: [for (final m in makes) DropdownMenuItem(value: m.id, child: Text(_name(m.nameAr, m.nameEn)))],
              onChanged: (v) => setState(() {
                makeId = v;
                modelId = null;
              }),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              final r = await _twoNames(context, 'ماركة جديدة');
              if (r == null || !context.mounted) return;
              final id = await runAction(context, () => repo.addMake(r.$1, r.$2));
              if (id != null) setState(() => makeId = id);
            },
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: models.any((m) => m.id == modelId) ? modelId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الموديل *'),
              items: [for (final m in models) DropdownMenuItem(value: m.id, child: Text(_name(m.nameAr, m.nameEn)))],
              onChanged: makeId == null ? null : (v) => setState(() => modelId = v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: makeId == null
                ? null
                : () async {
                    final r = await _twoNames(context, 'موديل جديد');
                    if (r == null || !context.mounted) return;
                    final id = await runAction(context, () => repo.addModel(makeId!, r.$1, r.$2));
                    if (id != null) setState(() => modelId = id);
                  },
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: yearFrom, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'من سنة'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: yearTo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إلى سنة'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: capacity, decoration: const InputDecoration(labelText: 'سعة المحرك'), textDirection: TextDirection.ltr)),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: engine, decoration: const InputDecoration(labelText: 'كود المحرك'), textDirection: TextDirection.ltr)),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'confirmed', label: Text('مؤكد'), icon: Icon(Icons.verified)),
            ButtonSegment(value: 'needs_verification', label: Text('يحتاج تحقق'), icon: Icon(Icons.help_outline)),
          ],
          selected: {status},
          onSelectionChanged: (s) => setState(() => status = s.first),
        ),
        const SizedBox(height: 10),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            if (makeId == null || modelId == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر الماركة والموديل')));
              return;
            }
            final mk = makes.firstWhere((m) => m.id == makeId);
            final md = models.firstWhere((m) => m.id == modelId);
            Navigator.pop(
              context,
              CompatInput(
                vehicleModelId: modelId!,
                label: '${mk.nameAr} ${md.nameAr}',
                yearFrom: int.tryParse(yearFrom.text.trim()),
                yearTo: int.tryParse(yearTo.text.trim()),
                engineCapacity: capacity.text.trim(),
                engineCode: engine.text.trim(),
                status: status,
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
              ),
            );
          },
          child: const Text('إضافة'),
        ),
      ]),
    );
  }
}

String _name(String ar, String? en) => (en == null || en.isEmpty) ? ar : '$ar ($en)';

Future<(String, String?)?> _twoNames(BuildContext context, String title) async {
  final ar = TextEditingController();
  final en = TextEditingController();
  return showDialog<(String, String?)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ar, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم بالعربية *')),
        const SizedBox(height: 8),
        TextField(controller: en, decoration: const InputDecoration(labelText: 'الاسم بالإنجليزية'), textDirection: TextDirection.ltr),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (ar.text.trim().isEmpty) return;
            Navigator.pop(c, (ar.text.trim(), en.text.trim().isEmpty ? null : en.text.trim()));
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

/// Public so the vehicles management screen can reuse it.
Future<(String, String?)?> askVehicleNames(BuildContext context, String title) => _twoNames(context, title);
