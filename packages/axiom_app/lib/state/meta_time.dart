/// Bucht die Zeit, die ein Bildschirm auf das Meta-Work-Budget zieht (M12).
///
/// **Warum das ein eigener Baustein ist.** Die Buchung stand zweimal als
/// Handarbeit im Code — auf dem Systemscreen und im Review. Alle anderen
/// Bildschirme, auf denen man sich verlieren kann, zählten nicht mit: der
/// Regeleditor, der Systemcheck, der Zustand, die Kanäle, der
/// Expertenmodus. Das Budget stand deshalb faktisch immer auf null, und
/// G4 — laut CLAUDE.md das wichtigste Gesetz dieses Projekts — hat nie
/// zugeschlagen.
///
/// **Was zählt und was nicht.** Erfassung zählt nie: Sie ist der Zweck, und
/// sie zu bremsen wäre das Gegenteil von G1. „Jetzt" zählt auch nicht — dort
/// steht die Handlung, nicht das System. Gezählt wird alles, worauf man
/// *über* das System schaut: konfigurieren, auswerten, herumsehen.
///
/// **Warum drei Sekunden Karenz.** Ein Screen, den man versehentlich
/// antippt und sofort wieder verlässt, ist keine Nutzungszeit. Ohne die
/// Karenz addierte sich jedes Durchtippen zu Minuten, die niemand verbracht
/// hat — und ein Deckel, der falsch misst, ist schlimmer als keiner.
///
/// **Warum die Buchung nicht mehr allein an `dispose()` hängt.** Sie tat es,
/// und damit blieb G4 in beide Richtungen falsch. Beendet Android den Prozess
/// (Swipe-away, Speicherdruck), läuft `dispose()` nie: Eine halbe Stunde im
/// Regeleditor war danach spurlos verschwunden, `usageToday` stand wieder auf
/// null und die Sperre griff nicht. Und hing ein Bildschirm in einem
/// Behälter, der ihn dauerhaft montiert hält, maß `dispose()` nicht die
/// Verweildauer, sondern die Lebensdauer des Behälters. Deshalb wird jetzt
/// zusätzlich beim Wechsel in den Hintergrund gebucht und beim Zurückkommen
/// neu angesetzt — und die Uhr ist der injizierte `Clock`, nicht
/// `DateTime.now()`, damit die Buchung überhaupt prüfbar ist.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'runtime.dart';

/// Unterhalb davon wird nichts gebucht.
const Duration kMetaGrace = Duration(seconds: 3);

mixin MetaTimed<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Wie der Bildschirm in der Auswertung heißt.
  String get metaScreen;

  DateTime? _openedAt;

  /// Beim Aufbau gemerkt: In `dispose()` ist `ref` nicht mehr benutzbar,
  /// die Zeit muss aber genau dann gebucht werden.
  AxiomRuntime? _runtime;
  Clock _clock = const SystemClock();

  /// Kein `WidgetsBindingObserver`-Mixin: `check_screen` und `expert_screen`
  /// bringen das selbst mit und überschreiben `didChangeAppLifecycleState`
  /// für ihre eigenen Zwecke. Ein zweites Mixin mit derselben Methode wäre
  /// stumm verloren gegangen — genau die Sorte Fehler, die niemand sieht.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(clockProvider);
    _openedAt = _clock.nowUtc();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    ref.read(runtimeProvider.future).then((runtime) {
      if (mounted) _runtime = runtime;
    });
  }

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      // Der Prozess kann ab hier jederzeit beendet werden, ohne dass noch
      // ein `dispose()` läuft. Was bis hierher verbraucht wurde, muss weg
      // sein, bevor das passiert.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      // `inactive` heißt: Das Fenster hat den Fokus nicht. Auf dem Telefon
      // ist das ein Durchgangszustand — Benachrichtigungsleiste, Anruf,
      // Systemdialog. Auf dem Rechner ist es der Normalfall: Der Companion
      // steht offen auf dem zweiten Bildschirm, gearbeitet wird woanders.
      // Der Zustandsschirm buchte dabei stundenlang weiter, ohne dass
      // jemand hinsah — derselbe Fehler, den die Weboberfläche hatte, nur
      // ohne Reiter. Gezählt wird deshalb, was den Fokus hat.
      //
      // Was das kostet: die Sekunden eines kurzen Systemdialogs. Das ist
      // der bessere Fehler — ein Deckel, der zu viel misst, wird
      // abgeschaltet; einer, der zu wenig misst, wird geglaubt.
      case AppLifecycleState.inactive:
        _book();
      case AppLifecycleState.resumed:
        _openedAt ??= _clock.nowUtc();
    }
  }

  /// Schreibt das bisher Verbrauchte weg und hält die Uhr an.
  ///
  /// Idempotent: Zweimal hintereinander gerufen bucht nichts doppelt. Nötig,
  /// weil beim Wechsel in den Hintergrund erst `hidden` und dann `paused`
  /// kommt und danach noch `dispose()` folgen kann.
  void _book() {
    final openedAt = _openedAt;
    _openedAt = null;
    if (openedAt == null) return;
    final spent = _clock.nowUtc().difference(openedAt);
    if (spent > kMetaGrace) {
      _runtime?.logScreenTime(metaScreen, spent);
    }
  }

  @override
  void dispose() {
    _book();
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// Dasselbe für Bildschirme ohne eigenen Zustand.
///
/// Ein `ConsumerWidget` hat kein `dispose`, an dem sich die Zeit buchen
/// ließe. Ihn nur deshalb in einen zustandsbehafteten umzubauen wäre
/// Umbau ohne Gegenwert — dieser Umschließer tut dasselbe von außen.
class MetaTimedScope extends ConsumerStatefulWidget {
  final String screen;
  final Widget child;
  const MetaTimedScope({
    super.key,
    required this.screen,
    required this.child,
  });

  @override
  ConsumerState<MetaTimedScope> createState() => _MetaTimedScopeState();
}

class _MetaTimedScopeState extends ConsumerState<MetaTimedScope>
    with MetaTimed<MetaTimedScope> {
  @override
  String get metaScreen => widget.screen;

  @override
  Widget build(BuildContext context) => widget.child;
}
