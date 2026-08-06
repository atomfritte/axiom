/// "Jetzt" — die Hauptansicht.
///
/// Zeigt genau EINE naechste Handlung, nie eine Liste zur Auswahl. Die
/// Auswahl aus einer Liste ist genau die Entscheidung, die bei niedriger
/// Kapazitaet am teuersten ist (G1). Die vollstaendige Liste bleibt
/// erreichbar, ist aber nie der Standardweg.
///
/// **Was die Reichweitenkante hier geaendert hat.** Vorher standen auf diesem
/// Schirm bis zu zwoelf Karten untereinander, fast jede mit farbigem Rahmen:
/// die Handlung, die Streifen, die Hinweise, die Kapazitaetsleiste, der
/// Zustand. Zehn gerahmte Kaesten sind ein Gitter, und ein Gitter hat keine
/// Ordnung — alles ist gleich weit weg, und jede Flaeche sieht aus wie ein
/// Angebot. Formal stand dort eine Handlung; gelesen wurde eine Auswahl.
///
/// Jetzt teilt die Kante den Schirm in zwei Zonen:
///
///  * **Darueber** liegt, was heute in die Hand geht: Kopfzeile, die wenigen
///    Streifen, die den Vorschlag mitbestimmen — und **genau eine erhobene
///    Karte**, die Handlung. Sie ist die einzige Flaeche des Schirms mit
///    Griffhoehe ([Shadows.reachable]).
///  * **Darunter** beginnt die Mulde: alles, was da ist und heute nicht die
///    Handlung ist — Bestand, Eingang, Anker, Rueckblick, Vorfaelle,
///    Werkzeuge, Koerper. Ohne Karten, ohne Ausgrauen, in vollem
///    Textkontrast, und **in immer derselben Reihenfolge**. Was hier liegt,
///    ist nicht weniger wert, es ist weiter weg.
///
/// **Kein Messwert steht auf diesem Schirm zweimal.** Zuerst fiel die
/// Kapazitaetsleiste weg — sie zeigte dieselbe Zahl wie die Kante, nur ein
/// zweites Mal und mit eigener Skala. Uebrig blieben drei `InstrumentBar`
/// unten in der Mulde: Kapazitaet, Kompensationslast, Reizbedarf, jede mit
/// aufklappbarer Herleitung — dieselben drei, die einen Reiter weiter auf
/// „Zustand" stehen. „Reichweite heute 61" und „Kapazitaet 61" standen drei
/// Zentimeter auseinander. Auch die sind weg. Ein Messwert hat einen Ort;
/// zwei Anzeigen desselben Werts lesen sich als zwei Aussagen (R7), und auf
/// diesem Schirm ist jede davon ein zweites Angebot neben der einen
/// Handlung (G1).
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/anchor_chain.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'anchors_screen.dart';
import 'atomize_sheet.dart';
import 'body_sheet.dart';
import 'focus_screen.dart';
import 'intercept_screen.dart';
import 'sensation_screen.dart';
import 'signal_screen.dart';
import 'capture_sheet.dart';
import 'checkin_sheet.dart';
import 'inbox_screen.dart';
import 'place_sheet.dart';
import 'review_screen.dart';
import 'system_screen.dart';
import 'tasks_screen.dart';
import '../i18n/i18n.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final inbox = ref.watch(inboxProvider).value ?? const [];

    return Scaffold(
      body: SafeArea(
        child: snapshot.when(
          loading: () => PatientLoader(
            hint: context.t('Das dauert länger als vorgesehen. Bleibt es dabei, sagt System → Systemcheck, ob eine Systemschnittstelle nicht antwortet.'),
          ),
          error: (e, _) => _ErrorPane(error: e),
          data: (snap) => RefreshIndicator(
            onRefresh: () async => refreshAxiom(ref),
            // Kein Rand an der Liste selbst: Die Mulde geht von Kante zu
            // Kante, sonst ist sie ein weiterer Kasten auf dem Grund statt
            // dessen Boden. Die Zone darueber bringt ihren Rand mit.
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.lg, Space.lg, Space.lg, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(snapshot: snap),
                      if (snap.regime.level != LoadLevel.l0) ...[
                        const SizedBox(height: Space.lg),
                        _RegimeBanner(snapshot: snap),
                      ],
                      if (snap.activeIntercept != null) ...[
                        const SizedBox(height: Space.lg),
                        _InterceptStrip(run: snap.activeIntercept!),
                      ],
                      // Hängt der Fokus an der laufenden Aufgabe, steht die
                      // Zeit schon auf deren Karte. Zweimal dasselbe wäre
                      // eine Liste mit einem Eintrag.
                      if (snap.focus != null &&
                          !snap.tasks.any((t) =>
                              t.state == TaskState.active &&
                              t.id == snap.focus!.anchorTaskId)) ...[
                        const SizedBox(height: Space.lg),
                        _FocusStrip(snapshot: snap),
                      ],
                      if (snap.nextStep != null) ...[
                        const SizedBox(height: Space.lg),
                        _AnchorStrip(next: snap.nextStep!),
                      ],
                      // Die Regel bekommt die Karte, die laufende Aufgabe
                      // diesen Streifen. Ohne ihn wäre sie in genau dem
                      // Moment unsichtbar, in dem etwas anderes
                      // dazwischenkommt — und das ist der Moment, in dem man
                      // sie am ehesten vergisst.
                      if (snap.decision != null && snap.decisionRule != null)
                        for (final task in snap.tasks
                            .where((t) => t.state == TaskState.active)) ...[
                          const SizedBox(height: Space.lg),
                          _RunningStrip(task: task),
                        ],
                      // Steht direkt über der Handlung, weil er sie
                      // mitbestimmt: Was hier vorgeschlagen wird, hängt am
                      // gesetzten Ort. Ein Filter, den man nicht sieht, wirkt
                      // wie ein Fehler (G2).
                      //
                      // Erscheint nur, wenn es etwas zu sehen gibt — solange
                      // keine Aufgabe einen Ort trägt und keiner gesetzt ist,
                      // ist die Zeile eine Einstellung ohne Wirkung, und die
                      // gehört nicht auf den Hauptbildschirm (D3).
                      if (snap.place != null ||
                          snap.tasks
                              .any((t) => t.place != null && isTaskOpen(t))) ...[
                        const SizedBox(height: Space.lg),
                        _PlaceStrip(snapshot: snap),
                      ],
                      const SizedBox(height: Space.xl),
                      _PrimaryAction(snapshot: snap),
                    ],
                  ),
                ),
                // Der Horizont. Seine Zahl ist die Kapazität — sinkt sie,
                // sinkt mehr vom Tag unter die Kante, ganz ohne einen Satz
                // darüber (G1, R7).
                ReachEdge(capacity: snap.state.capacity),
                _Below(snapshot: snap, inboxCount: inbox.length),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCaptureSheet(context),
        backgroundColor: context.axiom.signal,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        // Material gibt einem FAB Stufe 6 mit reinschwarzem Schatten (der
        // Schattenton kommt aus `ThemeData.shadowColor`, nicht aus der
        // Palette, und laesst sich am Knopf nicht setzen). Auf dem warmen
        // Grund dieser Palette las sich das als harter schwarzer Ring um den
        // Knopf, nicht als Hoehe.
        //
        // Ohne Erhebung: Die Griffhoehe dieses Schirms gehoert der einen
        // Handlung (G1). Der Erfassungsknopf ist immer da, hebt sich durch
        // seine Farbe deutlich genug ab und muss nicht zusaetzlich schweben.
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        icon: const Icon(Icons.add),
        label: Text(context.t('Erfassen')),
      ),
    );
  }
}

// ── Kopfzeile ───────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _Header({required this.snapshot});

  /// Wochentage und Monate als Funktion, nicht als Konstante: Sie haengen
  /// an der eingestellten Sprache wie jeder andere Text auch.
  static List<String> _weekdays(BuildContext c) => [
        c.t('Montag'), c.t('Dienstag'), c.t('Mittwoch'), c.t('Donnerstag'),
        c.t('Freitag'), c.t('Samstag'), c.t('Sonntag'),
      ];

  static List<String> _months(BuildContext c) => [
        c.t('Januar'), c.t('Februar'), c.t('März'), c.t('April'),
        c.t('Mai'), c.t('Juni'), c.t('Juli'), c.t('August'),
        c.t('September'), c.t('Oktober'), c.t('November'), c.t('Dezember'),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final p = context.axiom;
    final baseline = ref.watch(baselineProvider).value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hier stand `.toUpperCase()` auf Wochentag und Monat:
              // „MONTAG 3. AUGUST". Achtzehn Grossbuchstaben sind der erste
              // Text des Tages, und die Wortform faellt dabei weg — man liest
              // Buchstabe fuer Buchstabe. Normale Schreibweise ist schneller
              // und leiser, und die Zeile ist ohnehin nur Einordnung.
              Text(
                '${_weekdays(context)[now.weekday - 1]} '
                '${now.day}. ${_months(context)[now.month - 1]}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: Space.xs),
              Text(
                _greeting(context, now.hour),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ],
          ),
        ),
        // Der Hinweis bleibt, bis geeicht ist — er verschwindet nicht
        // ausgerechnet dann, wenn er relevant wird.
        if (baseline != null &&
            baseline.status == BaselineStatus.collecting)
          // Flexible mit Ellipse: Bei grosser Schrift ist die Marke breiter
          // als der Platz, den die Begruessung uebrig laesst.
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.xs),
              decoration: BoxDecoration(
                color: p.info.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              // War Schreibmaschine in 10 px. Der Tageszaehler ist ein
              // Messwert und laeuft jetzt mit Tabellenziffern in der
              // Hausschrift — derselbe saubere Ziffernstand, ohne den Ton
              // eines Terminalprotokolls.
              child: Text(context.t('Baseline Tag {0}', [baseline.day]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: readingStyle(context,
                      size: 12.5, weight: FontWeight.w600, color: p.info)),
            ),
          ),
      ],
    );
  }

  static String _greeting(BuildContext context, int hour) => switch (hour) {
        < 5 => context.t('Noch wach.'),
        < 11 => context.t('Morgen.'),
        < 14 => context.t('Mittag.'),
        < 18 => context.t('Nachmittag.'),
        < 22 => context.t('Abend.'),
        _ => context.t('Spät.'),
      };
}

// ── Die eine Handlung ───────────────────────────────────────────────────

class _PrimaryAction extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _PrimaryAction({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = snapshot.decision;
    final rule = snapshot.decisionRule;
    final candidate = snapshot.atomizeCandidates.firstOrNull;
    final next = snapshot.startable.firstOrNull;


    // Eine Regel hat gefeuert — sie gewinnt vor jedem eigenen Vorschlag.
    //
    // Aber: Die Aktion bestimmt, WAS gezeigt wird. Eine Regel, die zerlegen
    // will, muss die Zerlegung anbieten — nicht eine allgemeine Karte mit
    // ihrem Titel. Sonst ist die Ausgabe formal korrekt und praktisch
    // wertlos: Man liest, was zu tun waere, und kann es nicht tun (G1).
    if (decision != null && rule != null) {
      return switch (rule.then.type) {
        ActionType.forceAtomize when candidate != null =>
          _AtomizeCard(candidate: candidate, rule: rule),
        ActionType.suggestTask when next != null =>
          _TaskCard(task: next, rule: rule),
        _ => _DecisionCard(decision: decision, rule: rule),
      };
    }

    // Eine angefangene Aufgabe schlägt jeden eigenen Vorschlag — aber
    // keine Regel.
    //
    // Sie fiel vorher aus der Auswahl heraus (`startable` kennt nur
    // `ready`) und war damit weg: nicht abschließbar, nicht auffindbar,
    // nirgends sichtbar [D9]. Sie hier vor die Regeln zu setzen wäre
    // allerdings der nächste Fehler: Eine feuernde Regel ist die Instanz,
    // die entscheidet, und ein Termin in zehn Minuten schlägt jede laufende
    // Vertiefung. Feuert eine, steht die laufende Aufgabe stattdessen als
    // Streifen darüber — sichtbar, nur nicht als Handlung.
    final running = snapshot.tasks
        .where((t) => t.state == TaskState.active)
        .firstOrNull;
    if (running != null) return _RunningCard(task: running);

    if (next != null) return _TaskCard(task: next);

    // Nichts startbar, aber etwas wartet: zerlegen statt anmahnen (M2, D2).
    if (candidate != null) return _AtomizeCard(candidate: candidate);

    return _EmptyState(snapshot: snapshot);
  }
}

/// Die Marke ueber der einen Handlung.
///
/// Hier stand „JETZT" in gesperrten Versalien. Die Marke ist kurz genug, dass
/// Versalien erlaubt waeren — aber sie steht ueber der groessten Zeile des
/// Schirms, und zwei verschiedene Schreibweisen direkt uebereinander lesen
/// sich als zwei Stimmen. Farbe traegt hier, was vorher die Sperrung tragen
/// sollte: Die Marke der aktuellen Handlung ist die einzige Beschriftung des
/// Schirms in [AxiomPalette.signal].
class _ActionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _ActionLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: sectionStyle(context, color: color ?? context.axiom.signal),
      );
}

/// Die Aufgabe, die gerade läuft.
///
/// Solange sie läuft, ist sie die Ausgabe — kein Vorschlag daneben, keine
/// Auswahl. Zwei Wege hinaus, beide gleich leicht: fertig oder zurück in
/// den Bestand. Der Rückweg ist absichtlich genauso prominent wie der
/// Abschluss; etwas anzufangen und nicht zu beenden ist der Normalfall und
/// bekommt hier keinen Kommentar [D10].
class _RunningCard extends ConsumerWidget {
  final Task task;
  const _RunningCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final session = ref.watch(snapshotProvider).value?.focus;
    final focus = session?.anchorTaskId == task.id ? session : null;
    final elapsed = focus?.elapsed(ref.watch(nowProvider));

    return Panel(
      // Griffhoehe statt Rahmen: Was jetzt in die Hand geht, liegt oben.
      // Der farbige Rahmen, der hier stand, sagte dasselbe noch einmal und
      // machte die Karte zu einer von vielen gerahmten (siehe Kopfkommentar).
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _ActionLabel(context.t('Läuft'), color: p.calm)),
              if (elapsed != null && focus != null)
                Text(
                  context.t('{0} von {1} min',
                      [elapsed.inMinutes, focus.planned.inMinutes]),
                  style: readingStyle(context, size: 14, color: p.calm),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(task.title, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              // Gleich breit, nicht 2:1 — der Rueckweg ist absichtlich
              // genauso prominent wie der Abschluss. Im schmalen Drittel
              // brach „Zurücklegen" ausserdem mitten im Wort um.
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.completeTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Erledigt')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.releaseTask(task);
                    await HapticFeedback.selectionClick();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Zurücklegen')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends ConsumerWidget {
  final Decision decision;
  final Rule rule;
  const _DecisionCard({required this.decision, required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final isCheckin = rule.then.type == ActionType.promptCheckin;

    return Panel(
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionLabel(context.t('Jetzt')),
          const SizedBox(height: Space.sm),
          Text(context.ruleTitle(rule),
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RuleStamp(
                ruleId: rule.id,
                color: p.signal,
                onTap: () => _showRationale(context, rule, decision),
              ),
              if (rule.deficit != null)
                Text(rule.deficit!,
                    style: readingStyle(context,
                        size: 12.5, color: p.inkFaint)),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              // 3:2 statt 2:1. Bei 360 px logischer Breite brach die zweite
              // Beschriftung sonst mitten im Wort um („Erledi/gt"). Die
              // gemeinte Handlung bleibt dominant, weil sie gefuellt ist und
              // zuerst steht — nicht, weil sie doppelt so breit waere.
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    if (isCheckin && context.mounted) {
                      final done = await showCheckinSheet(context,
                          slot: rule.then.params['slot'] as String? ?? 'manual');
                      if (!done) return;
                    }
                    await runtime.respondTo(decision, DecisionResponse.followed);
                    refreshAxiom(ref);
                  },
                  child: Text(isCheckin
                      ? context.t('Check-in machen')
                      : context.t('Verstanden')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.respondTo(decision, DecisionResponse.deferred);
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Später')),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Center(
            child: TextButton(
              onPressed: () async {
                final runtime = await ref.read(runtimeProvider.future);
                await runtime.respondTo(decision, DecisionResponse.rejected);
                refreshAxiom(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          context.t('Notiert. Diese Regel meldet sich seltener.')),
                    ),
                  );
                }
              },
              child: Text(context.t('Passt nicht')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final Task task;

  /// Die Regel, die das ausgeloest hat — falls es eine gab.
  final Rule? rule;

  const _TaskCard({required this.task, this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionLabel(context.t('Jetzt')),
          const SizedBox(height: Space.sm),
          Text(task.title, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          // War eine `Row`: Bei grosser Schrift lief die Plakettenzeile nach
          // rechts hinaus. `Wrap` bricht stattdessen um.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Tag(label: context.t('Start {0}/10', [task.activationEnergy])),
              if (rule != null) RuleStamp(ruleId: rule!.id, color: p.info),
              if (task.decayAt != null)
                _Tag(
                  label: _until(context, task.decayAt!, ref.watch(nowProvider)),
                  color: p.info,
                ),
              // Ohne gesetzten Ort wird eine ortsgebundene Aufgabe nicht
              // unterdrückt — sie steht mit ihrem Ort da. Etwas zu
              // verstecken, das der Nutzer nie eingeschaltet hat, wäre der
              // schlimmere Fehler [D9].
              if (task.place != null) _Tag(label: task.place!),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              // Siehe `_DecisionCard`: 3:2, sonst bricht „Erledigt" bei
              // 360 px um.
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.startTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Anfangen')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.completeTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Erledigt')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _until(BuildContext context, DateTime when, DateTime now) {
    final diff = when.difference(now);
    if (diff.isNegative) return context.t('ÜBERFÄLLIG');
    if (diff.inHours < 24) return context.t('IN {0} H', [diff.inHours]);
    return context.t('IN {0} T', [diff.inDays]);
  }
}

/// Wichtig, aber außer Reichweite. Statt anzumahnen wird zerlegt.
///
/// Das ist der Bruch mit dem üblichen Muster: Andere Apps zeigen die Aufgabe
/// weiter oben an und markieren sie irgendwann rot. Beides macht den Start
/// unwahrscheinlicher, weil Schuld die Regulationsreserve senkt [D2, D10].
class _AtomizeCard extends ConsumerWidget {
  final AtomizeCandidate candidate;

  /// Die Regel, die das ausgeloest hat — falls es eine gab.
  final Rule? rule;

  const _AtomizeCard({required this.candidate, this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionLabel(context.t('ZU GROSS FÜR HEUTE'),
                    color: p.info),
              ),
              if (rule != null) RuleStamp(ruleId: rule!.id, color: p.info),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(candidate.task.title,
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          Text(candidate.explanation,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () async {
              final done = await showAtomizeSheet(context, candidate);
              if (done) refreshAxiom(ref);
            },
            child: Text(context.t('In einen ersten Schritt zerlegen')),
          ),
          const SizedBox(height: Space.xs),
          Center(
            child: TextButton(
              onPressed: () async {
                final runtime = await ref.read(runtimeProvider.future);
                await runtime.dropTask(candidate.task);
                refreshAxiom(ref);
              },
              child: Text(context.t('Fällt weg')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leerzustand. Fuehrt zur naechsten Handlung, statt Leere zu zeigen.
class _EmptyState extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _EmptyState({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final hasTasks = snapshot.tasks.any((t) => t.state == TaskState.ready);
    final blocked = hasTasks && snapshot.startable.isEmpty;
    // Wartet alles Offene auf etwas anderes, ist die Begründung eine andere:
    // Nicht die Startenergie hält zurück, sondern eine Abhängigkeit. Den
    // falschen Grund zu nennen ist schlimmer als keinen (G2).
    final waiting = blocked &&
        snapshot.waiting.isNotEmpty &&
        snapshot.waiting.length ==
            snapshot.tasks.where((t) => t.state == TaskState.ready).length;

    // Ohne Handlung wird nichts erhoben: Die Karte liegt auf dem Grund. Eine
    // hervorgehobene Flaeche, die nichts anbietet, waere ein Versprechen
    // ohne Einloesung (G1).
    return Panel(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionLabel(
            waiting
                ? context.t('ALLES WARTET')
                : blocked
                    ? context.t('Nichts in Reichweite')
                    : context.t('Nichts anliegend'),
            color: p.inkFaint,
          ),
          const SizedBox(height: Space.md),
          Text(
            waiting
                ? context.t('Alles Offene hängt an etwas anderem.')
                : blocked
                    ? context.t('Heute liegt nichts unter der Linie.')
                    : context.t('Ruhig gerade.'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: Space.md),
          Text(
            waiting
                ? context.t('Jede offene Aufgabe wartet auf einen Blocker, der selbst noch aussteht. Die Aufgabenliste zeigt, worauf.')
                : blocked
                    ? context.t('Alles Offene braucht mehr Anlauf, als heute da ist. Das ist eine Messung, keine Bewertung. Eine Aufgabe in kleinere Schritte zu zerlegen hilft mehr als Anlauf nehmen.')
                    : context.t('Kein Vorschlag heißt: gerade ist nichts nötig. Was dir einfällt, kannst du unten erfassen.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (blocked) ...[
            const SizedBox(height: Space.lg),
            // Ziel ist die Aufgabenliste, nicht der Eingang: Dort steht,
            // was außer Reichweite liegt, und dort führt jede Zeile ihren
            // eigenen Weg ins Zerlegen. Der Eingang enthält Erfasstes —
            // dort war nichts zu zerlegen, und der Weg endete im Nichts.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
              ),
              icon: Icon(waiting ? Icons.link : Icons.call_split,
                  size: 18, color: p.signal),
              label: Text(waiting
                  ? context.t('Ansehen, was wartet')
                  : context.t('Aufgabe zerlegen')),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Die Mulde ───────────────────────────────────────────────────────────

/// Alles unter der Reichweitenkante.
///
/// **Ohne Karten.** Was hier steht, ist da und heute nicht die Handlung —
/// Bestand, Eingang, Termine, Rueckblick, Vorfaelle, Werkzeuge, Koerper.
/// Vorher war jeder dieser Punkte eine eigene gerahmte Kachel, und
/// untereinander gelesen sahen sie aus wie sechs Angebote neben dem einen,
/// das gemeint war.
///
/// **Und ohne Ausgrauen.** Der Text behaelt seine Rollen und damit seinen
/// vollen Kontrast; [AxiomPalette.well] ist dafuer eigens knapp bemessen.
/// Ausgegraut hiesse „unwichtig"; gemeint ist „heute nicht die Handlung".
///
/// **Zwei Aenderungen an der Informationsarchitektur, beide mit Folgen:**
///
/// 1. **Die drei Messbalken sind weg.** Hier standen Kapazitaet,
///    Kompensationslast und Reizbedarf als `InstrumentBar` — dieselben
///    Balken, dieselben Zahlen und dieselbe aufklappbare Herleitung wie auf
///    dem Zustandsschirm, der einen Reiter weiter liegt. Der Kopfkommentar
///    dieser Datei sagt seit dem Umbau, die Kapazitaetsleiste sei
///    weggefallen, weil zwei Anzeigen desselben Messwerts sich als zwei
///    Aussagen lesen (R7) — genau das stand hier aber weiter: „Reichweite
///    heute 61" ueber der Kante und „Kapazitaet 61" drei Zentimeter
///    darunter. Ein Messwert hat einen Ort. Der Ort ist der Reiter
///    „Zustand"; die Kante nennt die Zahl, die den Tag begrenzt, und mehr
///    braucht dieser Schirm nicht.
/// 2. **Feste Plaetze statt Zeilen, die kommen und gehen.** Bestand,
///    Eingang, Rueckblick und Vorfaelle stehen immer, in immer derselben
///    Reihenfolge; was fehlt, sagt die Zeile in ihrer zweiten Zeile.
///    Vorher erschienen sie nur bei Inhalt — mit der Folge, dass der
///    Rueckblick ausserhalb seines Faelligkeitsfensters und die
///    Ankerverwaltung ohne bereits angelegten Anker **gar nicht erreichbar**
///    waren. Ein Weg, den es nur manchmal gibt, wird jedes Mal neu gesucht
///    [D9]; eine Zeile, die „nichts" meldet, liest man einmal.
class _Below extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  final int inboxCount;

  const _Below({required this.snapshot, required this.inboxCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final s = snapshot.state;
    final pending = ref.watch(pendingPostMortemsProvider).value ?? const [];
    final due = ref.watch(dueReviewProvider).value;
    final baseline = ref.watch(baselineProvider).value;

    final open =
        snapshot.tasks.where((t) => t.state == TaskState.ready).toList();
    final inReach = open
        .where((t) =>
            !snapshot.isWaiting(t.id) &&
            t.isStartable(s.capacity, atPlace: snapshot.place))
        .length;
    final beyond = open.length - inReach;

    // Der Rueckblick laeuft auch ausserhalb seines Fensters — dann eben als
    // Tagesrueckblick. Er war vorher an `due != null` gebunden und damit
    // nach dem Abhaken bis zum naechsten Tag nirgends mehr zu oeffnen,
    // obwohl der Schirm die Zahlen der letzten Tage zeigt.
    final reviewScope = due ?? ReviewScope.day;

    final passages = <Widget>[
      _WellRow(
        icon: Icons.checklist_outlined,
        title: context.t('Aufgaben'),
        // Dieselben Zahlen wie auf der Aufgabenliste, aus derselben
        // Bedingung gerechnet. Zwei Schirme, die verschiedene Staende
        // melden, kosten mehr Vertrauen, als beide zusammen aufbauen.
        detail: switch ((inReach, beyond)) {
          (0, 0) => context.t('Noch keine Aufgaben erfasst.'),
          (0, final b) => context.t('Nicht in Reichweite · {0}', [b]),
          (final r, 0) => context.t('In Reichweite · {0}', [r]),
          (final r, final b) => context.t(
              '{0} startbar · {1} heute außerhalb der Reichweite', [r, b]),
        },
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
        ),
      ),
      _WellRow(
        icon: Icons.inbox_outlined,
        title: context.t('Eingang'),
        detail: inboxCount == 0
            ? context.t('Nichts zu sortieren.')
            : context.t('{0} {1} auf Sortieren', [
                inboxCount,
                inboxCount == 1
                    ? context.t('Notiz wartet')
                    : context.t('Notizen warten'),
              ]),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const InboxScreen()),
        ),
      ),
      // Nur, wenn oben kein Schritt steht: Steht einer, traegt ihn der
      // Streifen ueber der Kante, und der fuehrt auf denselben Schirm. Zwei
      // Wege zum selben Ort auf einem Bildschirm sind einer zu viel.
      if (snapshot.nextStep == null)
        _WellRow(
          icon: Icons.schedule_outlined,
          title: context.t('Anker'),
          detail: snapshot.anchors.isEmpty
              ? context.t('Kein Termin hinterlegt.')
              : context.t('{0} hinterlegt, keiner steht heute an',
                  [snapshot.anchors.length]),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AnchorsScreen()),
          ),
        ),
      _WellRow(
        icon: Icons.done_all,
        // Der eingesetzte Wert lief hier nicht durch die Uebersetzung — in
        // der englischen App stand „Woche review". Ein Platzhalterwert ist
        // Nutzertext wie jeder andere.
        title: context.t('{0}-Review', [context.t(reviewScope.label)]),
        detail: due != null
            ? context.t('Fällig · {0} min', [reviewScope.timeCap.inMinutes])
            : context.t('Zahlen des Tages · {0} min',
                [reviewScope.timeCap.inMinutes]),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => ReviewScreen(scope: reviewScope)),
        ),
      ),
      _WellRow(
        icon: Icons.history_toggle_off,
        title: context.t('Vorfälle'),
        detail: switch (pending.length) {
          0 => context.t('Emotionale Spitzen festhalten und einordnen'),
          1 => context.t('Ein Vorfall wartet auf Einordnung'),
          final n => context.t('{0} Vorfälle warten auf Einordnung', [n]),
        },
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SignalScreen()),
        ),
      ),
      // Die einzige Zeile ohne festen Platz — sie meldet ein *Ereignis*,
      // keinen Ort, und verschwindet nach dem Eichen fuer immer.
      if (baseline != null && baseline.isReady)
        _WellRow(
          icon: Icons.tune,
          title: context.t('Baseline vollständig'),
          detail: context.t('Die Gewichte können jetzt geeicht werden.'),
          accent: p.signal,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SystemScreen()),
          ),
        ),
    ];

    return Well(
      // Vollflaechig: Die Mulde ist der Boden des Schirms, nicht ein
      // weiterer Kasten darauf.
      radius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.lg, Space.lg, Space.huge * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in passages.indexed) ...[
            if (i > 0) Divider(color: p.rule, height: 1),
            row,
          ],
          const SizedBox(height: Space.xxl),
          SectionLabel(context.t('Werkzeuge')),
          _Tools(snapshot: snapshot),
          const SizedBox(height: Space.xxl),
          SectionLabel(context.t('Körper')),
          const BodyStrip(),
          const SizedBox(height: Space.xxl),
          _MetaBudget(used: snapshot.metaUsedToday),
        ],
      ),
    );
  }
}

/// Eine Zeile in der Mulde: Symbol, Name, Stand, Pfeil.
///
/// Kein `Panel`: In der Tiefzone gibt es keine Karten. Getrennt wird durch
/// eine Haarlinie, nicht durch eine Kante — sechs Kacheln untereinander
/// waeren wieder ein Gitter.
class _WellRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  /// Faerbt Symbol und Pfeil. Nur fuer den einen Fall, in dem die Zeile
  /// etwas meldet, das ohne sie unbemerkt bliebe (die fertige Baseline).
  final Color? accent;

  const _WellRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent ?? p.inkDim),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
          ],
        ),
      ),
    );
  }
}

// ── Nebenelemente ───────────────────────────────────────────────────────

/// Die geltende Last-Stufe, wenn sie über L0 liegt (M9).
///
/// Steht ganz oben, weil sie alles darunter verändert: Was vorgeschlagen
/// wird, wie lang Fokusblöcke sein dürfen, ob Optionales überhaupt
/// erscheint. Eine Einschränkung, deren Grund man nicht sieht, wirkt
/// willkürlich (G2).
class _RegimeBanner extends StatelessWidget {
  final AxiomSnapshot snapshot;
  const _RegimeBanner({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final regime = snapshot.regime;
    final color = p.forLoadLevel(regime.level.index);

    // Der einzige Rahmen dieses Schirms — und der einzige zulaessige Fall:
    // Die Karte meldet einen *Zustand*, kein Messwert (siehe `Panel.accent`).
    return Panel(
      accent: color.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                // Zwei Zeichen — hier bleiben Versalien, weil sie keine Wortform
                // haben, die verlorengehen koennte.
                child: Text(regime.level.name.toUpperCase(),
                    style: readingStyle(context,
                        size: 12.5, weight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(context.t(regime.headline),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(context.t(regime.description),
              style: Theme.of(context).textTheme.bodyMedium),
          if (snapshot.suggestsReferral) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: p.well,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(
                context.t('Die Last ist seit über zwei Wochen auf diesem Niveau. AXIOM misst nur — für die Einordnung ist ärztliche oder psychotherapeutische Abklärung der richtige Weg.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ein Streifen ueber der Handlung: eine Zeile, ein Tipp, kein Angebot.
///
/// Alle Streifen dieses Schirms teilen sich diese Form. Vorher hatte jeder
/// seinen eigenen farbigen Rahmen und seine eigene Innenaufteilung — und
/// jeder sah damit aus wie eine zweite Handlung neben der einen (G1). Jetzt
/// liegen sie flach auf dem Grund; erhoben ist nur die Karte darunter.
class _Strip extends StatelessWidget {
  final IconData icon;

  /// Faerbt das Symbol und den Messwert rechts. Ohne Angabe: gedaempft.
  final Color? accent;
  final String title;
  final String detail;

  /// Zahl am rechten Rand — ein Messwert, kein Zusatz.
  final String? reading;
  final VoidCallback? onTap;

  const _Strip({
    required this.icon,
    required this.title,
    required this.detail,
    this.accent,
    this.reading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent ?? p.inkDim),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (reading != null) ...[
            const SizedBox(width: Space.md),
            Text(reading!,
                style: readingStyle(context,
                    size: 15, color: accent ?? p.inkDim)),
          ],
          if (onTap != null) ...[
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
          ],
        ],
      ),
    );
  }
}

/// Laufender Fokusblock mit dem Urteil des Governors (M4).
class _FocusStrip extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _FocusStrip({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final session = snapshot.focus!;
    final verdict = snapshot.focusVerdict;
    final elapsed = session.elapsed(ref.watch(nowProvider));
    final urgent = verdict?.action == FocusAction.hardStop ||
        verdict?.action == FocusAction.clearInterrupt;

    return _Strip(
      icon: Icons.center_focus_strong_outlined,
      accent: urgent ? p.signal : p.calm,
      title: session.anchorTitle ?? context.t('Fokus läuft'),
      detail: verdict == null ? context.t('Läuft.') : context.p(verdict.reason),
      reading: context.t('{0} min', [elapsed.inMinutes]),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FocusScreen()),
      ),
    );
  }
}

/// Der gesetzte Ort — eine Zeile, ein Tipp.
///
/// Kein eigener Bildschirm und keine Ortsverwaltung: Der Ort ist ein
/// Schalter, kein Datensatz. Ein Tipp öffnet die Auswahl, ein zweiter setzt
/// ihn — „kein Ort" steht dort immer an erster Stelle, und der zuletzt
/// gesetzte gleich darunter.
class _PlaceStrip extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _PlaceStrip({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final place = snapshot.place;
    final elsewhere = snapshot.elsewhere.length;

    return _Strip(
      icon: place == null ? Icons.place_outlined : Icons.place,
      accent: place == null ? null : p.signal,
      title: place ?? context.t('Kein Ort'),
      // Zustandsbeschreibung, keine Bewertung: Was der Filter gerade tut,
      // steht da — nicht, was man tun sollte [R7].
      detail: place == null
          ? context.t('Alles steht zur Auswahl.')
          : elsewhere == 0
              ? context.t('Nichts liegt woanders.')
              : elsewhere == 1
                  ? context.t('Eine Aufgabe gehört woanders hin.')
                  : context.t('{0} Aufgaben gehören woanders hin.', [elsewhere]),
      onTap: () => showPlaceSheet(
        context,
        current: place,
        known: snapshot.knownPlaces,
      ),
    );
  }
}

/// Laufende Wartezeit eines Impuls-Abfangs (M6).
class _InterceptStrip extends ConsumerWidget {
  final InterceptRun run;
  const _InterceptStrip({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final released = !run.isActive(now);

    return _Strip(
      icon: released ? Icons.lock_open : Icons.hourglass_bottom,
      accent: p.signal,
      title: run.triggerLabel,
      detail: released
          ? context.t('Wartezeit vorbei')
          : context.t('Wartezeit läuft'),
      reading:
          released ? null : context.t('{0} min', [run.remaining(now).inMinutes]),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InterceptScreen()),
      ),
    );
  }
}

/// Die laufende Aufgabe, während eine Regel die Hauptkarte belegt.
///
/// Schmal und ohne Knöpfe: Sie ist hier kein Angebot, sondern eine
/// Erinnerung daran, dass etwas offen ist. Der Tipp führt zur Liste, wo sie
/// sich abschließen lässt.
class _RunningStrip extends ConsumerWidget {
  final Task task;
  const _RunningStrip({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Strip(
        icon: Icons.play_circle_outline,
        accent: context.axiom.calm,
        title: task.title,
        detail: context.t('Läuft'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
        ),
      );
}

/// Zugang zu Fokus, Reiz und Bremse.
///
/// Bewusst nicht als eigene Navigationsreiter: Drei Ziele in der Navigation,
/// nicht sechs. Jeder weitere Reiter ist eine Entscheidung, die vor dem
/// eigentlichen Tun steht (G1).
///
/// **War eine Leiste aus drei gerahmten Kacheln.** Zwei Dinge stimmten daran
/// nicht. Erstens die Grammatik: In der Mulde gibt es keine Kaesten — alles
/// andere hier ist eine Zeile mit Symbol, Namen, Stand und Pfeil, und drei
/// gerahmte Quadrate mittendrin lasen sich als etwas anderer Art. Zweitens
/// stand unter jedem Symbol nur ein Wort. „Reiz" sagt nicht, was dahinter
/// liegt; eine Zeile hat Platz fuer den Stand, und der ist die eigentliche
/// Auskunft.
///
/// **Was dabei weggefallen ist:** Der Reiz-Knopf leuchtete kupfern, sobald
/// der Reizbedarf ueber 70 lag. Das ist eine Farbe an einem Messwert, und
/// Messwerte bekommen in AXIOM keine Note (R7). Wenn der Bedarf hoch genug
/// ist, um etwas zu tun, sagt das eine Regel mit Kennung ueber der Kante —
/// das ist der Weg, den G2 vorsieht. Gefaerbt wird hier nur noch, was
/// tatsaechlich *laeuft*: ein Zustand, keine Messung.
class _Tools extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _Tools({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final focus = snapshot.focus;
    final intercept = snapshot.activeIntercept;
    final now = ref.watch(nowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WellRow(
          icon: Icons.center_focus_strong_outlined,
          title: context.t('Fokus'),
          detail: focus == null
              ? context.t('Vertiefung mit Zeitdeckel und Ausstiegsanker')
              : context.t('Läuft seit {0} min', [focus.elapsed(now).inMinutes]),
          accent: focus == null ? null : p.calm,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FocusScreen()),
          ),
        ),
        Divider(color: p.rule, height: 1),
        _WellRow(
          icon: Icons.bolt_outlined,
          title: context.t('Reiz'),
          detail: context.t('Kanäle, Budget und der nächste geplante Slot'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SensationScreen()),
          ),
        ),
        Divider(color: p.rule, height: 1),
        _WellRow(
          icon: Icons.pan_tool_outlined,
          title: context.t('Bremse'),
          detail: intercept == null
              ? context.t('Wartezeit zwischen Impuls und Handlung')
              : context.t('Wartezeit läuft'),
          accent: intercept == null ? null : p.signal,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const InterceptScreen()),
          ),
        ),
      ],
    );
  }
}

/// Der nächste Ankerschritt, direkt unter dem Datum.
///
/// Steht bewusst über allem anderen: Ein Schritt mit Uhrzeit ist die einzige
/// Sache auf diesem Screen, die durch Warten teurer wird [D4].
class _AnchorStrip extends ConsumerWidget {
  final ({Anchor anchor, AnchorStep step}) next;
  const _AnchorStrip({required this.next});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);

    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AnchorsScreen()),
      ),
      child: NextStepBadge(
        anchor: next.anchor,
        step: next.step,
        now: now,
      ),
    );
  }
}

/// Zeigt das Meta-Work-Budget. Die App macht ihre eigenen Kosten sichtbar —
/// wenn sie mehr Zeit frisst als sie spart, ist sie das Problem (M12).
class _MetaBudget extends StatelessWidget {
  final Duration used;
  const _MetaBudget({required this.used});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final ratio = (used.inSeconds / kMetaBudget.inSeconds).clamp(0.0, 1.0);
    final over = used >= kMetaBudget;

    // Beschriftung und Messwert oben, der Balken darunter über die volle
    // Breite. Vorher standen alle drei in einer Zeile, und beide Texte waren
    // unflexibel: Bei 360 px und angehobener Schrift lief die Zeile über —
    // der Balken wurde dabei auf null Breite geklemmt. Ausgerechnet die
    // Anzeige, die G4 sichtbar macht, zeigte dann gar keinen Füllstand
    // mehr. [D9]
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              // War „ZEIT IN AXIOM HEUTE" — sechzehn Grossbuchstaben unter
              // einem Schirm, der sonst keine mehr fuehrt.
              child: Text(context.t('Zeit im System heute'),
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            const SizedBox(width: Space.md),
            Text(
                context
                    .t('{0}/{1} min', [used.inMinutes, kMetaBudget.inMinutes]),
                style: readingStyle(context,
                    size: 13.5, color: over ? p.caution : p.inkFaint)),
          ],
        ),
        const SizedBox(height: Space.sm),
        Stack(
          children: [
            Container(height: 2, color: p.rule),
            LayoutBuilder(
              builder: (context, c) => Container(
                height: 2,
                width: c.maxWidth * ratio,
                color: over ? p.caution : p.inkFaint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Eine Plakette an der Handlung: Messwert oder Randbedingung.
///
/// War ein Kasten mit Haarlinienrahmen und Schreibmaschinenschrift in
/// 10,5 px. Beides ist weg: Der Rahmen zog ein Gitter durch die Zeile, und
/// „Start 2/10" ist ein Messwert — er gehoert in die Hausschrift mit
/// Tabellenziffern. Die Vertiefung ([AxiomPalette.well]) sagt dasselbe wie
/// der Rahmen, ohne eine Linie zu ziehen.
class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  const _Tag({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.md, vertical: Space.xs),
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(label,
          style: readingStyle(context,
              size: 12.5, weight: FontWeight.w600, color: color ?? p.inkDim)),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final Object error;
  const _ErrorPane({required this.error});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('System'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(context.t('AXIOM konnte nicht starten.'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            // Der einzige Monospace-Satz, der auf diesem Schirm uebrig
            // bleibt — und der einzige richtige: eine Roh-Ausgabe, die
            // jemand Zeichen fuer Zeichen abliest oder abtippt.
            Text('$error', style: monoStyle(context, size: 12.5)),
          ],
        ),
      );
}

void _showRationale(BuildContext context, Rule rule, Decision decision) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final p = context.axiom;
      return AlertDialog(
        title: Row(
          children: [
            RuleStamp(ruleId: rule.id, color: p.signal),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(context.ruleTitle(rule),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t('Warum es sie gibt'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.sm),
              Text(decision.explanation,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  _Tag(label: context.t('Stufe {0}', [rule.severity.name])),
                  _Tag(label: context.t('Priorität {0}', [rule.priority])),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Schließen')),
          ),
        ],
      );
    },
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
