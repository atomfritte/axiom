/// Nimmt Einstiege von außerhalb der App entgegen.
///
/// Drei Wege führen direkt in die Erfassung, ohne dass man die App suchen
/// muss: Schnelleinstellung, langes Tippen auf das App-Symbol und Teilen aus
/// einer anderen App. Alle drei landen hier [D9].
library;

import 'dart:async';

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/anchors_screen.dart';
import '../screens/capture_sheet.dart';
import '../screens/body_sheet.dart';
import '../screens/checkin_sheet.dart';
import '../screens/focus_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/review_screen.dart';
import '../screens/sensation_screen.dart';
import '../state/providers.dart';
import 'android_bridge.dart';
import 'system_sync.dart';
import '../i18n/i18n.dart';

class IntentHandler extends ConsumerStatefulWidget {
  final Widget child;
  const IntentHandler({super.key, required this.child});

  @override
  ConsumerState<IntentHandler> createState() => _IntentHandlerState();
}

class _IntentHandlerState extends ConsumerState<IntentHandler>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('de.atomfritte.axiom/system');
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final language = context.language;
      unawaited(_drainPending());
      unawaited(SystemSync.installDailyAnchors(language: language));
      unawaited(SleepGate.schedule(language: language));
      unawaited(_maybeStartExpert());
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
      // Systemfreigaben aendern sich ausserhalb der App: Health Connect,
      // Benachrichtigungen, die Notiz-Rolle. Wer gerade aus dem
      // Systemdialog zurueckkommt, darf nicht den alten Stand sehen — sonst
      // wirkt eine erteilte Freigabe wie eine abgelehnte (R8).
      ref.invalidate(healthAvailabilityProvider);
      ref.read(expertModeProvider.notifier).refresh();
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
      //
      // Erst lesen, dann speichern, dann bestätigen. Was hier scheitert,
      // bleibt liegen und kommt beim nächsten Start wieder — ein Gedanke
      // darf nicht daran verlorengehen, dass die Datenbank kurz nicht da
      // war [D9].
      final memos = await AndroidBridge.peekPendingMemos();
      var stored = 0;
      for (final memo in memos) {
        if (memo.trim().isNotEmpty) {
          await runtime.capture(memo.trim(), via: 'quicktile');
        }
        stored++;
      }
      if (stored > 0) await AndroidBridge.ackPendingMemos(stored);

      // Ortswechsel aus Geräteroutinen (`de.atomfritte.axiom.PLACE`).
      //
      // Mit dem Zeitstempel des Empfangs, nicht dem von jetzt: Der Wechsel
      // ist passiert, als die Routine ausgelöst hat. Mit der aktuellen Zeit
      // abgelegt stünde er im Ereignisstrom an der falschen Stelle, und jede
      // spätere Auswertung „wo wurde eigentlich gearbeitet" wäre falsch.
      final places = await AndroidBridge.peekPendingPlaces();
      var seen = 0;
      for (final entry in places) {
        final at = entry['at'];
        await runtime.recordAt(
          at is int
              ? DateTime.fromMillisecondsSinceEpoch(at)
              : runtime.clock.nowUtc(),
          EventType.placeEntered,
          source: EventSource.device,
          payload: {'place': (entry['place'] as String?)?.trim() ?? ''},
        );
        seen++;
      }
      if (seen > 0) await AndroidBridge.ackPendingPlaces(seen);

      final action = await _invokeString('launchAction');
      if (!mounted) return;
      switch (action) {
        case AxiomRoute.capture:
          await showCaptureSheet(context);
        case AxiomRoute.checkin:
          await showCheckinSheet(context);
        case AxiomRoute.body:
          await showSleepSheet(context);
        // Ein Anstoß, der auf der Übersicht endet, ist kein Anstoß: Der Weg
        // zur eigentlichen Handlung beginnt dann von vorn, und genau dieser
        // Zwischenschritt ist die Stelle, an der es hängenbleibt [D2].
        case AxiomRoute.focus:
          await _open(const FocusScreen());
        case AxiomRoute.sensation:
          await _open(const SensationScreen());
        case AxiomRoute.anchors:
          await _open(const AnchorsScreen());
        case AxiomRoute.review:
          await _open(const ReviewScreen());
        case AxiomRoute.inbox:
          await _open(const InboxScreen());
        case 'de.atomfritte.axiom.EXPERT_STOP':
          // Der Knopf auf der Benachrichtigung. Er oeffnet die App, weil der
          // Server im App-Prozess laeuft — ihn von aussen zu beenden hiesse,
          // den Prozess zu beenden, und das waere ein Absturz, kein Stopp.
          await ref.read(expertModeProvider.notifier).stop();
      }
      refreshAxiom(ref);
    } on Object {
      // Ein fehlgeschlagener Plattformaufruf darf die App nie blockieren.
    } finally {
      _handling = false;
    }
  }

  Future<void> _open(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Startet den Expertenmodus mit, wenn er dafür eingeschaltet ist.
  ///
  /// Bewusst nur hier und nirgends sonst: Dieser Pfad läuft, wenn die App
  /// geöffnet wird — nicht beim Hochfahren, nicht aus einem Dienst heraus.
  /// Der Unterschied ist der ganze Punkt (ADR-0005, Punkt 3).
  Future<void> _maybeStartExpert() async {
    try {
      final runtime = await ref.read(runtimeProvider.future);
      if (!runtime.expertAutostart) return;
      if (ref.read(expertModeProvider).running) return;
      await ref.read(expertModeProvider.notifier).start();
    } on Object {
      // Kein Grund, die App nicht zu starten. Der Schalter im
      // Expertenmodus zeigt, dass er aus ist.
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
