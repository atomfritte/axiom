/// Zerlegen — M2.
///
/// Die Frage lautet bewusst nicht „In welche Teile zerfällt das?". Darauf
/// antwortet ein Systemizer mit einem vollständigen Projektplan — und der
/// ist selbst wieder eine Aufgabe mit hoher Aktivierungsenergie.
///
/// Sie lautet: **Was ist die allererste körperliche Handlung?**
///
/// AXIOM schlägt keine Teilschritte vor. Es kann nicht wissen, was
/// „Steuererklärung" konkret bedeutet, und Raten wäre hier schlimmer als
/// Schweigen (ADR-0003). Was es beisteuert: die richtige Frage, einen
/// Formenkatalog und die Prüfung, ob das Ergebnis tatsächlich startbar ist.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

/// Handle auf die Aktivierungsenergie-Skala.
///
/// Die Skala ist der einzige Weg, den Wert zu setzen. Ein Test, der sie
/// ueber „der letzte Row im Baum" sucht, bricht bei jeder Layoutaenderung
/// an einer voellig anderen Stelle.
const Key kEnergyScaleKey = ValueKey('atomize_energy_scale');

Future<bool> showAtomizeSheet(
  BuildContext context,
  AtomizeCandidate candidate,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AtomizeSheet(candidate: candidate),
    ) ??
    false;

class _AtomizeSheet extends ConsumerStatefulWidget {
  final AtomizeCandidate candidate;
  const _AtomizeSheet({required this.candidate});

  @override
  ConsumerState<_AtomizeSheet> createState() => _AtomizeSheetState();
}

class _AtomizeSheetState extends ConsumerState<_AtomizeSheet> {
  final _first = TextEditingController();
  final _focus = FocusNode();
  int _firstEnergy = 2;
  StepShape? _shape;
  bool _saving = false;

  Task get _task => widget.candidate.task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _first.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isReachable => _firstEnergy <= widget.candidate.targetEnergy + 1;

  Future<void> _save() async {
    final first = _first.text.trim();
    if (first.isEmpty || _saving) return;
    setState(() => _saving = true);

    final runtime = await ref.read(runtimeProvider.future);
    // **Hier stand ein zweiter Schritt: „Und dann? (optional)".** Ein
    // Textfeld am Ende des Blattes, das den Rest der Aufgabe grob
    // aufnehmen sollte; daraus wurde ein zweites Kind mit einer Stufe
    // weniger Startenergie.
    //
    // Es ist ersatzlos raus, und zwar aus zwei Gruenden, die beide aelter
    // sind als dieses Blatt:
    //
    //  1. **Es fragte nach dem Plan.** Genau das schliesst der Kopf dieser
    //     Datei aus: Die Frage lautet bewusst nicht „In welche Teile
    //     zerfaellt das?", weil ein Systemizer darauf mit einem
    //     vollstaendigen Projektplan antwortet — und der ist selbst wieder
    //     eine Aufgabe mit hoher Aktivierungsenergie (D3). Das Feld stand
    //     genau dort, wo dieser Reflex am billigsten zu bedienen war.
    //  2. **Der Rest ist schon gespeichert.** `atomize` loescht die
    //     Elternaufgabe nicht, sie wird nur blockiert („vertreten durch die
    //     eigenen Schritte") und kommt zurueck, sobald kein Schritt mehr
    //     offen ist. Der Rest hiess also ohnehin immer schon so wie die
    //     Aufgabe — das Feld hat ihn nur ein zweites Mal abgetippt.
    //
    // Was damit auch weg ist: die `clamp(1, 10)`-Rechnung fuer die Energie
    // des Restes, die es nur gab, weil bei einer Aufgabe mit Energie 1
    // sonst 0 herauskam und `Task` erst ab 1 gilt.
    await runtime.atomize(
      parent: _task,
      steps: [(title: first, energy: _firstEnergy)],
    );
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return SafeArea(
      // **Die Handlung bleibt stehen, der Inhalt rollt darunter durch.**
      //
      // Das laengste der Blaetter, und ausgerechnet das, das man bei
      // erschoepfter Startenergie oeffnet. Bei 360 px und 2,4-facher Schrift
      // sind das mehrere Bildschirme, und „Übernehmen" lag hinter allen —
      // waehrend das Feld oben den Fokus holt und die Ansicht zu sich zieht.
      // Wer den ersten Schritt getippt hat, soll ihn nicht suchen muessen
      // (G1, D2).
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.lg,
                  Space.lg,
                  Space.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('Zerlegen'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      _task.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      widget.candidate.explanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Space.xl),

                    Text(
                      context.t('Was ist die allererste Handlung?'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      context.t(
                        'Etwas Körperliches, das in zwei Minuten erledigt ist. Nicht der Plan — der erste Handgriff.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.md),

                    TextField(
                      controller: _first,
                      focusNode: _focus,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            _shape?.examples ??
                            context.t('Ordner auf den Tisch legen'),
                      ),
                    ),
                    const SizedBox(height: Space.lg),

                    // **Der Formenkatalog steht nur da, solange das Feld
                    // leer ist.**
                    //
                    // Sieben Chips ueber vier Zeilen waren der groesste
                    // einzelne Block des laengsten Blattes der App — und ihr
                    // ganzer Beitrag ist ein anderer Platzhalter im Feld
                    // darueber. Wer schon tippt, hat die Antwort; fuer den
                    // sind sie ab dem ersten Zeichen nur noch Weg zwischen
                    // Feld und Skala.
                    //
                    // Gebraucht werden sie an genau einer Stelle: wenn man
                    // vor dem leeren Feld sitzt und nicht weiss, was eine
                    // „erste koerperliche Handlung" ueberhaupt sein soll
                    // [D2]. Dort bleiben sie vollstaendig stehen. Weggenommen
                    // ist nicht der Katalog, sondern seine Anwesenheit
                    // danach.
                    if (_first.text.trim().isEmpty) ...[
                      // War `ODER EINE DIESER FORMEN` — dreiundzwanzig
                      // Versalien auf dem Schirm fuer den schlechtesten Tag.
                      Text(
                        context.t('Oder eine dieser Formen'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final shape in StepShape.values)
                            _ShapeChip(
                              shape: shape,
                              selected: _shape == shape,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(
                                  () => _shape = _shape == shape ? null : shape,
                                );
                                _focus.requestFocus();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.xl),
                    ],

                    _EnergyPicker(
                      value: _firstEnergy,
                      target: widget.candidate.targetEnergy,
                      onChanged: (v) => setState(() => _firstEnergy = v),
                    ),

                    if (!_isReachable) ...[
                      const SizedBox(height: Space.md),
                      Panel(
                        accent: p.caution.withValues(alpha: 0.45),
                        child: Text(
                          context.t(
                            'Das ist noch zu groß. Ein Schritt, der gerade so passt, passt morgen nicht mehr — dann fängt das Ganze von vorn an. Was wäre der Handgriff davor?',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    // Hier endete das Blatt frueher mit „UND DANN?
                    // (OPTIONAL)" und einem zweiten Textfeld. Beides ist
                    // weg; die Begruendung steht bei [_save].
                  ],
                ),
              ),
            ),
            Container(height: 1, color: p.rule),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                Space.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: _saving || _first.text.trim().isEmpty
                        ? null
                        : _save,
                    child: Text(context.t('Übernehmen')),
                  ),
                  const SizedBox(height: Space.xs),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(context.t('Später')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeChip extends StatelessWidget {
  final StepShape shape;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeChip({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          // Ungewaehlt war das hier `panel` mit Haarlinienrahmen — in einem
          // Blatt ist `panel` der Untergrund selbst, also blieb vom Chip nur
          // der Rahmen uebrig. Jetzt traegt die Vertiefung, wie bei den
          // Reglern: Der Chip liegt im Grund, gewaehlt kommt er heraus.
          color: selected ? p.signal.withValues(alpha: 0.16) : p.well,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(
            color: selected ? p.signal : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          shape.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected ? p.signal : p.inkDim,
          ),
        ),
      ),
    );
  }
}

/// Wie schwer fällt DER erste Schritt? Die Kerbe unter der Skala zeigt, wie
/// weit die heutige Kapazität reicht.
///
/// **Warum dort nicht mehr „ZIEL ≤ 2" steht.** Neben einer Zehnerskala war
/// das eine Prüfung mit Bestehensgrenze — und zwar über eine Zahl, die der
/// Nutzer eine Sekunde vorher selbst geschätzt hat, auf dem Blatt, das man
/// bei niedriger Kapazität öffnet. Wer 4 antippt, hat dann nicht gemessen,
/// sondern verfehlt. Das ist eine Note mit Schwellenwert, und Zustandswerte
/// sind Messwerte (R7).
///
/// Die Kerbe bleibt — sie trägt dieselbe Information ohne Vergleichszeichen
/// und ohne das Wort „Ziel". Was sie bedeutet, sagt jetzt ein Satz darunter,
/// und der sagt es über das System („so weit reicht die Kapazität heute")
/// statt über den Nutzer.
///
/// **Warum hier gefüllt wird und im Check-in nicht.** Die Regler im
/// Check-in fragen nach einer *Stelle* zwischen zwei benannten Enden; dort
/// steht genau ein Feld erhoben da. Diese Skala fragt nach einer *Menge*
/// und vergleicht sie mit einer Marke — dafür ist die Länge des gefüllten
/// Laufs die Aussage, nicht die Position eines einzelnen Feldes.
///
/// **Warum die Farbe nicht mehr umschlägt.** Vorher waren die Felder bis
/// zur Zielmarke grün und darüber kupfern. Das ist gut/schlecht in zwei
/// Farben, über eine Zahl, die der Nutzer gerade selbst geschätzt hat — und
/// gemeint ist nicht „falsch", sondern „weiter weg als heute erreichbar"
/// (R7). Entfernung zeigt diese Oberfläche über Position, nicht über Farbe:
/// Die Zielmarke steht als Kerbe unter der Skala, und wer darüber hinaus
/// füllt, sieht das, ohne dass ihm jemand eine Farbe dazu sagt. Die eine
/// Stelle, an der Kupfer bleibt, ist der Hinweis darunter — er sagt in
/// Worten, was zu tun ist.
class _EnergyPicker extends StatelessWidget {
  final int value;
  final int target;
  final ValueChanged<int> onChanged;

  const _EnergyPicker({
    required this.value,
    required this.target,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hier stand ein `Wrap` mit zwei Kindern: links die Frage, rechts
        // „ZIEL ≤ 2". Der `Wrap` gab es nur, weil die Marke rechts nicht
        // umbrechen durfte und die Frage links sonst bei 2,4-facher Schrift
        // auf wenige Zeichen zusammengepresst wurde. Ohne die Marke braucht
        // die Frage keine Sonderbehandlung mehr — sie ist wieder ein Text.
        Text(
          context.t('Wie schwer fällt dieser Schritt?'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Space.md),
        // Fester Schluessel: Die Skala ist der einzige Weg, den Wert zu
        // setzen, und ein Test, der sie ueber "der letzte Row im Baum"
        // sucht, bricht bei jeder Layoutaenderung woanders.
        Row(
          key: kEnergyScaleKey,
          children: [
            for (var i = 1; i <= 10; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      Container(
                        // 52 wie die Regler im Check-in: dieselbe
                        // Instrumentenfamilie, also dieselbe Hoehe — und
                        // Androids Richtlinie sind 48 dp. Die Breite bleibt
                        // bei zehn Stufen auf einem 360er Schirm knapp; das
                        // ist der Preis der Zehnerskala und steht im Bericht.
                        height: 52,
                        margin: EdgeInsets.only(right: i < 10 ? 3 : 0),
                        decoration: BoxDecoration(
                          color: value >= i
                              ? p.signal.withValues(alpha: value == i ? 1 : 0.3)
                              : p.well,
                          // Radius 2 hiess: gefraeste Kante. Auf zehn
                          // Feldern nebeneinander liest sich das als Raster
                          // eines Messschiebers — die Oberflaeche soll aber
                          // nicht praezise wirken, sondern anfassbar sein.
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      // Die Zielmarke — eine Kerbe unter dem Feld, das die
                      // Grenze ist. Sie steht unabhaengig vom gewaehlten
                      // Wert da; wer darueber hinaus fuellt, sieht es an der
                      // Laenge des Laufs.
                      const SizedBox(height: Space.xs),
                      Container(
                        height: 2,
                        margin: EdgeInsets.only(right: i < 10 ? 3 : 0),
                        color: i == target ? p.inkFaint : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        // Die Kerbe braucht einen Satz, sonst ist sie ein Raetsel — und ein
        // unerklaertes Zeichen unter einer Skala laedt genau die Deutung
        // ein, die hier nicht gemeint ist. Der Satz nennt die Zahl und sagt,
        // was AXIOM damit tut; er sagt nichts darueber, ob der gewaehlte
        // Wert richtig ist (R7, G2).
        Text(
          context.t('Die Marke bei {0} ist die heutige Reichweite.', [target]),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
