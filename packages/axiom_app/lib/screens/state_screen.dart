/// "Zustand" — alle sechs Dimensionen mit Herleitung.
///
/// Jeder Wert ist aufklappbar. Ein Score, dessen Rechenweg unsichtbar
/// bleibt, wird von diesem Nutzerprofil zu Recht verworfen (G2).
///
/// **Warum dieser Schirm eine Rangfolge hat.** Hier standen sechs
/// Messwertzeilen gleicher Groesse in einer einzigen Karte, jede mit ihrer
/// eigenen Farbe. Zwei Folgen: Erstens war nicht zu sehen, welche Zahl den
/// Tag bestimmt — die Kapazitaet entscheidet, wie viel AXIOM ueberhaupt
/// zeigt, die anderen fuenf erklaeren sie. Zweitens lasen sich sechs Farben
/// untereinander als sechs *Urteile* ueber denselben Menschen, und genau das
/// verbietet R7.
///
/// Jetzt traegt die Kapazitaet die eine erhobene Flaeche des Schirms, die
/// uebrigen fuenf liegen darunter ruhig auf dem Grund. Unterschieden wird
/// ueber Position und Beschriftung, nicht ueber Farbe.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';
import 'checkin_sheet.dart';
import '../i18n/i18n.dart';

class StateScreen extends ConsumerWidget {
  const StateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final p = context.axiom;

    return MetaTimedScope(
      screen: 'state',
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.t('Zustand')),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await showCheckinSheet(context);
              refreshAxiom(ref);
            },
            icon: Icon(Icons.add_chart, size: 18, color: p.signal),
            label: Text(context.t('Check-in'),
                style: TextStyle(color: p.signal)),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: snapshot.when(
        loading: () => PatientLoader(
          hint: context.t('Das dauert länger als vorgesehen. Bleibt es dabei, sagt System → Systemcheck, ob eine Systemschnittstelle nicht antwortet.'),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) {
          final s = snap.state;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.huge),
            children: [
              _LoadHeader(level: s.loadLevel),
              const SizedBox(height: Space.xl),

              // **Die eine erhobene Flaeche.** Die Kapazitaet ist kein
              // Messwert unter sechs, sondern der, aus dem die App ihr
              // Verhalten ableitet — sie entscheidet, wie viel heute
              // ueberhaupt gezeigt wird. Griffhoehe sagt das, ohne dass ein
              // Satz es behaupten muss.
              Panel(
                reachable: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ohne `reading`: Der erklaerende Satz steht hier
                    // *unter* der Skalenbeschriftung, sonst schoebe er sich
                    // zwischen den Balken und seine beiden Enden — und eine
                    // Achsenbeschriftung, die nicht an ihrer Achse steht,
                    // beschriftet nichts.
                    InstrumentBar(
                      label: context.t('Kapazität'),
                      value: s.capacity,
                      breakdown: snap.breakdown['capacity'] ?? const [],
                      confidence: s.confidenceOf('capacity'),
                    ),
                    const SizedBox(height: Space.xs),
                    // Die Skala wird als **Verhalten des Systems**
                    // beschriftet, nicht als Wertung. „niedrig/hoch" waere
                    // eine Note ueber den Nutzer; „weniger zeigen / mehr
                    // zeigen" sagt dieselbe Zahl als das, was AXIOM damit
                    // tut (R7).
                    ScaleEnds(
                      low: context.t('weniger zeigen'),
                      high: context.t('mehr zeigen'),
                    ),
                    const SizedBox(height: Space.md),
                    Text(context.t('Wie viel exekutive Reserve heute da ist.'),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),

              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Weitere Messwerte')),
              Panel(
                child: Column(
                  children: [
                    // Der `color`-Parameter von `InstrumentBar` ist hier
                    // ersatzlos gestrichen. Er faerbte frueher jede Zeile
                    // eigen — Kapazitaet bernstein, Kompensationslast ueber
                    // `forLoadLevel` gruen, Reizbedarf kupfern, Fokuslast
                    // blau, Regulationsreserve gruen. Untereinander gelesen
                    // waren das fuenf Noten statt fuenf Messungen (R7); der
                    // Baustein wertet ihn seit dem Fundament nicht mehr aus.
                    InstrumentBar(
                      label: context.t('Kompensationslast'),
                      value: s.loadIndex,
                      reading:
                          context.t('Kumulierter Aufwand, den Alltag zu strukturieren.'),
                      breakdown: snap.breakdown['load_index'] ?? const [],
                      confidence: s.confidenceOf('load_index'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: context.t('Reizbedarf'),
                      value: s.sensationNeed,
                      reading: context.t('Ungedeckter Bedarf sucht sich den schnellsten Kanal.'),
                      breakdown: snap.breakdown['sensation_need'] ?? const [],
                      confidence: s.confidenceOf('sensation_need'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: context.t('Fokuslast heute'),
                      value: s.focusDebt,
                      reading: context.t('Verbrauchte Konzentrationszeit seit heute früh.'),
                      confidence: s.confidenceOf('focus_debt'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: context.t('Regulationsreserve'),
                      value: s.regulation,
                      reading: context.t('Puffer für emotionale Belastung.'),
                      confidence: s.confidenceOf('regulation'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: context.t('Schlafschuld'),
                      value: s.sleepDebt,
                      reading: context.t('Stärkster einzelner Modulator der Kapazität.'),
                      confidence: s.confidenceOf('sleep_debt'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xxl),
              const _Disclaimer(),
            ],
          );
        },
      ),
    ),
    );
  }
}

/// Die Laststufe — als Kopfzeile, nicht als Karte.
///
/// Hier stand eine gerahmte Karte mit farbiger Plakette. Sie war damit die
/// erhobenste Flaeche des Schirms, obwohl darunter die Zahl steht, um die es
/// geht. Jetzt traegt der Kopf, was ueberall sonst der Titel traegt: eine
/// Marke, eine Zeile, ein Satz — ohne Flaeche darunter.
///
/// **Ab L2 wird daraus doch eine Flaeche.** Nicht aus Systematik, sondern
/// weil sich ab dort das Verhalten des Systems aendert: Es nimmt nichts
/// Neues mehr auf. Ein Regime ist ein *Zustand*, und ein Zustand darf eine
/// Karte faerben — im Gegensatz zu einem Messwert (R7). Erhoben wird sie
/// trotzdem nicht; die Griffhoehe bleibt bei der Kapazitaet.
class _LoadHeader extends StatelessWidget {
  final LoadLevel level;
  const _LoadHeader({required this.level});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final color = p.forLoadLevel(level.index);
    final marked = level.index >= 2;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              // „L0" ist zwei Zeichen — die Ausnahme fuer kurze Plaketten.
              // Die Schreibmaschine ist hier trotzdem weg: Sie war fuer die
              // Regel-ID reserviert, und eine Stufe ist keine.
              child: Text(level.name.toUpperCase(),
                  style: readingStyle(context,
                      size: 12.5, weight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(_headline(context, level),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(_body(context, level),
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );

    if (!marked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: content,
      );
    }
    return Panel(accent: color.withValues(alpha: 0.45), child: content);
  }

  static String _headline(BuildContext context, LoadLevel l) => switch (l) {
        LoadLevel.l0 => context.t('Normalbetrieb'),
        LoadLevel.l1 => context.t('Last erhöht'),
        LoadLevel.l2 => context.t('Last kritisch'),
        LoadLevel.l3 => context.t('Erhaltungsmodus'),
      };

  static String _body(BuildContext context, LoadLevel l) => switch (l) {
        LoadLevel.l0 => context.t('Die Kompensationslast liegt im gewohnten Bereich.'),
        LoadLevel.l1 =>
          context.t('Die Last steigt seit einigen Tagen. Noch unauffällig nach außen — genau deshalb wird sie hier angezeigt.'),
        LoadLevel.l2 =>
          context.t('Jetzt nichts Neues zusätzlich aufnehmen. Bestehendes eher abgeben als erweitern.'),
        LoadLevel.l3 =>
          context.t('Für die nächsten Tage nur Pflicht und Erholung. Dass dieser Modus greift, ist der Zweck des Systems — nicht dein Versagen.'),
      };
}

/// Die Abgrenzung. Steht am Fuss, leise, und ohne Rahmen.
///
/// Der Rahmen war hier das letzte Gitter des Schirms: eine Haarlinie um
/// einen Absatz, der nichts umschliesst, was der Abstand nicht schon trennt.
/// Und „EINORDNUNG" waren zehn gesperrte Grossbuchstaben — die Wortform
/// faellt dabei weg, man liest Buchstabe fuer Buchstabe.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(context.t('Einordnung')),
          Text(
            context.t('Diese Werte sind Messungen aus deinen eigenen Angaben und Gerätedaten. Sie sind keine Diagnose und kein Befund. AXIOM ersetzt weder ärztliche noch psychotherapeutische Behandlung.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}
