/// Alle Aufgaben — der Überblick, den „Jetzt" bewusst nicht gibt.
///
/// **Warum es das gibt, obwohl G1 keine Liste zur Auswahl erlaubt.** Das
/// Gesetz verbietet, die Entscheidung *im Moment* an eine Liste zu delegieren
/// — nicht, den Bestand zu kennen. Beides sind verschiedene Tätigkeiten:
/// Planen ist etwas anderes als Entscheiden, und wer nie sieht, was
/// eingetragen ist, vertraut dem System nicht (D9). Was ohne diese Ansicht
/// passiert, ist absehbar: Man führt daneben eine zweite Liste im Kopf.
///
/// **Was sie deshalb nicht ist.** Nicht der Startbildschirm, nicht der Weg,
/// über den normalerweise gearbeitet wird, und ohne Sortierregler,
/// Filterleiste oder Ansichtswechsel — das wäre Meta-Work mit Aussicht (D3).
/// Die Reihenfolge ist die des Systems, dieselbe wie bei der Auswahl, und
/// sie ist nicht verstellbar.
///
/// ---
///
/// **Die Reichweitenkante.** Dieser Schirm ist ihr eigentlicher Ort. Vorher
/// standen hier sechs gleich aussehende Abschnitte untereinander, jeder aus
/// gerahmten Kästen mit demselben Knopfsatz — „In Reichweite" und „Nicht in
/// Reichweite" unterschieden sich in nichts als der Überschrift. Der
/// wichtigste Unterschied des ganzen Bildschirms war damit der leiseste.
///
/// Jetzt trägt ihn die Form:
///
///  * **Über der Kante** schweben Karten mit Schatten — was heute in die
///    Hand geht. Sie tragen ihre Knöpfe.
///  * **Unter der Kante** beginnt die Mulde: keine Karten, keine Rahmen —
///    und **kein Ausgrauen**. Der Text behält seinen vollen Kontrast.
///    Ausgegraut hieße „unwichtig"; gemeint ist „heute nicht erreichbar",
///    und der Unterschied ist der ganze Punkt (R7, D10).
///  * Die einzige farbige Handlung in der Tiefzone ist **„Zerlegen"**. Das
///    ist der Weg nach oben, und er ist der einzige, der angeboten wird.
///    „Anfangen" fällt dort weg: Es war ein Angebot, das die Messung
///    daneben im selben Atemzug zurücknahm (G1).
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'atomize_sheet.dart';

/// Kommazahl in der eingestellten Sprache.
///
/// „Anlauf 2.5 h" ist im Deutschen kein Messwert, sondern ein Tippfehler —
/// und ein Wert, ueber den man stolpert, wird nicht nachgerechnet (G2).
/// Beide Zahlen dieses Schirms liefen vorher ueber `toStringAsFixed` und
/// standen damit auf Deutsch mit Punkt da.
///
/// Dieselbe Rechnung steht als `_decimal` in `instruments.dart` fuer die
/// Herleitungstafel; sie ist dort dateiprivat. Wer beide zusammenlegt —
/// eine oeffentliche Fassung im Gestaltungsteil — streicht die hier.
String _decimal(BuildContext context, double value, {int digits = 1}) {
  final text = value.toStringAsFixed(digits);
  return context.language == AppLanguage.de ? text.replaceAll('.', ',') : text;
}

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);

    return MetaTimedScope(
      screen: 'tasks',
      child: Scaffold(
        appBar: AppBar(title: Text(context.t('Aufgaben'))),
        body: snapshot.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (snap) => _Body(snapshot: snap),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _Body({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = snapshot.state.capacity;
    final place = snapshot.place;

    List<Task> sorted(bool Function(Task) test) => snapshot.tasks
        .where(test)
        .toList()
      ..sort((a, b) => snapshot.scoreOf(b).compareTo(snapshot.scoreOf(a)));

    /// Wartet die Aufgabe auf einen offenen Blocker?
    ///
    /// Steht vor allen anderen Gründen: Warten ist die härteste Bedingung.
    /// Eine Aufgabe, die wartet und außerdem am falschen Ort liegt, gehört
    /// einmal in die Liste, nicht zweimal.
    bool waits(Task t) => snapshot.isWaiting(t.id);

    final running = sorted((t) => t.state == TaskState.active);
    final reachable = sorted((t) =>
        t.state == TaskState.ready &&
        !waits(t) &&
        t.isStartable(capacity, atPlace: place));
    final waiting = snapshot.waiting;
    // Eigener Abschnitt statt „nicht in Reichweite": Der Grund ist ein
    // anderer, und die Begründung darunter wäre schlicht falsch — die
    // Startenergie hat damit nichts zu tun. Die Menge kommt aus dem
    // Snapshot, damit „woanders" nur einmal definiert ist.
    final elsewhere = snapshot.elsewhere.where((t) => !waits(t)).toList();
    final outOfReach = sorted((t) =>
        t.state == TaskState.ready &&
        !waits(t) &&
        t.isHere(place) &&
        !t.isStartable(capacity));

    /// Titel einer Aufgabe zu ihrer ID — für „wartet auf: …".
    ///
    /// Eine ID im Klartext wäre eine Begründung, die niemand liest [G2].
    String titleOf(String id) {
      for (final task in snapshot.tasks) {
        if (task.id == id) return task.title;
      }
      return context.t('eine andere Aufgabe');
    }

    /// Worauf diese Aufgabe wartet. Eine Tatsache, kein Vorwurf.
    ///
    /// Bei mehreren Blockern steht der erste mit Namen da und der Rest als
    /// Zahl: Drei Titel nebeneinander wären wieder eine Liste zur Auswahl,
    /// und zu tun ist hier ohnehin nichts (G1).
    String waitingReason(Task task) {
      final blockers = snapshot.blockersOf(task.id).map(titleOf).toList();
      if (blockers.isEmpty) return '';
      if (blockers.length == 1) {
        return context.t('wartet auf: {0}', [blockers.first]);
      }
      if (blockers.length == 2) {
        return context.t('wartet auf: {0} und {1}', blockers);
      }
      return context.t(
          'wartet auf: {0} und {1} weitere', [blockers.first, blockers.length - 1]);
    }

    // Zerlegte Aufgaben standen hier bisher nirgends. Damit war die
    // Klammer nach dem Zerlegen unsichtbar: nicht auffindbar, nicht
    // abschließbar, nicht weiter zerlegbar — und wer seinen Bestand nicht
    // sieht, führt daneben eine zweite Liste im Kopf [D9].
    final split = sorted((t) => t.state == TaskState.blocked);
    final done = sorted((t) => t.state == TaskState.done);

    /// Wie viele Teilschritte einer Aufgabe stehen noch aus?
    int openSteps(Task parent) => snapshot.tasks
        .where((t) => t.parentId == parent.id && isTaskOpen(t))
        .length;

    if (snapshot.tasks.every((t) =>
        t.state != TaskState.active &&
        t.state != TaskState.ready &&
        t.state != TaskState.blocked &&
        t.state != TaskState.done)) {
      return const _Empty();
    }

    // Zeigt eine Aufgabe den Hebel? Nur dann steht die Formel darunter —
    // eine Formel, die immer sichtbar ist, wird nicht gelesen (G2).
    final showsLeverage =
        snapshot.tasks.any((t) => snapshot.links.unblocks(t.id) > 0);

    return ListView(
      // Kein Rand an der Liste: Die Mulde geht von Kante zu Kante. Die Zone
      // darüber bringt ihren Rand mit.
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('Die Reihenfolge ist die der Auswahl — dieselbe Formel, kein zweiter Maßstab. Sie lässt sich hier nicht umstellen.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.xl),
              if (running.isNotEmpty) ...[
                SectionLabel(context.t('Läuft')),
                for (final task in running)
                  _ReachCard(
                    task: task,
                    holdsUp: snapshot.links.unblocks(task.id),
                  ),
                const SizedBox(height: Space.lg),
              ],
              if (reachable.isNotEmpty) ...[
                SectionLabel(
                    context.t('In Reichweite · {0}', [reachable.length])),
                for (final task in reachable)
                  _ReachCard(
                    task: task,
                    place: place,
                    holdsUp: snapshot.links.unblocks(task.id),
                  ),
              ],
            ],
          ),
        ),
        // Der Horizont. Seine Zahl ist die Kapazität — sie sagt, wie weit
        // heute gegriffen werden kann, nicht wie gut jemand ist (R7).
        ReachEdge(capacity: capacity),
        _Deep(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.lg, Space.lg, Space.huge),
          children: [
            if (outOfReach.isNotEmpty)
              _DeepSection(
                label: context.t('Nicht in Reichweite · {0}',
                    [outOfReach.length]),
                // Kein Vorwurf, eine Messung: Die Startenergie liegt über
                // dem, was die heutige Kapazität trägt. Morgen kann das
                // anders sein [R7].
                note: context.t('Startenergie über der heutigen Kapazität ({0}). Zerlegen macht sie erreichbar.', [capacity]),
                rows: [
                  for (final task in outOfReach)
                    _DeepRow(
                      task: task,
                      place: place,
                      holdsUp: snapshot.links.unblocks(task.id),
                    ),
                ],
              ),
            // Wartet — nicht „blockiert": `blocked` heißt in AXIOM zerlegt.
            // Dasselbe Wort für zweierlei wäre der teuerste Namensfehler,
            // den dieses Modell machen kann.
            if (waiting.isNotEmpty)
              _DeepSection(
                label: context.t('Wartet · {0}', [waiting.length]),
                note: context.t('Diese Aufgaben hängen an einer anderen. Sie kommen zurück, sobald ihr letzter Blocker erledigt ist.'),
                rows: [
                  for (final task in waiting)
                    _DeepRow(
                      task: task,
                      place: place,
                      waitingFor: waitingReason(task),
                      holdsUp: snapshot.links.unblocks(task.id),
                    ),
                ],
              ),
            if (elsewhere.isNotEmpty)
              _DeepSection(
                label: context.t('Anderswo · {0}', [elsewhere.length]),
                note: context.t('Gehört zu einem anderen Ort als „{0}". Sie kommen zurück, sobald der Ort passt oder keiner gesetzt ist.', [place ?? '']),
                rows: [
                  for (final task in elsewhere)
                    _DeepRow(
                      task: task,
                      place: place,
                      holdsUp: snapshot.links.unblocks(task.id),
                    ),
                ],
              ),
            if (split.isNotEmpty)
              _DeepSection(
                label: context.t('Zerlegt · {0}', [split.length]),
                // Keine Mahnung, eine Einordnung: Die Aufgabe ist durch ihre
                // Schritte vertreten, deshalb steht sie nicht bei der Auswahl.
                note: context.t('Diese Aufgaben sind durch ihre Teilschritte vertreten. Sie kommen zurück, sobald kein Schritt mehr offen ist.'),
                rows: [
                  for (final task in split)
                    _DeepRow(
                      task: task,
                      place: place,
                      openSteps: openSteps(task),
                    ),
                ],
              ),
            if (done.isNotEmpty)
              _DeepSection(
                label: context.t('Erledigt · {0}', [done.length]),
                rows: [
                  for (final task in done.take(20))
                    _DeepRow(task: task, place: place),
                ],
              ),
            // Der Hebel steht nur da, wenn er wirkt — und er steht dort, wo
            // die Plakette steht, die er erklärt, nicht als Vorspann über
            // dem ganzen Bildschirm (G2).
            if (showsLeverage)
              Padding(
                padding: const EdgeInsets.only(top: Space.xl),
                child: Text(
                  context.t('Was anderes aufhält, zählt mehr: Wert × (1 + 0,35 × log2(1 + aufgehaltene)). Drei aufgehaltene heben den Wert um 70 %, nicht um 200 %.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Die Mulde dieses Schirms.
///
/// Eigener Baustein statt eines `Well` mit Kindern im Aufrufort, weil er
/// einen Fall abfangen muss, den man leicht uebersieht: Liegt unter der
/// Kante gerade nichts, darf die Mulde nicht verschwinden. Ein Horizont
/// ohne Boden darunter ist nur eine Zeile — und „heute liegt nichts
/// darunter" ist selbst eine Aussage, die man sehen koennen muss.
class _Deep extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const _Deep({required this.children, required this.padding});

  @override
  Widget build(BuildContext context) => Well(
        // Vollflaechig: Die Mulde ist der Boden des Schirms, nicht ein
        // weiterer Kasten darauf.
        radius: BorderRadius.zero,
        padding: padding,
        child: children.isEmpty
            ? const SizedBox(width: double.infinity, height: Space.xxl)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
      );
}

/// Ein Abschnitt in der Tiefzone: Marke, Begruendung, Zeilen.
class _DeepSection extends StatelessWidget {
  final String label;
  final String? note;
  final List<Widget> rows;

  const _DeepSection({required this.label, required this.rows, this.note});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(label),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(note!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(color: p.rule, height: 1),
            row,
          ],
        ],
      ),
    );
  }
}

/// Eine Aufgabe **ueber** der Kante: eine Karte, die in die Hand geht.
class _ReachCard extends ConsumerWidget {
  final Task task;

  /// Der gerade gesetzte Ort. Null heisst: keiner, dann bindet nichts.
  final String? place;

  /// Wie viele offene Aufgaben diese hier aufhaelt — transitiv gezaehlt.
  final int holdsUp;

  const _ReachCard({
    required this.task,
    this.place,
    this.holdsUp = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final running = task.state == TaskState.active;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Panel(
        // Griffhoehe. Hier stand ein farbiger Rahmen fuer die laufende
        // Aufgabe und ein 3-px-Streifen links an jeder Zeile; beide sagten
        // dasselbe wie die Ueberschrift darueber und zogen zusaetzlich ein
        // Gitter durch die Liste.
        reachable: true,
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kein „Läuft" in der Karte: Die Abschnittsmarke darüber sagt es
            // schon, und zweimal dasselbe Wort direkt untereinander liest
            // sich als zwei Aussagen.
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.sm),
            // Zerlegen geht immer und auf jeder Ebene — auch bei einem
            // Teilschritt, der sich als immer noch zu groß herausstellt.
            // Die Hürde liegt am Anfang; wo sie liegt, weiß nur der
            // Nutzer [D2].
            //
            // Hier oben gedämpft, in der Tiefzone farbig: Über der Kante ist
            // der angebotene Weg „Anfangen", unter ihr ist es Zerlegen. Die
            // Farbe sagt, welcher gerade gemeint ist.
            if (_sideBySide(context))
              Row(
                children: [
                  Expanded(
                    child:
                        _TaskTags(task: task, place: place, holdsUp: holdsUp),
                  ),
                  const SizedBox(width: Space.sm),
                  _Link(
                    label: context.t('Zerlegen'),
                    color: p.inkDim,
                    onTap: () => splitTask(context, ref, task),
                  ),
                ],
              )
            else ...[
              _TaskTags(task: task, place: place, holdsUp: holdsUp),
              Align(
                alignment: Alignment.centerLeft,
                child: _Link(
                  label: context.t('Zerlegen'),
                  color: p.inkDim,
                  onTap: () => splitTask(context, ref, task),
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            Row(
              children: [
                if (running) ...[
                  // Gleich breit, nicht 2:1. Der Rückweg ist absichtlich
                  // genauso prominent wie der Abschluss; etwas anzufangen
                  // und nicht zu beenden ist der Normalfall und bekommt hier
                  // keinen Kommentar [D10]. Nebenbei bricht „Zurücklegen"
                  // im schmalen Drittel um.
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _act(ref, (r) => r.completeTask(task)),
                      child: Text(context.t('Erledigt')),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _act(ref, (r) => r.releaseTask(task)),
                      child: Text(context.t('Zurücklegen')),
                    ),
                  ),
                ] else ...[
                  // 3:2 statt 2:1: Bei 360 px brach „Erledigt" im schmalen
                  // Drittel mitten im Wort um.
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: () => _act(ref, (r) => r.startTask(task)),
                      child: Text(context.t('Anfangen')),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: () => _act(ref, (r) => r.completeTask(task)),
                      child: Text(context.t('Erledigt')),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Aufgabe **unter** der Kante: eine Zeile, keine Karte.
///
/// Kein Ausgrauen — der Text behaelt seine Rollen. Was hier liegt, ist nicht
/// weniger wert, es ist heute weiter weg.
class _DeepRow extends ConsumerWidget {
  final Task task;
  final String? place;

  /// Offene Teilschritte — nur bei zerlegten Aufgaben gesetzt.
  final int openSteps;

  /// „wartet auf: Ordner holen". Leer heisst: nichts haelt sie auf.
  final String waitingFor;

  /// Wie viele offene Aufgaben diese hier aufhaelt — transitiv gezaehlt.
  final int holdsUp;

  const _DeepRow({
    required this.task,
    this.place,
    this.openSteps = 0,
    this.waitingFor = '',
    this.holdsUp = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final done = task.state == TaskState.done;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? p.inkFaint : null,
              ),
        ),
        const SizedBox(height: Space.sm),
        _TaskTags(
          task: task,
          place: place,
          holdsUp: done ? 0 : holdsUp,
          openSteps: openSteps,
          inWell: true,
        ),
        // Kein Vorwurf, eine Tatsache: Hier steht, was fehlt, nicht was
        // versäumt wurde [R7].
        if (waitingFor.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            waitingFor,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: p.info),
          ),
        ],
      ],
    );

    final links = <Widget>[
      // Die einzige farbige Affordanz der Tiefzone: der Weg nach oben. Er
      // steht zuerst, weil er der gemeinte ist.
      _Link(
        label: context.t('Zerlegen'),
        color: p.signal,
        onTap: () => splitTask(context, ref, task),
      ),
      // Dass etwas auf anderem Weg erledigt wurde, muss sich immer
      // eintragen lassen — auch außer Reichweite. Leise gesetzt: Es ist die
      // Ausnahme, nicht der Weg.
      _Link(
        label: context.t('Erledigt'),
        color: p.inkDim,
        onTap: () => _act(ref, (r) => r.completeTask(task)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: done
          ? content
          : _sideBySide(context)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: content),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      flex: 2,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: Space.xs,
                        children: links,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    Wrap(spacing: Space.xs, children: links),
                  ],
                ),
    );
  }
}

/// Passt ein Textweg noch neben den Text, oder muss er darunter?
///
/// Ein Textknopf kann nicht schmaler werden als sein Wort. Bei angehobener
/// Schrift lief „Zerlegen ›" deshalb nach rechts aus der Zeile hinaus —
/// `robustness_test.dart` faengt genau das, bei 412 px und 1,6-fach ebenso
/// wie bei 360 px und 2,4-fach.
///
/// Die Schwelle liegt an der gerechneten Groesse, nicht am Faktor: Wer die
/// Schrift gross stellt, bekommt dieselbe Zeile untereinander statt
/// abgeschnitten. Abschneiden waere hier die schlechtere Antwort — „Zerle…"
/// ist kein Weg [D9].
bool _sideBySide(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) <= 18;

/// Ein Textweg: Wort und Pfeil, kein Rahmen.
///
/// Dieselbe Form ueber und unter der Kante — nur die Farbe sagt, ob der Weg
/// gerade der gemeinte ist.
class _Link extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Link({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.xs, vertical: Space.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible als Notbremse: Der Pfeil ist 16 px breit und
              // waechst nicht mit der Schrift, das Wort schon. Bei 360 px
              // und 2,4-fach passte beides zusammen um zwei Pixel nicht mehr
              // in die Zeile. Lieber ein Wort mit Auslassungspunkt als ein
              // gestreifter Ueberlaufbalken quer durch die Handlung.
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, size: 16, color: color),
            ],
          ),
        ),
      );
}

/// Die Plaketten einer Aufgabe: Startenergie, Frist, Anlauf, Ort, Hebel.
///
/// Alle waren Schreibmaschine in 10,5 px — unter der Grenze, ab der ein Text
/// noch gelesen statt erkannt wird, und in einer Schrift, die „Protokoll"
/// sagt. Es sind Messwerte: Hausschrift mit Tabellenziffern, und die Zahlen
/// stehen genauso sauber untereinander wie vorher.
class _TaskTags extends ConsumerWidget {
  final Task task;
  final String? place;
  final int holdsUp;
  final int openSteps;

  /// In der Mulde liegt der Grund tiefer als auf einer Karte — dort muss die
  /// Plakette heller sein als ihr Untergrund, hier oben dunkler. Sonst
  /// verschwindet sie in genau einer der beiden Zonen.
  final bool inWell;

  const _TaskTags({
    required this.task,
    this.place,
    this.holdsUp = 0,
    this.openSteps = 0,
    this.inWell = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final done = task.state == TaskState.done;
    final split = task.state == TaskState.blocked;
    final here = task.isHere(place);
    // Der Anlauf steht nur da, wenn er nicht mehr passt. Eine Zahl, die immer
    // da ist, wird nicht gelesen — und die Formel ist genau dann interessant,
    // wenn sie etwas aussagt (G2).
    final runway = task.decayAt == null || done
        ? null
        : taskRunway(task) > task.decayAt!.difference(now)
            ? taskRunway(task)
            : null;

    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      children: [
        _Tag(
          label: context.t('Start {0}/10', [task.activationEnergy]),
          inWell: inWell,
        ),
        if (task.decayAt != null)
          _Tag(
            label: _deadline(context, task.decayAt!, now),
            color: task.decayAt!.isBefore(now) ? p.caution : null,
            inWell: inWell,
          ),
        if (runway != null)
          _Tag(
            label: context.t('Anlauf {0} h',
                [_decimal(context, hoursOf(runway))]),
            color: p.caution,
            inWell: inWell,
          ),
        if (task.place != null)
          _Tag(
            label: task.place!,
            color: here ? null : p.info,
            inWell: inWell,
          ),
        if (split)
          _Tag(
            label: context.t('Schritte offen: {0}', [openSteps]),
            color: p.info,
            inWell: inWell,
          ),
        // Der Hebel, sichtbar an der Aufgabe, die ihn hat: Zahl und Faktor
        // stehen nebeneinander, damit die Formel nachrechenbar bleibt (G2).
        if (holdsUp > 0)
          _Tag(
            // War Versalien: „HÄLT 3 AUF · HEBEL ×1,70". Die Plakette
            // steht zwischen zwei normal geschriebenen („Start 2/10",
            // „Anlauf 2,5 h") und schrie als einzige.
            label: context.t('Hält {0} auf · Hebel ×{1}', [
              holdsUp,
              _decimal(context, taskLeverage(holdsUp), digits: 2),
            ]),
            color: p.signal,
            inWell: inWell,
          ),
      ],
    );
  }

  /// Verfallszeitpunkt in Worten. Kein Ausrufezeichen, keine Mahnung —
  /// überfällig ist eine Tatsache, kein Vorwurf [R7].
  ///
  /// Stand in Versalien und steht jetzt wie jede andere Plakette dieser
  /// Zeile geschrieben; „IN 3 T" war zusätzlich eine Abkürzung, die die
  /// Plakette nicht braucht. Wortgleich mit `_until` in `now_screen.dart` —
  /// dieselbe Angabe an derselben Aufgabe darf nicht zweierlei heißen.
  static String _deadline(BuildContext context, DateTime when, DateTime now) {
    final diff = when.difference(now);
    if (diff.isNegative) return context.t('Überfällig');
    if (diff.inHours < 24) return context.t('In {0} h', [diff.inHours]);
    return context.t('In {0} Tagen', [diff.inDays]);
  }
}

/// Eine Plakette. Vertiefung statt Rahmen — ein Haarlinienrahmen um jede
/// Kleinigkeit zieht ein Gitter durch die Zeile.
class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  final bool inWell;

  const _Tag({required this.label, this.color, this.inWell = false});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
      decoration: BoxDecoration(
        color: inWell ? p.base : p.well,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(label,
          style: readingStyle(context,
              size: 12.5, weight: FontWeight.w600, color: color ?? p.inkDim)),
    );
  }
}

/// Oeffnet das Zerlegen-Blatt fuer genau diese Aufgabe.
///
/// Frei stehend statt als Methode zweier Zeilentypen: Ueber und unter der
/// Kante fuehrt derselbe Weg nach oben, und er soll auch derselbe Code sein.
Future<void> splitTask(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final runtime = await ref.read(runtimeProvider.future);
  final candidate = await runtime.atomizeCandidateFor(task);
  if (!context.mounted) return;
  await showAtomizeSheet(context, candidate);
  refreshAxiom(ref);
}

Future<void> _act(
  WidgetRef ref,
  Future<void> Function(AxiomRuntime) action,
) async {
  final runtime = await ref.read(runtimeProvider.future);
  await action(runtime);
  await HapticFeedback.mediumImpact();
  refreshAxiom(ref);
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  // Der leere Schirm ist die Stelle, an der jemand zum ersten Mal liest,
  // wozu es die Liste gibt — und die Marke stand dort in Versalien.
  Widget build(BuildContext context) => EmptyState(
        label: context.t('Nichts eingetragen'),
        headline: context.t('Keine Aufgaben.'),
        body: context.t('Was du erfasst, landet zuerst im Eingang. Nach dem Sortieren steht es hier.'),
      );
}
