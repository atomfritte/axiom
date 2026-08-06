/// "System" — der Regelinspektor.
///
/// Hier wird G2 einloesbar: Jede Regel ist lesbar, mit Begruendung,
/// Bedingung, Stufe und Trefferquote. Ein Systemizer, der sein eigenes
/// System auditieren kann, bleibt dabei. Einer, der glauben muss, nicht.
///
/// Gleichzeitig ist dieser Screen der gefaehrlichste der App: Er ist der
/// direkte Zugang zur Meta-Work-Falle (D3). Deshalb zaehlt die hier
/// verbrachte Zeit voll auf das Tagesbudget, und Aenderungen sind gesperrt,
/// sobald es aufgebraucht ist.
///
/// **Was hier nicht mehr steht — und warum.** „System" war zuletzt der Ort
/// fuer alles, was anderswo nicht hinpasste: neun Dinge von der Textgroesse
/// bis zur Aufgabenliste. Zwei davon sind kein System, sondern Inhalt, und
/// sie sind hier ersatzlos gestrichen:
///
///  * **Aufgaben** — der Bestand. Er stand zusaetzlich als erste Zeile in
///    der Mulde auf „Jetzt". Zwei Wege zu einer Liste sind kein
///    Entgegenkommen, sondern zwei Orte, an denen man sie suchen kann.
///  * **Vorfälle** — das Ereignisprotokoll (M10). Es steht jetzt fest in der
///    Mulde auf „Jetzt", nicht mehr nur bei offener Nachbetrachtung. Einen
///    Vorfall haelt man in dem Moment fest, in dem er passiert, und in dem
///    Moment ist man nicht im Konfigurationsschirm.
///
/// Was bleibt, laesst sich in einem Satz sagen: **die Maschine** — was sie
/// kostet, wie weit sie geeicht ist, wie sie eingestellt ist, und wo man
/// nachliest, warum sie etwas gesagt hat.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/baseline_card.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../platform/health_sync.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'channels_screen.dart';
import 'check_screen.dart';
import 'expert_screen.dart';
import 'help_screen.dart';
import 'rule_editor_screen.dart';
import 'vault_screen.dart';

class SystemScreen extends ConsumerStatefulWidget {
  const SystemScreen({super.key});

  @override
  ConsumerState<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends ConsumerState<SystemScreen> {
  final _openedAt = DateTime.now();

  /// Waehrend des Aufbaus gemerkt: In dispose() ist `ref` nicht mehr
  /// benutzbar, die Nutzungszeit muss aber genau dann gebucht werden.
  AxiomRuntime? _runtime;

  @override
  void dispose() {
    // Zeit auf diesem Screen zaehlt voll auf das Meta-Work-Budget (M12).
    final spent = DateTime.now().difference(_openedAt);
    if (spent > const Duration(seconds: 3)) {
      _runtime?.logScreenTime('system', spent);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(runtimeProvider);
    _runtime ??= runtime.value;
    final snapshot = ref.watch(snapshotProvider);
    final p = context.axiom;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('System'))),
      body: runtime.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rt) {
          final used = snapshot.value?.metaUsedToday ?? Duration.zero;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.huge,
            ),
            children: [
              // Reihenfolge nach Aufmerksamkeit, nicht nach Systematik:
              // oben steht, was einen Zustand meldet, darunter das, was man
              // einmal einstellt. Alles, was laenger als ein Bildschirm ist
              // — Regelwerk, Systemcheck, Erfassungswege — liegt hinter
              // genau einem Tipp. Eine Seite, auf der man scrollen muss, um
              // eine Einstellung wiederzufinden, wird nicht benutzt.
              //
              // Das Meta-Work-Budget steht oben und nicht unten: Es ist die
              // Selbstbegrenzung (G4), und eine Grenze, die man erst nach
              // dem Scrollen sieht, ist keine.
              _BudgetCard(used: used),

              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Eichung')),
              _BaselineSection(
                ungauged: rt.rules
                    .where(
                      (r) =>
                          !r.isShadow &&
                          r.when.referencedVariables
                              .intersection(_uncalibratedInputs)
                              .isNotEmpty,
                    )
                    .length,
              ),
              if (rt.ruleIssues.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                _IssuesCard(issues: rt.ruleIssues),
              ],

              const SizedBox(height: Space.xl),
              const _DisplaySettings(),

              // **„Nachsehen" steht jetzt vor „Einrichten".** Der Kommentar
              // oben sagt, die Reihenfolge richte sich nach Aufmerksamkeit
              // und nicht nach Systematik — sie tat es nur nicht: Ganz oben
              // stand, was man **einmal** einrichtet, darunter das, was man
              // immer wieder aufschlaegt. „Warum hat es das gerade gesagt"
              // ist die haeufigste Frage an diesen Schirm; sie fuehrt ins
              // Regelwerk, und das lag hinter vier Einrichtungszeilen.
              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Nachsehen')),
              _LinkGroup(
                rows: [
                  _LinkRow(
                    icon: Icons.rule,
                    label: context.t('Regelwerk'),
                    detail: context.t('{0} Regeln, jede lesbar und abschaltbar', [
                      rt.rules.length,
                    ]),
                    target: const RulesScreen(),
                  ),
                  _LinkRow(
                    icon: Icons.help_outline,
                    label: context.t('Hilfe'),
                    detail: context.t(
                      'Wozu jeder Bildschirm da ist und wie eine Regel entscheidet',
                    ),
                    target: const HelpScreen(),
                  ),
                  _LinkRow(
                    icon: Icons.lock_outline,
                    label: context.t('Daten'),
                    detail: context.t(
                      'Verschlüsselter Export, Import, Wirkfenster',
                    ),
                    target: const VaultScreen(),
                  ),
                ],
              ),

              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Einrichten')),
              // Vorher stand hier jede Zeile als eigene Karte mit acht
              // Pixeln Luft dazwischen: vier bzw. fuenf schwebende Flaechen,
              // die alle gleich weit weg wirkten. Eine Gruppe, die
              // zusammengehoert, ist **eine** Flaeche mit Haarlinien darin —
              // dann traegt der Abschnittstitel die Ordnung und nicht der
              // Zwischenraum.
              _LinkGroup(
                rows: [
                  _LinkRow(
                    icon: Icons.bolt_outlined,
                    // Hiess „Erfassen" — genau wie der Knopf auf „Jetzt",
                    // der etwas ganz anderes tut. Ein Wort fuer zwei Dinge
                    // ist teurer als ein laengeres Wort: Wer hier tippt,
                    // will erfassen und landet in einer Einstellungsseite.
                    label: context.t('Erfassungswege'),
                    detail: context.t(
                      'Sieben Wege hinein — Widget, Benachrichtigung, Stift, Sprache',
                    ),
                    target: const ChannelsScreen(),
                  ),
                  _LinkRow(
                    icon: Icons.monitor_heart_outlined,
                    label: context.t('Datenquellen'),
                    detail: context.t('Schlaf und Bewegung aus Health Connect'),
                    target: const SourcesScreen(),
                  ),
                  _LinkRow(
                    icon: Icons.desktop_windows_outlined,
                    label: context.t('Expertenmodus'),
                    detail: context.t('Regeln und Listen am großen Bildschirm — aus, bis du ihn startest'),
                    target: const ExpertScreen(),
                  ),
                  _LinkRow(
                    icon: Icons.fact_check_outlined,
                    label: context.t('Systemcheck'),
                    detail: context.t('Was das Gerät wirklich freigegeben hat'),
                    target: const CheckScreen(),
                  ),
                ],
              ),

              const SizedBox(height: Space.xxl),
              Text(
                context.t('Schema v{0} · {1} Regeln', [
                  kSchemaVersion,
                  rt.rules.length,
                ]),
                style: readingStyle(context,
                    size: 12.5, weight: FontWeight.w400, color: p.inkFaint),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Duration used;
  const _BudgetCard({required this.used});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final over = used >= kMetaBudget;
    return Panel(
      accent: over ? p.caution.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hiess „Meta-Work-Budget", waehrend dieselbe Zahl unten auf
          // „Jetzt" „Zeit im System heute" hiess. Zwei Namen fuer einen
          // Messwert sind schlimmer als zwei Anzeigen: Man haelt sie fuer
          // zwei Zahlen und sucht nach dem Unterschied. Jetzt derselbe Name
          // an beiden Orten — und der deutsche statt des Jargons.
          Text(
            context.t('Zeit im System heute'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: Space.sm),
          // Die Zahl bleibt in der Messfarbe, auch wenn der Deckel erreicht
          // ist. Vorher wechselte sie dort nach Kupfer — dieselbe Groesse in
          // zwei Farben liest sich als „gut" und „schlecht", und damit war
          // aus einem Messwert eine Note geworden (R7). Dass der Deckel
          // erreicht ist, sagt der Rahmen der Karte und der Satz darunter;
          // beides meldet einen *Zustand* und darf faerben.
          BigReading(
            value: '${used.inMinutes}',
            unit: context.t('/ {0} min heute', [kMetaBudget.inMinutes]),
            valueColor: p.signal,
          ),
          const SizedBox(height: Space.md),
          Text(
            over
                // Tagesweise, nicht bis zum nächsten Review: Genau das
                // prüft `AxiomRuntime.isConfigLocked()`, und ein Deckel, den
                // man vorhersagen kann, ist einer, um den herum man plant.
                // „Morgen wieder" ist lernbar, „irgendwann nach dem nächsten
                // Rückblick" nicht — und ein unlernbarer Deckel wird
                // bekämpft statt angenommen (R7).
                ? context.t(
                    'Budget aufgebraucht. Änderungen am Regelwerk sind bis morgen zu. Erfassen, Arbeiten und Nachsehen bleiben offen. Das ist Absicht: Das System zu optimieren fühlt sich an wie Arbeit, ist aber keine.',
                  )
                : context.t(
                    'Zeit, die du im System verbringst statt im Leben. Erfassen zählt nicht mit.',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Anzeige: Sprache, Textgröße, Helligkeit, Farbschema.
///
/// Vier Zeilen, mehr nicht. Endlose Konfigurierbarkeit ist bei diesem Profil
/// selbst ein Problem (D3) — aber eine Oberfläche, die man nicht lesen kann,
/// bekommt keine ehrlichen Daten. Die vier hier zahlen alle darauf ein, dass
/// der Text ankommt; sie sind keine Geschmacksfragen.
/// Zugeklappt, weil man sie einmal einstellt und danach nie wieder.
///
/// Vier Wahlzeilen dauerhaft offen sind vier Zeilen Aufforderung, etwas zu
/// verstellen — auf einem Screen, den man aufsucht, um etwas anderes zu tun.
/// Der eingestellte Zustand bleibt trotzdem lesbar: Er steht in der
/// Kopfzeile. Zuklappen darf verbergen, was man ändern kann, nie das, was
/// gilt.
class _DisplaySettings extends ConsumerStatefulWidget {
  const _DisplaySettings();

  @override
  ConsumerState<_DisplaySettings> createState() => _DisplaySettingsState();
}

class _DisplaySettingsState extends ConsumerState<_DisplaySettings> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final textSize = ref.watch(textSizeProvider);
    final brightness = ref.watch(themeModeProvider);
    final scheme = ref.watch(schemeProvider);

    final summary = [
      language.code.toUpperCase(),
      switch (textSize) {
        TextSize.compact => 'S',
        TextSize.normal => 'M',
        TextSize.large => 'L',
        TextSize.larger => 'XL',
      },
      context.t(const ['AUTO', 'DUNKEL', 'HELL'][brightness]),
      // Ohne `.toUpperCase()`: „INSTRUMENT" sind zehn gesperrte
      // Grossbuchstaben. Die Ausnahme fuer Plaketten reicht bis sieben
      // Zeichen — bis dahin liest man Formen, danach Buchstaben.
      context.t(scheme.label),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FoldHeader(
          label: context.t('Anzeige'),
          summary: summary,
          open: _open,
          onTap: () => setState(() => _open = !_open),
        ),
        if (!_open) const SizedBox(height: Space.xs),
        if (_open) ...[
          const SizedBox(height: Space.md),
        _ChoiceRow(
          icon: Icons.translate,
          label: context.t('Sprache der Oberfläche'),
          options: [
            for (final l in AppLanguage.values)
              (
                key: l.code.toUpperCase(),
                selected: l == language,
                onTap: () => ref.read(languageProvider.notifier).set(l),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        _ChoiceRow(
          icon: Icons.format_size,
          label: context.t('Textgröße'),
          hint: context.t(textSize.label),
          options: [
            for (final size in TextSize.values)
              (
                key: switch (size) {
                  TextSize.compact => 'S',
                  TextSize.normal => 'M',
                  TextSize.large => 'L',
                  TextSize.larger => 'XL',
                },
                selected: size == textSize,
                onTap: () => ref.read(textSizeProvider.notifier).set(size),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        _ChoiceRow(
          icon: Icons.contrast,
          label: context.t('Helligkeit'),
          options: [
            for (final (index, name) in const [
              (0, 'AUTO'),
              (1, 'DUNKEL'),
              (2, 'HELL'),
            ])
              (
                key: context.t(name),
                selected: index == brightness,
                onTap: () => ref.read(themeModeProvider.notifier).set(index),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        _ChoiceRow(
          icon: Icons.palette_outlined,
          label: context.t('Farbschema'),
          // Ohne Hinweis rechts: Seit die Plaketten normal geschrieben sind,
          // stand dort dasselbe Wort wie auf der ausgewaehlten Plakette
          // darunter. Bei „Textgröße" ist es anders — „M" und „Normal" sagen
          // nicht dasselbe.
          options: [
            for (final s in AxiomScheme.values)
              (
                key: context.t(s.label),
                selected: s == scheme,
                onTap: () => ref.read(schemeProvider.notifier).set(s),
              ),
          ],
        ),
        ],
      ],
    );
  }
}

/// Kopfzeile einer zuklappbaren Gruppe.
///
/// Zeigt zugeklappt, was gilt — nicht bloss den Namen der Gruppe. Eine
/// Kopfzeile ohne Zustand zwingt zum Aufklappen, nur um nachzusehen.
///
/// **Sieht aus wie eine `SectionLabel`, ist aber von Hand gesetzt.** Der
/// Baustein legt vor seinen Anhang einen `Spacer`, und der teilt sich den
/// freien Platz mit der Zusammenfassung — bei „DE · M · AUTO · Instrument"
/// blieb von „Anzeige" ein „An…" uebrig. Die Schrift kommt deshalb aus
/// `sectionStyle` (dieselbe Rolle, direkt greifbar), der Aufbau von hier.
///
/// Was der Sonderweg vorher zusaetzlich kostete, ist weg: „ANZEIGE" stand
/// als einzige Marke des Schirms in gesperrten Versalien, die Zusammenfassung
/// in Schreibmaschine.
class _FoldHeader extends StatelessWidget {
  final String label;
  final String summary;
  final bool open;
  final VoidCallback onTap;

  const _FoldHeader({
    required this.label,
    required this.summary,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Row(
          children: [
            Text(label, style: sectionStyle(context)),
            const SizedBox(width: Space.md),
            if (!open) ...[
              Expanded(
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: readingStyle(context,
                      size: 12.5,
                      weight: FontWeight.w400,
                      color: p.inkFaint),
                ),
              ),
              const SizedBox(width: Space.sm),
            ] else
              const Spacer(),
            Icon(open ? Icons.expand_less : Icons.expand_more,
                size: 18, color: p.inkDim),
          ],
        ),
      ),
    );
  }
}

typedef _Option = ({String key, bool selected, VoidCallback onTap});

class _ChoiceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final List<_Option> options;

  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.options,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: p.inkDim),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (hint != null)
                Text(hint!,
                    style: readingStyle(context,
                        size: 13.5,
                        weight: FontWeight.w400,
                        color: p.inkDim)),
            ],
          ),
          const SizedBox(height: Space.md),
          // Umbrechend statt in einer Zeile gequetscht: Bei grosser Schrift
          // passen vier Chips sonst nicht nebeneinander.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final option in options)
                _Chip(
                  label: option.key,
                  selected: option.selected,
                  onTap: option.onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Semantics(
      button: true,
      selected: selected,
      // Ohne Beschriftung liest die Vorlesefunktion nur „S", „M", „L" vor —
      // ohne zu sagen, wovon.
      label: label,
      child: GestureDetector(
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        behavior: HitTestBehavior.opaque,
        child: Container(
          // 48 dp ist die Untergrenze fuer ein Tippziel. Darunter trifft man
          // im Gehen daneben, und Danebentreffen kostet hier einen zweiten
          // Anlauf [D2].
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? p.signal.withValues(alpha: 0.9) : p.base,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: selected ? p.signal : p.rule),
          ),
          // **Hier stand `alignment: Alignment.center` am `Container`.**
          // `Container` baut daraus ein `Align` ohne Faktoren, und ein
          // solches `Align` nimmt sich die volle angebotene Breite. Im
          // `Wrap` darueber war das die ganze Kartenbreite — jede Plakette
          // wurde so breit wie der Schirm, und aus „DE EN" bzw.
          // „S M L XL" wurden zwei bzw. vier volle Zeilen untereinander.
          // Der Kommentar am `Wrap` sagt seit jeher „umbrechend statt in
          // einer Zeile gequetscht"; nebeneinander gestanden haben sie nie.
          //
          // `Center` mit `widthFactor`/`heightFactor` 1 misst sich am Text;
          // die Mindestmasse von oben gelten weiter, und darin wird
          // zentriert.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: readingStyle(
                context,
                size: 13.5,
                weight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : p.inkDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Health Connect: Schlaf und Bewegung aus dem System statt aus Erinnerung.
///
/// Der Zustand wird ausgeschrieben, nicht nur als Schalter gezeigt. Wenn
/// keine Schlafdaten ankommen, muss ohne Suchen erkennbar sein, woran es
/// liegt — sonst rechnet die Kapazität still mit Lücken (R8).
class _HealthCard extends ConsumerStatefulWidget {
  const _HealthCard();

  @override
  ConsumerState<_HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends ConsumerState<_HealthCard> {
  bool _busy = false;
  String? _lastResult;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final availability = ref.watch(healthAvailabilityProvider).value;

    final (label, body, action) = switch (availability) {
      null => (context.t('Wird geprüft'), context.t('Einen Moment.'), null),
      HealthAvailability.unavailable => (
        context.t('Nicht verfügbar'),
        context.t(
          'Auf diesem Gerät gibt es kein Health Connect. Schlaf und Bewegung kommen weiterhin aus deiner Eingabe.',
        ),
        null,
      ),
      HealthAvailability.needsUpdate => (
        context.t('Aktualisierung nötig'),
        context.t(
          'Die Systemkomponente ist älter als das, was AXIOM liest. Sie lässt sich in den Systemeinstellungen aktualisieren.',
        ),
        context.t('Einstellungen öffnen'),
      ),
      HealthAvailability.notGranted => (
        context.t('Nicht freigegeben'),
        context.t(
          'AXIOM liest zwei Größen: Schlaffenster und Tagesschritte. Beide gehen in die Kapazität ein — heute nur, soweit du sie selbst einträgst.',
        ),
        'Freigeben',
      ),
      HealthAvailability.ready => (
        'Verbunden',
        context.t(
          'Schlaffenster und Tagesschritte werden beim Start nachgezogen. Nur lesend, nur diese beiden, jederzeit widerrufbar.',
        ),
        context.t('Jetzt abgleichen'),
      ),
    };

    return Panel(
      accent: availability == HealthAvailability.ready
          ? p.calm.withValues(alpha: 0.45)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 19,
                color: availability == HealthAvailability.ready
                    ? p.calm
                    : p.inkDim,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  context.t('Health Connect · {0}', [label]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          if (_lastResult != null) ...[
            const SizedBox(height: Space.md),
            Text(
              _lastResult!,
              style: readingStyle(context, size: 13.5, color: p.signal),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy ? null : () => _act(availability!),
                child: Text(_busy ? context.t('Läuft') : action),
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          // Vorher stand hier, nichts davon verlasse das Telefon, weil AXIOM
          // gar keine Berechtigung fuers Netz habe. Beide Haelften waren
          // falsch: Das Manifest deklariert seit ADR-0005 `INTERNET`, und der
          // Expertenmodus liefert genau diese Schlaf- und Schrittereignisse
          // ueber `GET /api/events` ins lokale Netz aus. Eine falsche
          // Datenschutzzusage ausgerechnet auf dem Schirm fuer
          // Gesundheitsdaten. Was bleibt, ist die engere, getestete Zusage
          // aus ADR-0005 — und der ehrliche Hinweis auf die eine Ausnahme.
          // Der Datenschutzsatz stand in Schreibmaschine in 10,5 px — also
          // unter der Lesegrenze und im Ton einer Fussnote im Kleingedruckten.
          // Ausgerechnet die Zusage darueber, was das Geraet weitergibt, darf
          // nicht wie ein Lizenztext aussehen.
          Text(
            context.t(
              'Health Connect ist eine Schnittstelle des Geräts. AXIOM liest nur und ruft nichts von sich aus auf. Solange der Expertenmodus läuft, sind diese Werte im lokalen Netz abrufbar.',
            ),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: p.inkFaint),
          ),
        ],
      ),
    );
  }

  Future<void> _act(HealthAvailability availability) async {
    switch (availability) {
      case HealthAvailability.needsUpdate:
        await HealthSync.openSettings();
      case HealthAvailability.notGranted:
        await HealthSync.connect();
      case HealthAvailability.ready:
        await _import();
      case HealthAvailability.unavailable:
        break;
    }
    if (mounted) ref.invalidate(healthAvailabilityProvider);
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final runtime = await ref.read(runtimeProvider.future);
    final result = await HealthSync.import(runtime);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Sachlich zaehlen, nicht loben. Auch "nichts Neues" ist ein Ergebnis.
      _lastResult = result.imported == 0
          ? context.t('Nichts Neues · {0} bereits vorhanden', [result.skipped])
          : context.t('{0} Nächte · {1} Tage Schritte übernommen', [
              result.sleepNights,
              result.stepDays,
            ]);
    });
    if (result.imported > 0) refreshAxiom(ref);
  }
}

/// Stand der Eichung: Fortschritt, Anleitung und die Zahl betroffener Regeln.
class _BaselineSection extends ConsumerWidget {
  final int ungauged;
  const _BaselineSection({required this.ungauged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(baselineProvider).value;
    if (progress == null) return const SizedBox.shrink();
    final p = context.axiom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BaselineCard(progress: progress),
        if (ungauged > 0 && progress.status != BaselineStatus.calibrated) ...[
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: p.caution),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  context.t(
                    '{0} aktive {1} auf geschätzten Gewichten — unten markiert.',
                    [
                      ungauged,
                      ungauged == 1
                          ? context.t('Regel läuft')
                          : context.t('Regeln laufen'),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IssuesCard extends StatelessWidget {
  final List<RuleLoadIssue> issues;
  const _IssuesCard({required this.issues});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      accent: p.caution.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('Nicht geladen · {0}', [issues.length]),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t(
              'Diese Regeln wurden abgelehnt und sind nicht aktiv. Eine stumm übersprungene Regel wäre schlimmer als ein Fehler: Man verlässt sich auf etwas, das es nicht gibt.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text(
                '${issue.ruleId}: ${issue.message}',
                style: monoStyle(context, size: 11, color: p.caution),
              ),
            ),
        ],
      ),
    );
  }
}

/// `intervene` → `Intervene`. Gleiche Schreibweise wie im Regeleditor.
String _capitalized(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

/// Abgeleitete Werte, deren Formelgewichte bis zur Kalibrierung geschaetzt
/// sind. Regeln, die darauf pruefen, werden markiert — damit sichtbar
/// bleibt, worauf eine Empfehlung beruht (G2).
const _uncalibratedInputs = {
  'capacity',
  'focus_debt',
  'sensation_need',
  'load_index',
  'regulation',
  'sleep_debt',
  'load_level',
};

class _RuleTile extends StatelessWidget {
  final Rule rule;
  final SkipReason? skipReason;
  final RuleStats? stats;
  final bool calibrated;

  /// Im Geraet bearbeitet — dann ist „zuruecksetzen" moeglich.
  ///
  /// Nicht `override` genannt: Das ist in Dart eine Annotation, und ein Feld
  /// dieses Namens macht jede folgende `@override`-Zeile ungueltig.
  final RuleOverride? edit;

  const _RuleTile({
    required this.rule,
    required this.calibrated,
    this.skipReason,
    this.stats,
    this.edit,
  });

  bool get edited => edit != null;

  /// Laeuft diese Regel auf geschaetzten Schwellen?
  bool get _isUngauged =>
      !calibrated &&
      !rule.isShadow &&
      rule.when.referencedVariables
          .intersection(_uncalibratedInputs)
          .isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final shadow = rule.isShadow;
    final followRate = stats?.followRate;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // Karte statt Rahmen: Achtzehn haarliniengerahmte Kaesten
        // untereinander sind ein Gitter, und in einem Gitter ist alles gleich
        // weit weg. `Panel` traegt Flaeche, Radius und Schatten; das
        // `ClipRRect` haelt den Tipp-Effekt der `ExpansionTile` in den Ecken.
        child: Panel(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.panel),
            child: ExpansionTile(
            // Farbe am Tile statt am Container — sonst verdeckt der
            // DecoratedBox die Ink-Effekte des ListTile.
            backgroundColor: p.panel,
            collapsedBackgroundColor: p.panel,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: Space.lg),
            // Ohne diese Zeile zentriert `ExpansionTile` seine Kinder. Jedes
            // Feld war damit so breit wie seine laengste Zeile und schwebte
            // mittig — „Bedingung", „Aktion" und „Grenzen" standen an drei
            // verschiedenen linken Kanten, obwohl jedes intern sauber links
            // ausgerichtet ist. Nur „Begruendung" sah richtig aus, weil ihr
            // Fliesstext ohnehin die volle Breite fuellt.
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(
              Space.lg,
              0,
              Space.lg,
              Space.lg,
            ),
            // Die Regel-ID als `RuleStamp` statt als Text in
            // Schreibmaschine. Sie ist damit dasselbe Zeichen wie ueberall
            // sonst in der App — und der einzige Ort, an dem Monospace noch
            // steht, ist genau der, an dem sie etwas bedeutet (G2).
            title: Row(
              children: [
                RuleStamp(
                  ruleId: rule.id,
                  color: shadow ? p.inkFaint : p.info,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    context.ruleTitle(rule),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: p.ink),
                  ),
                ),
              ],
            ),
            // Wrap statt Row: Bis zu vier Marken, jede so breit wie ihr Text
            // — bei grosser Schrift passen die nicht mehr nebeneinander. Ein
            // ueberlaufender Row schneidet ausgerechnet die letzte Marke ab,
            // und die letzte ist hier UNGEEICHT oder die Befolgungsquote.
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  // „INTERVENE" waren neun Grossbuchstaben. Die vier Stufen
                  // sind Fachbegriffe des Regelwerks, stehen genau so in
                  // jeder YAML-Datei und werden deshalb nicht uebersetzt —
                  // aber sie brauchen keine Versalien, um Begriffe zu sein.
                  // Der Regeleditor schreibt sie schon so.
                  _Tag(
                    text: _capitalized(shadow ? 'shadow' : rule.severity.name),
                    color: shadow ? p.inkFaint : p.signal,
                  ),
                  if (rule.deficit != null)
                    _Tag(text: rule.deficit!, color: p.inkDim),
                  // Bleibt in Versalien, obwohl neun Zeichen: „UNGEEICHT" ist
                  // hier keine Ueberschrift, sondern der **Name** einer
                  // Markierung — die Eichungskarte weiter oben verweist mit
                  // genau diesem Wort darauf („betroffene Regeln sind unten
                  // mit UNGEEICHT markiert"). Wer ihn aendert, aendert beide
                  // Stellen.
                  if (_isUngauged)
                    _Tag(
                      text: context.t('Ungeeicht').toUpperCase(),
                      color: p.caution,
                    ),
                  // Die Befolgungsquote war gruen ab 40 % und kupfern
                  // darunter. Das ist die person-naechste Zahl der ganzen
                  // App — „wie oft hast du getan, was dir gesagt wurde" —
                  // und in zwei Farben liest sie sich als Zeugnis. Sie ist
                  // ein Messwert und traegt deshalb die Messfarbe, wie jeder
                  // andere auch (R7, D10). Was sie bedeutet, entscheidet das
                  // Review, nicht die Farbe.
                  if (followRate != null)
                    _Tag(
                      text: context.t('{0}% befolgt', [
                        (followRate * 100).round(),
                      ]),
                      color: p.signal,
                    ),
                ],
              ),
            ),
            children: [
              if (_isUngauged)
                _Field(
                  label: context.t('Ungeeicht'),
                  value: context.t(
                    'Diese Regel prüft auf Werte, deren Formelgewichte noch geschätzt sind. Sie kann danebenliegen, bis weights.yaml an echten Daten kalibriert ist.',
                  ),
                ),
              _Field(
                label: context.t('Begründung'),
                value: context.ruleRationale(rule).trim(),
              ),
              // Der Weg vom Lesen zum Ändern ist ein Tipp lang. Wer eine
              // Regel gerade versteht, ist der beste Zeitpunkt, sie zu
              // korrigieren — später erinnert man den Gedanken nicht mehr.
              Padding(
                padding: const EdgeInsets.only(top: Space.sm, bottom: Space.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(context.t('Bearbeiten')),
                    onPressed: () => showRuleEditor(
                      context,
                      existing: rule,
                      overridesShipped: !edited,
                    ),
                  ),
                ),
              ),
              _Field(
                label: context.t('Bedingung'),
                value: _describe(rule.when),
                mono: true,
              ),
              _Field(
                label: context.t('Aktion'),
                value: rule.then.type.token,
                mono: true,
              ),
              // Ab hier keine Schreibmaschine mehr: Grenzen und Statistik
              // sind Messwerte, kein woertlich abzutippender Text. Sie
              // laufen mit Tabellenziffern in der Hausschrift und stehen
              // damit genauso sauber untereinander, ohne den Ton eines
              // Terminalprotokolls. Woertlich bleiben nur Bedingung und
              // Aktion — die stehen so in der YAML-Datei.
              _Field(
                label: context.t('Grenzen'),
                value:
                    'Priorität ${rule.priority} · '
                    'Abstand ${rule.cooldown.minInterval.inMinutes} min'
                    '${rule.cooldown.maxPerDay == null ? "" : " · max ${rule.cooldown.maxPerDay}/Tag"}'
                    '${rule.cooldown.exponentialBackoff ? " · Backoff" : ""}',
                figures: true,
              ),
              if (stats != null)
                _Field(
                  label: context.t('Letzte 7 Tage'),
                  figures: true,
                  value:
                      '${stats!.fires}× gefeuert · '
                      '${stats!.suppressed}× verdrängt · '
                      '${stats!.followed} befolgt / ${stats!.deferred} später / '
                      '${stats!.rejected} abgelehnt',
                ),
              if (skipReason != null)
                _Field(
                  label: context.t('Gerade inaktiv'),
                  value: _skipText(context, skipReason!),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  static String _skipText(BuildContext context, SkipReason reason) =>
      switch (reason) {
        SkipReason.disabled => context.t('abgeschaltet'),
        SkipReason.conditionFalse => context.t('Bedingung trifft nicht zu'),
        SkipReason.cooldownActive => context.t('Cooldown läuft'),
        SkipReason.dailyLimitReached => context.t(
          'Tageslimit dieser Regel erreicht',
        ),
        SkipReason.globalLimitReached => context.t(
          'globales Tageslimit erreicht',
        ),
        // Gegenstueck zu „Meldungen pro Stunde" weiter unten in diesem
        // Screen: Die Grenze stand dort als geltend, ohne dass ein Grund
        // dafuer je hier auftauchen konnte.
        SkipReason.hourlyLimitReached => context.t(
          'Meldungen dieser Stunde erschöpft',
        ),
        SkipReason.quietHours => context.t('Ruhezeit'),
        SkipReason.lowConfidence => context.t(
          'Datenlage zu dünn — lieber schweigen',
        ),
      };

  /// Textform des Bedingungsbaums.
  static String _describe(Condition c, [int depth = 0]) {
    final pad = '  ' * depth;
    return switch (c) {
      AllOf(:final children) =>
        '${pad}ALLE:\n${children.map((x) => _describe(x, depth + 1)).join("\n")}',
      AnyOf(:final children) =>
        '${pad}EINE VON:\n${children.map((x) => _describe(x, depth + 1)).join("\n")}',
      NotCond(:final child) => '${pad}NICHT:\n${_describe(child, depth + 1)}',
      _ => '$pad$c',
    };
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  /// Woertlich abzutippen — Bedingungsbaum, Aktionstoken. Nur dafuer.
  final bool mono;

  /// Ein Messwert: Hausschrift mit Tabellenziffern.
  final bool figures;

  const _Field({
    required this.label,
    required this.value,
    this.mono = false,
    this.figures = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ohne `.toUpperCase()`: „BEGRÜNDUNG" und „GERADE INAKTIV" waren
          // gesperrte Versalien — die Wortform faellt dabei weg.
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: mono
                ? monoStyle(context, size: 12.5)
                : figures
                    ? readingStyle(context,
                        size: 14,
                        weight: FontWeight.w400,
                        height: 1.5,
                        color: p.inkDim)
                    : Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Mehrere Wege als **eine** Flaeche.
///
/// Die Karten waren einzeln, mit acht Pixeln Luft dazwischen. Auf einem
/// Schirm mit neun davon las sich das als neun gleich weit entfernte Dinge,
/// und der Abschnittstitel darueber ordnete nichts mehr — er stand nur da.
/// Eine Gruppe ist jetzt eine Karte mit Haarlinien; die Reihenfolge und das
/// Ziel jeder Zeile bleiben unveraendert.
class _LinkGroup extends StatelessWidget {
  final List<_LinkRow> rows;
  const _LinkGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      padding: EdgeInsets.zero,
      // Ohne Clip laeuft die Tippflaeche der ersten und letzten Zeile ueber
      // die abgerundeten Ecken der Karte hinaus.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.panel),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: Space.xxl + Space.md),
                  child: Divider(color: p.rule, height: 1),
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final Widget target;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => target)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        child: Row(
          // Das Zeichen sass mittig zur zweizeiligen Beschreibung und stand
          // damit neben nichts. Es gehoert auf die Hoehe der Zeile, die es
          // bezeichnet.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 19, color: p.inkDim),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Marke an einer Regel: Stufe, Defizit, Eichstand, Befolgungsquote.
///
/// Hier standen 9,5 px Schreibmaschine in einem Kasten mit 2 px Radius.
/// Beides zog in dieselbe Richtung: `monoStyle` hob die Groesse still auf
/// die Lesegrenze an, sodass der Kasten enger sass als die Schrift darin,
/// und der harte Radius machte aus vier Marken vier kleine Kaesten. Jetzt:
/// Hausschrift mit Tabellenziffern, Radius wie bei jedem anderen kleinen
/// Bedienelement.
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(Radii.control),
    ),
    child: Text(
      text,
      style: readingStyle(
        context,
        size: 12.5,
        weight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

class _Limit extends StatelessWidget {
  final String label;
  final String value;
  const _Limit({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: readingStyle(
            context,
            size: 15,
            weight: FontWeight.w600,
            color: context.axiom.signal,
          ),
        ),
      ],
    ),
  );
}

/// Das Regelwerk — die lange Liste, jetzt auf eigener Seite.
///
/// Sie stand vorher mitten im Systemscreen und hat alles darunter begraben:
/// Wer die Anzeige umstellen wollte, musste an siebzehn Regeln vorbei. Eine
/// lange Liste gehoert hinter einen Tipp, nicht in den Weg.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    final snapshot = ref.watch(snapshotProvider);
    final stats = ref.watch(ruleStatsProvider).value ?? const [];
    final p = context.axiom;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Regelwerk'))),
      body: runtime.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rt) {
          final skipped = snapshot.value?.skipped ?? const <SkippedRule>[];
          final skipReasons = {for (final s in skipped) s.rule.id: s.reason};
          final edits = {for (final o in rt.store.ruleOverrides()) o.id: o};

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.huge,
            ),
            children: [
              // Der Einstieg steht oben, nicht unten: Wer eine Regel anlegen
              // will, soll nicht erst an siebzehn vorbei.
              Panel(
                onTap: () => showRuleEditor(context),
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg, vertical: Space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.add, size: 19, color: p.signal),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.t('Neue Regel'),
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 2),
                          Text(
                            context.t('Geführt, mit Vorschau gegen den Zustand von jetzt'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              for (final rule in rt.rules)
                _RuleTile(
                  rule: rule,
                  calibrated: rt.weightsCalibrated,
                  skipReason: skipReasons[rule.id],
                  stats: stats.where((s) => s.ruleId == rule.id).firstOrNull,
                  edit: edits[rule.id],
                ),
              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Grenzen')),
              Panel(
                child: Column(
                  children: [
                    _Limit(
                      label: context.t('Interventionen pro Tag'),
                      value: '${rt.limits.maxInterventionsPerDay}',
                    ),
                    _Limit(
                      label: context.t('Meldungen pro Stunde'),
                      value: '${rt.limits.maxNotificationsPerHour}',
                    ),
                    _Limit(
                      label: context.t('Ruhezeit'),
                      value:
                          '${_hhmm(rt.limits.quietFromMinutes)}'
                          '–${_hhmm(rt.limits.quietToMinutes)}',
                    ),
                    _Limit(
                      label: context.t('Mindestkonfidenz'),
                      value: rt.limits.minConfidence.toStringAsFixed(2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(
                context.t(
                  'Regeln werden in YAML gepflegt und liegen unter Versionskontrolle. Neue Regeln laufen mindestens sieben Tage stumm mit (log_only), bevor sie etwas sagen dürfen.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              Text(
                context.t('Schema v{0} · {1} Regeln', [
                  kSchemaVersion,
                  rt.rules.length,
                ]),
                style: readingStyle(context,
                    size: 12.5, weight: FontWeight.w400, color: p.inkFaint),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, "0")}:'
      '${(minutes % 60).toString().padLeft(2, "0")}';
}

/// Datenquellen — bisher eine Karte mitten im Systemscreen.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('Datenquellen'))),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.huge,
      ),
      children: const [_HealthCard()],
    ),
  );
}
