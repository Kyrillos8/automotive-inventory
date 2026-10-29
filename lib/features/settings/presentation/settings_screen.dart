import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pin_service.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/presentation/stock_screens.dart';
import '../../products/presentation/pickers.dart';
import '../../products/product_providers.dart';
import '../../products/product_repository.dart';
import '../settings_repository.dart';

/// S21 — Settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _currency = TextEditingController();
  bool _loaded = false;
  bool? _pinOn;

  @override
  void initState() {
    super.initState();
    ref.read(pinServiceProvider).isEnabled().then((v) {
      if (mounted) setState(() => _pinOn = v);
    });
  }

  Future<void> _setPin() async {
    final a = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تعيين رقم سري'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'الرقم السري (4-8 أرقام)')),
          TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'تأكيد الرقم السري')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (a.text != b.text) {
      showSnack(context, 'الرقمان غير متطابقين', error: true);
      return;
    }
    try {
      await ref.read(pinServiceProvider).setPin(a.text);
      setState(() => _pinOn = true);
      if (mounted) showSnack(context, 'تم تفعيل قفل التطبيق');
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, '${e.message}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: s.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(settingsControllerProvider)),
        data: (v) {
          if (!_loaded) {
            _name.text = v.businessName;
            _currency.text = v.currency;
            _loaded = true;
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('بيانات النشاط'),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم النشاط التجاري')),
            const SizedBox(height: 12),
            TextField(controller: _currency, decoration: const InputDecoration(labelText: 'رمز العملة')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (_name.text.trim().isEmpty) {
                  showSnack(context, 'اسم النشاط مطلوب', error: true);
                  return;
                }
                await runAction(context, () => ref.read(settingsControllerProvider.notifier).updateBusiness(_name.text, _currency.text),
                    success: 'تم الحفظ');
                Fmt.currency = _currency.text.trim().isEmpty ? 'ج.م' : _currency.text.trim();
              },
              child: const Text('حفظ'),
            ),
            const SectionTitle('الأمان'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قفل التطبيق برقم سري'),
              subtitle: const Text('يُطلب عند فتح التطبيق'),
              value: _pinOn ?? false,
              onChanged: _pinOn == null
                  ? null
                  : (on) async {
                      if (on) {
                        await _setPin();
                      } else {
                        await ref.read(pinServiceProvider).disable();
                        setState(() => _pinOn = false);
                      }
                    },
            ),
            if (_pinOn == true) TextButton(onPressed: _setPin, child: const Text('تغيير الرقم السري')),
            const SectionTitle('المخزون'),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.block),
              title: Text('منع المخزون السالب'),
              subtitle: Text('مفعّل دائمًا لحماية دقة المخزون'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rule),
              title: const Text('مطابقة الأرصدة مع سجل الحركات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReconcileScreen())),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.manage_search),
              title: const Text('إعادة بناء فهرس البحث'),
              subtitle: const Text('استخدمه إذا لم يظهر منتج في البحث كما هو متوقع'),
              onTap: () async {
                await runAction(context, () => ref.read(productRepositoryProvider).rebuildAllSearchText(), success: 'تمت إعادة البناء');
                if (context.mounted) bumpCatalog(ref);
              },
            ),
            const SectionTitle('القوائم'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.category_outlined),
              title: const Text('أنواع المنتجات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _TypesScreen())),
            ),
            const SectionTitle('حول التطبيق'),
            const Text(
              'جميع البيانات محفوظة على هذا الجهاز فقط ولا تُرسل لأي خادم. فقدان الجهاز أو تلفه يعني فقدان البيانات '
              'ما لم تكن هناك نسخة احتياطية محفوظة خارجه — صدّر نسخة احتياطية بانتظام.',
              style: TextStyle(fontSize: 12),
            ),
          ]);
        },
      ),
    );
  }
}

class _TypesScreen extends ConsumerWidget {
  const _TypesScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(productTypesProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('أنواع المنتجات')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_type',
        onPressed: () => showAddTypeDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(children: [
        for (final t in types)
          ListTile(
            title: Text(t.nameAr),
            subtitle: Text(switch (t.kind) { 'ring' => 'مواصفات الشنابر', 'piston' => 'مواصفات البساتم', _ => 'مواصفات عامة' }),
          ),
      ]),
    );
  }
}
