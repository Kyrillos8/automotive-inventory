import 'package:flutter/material.dart';

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.error_outline,
        title: 'حدث خطأ',
        message: '$error',
        action: onRetry == null ? null : FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      );
}

/// Honest marker for features scheduled in a later phase (never presented as done).
class UpcomingFeatureView extends StatelessWidget {
  const UpcomingFeatureView({super.key, required this.title, required this.phase});
  final String title;
  final int phase;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.construction,
        title: title,
        message: 'هذه الميزة غير متاحة بعد — مخطط تنفيذها في المرحلة $phase.',
      );
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  ));
}
