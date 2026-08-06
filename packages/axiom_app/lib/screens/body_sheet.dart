/// Körper und Schlaf — M7 und M8.
///
/// M7: Hunger, Durst, Blase und Bewegungsbedarf werden bei diesem Profil
/// systematisch zu spät bemerkt, im Hyperfokus gar nicht [D7]. Gleichzeitig
/// ist der körperliche Zustand der größte einzelne Modulator der
/// Exekutivfunktion — ein dehydrierter, unterschlafener Tag hat objektiv
/// weniger Kapazität. Sehr billig zu adressieren: reine Zeittrigger, und
/// Zeittrigger wirken hier zuverlässig [D4].
///
/// M8: Die Nacht ist reizarm genug für Hyperfokus und bietet zugleich die
/// stärkste Neuheit. Daraus wird eine sich selbst verstärkende Kaskade —
/// Schlafdefizit senkt die Exekutivfunktion, das erhöht Kompensationsaufwand
/// und Reizbedarf, was den Abendkonsum steigert [D8]. Der Ausstiegsanker
/// bricht den Kreis an seiner schwächsten Stelle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../platform/android_bridge.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import '../i18n/i18n.dart';

/// Die vier Körpersignale, die am häufigsten übersehen werden.
enum BodySignal {
  water('water', 'Wasser', Icons.water_drop_outlined),
  food('food', 'Essen', Icons.restaurant_outlined),
  move('move', 'Bewegen', Icons.directions_walk_outlined),
  eyes('eyes', 'Augen', Icons.visibility_outlined);

  const BodySignal(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

/// Kompakte Zeile für die Hauptansicht. Antippen quittiert.
///
/// Bewusst keine Zielvorgaben und keine Zähler mit Soll-Wert: Ein „3 von 8
/// Gläsern" erzeugt genau die Bewertung, die dieses System vermeiden soll
/// (R7). Es wird nur festgehalten, dass es passiert ist.
class BodyStrip extends ConsumerStatefulWidget {
  const BodyStrip({super.key});

  @override
  ConsumerState<BodyStrip> createState() => _BodyStripState();
}

class _BodyStripState extends ConsumerState<BodyStrip> {
  final _justAcked = <String>{};

  Future<void> _ack(BodySignal signal) async {
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.acknowledgeBodyPrompt(signal.key);
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _justAcked.add(signal.key));
    refreshAxiom(ref);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    // IntrinsicHeight, damit alle Kacheln die Hoehe der hoechsten bekommen:
    // Die Beschriftungen sind unterschiedlich lang und brechen bei grosser
    // Schrift unterschiedlich um. Ohne die feste Hoehe braucht der Row eine
    // bekannte Hoehe, sonst ist `stretch` nicht definiert.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final signal in BodySignal.values)
            Expanded(
              child: Semantics(
                button: true,
                label: context.t('{0} erledigt', [signal.label]),
                child: Padding(
                  padding: EdgeInsets.only(
                    right: signal == BodySignal.eyes ? 0 : Space.sm,
                  ),
                  // Vorher ein `Container` mit Haarlinienrahmen. Vier
                  // gerahmte Kaesten nebeneinander sind ein Gitter; die
                  // Leiste steht auf dem Seitengrund, also traegt hier der
                  // Schatten die Aussage — genau dafuer gibt es [Panel].
                  child: Panel(
                    onTap: () => _ack(signal),
                    accent: _justAcked.contains(signal.key) ? p.calm : null,
                    // Feste Hoehe waere hier falsch: Sie haelt genau so
                    // lange, bis jemand die Schrift groesser stellt.
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xs,
                      vertical: Space.md,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _justAcked.contains(signal.key)
                              ? Icons.check
                              : signal.icon,
                          size: 20,
                          color: _justAcked.contains(signal.key)
                              ? p.calm
                              : p.inkDim,
                        ),
                        const SizedBox(height: Space.xs + 2),
                        Text(
                          signal.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // War Schreibmaschine. Eine Kachelbeschriftung ist
                          // kein Messwert und kein Befehl — sie laeuft in der
                          // Hausschrift wie jede andere Marke.
                          style: sectionStyle(
                            context,
                            color: _justAcked.contains(signal.key)
                                ? p.calm
                                : p.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Schlaf (M8) ─────────────────────────────────────────────────────────

/// Stundenzahl in der eingestellten Sprache.
///
/// „7.5 Stunden" ist im Deutschen keine Zahl, sondern ein Tippfehler — und
/// er stand ausgerechnet an der Stelle, die den staerksten Einzelfaktor der
/// Kapazitaet meldet. Dieselbe Regel wie in der Herleitungstafel.
String _hours(BuildContext context, double value) {
  final text = value.toStringAsFixed(1);
  return context.language == AppLanguage.de ? text.replaceAll('.', ',') : text;
}

/// Tag und Monat, ohne Jahr — „5.8." beziehungsweise „8/5".
///
/// Kein uebersetzter Satz, sondern eine Zahlenschreibweise: Deutsch schreibt
/// Tag zuerst mit Punkt, Englisch Monat zuerst mit Schraegstrich. Das Jahr
/// fehlt bewusst — gemeint ist immer die letzte Nacht, und eine Jahreszahl
/// waere Ballast in einer Zeile, die in einer Sekunde gelesen wird.
String _dayLabel(BuildContext context, DateTime at) =>
    context.language == AppLanguage.de
    ? '${at.day}.${at.month}.'
    : '${at.month}/${at.day}';

/// Groesse der beiden Uhrzeiten. Steht hier, weil das Blatt daran ausrechnet,
/// ob die zwei Knoepfe noch nebeneinander passen.
const double _timeSize = 24;

Future<bool> showSleepSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SleepSheet(),
    ) ??
    false;

class _SleepSheet extends ConsumerStatefulWidget {
  const _SleepSheet();

  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  late DateTime _bedAt = _guessBedtime();
  late DateTime _wakeAt = _guessWaketime();
  int _quality = 3;
  bool _saving = false;

  /// Heute — aus dem Clock-Port, nicht aus `DateTime.now()`.
  ///
  /// Hier stand zweimal `DateTime.now()`. Damit rechnete das Blatt mit einer
  /// anderen Uhr als die Engine, und im Test hing sein Inhalt an der
  /// Wanduhr des Rechners: Dasselbe Referenzbild sah morgens anders aus als
  /// abends. Die Uhr kommt jetzt von dort, wo alle anderen sie auch holen.
  DateTime get _today => ref.read(clockProvider).nowLocal();

  DateTime _guessBedtime() {
    final yesterday = _today.subtract(const Duration(days: 1));
    return DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 30);
  }

  DateTime _guessWaketime() {
    final now = _today;
    return DateTime(now.year, now.month, now.day, 7, 0);
  }

  /// Dieselbe Ableitung, die auch [AxiomRuntime.logSleep] macht.
  ///
  /// Sie steht hier nicht doppelt, sondern wird von dort geholt: Sonst zeigte
  /// das Blatt eine Stundenzahl an und speicherte eine andere — und das
  /// waere schlimmer als der Fehler, den beide beheben.
  ///
  /// **Und sie wird angezeigt, nicht nur gerechnet.** Der Tag am Zubettgehen
  /// ist seit dem Fix abgeleitet: Wer 00:30 einstellt, meint die Nacht auf
  /// heute, nicht gestern frueh. Bisher stand unter den Knoepfen nur die
  /// Uhrzeit — welche Nacht gemeint war, musste man sich denken. Jetzt steht
  /// das Datum darunter, und zwar genau das, das gespeichert wird.
  ({DateTime bedAt, DateTime wakeAt}) get _window =>
      AxiomRuntime.normaliseSleepWindow(_bedAt, _wakeAt);

  Duration get _duration => _window.wakeAt.difference(_window.bedAt);

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.logSleep(bedAt: _bedAt, wakeAt: _wakeAt, quality: _quality);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Die beiden Uhrzeiten — nebeneinander, solange sie nebeneinander passen.
  ///
  /// Bei 360 px und 2,4-facher Schrift stand hier „23:3" und „07:0": Die
  /// Uhrzeit lief aus ihrem halben Kasten heraus und brach hinter der
  /// dritten Ziffer um. Kein Ueberlauf, den Flutter meldet — ein still
  /// abgeschnittener Messwert, und zwar der, aus dem die Stundenzahl
  /// darunter entsteht.
  ///
  /// Gerechnet, nicht geraten: „23:30" sind mit Tabellenziffern etwa drei
  /// Geviert. Passen zwei Kaesten dieser Breite nebeneinander, stehen sie
  /// nebeneinander; sonst untereinander. Kleiner setzen waere die falsche
  /// Antwort — wer die Schrift hochstellt, will sie gross lesen [D9].
  Widget _times(BuildContext context) {
    // Waren `INS BETT` und `AUF`. Zwei Knopfbeschriftungen in Versalien auf
    // einem Blatt, das morgens um sieben in fuenfzehn Sekunden ausgefuellt
    // werden soll — normale Schreibweise liest sich schneller, und die
    // Auszeichnung traegt `labelSmall` seit der Typografiereform selbst.
    final bed = _TimeButton(
      label: context.t('Ins Bett'),
      value: _window.bedAt,
      onChanged: (v) => setState(() => _bedAt = v),
    );
    final wake = _TimeButton(
      label: context.t('Auf'),
      value: _window.wakeAt,
      onChanged: (v) => setState(() => _wakeAt = v),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final glyphs = MediaQuery.textScalerOf(context).scale(_timeSize) * 3;
        final box = glyphs + Space.lg * 2;
        if (box * 2 + Space.md <= constraints.maxWidth) {
          // IntrinsicHeight, damit beide Kaesten gleich hoch sind: „Ins
          // Bett" bricht bei grosser Schrift auf zwei Zeilen um, „Auf"
          // nicht — ohne das steht ein hoher neben einem niedrigen Kasten.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: bed),
                const SizedBox(width: Space.md),
                Expanded(child: wake),
              ],
            ),
          );
        }
        // Untereinander laufen beide ueber die volle Breite: Ein Kasten, der
        // nur so breit ist wie seine Uhrzeit, sieht aus wie ein Rest — und
        // er ist obendrein ein kleineres Ziel.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bed,
            const SizedBox(height: Space.sm),
            wake,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final hours = _duration.inMinutes / 60;

    return SafeArea(
      // Die Handlung bleibt stehen, der Inhalt rollt darunter durch.
      //
      // Vorher lag „Eintragen" am Ende einer Spalte. Bei 360 px und
      // 2,4-facher Schrift misst diese Spalte gut zweitausend Pixel — der
      // Knopf stand also hinter drei Bildschirmen, und ein Eintrag, den man
      // suchen muss, wird morgens um sieben nicht gemacht. Jetzt traegt eine
      // `Flexible`-Spalte den Inhalt und der Abschluss steht fest: eine
      // Handlung, immer in Reichweite (G1). Dieselbe Bauart tragen das
      // Check-in-, Erfassungs- und Zerlegeblatt.
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
                  // War `SCHLAF` — Rubrik ueber der Ueberschrift, dieselbe
                  // Rolle wie „Zerlegen" im Zerlegeblatt.
                  Text(
                    context.t('Schlaf'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    context.t('Wie lang, wie gut?'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: Space.lg),

                  _times(context),
                  const SizedBox(height: Space.md),
                  Center(
                    // War Schreibmaschine in w300, und unter sechs Stunden kupfern.
                    // Beides ist weg: Die Stundenzahl ist das Ergebnis der beiden
                    // Uhrzeiten darueber, also ein Messwert wie jeder andere — und
                    // ein Messwert traegt genau eine Farbe (R7). Kupfer sagte hier
                    // „zu wenig geschlafen", also ein Urteil ueber eine Nacht, die
                    // ohnehin vorbei ist. Was daraus folgt, rechnet die Kapazitaet
                    // aus; sie muss es nicht auch noch anmalen.
                    child: Text(
                      context.t('{0} Stunden', [_hours(context, hours)]),
                      style: readingStyle(context, size: 28, color: p.signal),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  // Der Satz stand ueber den Uhrzeiten. Bei 360 px und
                  // 2,4-facher Schrift waren das fuenf Zeilen — zusammen mit
                  // der Ueberschrift sieben Zehntel des Bildschirms, bevor
                  // das erste Bedienelement kam. Er steht jetzt unter der
                  // Stundenzahl, und zwar dort, wo er hingehoert: Er
                  // erklaert, was diese Zahl bedeutet. Nichts ist versteckt,
                  // nur spaeter — das Instrument kommt zuerst (G1).
                  Text(
                    context.t(
                      'Der stärkste einzelne Einfluss auf die Kapazität von heute. Grob geschätzt reicht.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.xl),

                  Text(
                    context.t('Hat es getragen?'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.md),
                  // Dieselbe Bauart wie die Regler im Check-in-Blatt: genau ein
                  // erhobenes Feld, der Rest liegt zurueck. Vorher war alles bis
                  // zur gewaehlten Stufe gruen gefuellt — ein Balken, der bei 5
                  // voll ist, und damit eine Bestleistung statt einer Ablesung.
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Expanded(
                          child: Semantics(
                            selected: _quality == i,
                            label: context.t('{0} Stufe {1} von 5', [
                              context.t('Hat es getragen?'),
                              i,
                            ]),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _quality = i);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 52,
                                margin: EdgeInsets.only(
                                  right: i < 5 ? Space.sm : 0,
                                ),
                                decoration: BoxDecoration(
                                  color: _quality == i ? p.signal : p.well,
                                  borderRadius: BorderRadius.circular(
                                    Radii.control,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  ScaleEnds(
                    low: context.t('gar nicht'),
                    high: context.t('vollständig'),
                  ),
                ],
              ),
            ),
          ),
          // Die Haarlinie sagt: darueber geht es weiter. Ohne sie klebt der
          // Knopf bei grosser Schrift am durchlaufenden Text.
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
                  onPressed: _saving ? null : _save,
                  child: Text(context.t('Eintragen')),
                ),
                const SizedBox(height: Space.xs),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.t('Überspringen')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final radius = BorderRadius.circular(Radii.control);
    // Hier stand ein [Panel]. Das ist auf einem Bildschirm richtig und in
    // einem Blatt falsch: Das Blatt **ist** bereits die erhobene Flaeche
    // (`panel`), eine Karte darauf war im Hellen weiss auf weiss und nur an
    // ihrem Schatten zu erahnen. Innerhalb eines Blattes zeigt eine
    // Vertiefung, wo etwas einzugeben ist — dieselbe Sprache wie bei den
    // Reglern.
    return Material(
      color: p.well,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(value),
          );
          if (time == null) return;
          onChanged(
            DateTime(
              value.year,
              value.month,
              value.day,
              time.hour,
              time.minute,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.xs),
              // War Schreibmaschine in w300. Eine Uhrzeit ist ein Messwert:
              // Hausschrift mit Tabellenziffern, damit 07:00 und 23:30
              // dieselbe Breite haben.
              //
              // `maxLines: 1` ohne Ellipse ist hier Absicht und wird geprueft
              // (`robustness_test.dart`): Bricht die Uhrzeit um, ist das
              // Layout falsch — abschneiden waere die schlechtere Antwort,
              // „23:3" ist keine Zeit.
              Text(
                '${value.hour.toString().padLeft(2, "0")}:'
                '${value.minute.toString().padLeft(2, "0")}',
                maxLines: 1,
                softWrap: false,
                style: readingStyle(context, size: _timeSize, color: p.ink),
              ),
              const SizedBox(height: 2),
              // Der Tag, den das Blatt speichert — abgeleitet, nicht geraten.
              // Ohne ihn steht dort „00:30", und ob die Nacht auf heute oder
              // die auf gestern gemeint ist, weiss nur die Rechnung.
              Text(
                _dayLabel(context, value),
                maxLines: 1,
                style: readingStyle(context, size: 13.5, color: p.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Wind-Down (M8) ──────────────────────────────────────────────────────

/// Plant die Abendgrenze und den Morgen-Schlafeintrag.
///
/// Die Wind-Down-Meldung geht bewusst über den leisen Kanal: Wer um 22:30
/// angeschrien wird, schaltet die App stumm — und eine stummgeschaltete App
/// ist eine gelöschte App mit Extraschritten (R2).
abstract final class SleepGate {
  static const int alarmWindDown = 10;
  static const int alarmSleepLog = 11;

  /// [language] wird durchgereicht statt aus dem Kontext geholt: Diese
  /// Texte landen in einer Benachrichtigung, und die entsteht ohne Widget.
  static Future<void> schedule({
    AppLanguage language = AppLanguage.de,
    int windDownHour = 22,
    int windDownMinute = 30,
    int logHour = 8,
  }) async {
    if (!AndroidBridge.isSupported) return;
    final now = DateTime.now();

    var windDown = DateTime(
      now.year,
      now.month,
      now.day,
      windDownHour,
      windDownMinute,
    );
    if (windDown.isBefore(now)) {
      windDown = windDown.add(const Duration(days: 1));
    }
    await AndroidBridge.scheduleExact(
      id: alarmWindDown,
      at: windDown,
      title: translate(language, 'Abendgrenze'),
      body: translate(
        language,
        'Ab jetzt runterfahren. Was offen ist, ist morgen noch offen.',
      ),
      channel: 'axiom_nudge',
      route: AxiomRoute.review,
    );

    var log = DateTime(now.year, now.month, now.day, logHour);
    if (log.isBefore(now)) log = log.add(const Duration(days: 1));
    await AndroidBridge.scheduleExact(
      id: alarmSleepLog,
      at: log,
      title: translate(language, 'Schlaf eintragen'),
      body: translate(language, 'Zwei Zeiten, eine Einschätzung.'),
      channel: 'axiom_nudge',
      // Führt direkt ins Schlafblatt statt auf die Übersicht.
      route: AxiomRoute.body,
    );
  }
}
