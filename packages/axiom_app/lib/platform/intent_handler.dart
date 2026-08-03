/// Nimmt Einstiege von außerhalb der App entgegen.
///
/// Drei Wege führen direkt in die Erfassung, ohne dass man die App suchen
/// muss: Schnelleinstellung, langes Tippen auf das App-Symbol und Teilen aus
/// einer anderen App. Alle drei landen hier [D9].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/capture_sheet.dart';
import '../screens/body_sheet.dart';
import '../screens/checkin_sheet.dart';
import '../state/providers.dart';
import 'android_bridge.dart';
import 'system_sync.dart';

class IntentHandler extends ConsumerStatefulWidget {
  final Widget child;
  const IntentHandler({super.key, required this.child});

  @override
  ConsumerState<IntentHandler> createState() => _IntentHandlerState();
}

class _IntentHandlerState extends ConsumerState<IntentHandler>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('de.axiom/system');
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_drainPending());
      unawaited(SystemSync.installDailyAnchors());
      unawaited(SleepGate.schedule());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Beim Zurückkommen: Wartendes einsammeln und neu auswerten.
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainPending());
      refreshAxiom(ref);
    }
  }

  /// Holt ab, was außerhalb der App entstanden ist.
  Future<void> _drainPending() async {
    if (_handling || !AndroidBridge.isSupported) return;
    _handling = true;
    try {
      final runtime = await ref.read(runtimeProvider.future);

      // Aus einer anderen App geteilter Text.
      final shared = await _invokeString('pendingSharedText');
      if (shared != null && shared.trim().isNotEmpty) {
        await runtime.capture(shared.trim(), via: 'share');
      }

      // Schnelleinstellung und künftig S-Pen-Memos.
      for (final memo in await AndroidBridge.pullPendingMemos()) {
        if (memo.trim().isNotEmpty) {
          await runtime.capture(memo.trim(), via: 'quicktile');
        }
      }

      final action = await _invokeString('launchAction');
      if (!mounted) return;
      switch (action) {
        case 'de.axiom.CAPTURE':
          await showCaptureSheet(context);
        case 'de.axiom.CHECKIN':
          await showCheckinSheet(context);
      }
      refreshAxiom(ref);
    } on Object {
      // Ein fehlgeschlagener Plattformaufruf darf die App nie blockieren.
    } finally {
      _handling = false;
    }
  }

  static Future<String?> _invokeString(String method) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
