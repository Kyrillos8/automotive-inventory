import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_screen.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Overridden in main(): true when a PIN is configured.
final startLockedProvider = Provider<bool>((ref) => false);

class AutoPartsApp extends ConsumerWidget {
  const AutoPartsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(startLockedProvider);
    return MaterialApp.router(
      title: 'مخزن قطع غيار الموتور',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      // Arabic is the default and primary language; RTL comes from the locale.
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LockGate(locked: locked, child: child ?? const SizedBox.shrink()),
    );
  }
}
