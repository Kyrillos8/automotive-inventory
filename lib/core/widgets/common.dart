import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../errors/business_exception.dart';
import '../utils/money.dart';
import 'state_views.dart';

/// Display formatting. Values are always stored as integers.
abstract final class Fmt {
  static String currency = 'ج.م';
  static String money(int minor) => Money(minor).format(currency: currency);
  static String qty(int milli) => Qty(milli).toPlain();
  static final _d = DateFormat('yyyy/MM/dd', 'en');
  static final _dt = DateFormat('yyyy/MM/dd HH:mm', 'en');
  static String date(DateTime d) => _d.format(d);
  static String dateTime(DateTime d) => _dt.format(d);
}

/// Runs [action], showing an Arabic error on failure. Returns null on failure.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } on BusinessException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, 'حدث خطأ غير متوقع: $e', error: true);
  }
  return null;
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'تأكيد', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title,
    {String initial = '', String label = '', bool required = true}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().isEmpty) return;
            Navigator.pop(c, ctrl.text.trim());
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  return r;
}

final _numFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.٫,]'));

class MoneyField extends StatelessWidget {
  const MoneyField({super.key, required this.controller, required this.label, this.required = false, this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool required;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_numFormatter],
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(labelText: label, suffixText: Fmt.currency),
        onChanged: onChanged,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return required ? 'مطلوب' : null;
          final m = Money.tryParse(v);
          if (m == null || m.isNegative) return 'قيمة غير صحيحة';
          return null;
        },
      );
}

class QtyField extends StatelessWidget {
  const QtyField({super.key, required this.controller, required this.label, this.required = true, this.onChanged, this.allowZero = false});
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowZero;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_numFormatter],
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return required ? 'مطلوب' : null;
          final q = Qty.tryParse(v);
          if (q == null || q.isNegative) return 'كمية غير صحيحة';
          if (!allowZero && q.milli == 0) return 'يجب أن تكون أكبر من صفر';
          return null;
        },
      );
}

int parseMoney(String s) => Money.tryParse(s)?.minor ?? 0;
int parseQty(String s) => Qty.tryParse(s)?.milli ?? 0;

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.ltr = false});
  final String label;
  final String? value;
  final bool ltr;
  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
        Expanded(child: Text(value!, textDirection: ltr ? TextDirection.ltr : null, textAlign: TextAlign.start)),
      ]),
    );
  }
}

class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.quantity, required this.status, this.unit});
  final int quantity;
  final String status; // in | low | out
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'out' => Colors.red.shade700,
      'low' => Colors.orange.shade800,
      _ => Colors.green.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text('${Fmt.qty(quantity)}${unit == null ? '' : ' $unit'}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class TagChips extends StatelessWidget {
  const TagChips(this.tags, {super.key, this.max = 3});
  final List<String> tags;
  final int max;
  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final shown = tags.take(max).toList();
    final more = tags.length - shown.length;
    final style = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSecondaryContainer);
    Widget chip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: style),
        );
    return Wrap(spacing: 4, runSpacing: 2, children: [
      ...shown.map(chip),
      if (more > 0)
        InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('الوسوم'),
              content: Wrap(spacing: 6, runSpacing: 6, children: tags.map(chip).toList()),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
            ),
          ),
          child: chip('+$more'),
        ),
    ]);
  }
}

/// Simple async loader that rebuilds when [reloadKey] changes.
class FutureLoader<T> extends StatefulWidget {
  const FutureLoader({super.key, required this.load, required this.builder, this.reloadKey});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, VoidCallback reload) builder;
  final Object? reloadKey;
  @override
  State<FutureLoader<T>> createState() => _FutureLoaderState<T>();
}

class _FutureLoaderState<T> extends State<FutureLoader<T>> {
  late Future<T> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  @override
  void didUpdateWidget(covariant FutureLoader<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _f = widget.load();
  }

  void _reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return widget.builder(c, s.data as T, _reload);
        },
      );
}
