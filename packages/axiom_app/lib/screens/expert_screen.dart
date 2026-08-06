/// Expertenmodus — der Schalter für den lokalen Server.
///
/// Hier steht bewusst mehr Text als sonst irgendwo in dieser App. Ein
/// offener Port mit Gesundheitsdaten ist die eine Stelle, an der Kürze der
/// falsche Wert wäre: Wer ihn einschaltet, soll wissen, was er einschaltet,
/// und wer ihn vergisst, soll es auf der Benachrichtigung sehen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../server/expert_server.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';

class ExpertScreen extends ConsumerStatefulWidget {
  const ExpertScreen({super.key});

  @override
  ConsumerState<ExpertScreen> createState() => _ExpertScreenState();
}

class _ExpertScreenState extends ConsumerState<ExpertScreen>
    with WidgetsBindingObserver, MetaTimed<ExpertScreen> {
  @override
  String get metaScreen => 'expert';

  bool _busy = false;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(runtimeProvider.future).then((runtime) {
      if (mounted) setState(() => _autostart = runtime.expertAutostart);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Der Server kann sich zwischen zwei Blicken selbst abgeschaltet haben —
  /// nach Leerlauf oder nach zu vielen Fehlversuchen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(expertModeProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final status = ref.watch(expertModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Expertenmodus'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: [
          Text(
            context.t('Regeln schreiben, die Aufgabenliste mit allen Feldern überblicken, den Ereignisstrom lesen — am großen Bildschirm, auf den echten Daten dieses Geräts.'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: p.inkDim,
                ),
          ),
          const SizedBox(height: Space.xxl),

          // Eine offene Freigabeanfrage schlaegt alles andere: Sie ist
          // zeitkritisch, und sie ist der Moment, in dem der Vergleich
          // stattfinden muss.
          if (status.pendingNumber != null)
            _Approval(
              number: status.pendingNumber!,
              onApprove: () => ref
                  .read(expertModeProvider.notifier)
                  .resolvePending(approve: true),
              onDeny: () => ref
                  .read(expertModeProvider.notifier)
                  .resolvePending(approve: false),
            )
          else if (status.running)
            _Running(status: status)
          else
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('Aus'), style: sectionStyle(context)),
                  const SizedBox(height: Space.sm),
                  Text(
                    context.t('Der Server läuft nur, solange du ihn eingeschaltet lässt. Kein Autostart, kein Wiederanlaufen nach einem Neustart.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy ? null : _toggle,
            child: Text(status.running
                ? context.t('Server beenden')
                : context.t('Server starten')),
          ),

          const SizedBox(height: Space.xl),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t('Mitstarten, wenn AXIOM aufgeht'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: Space.xs),
                      Text(
                        context.t('Nicht beim Hochfahren und nicht ohne die App — nur, wenn du sie öffnest. Anmeldung, dauerhafte Anzeige und die Abschaltung nach dreißig Minuten Leerlauf bleiben.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autostart,
                  onChanged: (value) async {
                    final runtime = await ref.read(runtimeProvider.future);
                    runtime.expertAutostart = value;
                    if (!mounted) return;
                    setState(() => _autostart = value);
                    if (value && !ref.read(expertModeProvider).running) {
                      await ref.read(expertModeProvider.notifier).start();
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Was das kostet')),
          Panel(
            accent: p.caution.withValues(alpha: 0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Point(
                  title: context.t('Der Browser wird einmal warnen'),
                  body: context.t('Das Zertifikat ist selbst signiert — keine fremde Stelle bürgt dafür. Statt die Warnung wegzuklicken: den Fingerabdruck oben mit dem vergleichen, den der Browser unter „Zertifikat anzeigen" nennt. Stimmen beide überein, sprichst du mit diesem Telefon und mit nichts dazwischen. Danach merkt sich der Browser die Ausnahme.'),
                ),
                Divider(color: p.rule, height: Space.xl),
                _Point(
                  title: context.t('AXIOM hat jetzt die Netzwerkberechtigung'),
                  body: context.t('Bis hierher war auf Systemebene ausgeschlossen, dass Daten das Gerät verlassen. Das gilt nicht mehr. Was bleibt: AXIOM lauscht, ruft aber nichts von sich aus auf — kein Netzwerk-Client im Code, und ein Test hält das fest.'),
                ),
                Divider(color: p.rule, height: Space.xl),
                _Point(
                  title: context.t('Der Name wird im Netz angesagt'),
                  body: context.t('Damit „axiom.local" aufgeht, beantwortet AXIOM Namensanfragen im lokalen Netz. Das Paket geht an eine Adresse, die kein Router weiterleitet, enthält nur Name und IP dieses Geräts, und läuft nur, solange der Server läuft. Beim Beenden wird der Name zurückgenommen.'),
                ),
                Divider(color: p.rule, height: Space.xl),
                _Point(
                  title: context.t('Was ihn wieder ausmacht'),
                  body: context.t('Fünf falsche PINs, dreißig Minuten ohne Anfrage, der Knopf hier, oder der Knopf auf der Benachrichtigung. Beim Beenden der App ist er ohnehin weg.'),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Was dort geht')),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Point(
                  title: context.t('Aufgaben als Liste'),
                  body: context.t('Alle Felder, alle Zustände, direkt änderbar. Die App zeigt bewusst nur eine Handlung — Planen ist etwas anderes als Entscheiden im Moment.'),
                ),
                Divider(color: p.rule, height: Space.xl),
                _Point(
                  title: context.t('Regelwerk im YAML'),
                  body: context.t('Ungültiges wird abgelehnt, nicht übersprungen. Jede gespeicherte Änderung läuft sieben Tage stumm mit — dieselbe Zusage wie im Editor hier.'),
                ),
                Divider(color: p.rule, height: Space.xl),
                _Point(
                  title: context.t('Zustand und Ereignisstrom'),
                  body: context.t('Die Werte mit ihrer Herleitung, und darunter der Strom, aus dem sie gerechnet werden. Nur lesend — Ereignisse sind unveränderlich.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final notifier = ref.read(expertModeProvider.notifier);
    final wasRunning = ref.read(expertModeProvider).running;
    try {
      if (wasRunning) {
        await notifier.stop();
      } else {
        await notifier.start();
      }
      await HapticFeedback.mediumImpact();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.t('Der Server ließ sich nicht starten: {0}', [e])),
        ));
      }
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Adresse und PIN — die zwei Dinge, die man am Rechner braucht.
///
/// **Warum die drei Werte in einer Mulde liegen.** Adresse, PIN und
/// Fingerabdruck werden nicht bedient, sondern *abgelesen* und Zeichen fuer
/// Zeichen an einem zweiten Geraet verglichen. Genau dafuer ist die Mulde da:
/// Was tiefer liegt, ist nicht weniger wert — es ist eine andere Handlung.
/// Vorher standen sie frei auf der Karte, mit einem Rahmen in Signalfarbe
/// darum, und Fliesstext, Ueberschrift und abzutippender Wert sahen gleich
/// weit weg aus.
///
/// Schreibmaschine bleibt hier richtig und ist der Grund, aus dem es sie
/// ueberhaupt noch gibt: Ein Fingerabdruck wird verglichen, eine PIN
/// abgetippt. Was **nicht** dazugehoerte, war der Satz ueber die Abschaltung
/// nach dreissig Minuten — der ist Prosa und steht jetzt auch so da.
class _Running extends StatelessWidget {
  final ExpertStatus status;
  const _Running({required this.status});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      reachable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: p.signal, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.sm),
              Text(context.t('Läuft'),
                  style: sectionStyle(context, color: p.signal)),
            ],
          ),
          const SizedBox(height: Space.lg),
          _Readout(
            label: context.t('Im Browser öffnen'),
            value: status.address ?? '',
            size: 19,
            color: p.ink,
          ),
          if (status.fallbackAddress != null) ...[
            const SizedBox(height: Space.md),
            _Readout(
              label: context.t('Falls der Name nicht aufgeht — in manchen Netzen ist Multicast gesperrt:'),
              value: status.fallbackAddress!,
              size: 15,
              color: p.inkDim,
            ),
          ],
          const SizedBox(height: Space.md),
          _Readout(
            label: context.t('PIN — gilt nur für diesen Start'),
            value: _spaced(status.pin ?? ''),
            size: 30,
            spacing: 4,
            color: p.signal,
          ),
          const SizedBox(height: Space.md),
          // **Der Fingerabdruck war das kleinste Element des Schirms** — 12,5
          // px, die Untergrenze der App, in Gruen. Beides war falsch herum:
          // Er ist der einzige Wert hier, den man Zeichen fuer Zeichen mit
          // einem zweiten Bildschirm vergleicht, also braucht er Lesegroesse.
          // Und Gruen sagt „geprueft", bevor irgendjemand verglichen hat —
          // eine Note auf einer Zeichenkette. Er steht jetzt in der
          // Textfarbe, wie jeder andere abzulesende Wert.
          //
          // Umbrochen wird in festen Gruppen statt an der Kastenbreite (siehe
          // [_grouped]): Vergleichen heisst, zwei Zeilen nebeneinanderzu-
          // halten, und das geht nur, wenn die Zeilen bei jedem Blick
          // dieselben sind.
          _Readout(
            label: context.t('Fingerabdruck des Zertifikats'),
            value: _grouped(status.fingerprint ?? ''),
            size: 15,
            color: p.ink,
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Muss mit dem übereinstimmen, den der Browser zeigt. Tut er das, ist die Verbindung geprüft — nicht bloß weggeklickt.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: Space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.timer_outlined, size: 16, color: p.inkFaint),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  context.t('Schaltet sich ohne Anfrage nach 30 Minuten ab.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sechs Ziffern in Zweiergruppen — so tippt man sie ohne zu verzählen.
  static String _spaced(String pin) {
    final buffer = StringBuffer();
    for (var i = 0; i < pin.length; i++) {
      if (i > 0 && i % 2 == 0) buffer.write(' ');
      buffer.write(pin[i]);
    }
    return buffer.toString();
  }

  /// Der Fingerabdruck in Zeilen zu vier Bytepaaren.
  ///
  /// Die Umbruchstelle darf nicht von der Kastenbreite abhängen: Wer den Wert
  /// mit dem Browser vergleicht, sucht sich eine Zeile und geht sie ab.
  /// Springt der Umbruch mit der Schriftgröße, fängt er von vorn an — und bei
  /// acht Paaren tut er das ab etwa anderthalbfacher Schrift, mit einem
  /// einzelnen Bytepaar als Waise am Zeilenende.
  ///
  /// Vier Paare passen bei jeder zugelassenen Schriftgröße in die Mulde. Acht
  /// kurze Zeilen sind länger als vier lange und dafür bei jedem Blick
  /// dieselben — genau das ist hier die Arbeit.
  static const int _bytesPerLine = 4;

  static String _grouped(String fingerprint) {
    final parts = fingerprint.split(':');
    if (parts.length <= _bytesPerLine) return fingerprint;
    final lines = <String>[];
    for (var i = 0; i < parts.length; i += _bytesPerLine) {
      final end = i + _bytesPerLine;
      lines.add(
          parts.sublist(i, end > parts.length ? parts.length : end).join(':'));
    }
    return lines.join('\n');
  }
}

/// Ein Wert zum Ablesen: Beschriftung darueber, Wert in der Mulde.
class _Readout extends StatelessWidget {
  final String label;
  final String value;
  final double size;
  final Color color;
  final double? spacing;

  const _Readout({
    required this.label,
    required this.value,
    required this.size,
    required this.color,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Die Beschriftung steht **ueber** der Mulde, nicht darin: In der
          // Mulde liegt nur, was abgelesen wird. Ein erklaerender Satz darin
          // haette genau die Trennung wieder aufgehoben, um die es hier geht.
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Space.xs),
          Well(
            padding: const EdgeInsets.all(Space.md),
            radius: BorderRadius.circular(Radii.control),
            child: SelectableText(
              value,
              style: monoStyle(context,
                  size: size,
                  weight: FontWeight.w600,
                  color: color,
                  spacing: spacing ?? 0.2),
            ),
          ),
        ],
      );
}

class _Point extends StatelessWidget {
  final String title;
  final String body;
  const _Point({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// Eine offene Freigabeanfrage aus dem Browser.
///
/// **Warum die Zahl groß ist und der Text kurz.** Der Schutz liegt nicht in
/// der Bestätigung, sondern im Vergleich. Eine Meldung „Anmeldung zulassen?"
/// wird weggedrückt wie jede andere; zwei Zahlen nebeneinander zu halten
/// verlangt einen Blick, und genau der ist die Sicherung: Fragt jemand
/// anders im selben Moment an, steht dessen Zahl hier — und nicht auf dem
/// Bildschirm, vor dem du sitzt.
///
/// Deshalb steht „Stimmt nicht" gleichberechtigt daneben und nicht klein
/// darunter. Ablehnen ist hier die richtige Antwort, nicht die Ausnahme.
class _Approval extends StatelessWidget {
  final String number;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const _Approval({
    required this.number,
    required this.onApprove,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      reachable: true,
      accent: p.signal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('Freigabe angefragt'),
              style: sectionStyle(context, color: p.signal)),
          const SizedBox(height: Space.lg),
          Center(
            // Der Grad ist kein Geschmack: Verglichen wird ueber einen
            // Schreibtisch hinweg, das Telefon liegt daneben und der Browser
            // steht davor. Bei 56 px muss man das Geraet dafuer in die Hand
            // nehmen — und was man in die Hand nimmt, guckt man an, statt zu
            // vergleichen. Schreibmaschine bleibt richtig: Hier wird Zeichen
            // gegen Zeichen gehalten.
            child: Text(
              number,
              style: monoStyle(context,
                  size: 76, weight: FontWeight.w600, color: p.signal),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            context.t('Steht dieselbe Zahl auf dem Bildschirm, vor dem du sitzt?'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Wenn nicht, hat jemand anders angefragt. Dann ablehnen — das kostet nichts außer einem zweiten Versuch.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),
          // **Gleich hoch, nicht nur gleich breit.** „Stimmt überein" bricht
          // auf einem Telefon in zwei Zeilen um, „Stimmt nicht" nicht — und
          // damit stand die Ablehnung als flacherer Knopf neben der
          // Zustimmung. Das ist genau die Schieflage, die dieser Schirm nicht
          // haben darf: Ablehnen ist hier die richtige Antwort, nicht die
          // Ausnahme. `IntrinsicHeight` mit `stretch` gibt beiden die Hoehe
          // des hoeheren; der engere Innenabstand haelt den Umbruch
          // ausserdem laenger hinaus.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm),
                    ),
                    child: Text(context.t('Stimmt überein'),
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDeny,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm),
                    ),
                    child: Text(context.t('Stimmt nicht'),
                        textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
