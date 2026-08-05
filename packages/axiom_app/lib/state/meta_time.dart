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
library;

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

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    ref.read(runtimeProvider.future).then((runtime) {
      if (mounted) _runtime = runtime;
    });
  }

  @override
  void dispose() {
    final openedAt = _openedAt;
    if (openedAt != null) {
      final spent = DateTime.now().difference(openedAt);
      if (spent > kMetaGrace) {
        _runtime?.logScreenTime(metaScreen, spent);
      }
    }
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
