/// Signal-Log — M10.
///
/// Zwei getrennte Momente, und die Trennung ist der ganze Punkt:
///
///   **Erfassen** passiert im Spike. Zwei Tipps, fertig. Wer in dem Moment
///   nach Reflexion gefragt wird, erfasst gar nichts.
///
///   **Nachbetrachten** passiert frühestens zwölf Stunden später, wenn die
///   Regulationsreserve wieder da ist. Vorher ist niemand analysefähig, und
///   der Versuch verlängert das Ereignis, statt es abzuschließen [D10].
///
/// Sprache durchgehend als Störungsbericht, nicht als Gefühlstagebuch.
/// Identischer Inhalt, anderes Wort — und das Wort entscheidet, ob es
/// überhaupt geführt wird.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

class SignalScreen extends ConsumerWidget {
  const SignalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidents = ref.watch(incidentsProvider).value ?? const [];
    final pending = ref.watch(pendingPostMortemsProvider).value ?? const [];
    final patterns = ref.watch(incidentPatternsProvider).value ?? const {};
    final delta = ref.watch(hindsightProvider).value;
    final p = context.axiom;

    return MetaTimedScope(
      screen: 'signal',
      child: Scaffold(
      appBar: AppBar(title: Text(context.t('Vorfälle'))),
      body: ListView(
        // Unten so viel Platz, dass die letzte Zeile neben dem Knopf endet
        // und nicht unter ihm. Ein fester Wert reicht dafuer nicht: Der Knopf
        // waechst mit der Schrift mit, die Liste tat es nicht — bei grosser
        // Schrift lag er wieder auf dem Text.
        padding: EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, _fabClearance(context)),
        children: [
          if (pending.isNotEmpty) ...[
            _PendingCard(incident: pending.first, open: pending.length),
            const SizedBox(height: Space.xl),
          ],

          if (delta != null) ...[
            _HindsightCard(delta: delta),
            const SizedBox(height: Space.xl),
          ],

          if (incidents.isEmpty)
            const _EmptyState()
          else ...[
            if (patterns.isNotEmpty) ...[
              SectionLabel(context.t('Häufungen · 30 Tage')),
              Panel(
                child: Column(
                  children: [
                    // **Feste Reihenfolge, nicht die des Kerns.**
                    // `SignalLog.patterns` sortiert absteigend nach Anzahl —
                    // fuer ein Monatsreview sinnvoll, auf diesem Schirm eine
                    // Rangliste eigener Kraenkungen. Gezeigt wird deshalb die
                    // Reihenfolge, in der die Klassen beim Erfassen zur
                    // Auswahl stehen; sie ist immer dieselbe und sagt nichts
                    // ueber das Gewicht (R7, D10).
                    for (final trigger in TriggerClass.values)
                      if (patterns[trigger] != null)
                        _PatternCount(
                          triggerClass: trigger,
                          count: patterns[trigger]!,
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                context.t('Gezählt, nicht gewichtet — die Reihenfolge ist immer dieselbe.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.xl),
            ],
            SectionLabel(context.t('Verlauf · {0}', [incidents.length])),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, incident)
                      in incidents.take(20).indexed) ...[
                    if (index > 0) Divider(color: p.rule, height: 1),
                    _IncidentRow(incident: incident),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: Space.xxl),
          // Der Rahmen ist weg. Er umschloss einen Absatz, den der Abstand
          // ohnehin trennt, und zog damit noch eine Linie ueber einen Schirm,
          // der schon genug davon hat.
          SectionLabel(context.t('Einordnung')),
          Text(
            context.t('Dieses Modul hält fest und zeigt Muster. Es deutet nichts und behandelt nichts. Wenn dich etwas davon länger belastet, ist das ein Grund, mit einer Fachperson zu sprechen — nicht mit einer App.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      // **Bernstein, nicht Kupfer.** Der Knopf trug die Aufmerksamkeitsfarbe
      // dieses Moduls — dieselbe, die den Vorfall selbst markiert. Damit
      // stand die Farbe „Achtung" auf dem *Erfassen*, und der Schirm sah aus,
      // als sei das Festhalten das Problem. Erfassen ist die Handlung, die
      // hier gemeint ist (G1), also traegt sie die Signalfarbe wie jede
      // andere Haupthandlung der App.
      //
      // **Und er schwebt wieder.** Der Schatten kommt aus derselben Quelle
      // wie bei den Karten: Der Materialvorgabe-Schatten zeichnet auf hellem
      // Grund einen harten Ring, `Shadows.reachable` nicht. Ohne Erhebung
      // ueberhaupt lag der Knopf flach auf der Liste — ausgerechnet das eine
      // Element, das ueber allem liegen soll.
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.panel),
          boxShadow: Shadows.reachable(p),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => showIncidentSheet(context),
          backgroundColor: p.signal,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.panel),
          ),
          icon: const Icon(Icons.bolt),
          label: Text(context.t('Vorfall')),
        ),
      ),
    ),
    );
  }
}

/// Wie viel Platz eine Liste unter ihrer letzten Zeile braucht.
///
/// Der schwebende Knopf lag auf dem Text: `FloatingActionButton.extended` ist
/// 56 px hoch, sitzt 16 px ueber dem Rand — und die Liste endete darunter.
/// Ein fester Zahlenwert reicht nicht, weil der Knopf mit der Schriftgroesse
/// waechst; `scaledHeight` zieht ihn mit.
double _fabClearance(BuildContext context) =>
    scaledHeight(context, 56) + Space.huge;

/// Kommazahl in der eingestellten Sprache.
///
/// „2.5" ist im Deutschen keine Zahl, sondern ein Tippfehler. Dieselbe Regel
/// wie in der Herleitungstafel (`instruments.dart`).
String _decimal(BuildContext context, double value) {
  final text = value.toStringAsFixed(1);
  return context.language == AppLanguage.de ? text.replaceAll('.', ',') : text;
}

/// Nichts erfasst — und das eine Aussage, kein Fehler.
///
/// War von Hand gebaut, mit „NICHTS ERFASST" in gesperrten Versalien. Der
/// Baustein `EmptyState` macht dasselbe, in normaler Schreibweise, und
/// scrollt bei grosser Schrift, statt den Erklaertext unten abzuschneiden —
/// ausgerechnet hier steht er, weil man auf einem leeren Schirm zum ersten
/// Mal liest, wozu es ihn gibt.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => EmptyState(
        label: context.t('Nichts erfasst'),
        headline: context.t('Noch keine Vorfälle.'),
        body: context.t('Gemeint sind Momente, in denen etwas unverhältnismäßig hart getroffen hat — Kritik, Zurückweisung, ein eigener Fehler. Zwei Tipps im Moment, die Einordnung kommt später.'),
        footnote: context.t('Der Nutzen liegt nicht im Aufschreiben, sondern im Muster: Was regelmäßig trifft, lässt sich vorbereiten.'),
      );
}

/// Eine Nachbetrachtung ist fällig.
class _PendingCard extends ConsumerWidget {
  final SignalIncident incident;
  final int open;

  const _PendingCard({required this.incident, required this.open});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    // Ueber den Clock-Port, nicht ueber DateTime.now(): Sonst rechnet die
    // Oberflaeche mit einer anderen Zeit als die Engine.
    final hours =
        ref.watch(nowProvider).difference(incident.at).inHours.clamp(0, 999);

    return Panel(
      accent: p.info.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              open > 1
                  ? context.t('Nachbetrachtung · {0} offen', [open])
                  : context.t('Nachbetrachtung'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(incident.triggerClass.label,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.sm),
          // Zeit und Staerke sind Messwerte: Hausschrift mit
          // Tabellenziffern. Die Schreibmaschine bleibt der Regel-ID.
          Text(context.t('vor {0} Stunden · Stärke {1}/5', [hours, incident.intensity]),
              style: readingStyle(context,
                  size: 14, weight: FontWeight.w400, color: p.inkDim)),
          const SizedBox(height: Space.lg),
          Text(
            context.t('Jetzt ist genug Abstand da. Zwei Fragen, dann ist es abgelegt.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => showPostMortemSheet(context, incident),
            child: Text(context.t('Kurz durchgehen')),
          ),
        ],
      ),
    );
  }
}

/// Die nützlichste Zahl des Moduls.
///
/// **Sie ist ein Messwert, kein Erfolg.** Vorher stand sie in Grün, sobald
/// sie über 0,5 lag, und sonst in Grau — grün heißt „gut gemacht", und damit
/// war aus „so weit liegen Moment und Rückblick auseinander" eine Note
/// geworden (R7, D10). Jetzt trägt sie die Messfarbe wie jeder andere Wert
/// der App; was sie bedeutet, sagt der Satz darunter.
///
/// Die 32 px standen zusätzlich in Schreibmaschine in w300 — auf einem
/// Telefon dünn und blass. `BigReading` setzt sie in der Hausschrift mit
/// Tabellenziffern und hängt die Einheit umbruchsicher daneben.
class _HindsightCard extends StatelessWidget {
  final double delta;
  const _HindsightCard({required this.delta});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('Im Rückblick'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          BigReading(
            value: delta >= 0
                ? '−${_decimal(context, delta)}'
                : '+${_decimal(context, -delta)}',
            unit: context.t('Stufen'),
            valueColor: p.signal,
            size: 32,
          ),
          const SizedBox(height: Space.md),
          Text(
            delta >= 0.5
                ? context.t('So viel niedriger fällt ein Vorfall bei dir im Rückblick aus. Kein Trost — ein Erfahrungswert, den du beim nächsten Mal einkalkulieren kannst.')
                : context.t('Die Einschätzung im Moment und im Rückblick liegen bei dir nah beieinander.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Wie oft ein Auslöser in dreissig Tagen vorkam — **als Zahl, nicht als
/// Balken.**
///
/// Hier stand ein gefüllter Balken je Klasse, dessen Skalenmaximum die
/// häufigste Klasse war. Das ist die teuerste Grafik, die dieses Modul haben
/// kann: Es entsteht eine **Rangliste eigener Kränkungen**, in der die
/// schmerzhafteste Klasse den längsten Balken bekommt — und weil das Maximum
/// mitläuft, sieht ein einziges zusätzliches Ereignis aus wie eine
/// Verdopplung. Bei Rejection Sensitivity ist das kein Schönheitsfehler
/// (D10), und R7 verbietet die Form ohnehin: Eine Zählung ist ein Messwert
/// und kein Rang.
///
/// Was bleibt, ist die Zahl in der Messfarbe — dieselbe Rolle wie jeder Wert
/// auf dem Zustandsschirm. Kupfer wäre hier die Farbe des Vorfalls und würde
/// „das ist zu viel" sagen; das ist ein Urteil, kein Messwert.
class _PatternCount extends StatelessWidget {
  final TriggerClass triggerClass;
  final int count;

  const _PatternCount({required this.triggerClass, required this.count});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(triggerClass.label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: Space.md),
          Text('$count',
              style: readingStyle(context, size: 15, color: p.signal)),
        ],
      ),
    );
  }
}

/// Eine Zeile im Verlauf.
///
/// Kein eigenes Panel mehr — die Zeilen bilden zusammen eine Liste, und eine
/// Liste ist eine Flaeche mit Haarlinien statt zwanzig schwebender Kaesten.
class _IncidentRow extends StatelessWidget {
  final SignalIncident incident;
  const _IncidentRow({required this.incident});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final at = incident.at;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      child: Row(
        children: [
          // Staerke als Skala, nicht als Note — und deshalb in der Messfarbe.
          // Kupfer sagte hier „schlimm"; gemeint ist „so stark war es".
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Container(
                  width: 3,
                  height: 4.0 + i * 2.5,
                  margin: const EdgeInsets.only(right: 2),
                  color: i <= incident.intensity ? p.signal : p.rule,
                ),
            ],
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(incident.triggerClass.label,
                    style: Theme.of(context).textTheme.bodyLarge),
                if (incident.note != null && incident.note!.isNotEmpty)
                  Text(incident.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            '${at.day}.${at.month}.',
            style: readingStyle(context,
                size: 13.5, weight: FontWeight.w400, color: p.inkFaint),
          ),
        ],
      ),
    );
  }
}

// ── Erfassen: zwei Tipps im Spike ───────────────────────────────────────

Future<void> showIncidentSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _IncidentSheet(),
    );

class _IncidentSheet extends ConsumerStatefulWidget {
  const _IncidentSheet();

  @override
  ConsumerState<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends ConsumerState<_IncidentSheet> {
  int _intensity = 3;
  TriggerClass? _trigger;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_trigger == null) return;
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.logIncident(
      intensity: _intensity,
      triggerClass: _trigger!,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: Space.lg,
          right: Space.lg,
          top: Space.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('Vorfall'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text(context.t('Woran hing es?'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.xs),
            Text(context.t('Grob reicht. Einordnen kannst du später.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.lg),

            for (final trigger in TriggerClass.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Panel(
                  accent: _trigger == trigger
                      ? p.caution.withValues(alpha: 0.55)
                      : null,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg, vertical: Space.md),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _trigger = trigger);
                  },
                  child: Row(
                    children: [
                      Icon(
                        _trigger == trigger
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 17,
                        color: _trigger == trigger ? p.caution : p.inkFaint,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(trigger.label,
                                style: Theme.of(context).textTheme.bodyLarge),
                            Text(trigger.description,
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: Space.lg),
            Text(context.t('Wie hart?'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _intensity = i);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 46,
                        margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: _intensity >= i
                              ? p.caution.withValues(
                                  alpha: _intensity == i ? 0.9 : 0.28)
                              : p.panel,
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(
                              color: _intensity == i ? p.caution : p.rule),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Space.lg),
            TextField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t('Ein Stichwort, wenn du magst (optional)'),
              ),
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _trigger == null ? null : _save,
              child: Text(context.t('Festhalten')),
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: Text(
                context.t('Die Einordnung kommt in etwa zwölf Stunden.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nachbetrachten: später, mit Abstand ─────────────────────────────────

Future<void> showPostMortemSheet(
  BuildContext context,
  SignalIncident incident,
) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PostMortemSheet(incident: incident),
    );

class _PostMortemSheet extends ConsumerStatefulWidget {
  final SignalIncident incident;
  const _PostMortemSheet({required this.incident});

  @override
  ConsumerState<_PostMortemSheet> createState() => _PostMortemSheetState();
}

class _PostMortemSheetState extends ConsumerState<_PostMortemSheet> {
  final _cause = TextEditingController();
  final _counter = TextEditingController();
  late int _hindsight = widget.incident.intensity;

  @override
  void dispose() {
    _cause.dispose();
    _counter.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.savePostMortem(
      incidentId: widget.incident.id,
      rootCause: _cause.text.trim().isEmpty ? null : _cause.text.trim(),
      countermeasure:
          _counter.text.trim().isEmpty ? null : _counter.text.trim(),
      intensityInHindsight: _hindsight,
    );
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final incident = widget.incident;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: Space.lg,
          right: Space.lg,
          top: Space.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('Nachbetrachtung'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text(incident.triggerClass.label,
                style: Theme.of(context).textTheme.headlineMedium),
            if (incident.note != null && incident.note!.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(incident.note!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: Space.xl),

            Text(context.t('Wie fällt es heute aus?'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(context.t('Damals: {0}/5', [incident.intensity]),
                style: readingStyle(context,
                    size: 14, weight: FontWeight.w400, color: p.inkDim)),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _hindsight = i);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 44,
                        margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: _hindsight >= i
                              ? p.info.withValues(
                                  alpha: _hindsight == i ? 0.9 : 0.28)
                              : p.panel,
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(
                              color: _hindsight == i ? p.info : p.rule),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Space.xl),
            Text(context.t('Was war der eigentliche Auslöser?'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(context.t('Oft ein anderer als der gefühlte.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _cause,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: Space.lg),
            Text(context.t('Was ginge beim nächsten Mal anders?'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(context.t('Konkret, nicht als Vorsatz. Optional.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _counter,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _save,
              child: Text(context.t('Abgelegt')),
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('Später')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
