import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/settings_repository.dart';

/// S01 — Initial setup.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _currency = TextEditingController(text: 'ج.م');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsControllerProvider.notifier).completeSetup(_name.text, _currency.text);
      Fmt.currency = _currency.text.trim().isEmpty ? 'ج.م' : _currency.text.trim();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر حفظ الإعدادات: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعداد الأولي')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('مرحبًا! أدخل بيانات نشاطك التجاري للبدء.', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم النشاط التجاري *'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم النشاط مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _currency,
            decoration: const InputDecoration(labelText: 'رمز العملة', helperText: 'الافتراضي: جنيه مصري (ج.م)'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('حفظ والبدء'),
          ),
        ]),
      ),
    );
  }
}
