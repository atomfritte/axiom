/// Impuls-Abfang — M6.
///
/// Kein Verbot, keine Sperre, keine Moral (G3). Nur Latenz und Sichtbarkeit —
/// und der Impulsdurchbruch überlebt beides meistens nicht.
///
/// Der Wirkmechanismus ist ein anderer als bei Blocker-Apps: Eine fremde
/// Sperre ist eine Herausforderung, eine selbst gesetzte Regel ein Vertrag
/// mit dem Vergangenheits-Ich. Deshalb schreibt AXIOM die Prüffragen nicht
/// vor — sie werden im ruhigen Zustand selbst formuliert [D5, D10].
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

class InterceptScreen extends ConsumerWidget {
  const InterceptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triggers = ref.watch(triggersProvider).value ?? const [];
    final active = ref.watch(snapshotProvider).value?.activeIntercept;
    final stats = ref.watch(interceptStatsProvider).value ?? const [];

    return MetaTimedScope(
      screen: 'intercept',
      child: Scaffold(
      appBar: AppBar(title: Text(context.t('Bremse'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: [
          if (active != null) ...[
            _ActiveRunCard(run: active),
            const SizedBox(height: Space.xl),
          ],

          if (triggers.isEmpty)
            const _EmptyTriggers()
          else ...[
            SectionLabel(context.t('Trigger · {0}', [triggers.length])),
            for (final trigger in triggers)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _TriggerRow(
                  trigger: trigger,
                  stats: stats
                      .where((s) => s.triggerId == trigger.id)
                      .firstOrNull,
                  disabled: active != null,
                ),
              ),
          ],

          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: () => _edit(context, null),
            icon: Icon(Icons.add, size: 18, color: context.axiom.signal),
            label: Text(context.t('Trigger anlegen')),
          ),

          const SizedBox(height: Space.xl),
          Text(
            context.t('Die Prüffragen schreibst du im ruhigen Zustand. Eine fremde Frage klickt man weg, die eigene beantwortet man.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _edit(BuildContext context, InterceptTrigger? existing) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TriggerSheet(existing: existing),
      );
}

/// Hier stand dieselbe Spalte noch einmal von Hand: Marke, Ueberschrift,
/// Erklaertext. [EmptyState] ist genau dafuer da und bringt zwei Dinge mit,
/// die die Handarbeit nicht hatte — die richtigen Abstaende und eine
/// eigene Scrollansicht, wenn der Erklaertext bei grosser Schrift laenger
/// wird als der Schirm.
///
/// Die Marke stand als `KEINE TRIGGER` in Versalien da — auf dem einzigen
/// Schirm, den man im Impuls oeffnet, und ueber einem Satz, der erklaeren
/// soll, warum Warten hilft. Jetzt normale Schreibweise.
class _EmptyTriggers extends StatelessWidget {
  const _EmptyTriggers();

  @override
  Widget build(BuildContext context) => EmptyState(
        label: context.t('Keine Trigger'),
        headline: context.t('Noch nichts eingerichtet.'),
        body: context.t('Ein Trigger ist eine Handlung, die du im Moment tun willst und am nächsten Tag oft nicht mehr. Statt sie zu sperren, schiebt AXIOM eine Wartezeit dazwischen — und stellt dir deine eigenen Fragen.'),
      );
}

/// Läuft gerade eine Wartezeit.
class _ActiveRunCard extends ConsumerStatefulWidget {
  final InterceptRun run;
  const _ActiveRunCard({required this.run});

  @override
  ConsumerState<_ActiveRunCard> createState() => _ActiveRunCardState();
}

class _ActiveRunCardState extends ConsumerState<_ActiveRunCard> {
  final _answers = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final run = widget.run;
    final released = !run.isActive(now);
    final runtime = ref.watch(runtimeProvider).value;
    final trigger = ref
        .watch(triggersProvider)
        .value
        ?.where((t) => t.id == run.triggerId)
        .firstOrNull;

    // Die laufende Wartezeit ist das Einzige, worum es auf diesem Schirm
    // gerade geht — also die einzige erhobene Flaeche (G1). Vorher trug sie
    // einen Signalrahmen; ein Rahmen sagt „hier ist eine Grenze", die
    // Griffhoehe sagt „das hier geht jetzt in die Hand".
    return Panel(
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // War `WARTEZEIT LÄUFT` / `WARTEZEIT VORBEI`. Fuenfzehn Versalien
          // ueber einer laufenden Wartezeit lesen sich als Sperre; gemeint
          // ist eine Ablesung — es laeuft eine Uhr, sonst nichts (G3).
          Text(released ? context.t('Wartezeit vorbei') : context.t('Wartezeit läuft'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(run.triggerLabel,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.lg),

          if (!released)
            // War Schreibmaschine in w300, 36 px. Die Restzeit ist der
            // Messwert dieses Schirms — Hausschrift, Tabellenziffern, damit
            // beim Herunterzaehlen von 11 auf 9 nichts springt.
            Text(
              context.t('{0} min', [run.remaining(now).inMinutes]),
              style: readingStyle(context, size: 40, color: p.signal),
            ),
          const SizedBox(height: Space.sm),
          // Vorher `interceptWaitingText` — der fertig zusammengesetzte
          // deutsche Satz. Die uebersetzbare Fassung mit getrennten Werten
          // gab es daneben schon; sie wurde nur nicht benutzt, und die
          // Wartezeit stand deshalb in der englischen App deutsch da.
          Text(
            runtime == null
                ? ''
                : context.p(runtime.interceptWaitingPhrase(run)),
            style: Theme.of(context).textTheme.bodyMedium,
          ),

          if (trigger != null && trigger.checklist.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            // War `DEINE FRAGEN`. Es sind die selbst geschriebenen Fragen —
            // die Marke darueber soll sie nicht anschreien.
            Text(context.t('Deine Fragen'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            for (final (index, question) in trigger.checklist.indexed)
              _ChecklistRow(
                question: question,
                checked: _answers[index] ?? false,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _answers[index] = !(_answers[index] ?? false));
                },
              ),
          ],

          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: () => _resolve(InterceptOutcome.aborted),
                  child: Text(context.t('Lasse ich')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: released
                      ? () => _resolve(InterceptOutcome.proceeded)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  ),
                  child: Text(context.t('Mache ich'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (!released) ...[
            const SizedBox(height: Space.sm),
            Text(
              context.t('„Mache ich" wird frei, wenn die Wartezeit um ist.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(InterceptOutcome outcome) async {
    final runtime = await ref.read(runtimeProvider.future);
    final answers = List<bool>.generate(
      _answers.isEmpty ? 0 : _answers.keys.reduce((a, b) => a > b ? a : b) + 1,
      (i) => _answers[i] ?? false,
    );
    await runtime.resolveIntercept(widget.run, outcome, answers: answers);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
  }
}

class _ChecklistRow extends StatelessWidget {
  final String question;
  final bool checked;
  final VoidCallback onTap;

  const _ChecklistRow({
    required this.question,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 18,
              color: checked ? p.calm : p.inkFaint,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              // Dieselbe Frage wie im Editor, dieselbe Regel: Vorlagen
              // werden uebersetzt, eigene Formulierungen bleiben stehen.
              child: Text(context.t(question),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: checked ? p.ink : p.inkDim,
                      )),
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerRow extends ConsumerWidget {
  final InterceptTrigger trigger;
  final InterceptStats? stats;
  final bool disabled;

  const _TriggerRow({
    required this.trigger,
    required this.stats,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final hold = stats?.holdRate;

    return Panel(
      accent: stats?.needsReview == true
          ? p.caution.withValues(alpha: 0.4)
          : null,
      onTap: disabled
          ? null
          : () async {
              final runtime = await ref.read(runtimeProvider.future);
              await runtime.startIntercept(trigger);
              await HapticFeedback.mediumImpact();
              refreshAxiom(ref);
            },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trigger.label,
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                // War Schreibmaschine in 10,5 px — unter der Lesegrenze und
                // im Ton eines Protokolls. Wartezeit und Haltequote sind
                // Messwerte und laufen mit Tabellenziffern.
                Text(
                  trigger.releaseAt != null
                      ? context.t('Freigabe {0}', [trigger.releaseAt])
                      : context.t('{0} min warten{1}', [trigger.cooldown.inMinutes, hold == null ? "" : " · ${(hold * 100).round()} % gehalten"]),
                  style: readingStyle(context,
                      size: 13.5,
                      weight: FontWeight.w400,
                      color: stats?.needsReview == true ? p.caution : p.inkFaint),
                ),
              ],
            ),
          ),
          if (!disabled) ...[
            const SizedBox(width: Space.md),
            // War `AUSLÖSEN`. Eine Handlungsmarke am Zeilenende, kein
            // Warnschild — acht Versalien in Signalfarbe waren das
            // Auffaelligste der Liste und meinten das Unauffaelligste.
            Text(context.t('Auslösen'), style: sectionStyle(context, color: p.signal)),
          ],
        ],
      ),
    );
  }
}

// ── Trigger anlegen ─────────────────────────────────────────────────────

/// Auswahl-Chips in der Sprache dieser Oberflaeche — gewaehlt kommt heraus,
/// ungewaehlt liegt in der Mulde. Ohne das setzt Material
/// `secondaryContainer` (in dieser Palette ein Blau) und damit eine zweite
/// Farbe fuer dieselbe Aussage. Gehoert nach `theme.dart`; bis dahin steht
/// dasselbe Stueck in jeder Datei mit Chips.
ChipThemeData _chipLook(BuildContext context) {
  final p = context.axiom;
  return ChipThemeData(
    backgroundColor: p.well,
    selectedColor: p.signal.withValues(alpha: 0.16),
    showCheckmark: false,
    side: BorderSide.none,
    labelStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: p.ink),
    secondaryLabelStyle:
        Theme.of(context).textTheme.bodyMedium!.copyWith(color: p.signal),
    padding: const EdgeInsets.symmetric(
        horizontal: Space.md, vertical: Space.sm),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
    ),
  );
}

class _TriggerSheet extends ConsumerStatefulWidget {
  final InterceptTrigger? existing;
  const _TriggerSheet({this.existing});

  @override
  ConsumerState<_TriggerSheet> createState() => _TriggerSheetState();
}

class _TriggerSheetState extends ConsumerState<_TriggerSheet> {
  late final _label =
      TextEditingController(text: widget.existing?.label ?? '');
  late final _question = TextEditingController();
  late final List<String> _checklist =
      List.of(widget.existing?.checklist ?? const []);
  late int _minutes = widget.existing?.cooldown.inMinutes ?? 15;
  late String? _releaseAt = widget.existing?.releaseAt;

  @override
  void dispose() {
    _label.dispose();
    _question.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _label.text.trim().isNotEmpty && _checklist.isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final runtime = await ref.read(runtimeProvider.future);
    final label = _label.text.trim();
    await runtime.saveTrigger(InterceptTrigger(
      id: widget.existing?.id ??
          label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
      label: label,
      cooldown: Duration(minutes: _minutes),
      releaseAt: _releaseAt,
      checklist: _checklist,
      // Selbst angelegt heißt selbst autorisiert — genau das ist der Vertrag.
      authorized: true,
    ));
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
            // War `TRIGGER` — Rubrik ueber der Ueberschrift des Blattes,
            // dieselbe Rolle wie „Zerlegen" im Zerlegeblatt.
            Text(context.t('Trigger'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.t('Wobei willst du eine Wartezeit?'),
              ),
            ),

            const SizedBox(height: Space.xl),
            Text(context.t('Wie lange warten'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.md),
            ChipTheme(
              data: _chipLook(context),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final option in [5, 15, 30, 60, 1440])
                    ChoiceChip(
                      label: Text(option >= 1440 ? '24 h' : context.t('{0} min', [option])),
                      selected: _releaseAt == null && _minutes == option,
                      onSelected: (_) => setState(() {
                        _minutes = option;
                        _releaseAt = null;
                      }),
                    ),
                  ChoiceChip(
                    label: Text(context.t('bis 09:00')),
                    selected: _releaseAt == '09:00',
                    onSelected: (_) => setState(() => _releaseAt = '09:00'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.t('Für Nachtentscheidungen ist „bis 09:00" das Wirksamste — was um eins dringend wirkt, sieht um neun anders aus.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: Space.xl),
            Text(context.t('Deine Prüffragen'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              context.t('Ohne mindestens eine Frage kein Trigger. Sie ist der Vertrag.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),

            for (final (index, question) in _checklist.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Row(
                  children: [
                    Expanded(
                      // Eine uebernommene Vorlage steht deutsch in der
                      // Liste — hier wird sie uebersetzt. Eine selbst
                      // geschriebene Frage kennt die Woerterliste nicht und
                      // bleibt unveraendert stehen, genau wie eingetippt.
                      child: Text(context.t(question),
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: p.inkFaint),
                      onPressed: () =>
                          setState(() => _checklist.removeAt(index)),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _question,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _addQuestion(),
                    decoration: InputDecoration(
                      hintText: context.t('Eigene Frage…'),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                IconButton(
                  icon: Icon(Icons.add, color: p.signal),
                  onPressed: _addQuestion,
                ),
              ],
            ),

            const SizedBox(height: Space.lg),
            // War `ODER EINE VORLAGE`.
            Text(context.t('Oder eine Vorlage'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            // Hier standen `ActionChip`s. Das war die falsche Bauform, und
            // es hat sichtbar geschadet: Ein Material-Chip setzt seine
            // Beschriftung **einzeilig** (`maxLines: 1`, `softWrap: false`,
            // `TextOverflow.fade`). „Was genau löst es, das ich gestern noch
            // nicht lösen musste?" lief damit rechts aus dem Bild und
            // verblasste mitten im Satz — ohne Ueberlaufmeldung, weil der
            // Chip das als vorgesehen betrachtet. Wer die Vorlage nicht
            // lesen kann, kann sie nicht waehlen.
            //
            // Eine Vorlage ist ohnehin kein Chip, sondern ein Satz: volle
            // Breite, umbrechend, mit dem Plus als Aufforderung.
            for (final seed in kChecklistSeeds)
              if (!_checklist.contains(seed))
                // Gespeichert wird der deutsche Quelltext, angezeigt die
                // Uebersetzung: Der deutsche Satz ist der Schluessel, also
                // wandert eine einmal gewaehlte Vorlage bei einem
                // Sprachwechsel mit. Waere hier der englische Satz abgelegt,
                // haette die Checkliste dauerhaft die Sprache des Tages, an
                // dem sie entstand.
                _SeedRow(
                  text: context.t(seed),
                  onTap: () => setState(() => _checklist.add(seed)),
                ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(context.t('Trigger speichern')),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.archiveTrigger(widget.existing!.id);
                    refreshAxiom(ref);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(context.t('Trigger entfernen')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addQuestion() {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add(text);
      _question.clear();
    });
  }
}

/// Eine Vorlage zum Uebernehmen — voller Satz, volle Breite.
///
/// Liegt in der Mulde wie alles Waehlbare in einem Blatt. Das Plus steht
/// rechts und sagt, was ein Tipp bewirkt: Der Satz wandert nach oben in die
/// eigene Liste, er wird nicht ausgewaehlt.
class _SeedRow extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SeedRow({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final radius = BorderRadius.circular(Radii.control);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: p.well,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.lg, vertical: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(text,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(width: Space.md),
                Icon(Icons.add, size: 18, color: p.signal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
