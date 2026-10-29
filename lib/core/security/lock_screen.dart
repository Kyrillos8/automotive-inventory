import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pin_service.dart';

/// Shown on launch when a PIN is set; [child] is revealed after unlocking.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, required this.locked});
  final Widget child;
  final bool locked;
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late bool _locked = widget.locked;

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    // Own Navigator so the PIN field gets an Overlay (we sit above the router).
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _LockPage(onUnlocked: () => setState(() => _locked = false)),
      ),
    );
  }
}

class _LockPage extends ConsumerStatefulWidget {
  const _LockPage({required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  ConsumerState<_LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<_LockPage> {
  final _pin = TextEditingController();
  String? _error;
  int _attempts = 0;
  DateTime? _blockedUntil;

  Future<void> _check() async {
    if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) {
      setState(() => _error = 'محاولات كثيرة، انتظر 30 ثانية');
      return;
    }
    final ok = await ref.read(pinServiceProvider).verify(_pin.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    _attempts++;
    if (_attempts >= 5) {
      _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      _attempts = 0;
    }
    setState(() {
      _error = 'رقم سري غير صحيح';
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('أدخل الرقم السري', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _pin,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 8,
                decoration: InputDecoration(errorText: _error),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _check, child: const Text('فتح')),
            ]),
          ),
        ),
      ),
    );
  }
}
