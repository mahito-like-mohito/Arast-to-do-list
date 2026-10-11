import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings_controller.dart';
import '../../core/app_palette.dart';
import '../../core/external_picker.dart';
import '../../services/app_lock_service.dart';

class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final AppLockService _lockService = AppLockService();

  bool _unlocked = false;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAuthenticate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        !_authInFlight &&
        !ExternalPicker.isActive) {
      final lockEnabled = context.read<SettingsController>().appLockEnabled;
      if (lockEnabled && _unlocked) {
        setState(() => _unlocked = false);
      }
    }
    if (state == AppLifecycleState.resumed) {
      ExternalPicker.noteResumed();
      _maybeAuthenticate();
    }
  }

  Future<void> _maybeAuthenticate() async {
    if (!mounted || _authInFlight) return;
    final lockEnabled = context.read<SettingsController>().appLockEnabled;
    if (!lockEnabled || _unlocked) return;

    _authInFlight = true;
    final success = await _lockService.authenticate();
    _authInFlight = false;
    if (mounted && success) {
      setState(() => _unlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockEnabled =
        context.watch<SettingsController>().appLockEnabled;
    if (!lockEnabled || _unlocked) return widget.child;

    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.backdropBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: palette.onBackdropMuted),
            const SizedBox(height: 18),
            Text(
              'Arast is locked',
              style: TextStyle(
                color: palette.onBackdrop,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
              onPressed: _maybeAuthenticate,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
