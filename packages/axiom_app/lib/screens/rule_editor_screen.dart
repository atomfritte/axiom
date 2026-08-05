/// Regeleditor — das Regelwerk am Gerät ändern, ohne den Rechner.
///
/// **Was diesen Editor von einem Textfeld unterscheidet.** Er kennt den
/// Wortschatz der Engine (`RuleVocabulary`), also bietet er nur an, was sie
/// versteht — und er wertet jede Bedingung sofort gegen den *aktuellen*
/// Zustand aus. Man sieht beim Tippen, ob die Regel jetzt zuträfe und an
/// welchem Teil sie scheitert. Genau das macht G2 einlösbar: Wer nachrechnen
/// kann, muss nicht glauben.
///
/// **Was er bewusst nicht tut.** Er schreibt nicht in `rules/core/` — die
/// Assets bleiben unberührt, die Änderung liegt als Overlay in der Datenbank
/// und lässt sich als YAML wieder herauskopieren. Und er lässt keine Regel
/// sofort sprechen: Jede neue oder inhaltlich geänderte Regel läuft sieben
/// Tage stumm mit. Eine Regel, die am Tag ihrer Entstehung scharf geht, wird
/// an dem Tag beurteilt, an dem man sie für richtig hält.
library;

import 'package:axiom_core/axiom_core.dart';
// `Action` heisst in Flutter etwas anderes als im Regelwerk.
import 'package:axiom_core/axiom_core.dart' as core show Action;
import 'package:axiom_data/axiom_data.dart';
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
import '../state/rule_draft.dart';

/// Öffnet den Regeleditor — es sei denn, das Tagesbudget ist aufgebraucht.
///
/// **Warum hier gesperrt wird.** G4 ist laut CLAUDE.md das wichtigste Gesetz
/// dieses Projekts: AXIOM rationiert seine eigene Konfiguration. Das größte
/// Risiko ist nicht, dass die App zu wenig kann, sondern dass ihr Ausbau zur
/// Prokrastination wird (R1). Der Regeleditor ist die Stelle, an der das am
/// leichtesten passiert — er ist interessanter als jede Aufgabe, für die er
/// gebaut wurde.
///
/// Die Sperre stand bisher nur in der Roadmap. `isConfigLocked()` gab es,
/// aufgerufen hat sie niemand.
///
/// **Was nicht gesperrt wird.** Erfassen, Arbeiten, Nachsehen, Exportieren —
/// und das Abschalten einer Regel. Eine falsch feuernde Regel bis morgen
/// laufen zu lassen wäre Schadensbegrenzung durch Nichtstun; abschalten ist
/// keine Meta-Arbeit, sondern das Gegenteil.
Future<void> showRuleEditor(
  BuildContext context, {
  Rule? existing,
  bool overridesShipped = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final runtime = await container.read(runtimeProvider.future);
  if (await runtime.isConfigLocked()) {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => const _BudgetReached(),
    );
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => RuleEditorScreen(
      existing: existing,
      overridesShipped: overridesShipped,
    ),
  ));
}

/// Der Deckel greift. Sachlich, mit Regel-ID, ohne Vorwurf.
class _BudgetReached extends StatelessWidget {
  const _BudgetReached();

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    // Scrollbar, wie jedes Blatt: Bei grosser Schrift passt der Text sonst
    // nicht, und dann faehrt ausgerechnet die Begruendung unten hinaus.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RuleStamp(ruleId: 'R-010', color: p.info),
          const SizedBox(height: Space.lg),
          Text(context.t('Regelwerk heute zu'),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.md),
          Text(
            context.t('{0} Minuten im System sind heute verbraucht. Regeln zu schreiben ist ab jetzt bis morgen zu. Erfassen, Arbeiten und Nachsehen bleiben offen — und eine Regel abschalten geht weiterhin.', [kMetaBudget.inMinutes]),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          Text(
            context.t('Das ist keine Strafe, sondern der Zweck: Ein System zu bauen ist immer stimulierender als die Aufgabe, für die es gebaut wurde.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Verstanden')),
          ),
        ],
      ),
    );
  }
}

class RuleEditorScreen extends ConsumerStatefulWidget {
  final Rule? existing;
  final bool overridesShipped;

  const RuleEditorScreen({
    super.key,
    this.existing,
    this.overridesShipped = false,
  });

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> with MetaTimed<RuleEditorScreen> {
  @override
  String get metaScreen => 'rules';

  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _rationale =
      TextEditingController(text: widget.existing?.rationale.trim() ?? '');
  late final _actionText = TextEditingController(
      text: widget.existing?.then.params['text']?.toString() ?? '');

  late String _id;
  late String? _deficit = widget.existing?.deficit;
  late Severity _severity = widget.existing?.severity ?? Severity.nudge;
  late int _priority = widget.existing?.priority ?? 50;
  late int _cooldownMinutes =
      widget.existing?.cooldown.minInterval.inMinutes ?? 120;
  late int? _maxPerDay = widget.existing?.cooldown.maxPerDay;
  late ActionType _action = widget.existing?.then.type ?? ActionType.notify;
  late bool _enabled = widget.existing?.enabled ?? true;
  late final DraftGroup _root = widget.existing == null
      ? DraftGroup(children: [DraftLeaf()])
      : rootDraft(widget.existing!.when);

  StateEvalContext? _context;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _id = widget.existing?.id ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final runtime = await ref.read(runtimeProvider.future);
    final context_ = await runtime.currentContext();
    if (!mounted) return;
    setState(() {
      _context = context_;
      if (_id.isEmpty) _id = _nextId(runtime.rules);
    });
  }

  /// Neue Regeln bekommen IDs ab R-200.
  ///
  /// Der Bereich darunter gehört dem mitgelieferten Regelwerk; würde der
  /// Editor dort hineinvergeben, kollidierte die nächste ausgelieferte Regel
  /// mit einer selbst geschriebenen. IDs werden nie wiederverwendet — auch
  /// nicht nach dem Löschen.
  String _nextId(List<Rule> rules) {
    final used = rules
        .map((r) => int.tryParse(r.id.replaceFirst('R-', '')) ?? 0)
        .where((n) => n >= 200);
    final next = used.isEmpty ? 200 : used.reduce((a, b) => a > b ? a : b) + 1;
    return 'R-${next.toString().padLeft(3, '0')}';
  }

  @override
  void dispose() {
    _title.dispose();
    _rationale.dispose();
    _actionText.dispose();
    super.dispose();
  }

  // ── Prüfen ────────────────────────────────────────────────────────────

  /// Dieselben Pflichten wie im Validator, nur früher.
  ///
  /// `rationale` und `cooldown` sind keine Formalien: Ohne Begründung ist
  /// eine Ausgabe nicht auditierbar (G2), ohne Cooldown entsteht
  /// Benachrichtigungsflut (R2) — der häufigste Sterbeverlauf solcher Apps.
  List<String> get _problems {
    final problems = <String>[];
    if (_title.text.trim().length < 3) {
      problems.add(context.t('Der Titel fehlt. Er steht später in der Meldung.'));
    }
    if (_rationale.text.trim().length < 40) {
      problems.add(context.t('Die Begründung ist zu kurz. Sie erscheint im Systeminspektor und muss in einem halben Jahr noch erklären, warum es diese Regel gibt.'));
    }
    if (_cooldownMinutes < 1) {
      problems.add(context.t('Ohne Abstand meldet sich die Regel beliebig oft.'));
    }
    try {
      _root.build();
    } on ConditionError catch (e) {
      problems.add(e.message);
    }
    return problems;
  }

  Rule? _buildRule() {
    try {
      return Rule(
        id: _id,
        title: _title.text.trim(),
        rationale: _rationale.text.trim(),
        deficit: _deficit,
        when: _root.build(),
        then: core.Action(_action, {
          if (_action == ActionType.notify && _actionText.text.trim().isNotEmpty)
            'text': _actionText.text.trim(),
        }),
        priority: _priority,
        severity: _severity,
        cooldown: Cooldown(
          minInterval: Duration(minutes: _cooldownMinutes),
          maxPerDay: _maxPerDay,
        ),
        enabled: _enabled,
      );
    } on Object {
      return null;
    }
  }

  // ── Speichern ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    final rule = _buildRule();
    if (rule == null || _problems.isNotEmpty || _saving) return;
    setState(() => _saving = true);

    final runtime = await ref.read(runtimeProvider.future);
    final now = runtime.clock.nowLocal();
    runtime.store.saveRuleOverride(
      id: rule.id,
      yaml: ruleToYaml(rule),
      overridesShipped: widget.overridesShipped,
      updatedAt: now,
      // Jede Änderung startet die Schattenzeit neu. Auch bei einer bereits
      // laufenden Regel: Geändert ist neu, und beurteilt wird sie an Tagen,
      // die noch kommen.
      shadowUntil: now.add(kShadowPeriod),
    );
    ref.invalidate(runtimeProvider);
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.t('Gespeichert. Die Regel läuft sieben Tage stumm mit — im Systeminspektor siehst du, wie oft sie gefeuert hätte.')),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _reset() async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.store.deleteRuleOverride(_id);
    ref.invalidate(runtimeProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.overridesShipped
          ? context.t('Zurückgesetzt auf die mitgelieferte Fassung.')
          : context.t('Regel entfernt. Die Nummer wird nicht wiederverwendet.')),
    ));
  }

  // ── Aufbau ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final rule = _buildRule();
    final problems = _problems;
    final holds = _evaluate(_root);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? context.t('Neue Regel') : _id),
        actions: [
          if (rule != null)
            IconButton(
              icon: const Icon(Icons.code),
              tooltip: context.t('Als YAML zeigen'),
              onPressed: () => _showYaml(rule),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: [
          // Reihenfolge nach dem tatsächlichen Vorgehen, nicht nach der
          // Struktur der Datei: Man hat zuerst einen Gedanken („wenn wenig
          // da ist, nichts Schweres"), baut ihn, und *dann* fällt einem ein,
          // wie man ihn nennt und begründet. Die Begründung nach dem Bau zu
          // schreiben ist außerdem leichter — man sieht, was man gebaut hat.
          SectionLabel(context.t('Wie sie heißt')),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: context.t('Kurz und in deiner Sprache'),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Dieser Satz steht später in der Meldung. Kein Vorwurf, keine Frage — eine Feststellung.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),

          // ── Wann ────────────────────────────────────────────────────
          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Wann sie zutrifft')),
          // Als eigene Zeile statt als Anhängsel an der Überschrift: Die
          // Aussage ist der halbe Nutzen dieses Editors und darf nicht auf
          // drei Wörter gekürzt werden, weil rechts kein Platz ist.
          _HoldsBadge(holds: holds),
          const SizedBox(height: Space.sm),
          _GroupCard(
            group: _root,
            depth: 0,
            context_: _context,
            onChanged: () => setState(() {}),
            onRemove: null,
          ),

          // ── Dann ────────────────────────────────────────────────────
          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Was dann passiert')),
          _ActionPicker(
            value: _action,
            onChanged: (value) => setState(() => _action = value),
          ),
          if (_action == ActionType.notify) ...[
            const SizedBox(height: Space.md),
            TextField(
              controller: _actionText,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.t('Text der Meldung (optional)'),
              ),
            ),
          ],

          // ── Warum ───────────────────────────────────────────────────
          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Warum es sie gibt')),
          TextField(
            controller: _rationale,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.t('Was diese Regel verhindern oder auslösen soll'),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Pflichtfeld. Jede Ausgabe von AXIOM nennt ihre Regel und diese Begründung — ohne sie wäre die Empfehlung eine Behauptung.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          Text(context.t('Worauf sie einzahlt'),
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Space.sm),
          _DeficitPicker(
            value: _deficit,
            onChanged: (value) => setState(() => _deficit = value),
          ),

          // ── Wie laut ────────────────────────────────────────────────
          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Wie laut')),
          _SeverityPicker(
            value: _severity,
            onChanged: (value) => setState(() => _severity = value),
          ),

          const SizedBox(height: Space.lg),
          _Stepper(
            label: context.t('Mindestabstand'),
            value: _cooldownMinutes,
            unit: context.t('min'),
            steps: const [15, 30, 60, 120, 240, 480, 1440],
            meaning: context.t('Ohne Abstand entsteht Benachrichtigungsflut — der häufigste Grund, warum solche Apps wieder gelöscht werden.'),
            onChanged: (value) => setState(() => _cooldownMinutes = value),
          ),
          const SizedBox(height: Space.md),
          _Stepper(
            label: context.t('Höchstens pro Tag'),
            value: _maxPerDay ?? 0,
            unit: context.t('mal'),
            steps: const [0, 1, 2, 3, 5, 10],
            zeroLabel: context.t('kein Limit'),
            meaning: context.t('Eine harte Obergrenze zusätzlich zum Abstand.'),
            onChanged: (value) =>
                setState(() => _maxPerDay = value == 0 ? null : value),
          ),
          const SizedBox(height: Space.md),
          _Stepper(
            label: context.t('Rang bei Gleichstand'),
            value: _priority,
            unit: '',
            steps: const [10, 30, 50, 70, 90],
            meaning: context.t('Feuern zwei Regeln gleichzeitig, gewinnt die mit dem höheren Rang. Bei Gleichstand entscheidet die Nummer — nie der Zufall.'),
            onChanged: (value) => setState(() => _priority = value),
          ),

          const SizedBox(height: Space.lg),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t('Regel aktiv'),
                          style: Theme.of(context).textTheme.bodyLarge),
                      Text(
                        context.t('Ausgeschaltet bleibt sie erhalten, wird aber nicht ausgewertet.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),

          // ── Abschluss ───────────────────────────────────────────────
          const SizedBox(height: Space.xl),
          if (problems.isNotEmpty)
            Panel(
              accent: p.caution.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('Fehlt noch'),
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Space.sm),
                  for (final problem in problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: Text('· $problem',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            )
          else
            Panel(
              accent: p.info.withValues(alpha: 0.45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('SIEBEN TAGE STUMM'),
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Space.sm),
                  Text(
                    context.t('Die Regel läuft ab dem Speichern mit und wird protokolliert, sagt aber nichts. Im Systeminspektor siehst du, wie oft sie gefeuert hätte — danach entscheidest du, ob sie das wirklich soll.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: problems.isEmpty && !_saving ? _save : null,
            child: Text(context.t('Speichern')),
          ),
          if (!_isNew) ...[
            const SizedBox(height: Space.sm),
            Center(
              child: TextButton(
                onPressed: _reset,
                child: Text(widget.overridesShipped
                    ? context.t('Auf Auslieferungsstand zurücksetzen')
                    : context.t('Regel entfernen')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Trifft der Knoten gerade zu? Null heißt: noch nicht auswertbar.
  bool? _evaluate(DraftNode node) {
    final ctx = _context;
    if (ctx == null) return null;
    try {
      return node.build().eval(ctx);
    } on Object {
      return null;
    }
  }

  void _showYaml(Rule rule) {
    final yaml = ruleToYaml(rule);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sheet.t('ALS YAML'),
                style: Theme.of(sheet).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(
              sheet.t('Genau so kann die Regel nach rules/ zurück — der Editor ist keine Einbahnstraße.'),
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(yaml,
                    style: monoStyle(sheet, size: 12.5)),
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: yaml));
                if (!sheet.mounted) return;
                Navigator.of(sheet).pop();
              },
              child: Text(sheet.t('Kopieren')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bedingungsbaum ──────────────────────────────────────────────────────

/// Eine Gruppe: alle Bedingungen, oder eine von ihnen.
class _GroupCard extends StatelessWidget {
  final DraftGroup group;
  final int depth;
  final StateEvalContext? context_;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _GroupCard({
    required this.group,
    required this.depth,
    required this.context_,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      accent: depth > 0 ? p.rule : null,
      padding: EdgeInsets.all(depth > 0 ? Space.md : Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap statt Row: Bei grosser Schrift und in der zweiten
          // Verschachtelungsebene passen Umschalter, NICHT und Schliessen
          // nicht mehr nebeneinander. Ein ueberlaufender Row schneidet
          // ausgerechnet das Schliessen ab.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Segmented(
                options: [
                  (value: false, label: context.t('ALLE')),
                  (value: true, label: context.t('EINE VON')),
                ],
                value: group.any,
                onChanged: (value) {
                  group.any = value;
                  onChanged();
                },
              ),
              _NotToggle(
                on: group.negated,
                onChanged: (value) {
                  group.negated = value;
                  onChanged();
                },
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                  tooltip: context.t('Gruppe entfernen'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (var i = 0; i < group.children.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: switch (group.children[i]) {
                final DraftGroup child => _GroupCard(
                    group: child,
                    depth: depth + 1,
                    context_: context_,
                    onChanged: onChanged,
                    onRemove: () {
                      group.children.removeAt(i);
                      onChanged();
                    },
                  ),
                final DraftLeaf leaf => _LeafCard(
                    leaf: leaf,
                    context_: context_,
                    onChanged: onChanged,
                    onRemove: group.children.length == 1 && depth == 0
                        ? null
                        : () {
                            group.children.removeAt(i);
                            onChanged();
                          },
                  ),
              },
            ),
          Wrap(
            spacing: Space.sm,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.t('Bedingung')),
                onPressed: () {
                  group.children.add(DraftLeaf());
                  onChanged();
                },
              ),
              // Verschachtelung nur bis zur dritten Ebene: Drei sind lesbar,
              // vier sind ein Programm.
              if (depth < 2)
                TextButton.icon(
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: Text(context.t('Gruppe')),
                  onPressed: () {
                    group.children
                        .add(DraftGroup(any: !group.any, children: [DraftLeaf()]));
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eine einzelne Bedingung, mit dem Istwert daneben.
class _LeafCard extends StatelessWidget {
  final DraftLeaf leaf;
  final StateEvalContext? context_;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _LeafCard({
    required this.leaf,
    required this.context_,
    required this.onChanged,
    required this.onRemove,
  });

  bool? get _holds {
    final ctx = context_;
    if (ctx == null) return null;
    try {
      return leaf.build().eval(ctx);
    } on Object {
      return null;
    }
  }

  /// Was gerade tatsächlich anliegt — die halbe Miete beim Regelschreiben.
  String? _actual(BuildContext context) {
    final ctx = context_;
    if (ctx == null) return null;
    return switch (leaf.kind) {
      LeafKind.number => ctx.numeric(leaf.variable)?.toString(),
      LeafKind.choice => ctx.symbolic(leaf.variable),
      LeafKind.timeRange =>
        '${ctx.localNow.hour.toString().padLeft(2, '0')}:'
            '${ctx.localNow.minute.toString().padLeft(2, '0')}',
      LeafKind.minutesSince => ctx.minutesSince(leaf.event)?.toString() ??
          context.t('nie'),
      LeafKind.countToday => '${ctx.countToday(leaf.event)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final holds = _holds;
    final actual = _actual(context);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: p.base,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(
          color: holds == null
              ? p.rule
              : holds
                  ? p.calm.withValues(alpha: 0.6)
                  : p.rule,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _Dropdown<LeafKind>(
                  value: leaf.kind,
                  items: [
                    for (final kind in LeafKind.values)
                      (value: kind, label: context.t(kind.label)),
                  ],
                  onChanged: (kind) {
                    leaf.switchTo(kind);
                    onChanged();
                  },
                ),
              ),
              _NotToggle(
                on: leaf.negated,
                onChanged: (value) {
                  leaf.negated = value;
                  onChanged();
                },
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                  tooltip: context.t('Bedingung entfernen'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ..._fields(context),
          if (actual != null) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Icon(
                  holds == true ? Icons.check_circle_outline : Icons.circle_outlined,
                  size: 15,
                  color: holds == true ? p.calm : p.inkFaint,
                ),
                const SizedBox(width: Space.sm),
                Text(
                  context.t('jetzt: {0}', [actual]),
                  style: monoStyle(context,
                      size: 12, color: holds == true ? p.calm : p.inkDim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _fields(BuildContext context) => switch (leaf.kind) {
        LeafKind.number => [
            _Dropdown<String>(
              value: leaf.variable,
              items: [
                for (final v in RuleVocabulary.numerics)
                  (value: v.id, label: context.t(v.label)),
              ],
              onChanged: (id) {
                leaf.variable = id;
                onChanged();
              },
            ),
            const SizedBox(height: Space.sm),
            _meaning(context,
                RuleVocabulary.numeric(leaf.variable)?.meaning ?? ''),
            const SizedBox(height: Space.sm),
            _OpAndNumber(leaf: leaf, onChanged: onChanged, max: 100),
          ],
        LeafKind.choice => [
            _Dropdown<String>(
              value: leaf.variable,
              items: [
                for (final v in RuleVocabulary.symbolics)
                  (value: v.id, label: context.t(v.label)),
              ],
              onChanged: (id) {
                leaf.variable = id;
                leaf.symbol =
                    RuleVocabulary.symbolic(id)!.values.keys.first;
                onChanged();
              },
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                _Segmented<bool>(
                  options: [
                    (value: true, label: context.t('IST')),
                    (value: false, label: context.t('IST NICHT')),
                  ],
                  value: leaf.op == CompareOp.eq,
                  onChanged: (isEq) {
                    leaf.op = isEq ? CompareOp.eq : CompareOp.ne;
                    onChanged();
                  },
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final entry
                    in RuleVocabulary.symbolic(leaf.variable)!.values.entries)
                  _ValueChip(
                    label: context.t(entry.value),
                    selected: leaf.symbol == entry.key,
                    onTap: () {
                      leaf.symbol = entry.key;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
        LeafKind.timeRange => [
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: context.t('von'),
                    minutes: leaf.fromMinutes,
                    onChanged: (m) {
                      leaf.fromMinutes = m;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _TimeField(
                    label: context.t('bis'),
                    minutes: leaf.toMinutes,
                    onChanged: (m) {
                      leaf.toMinutes = m;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            _meaning(context,
                context.t('Über Mitternacht hinweg erlaubt — 22:00 bis 05:00 meint die Nacht.')),
          ],
        LeafKind.minutesSince || LeafKind.countToday => [
            _Dropdown<String>(
              value: leaf.event,
              items: [
                for (final e in RuleVocabulary.events)
                  (value: e.id, label: context.t(e.label)),
              ],
              onChanged: (id) {
                leaf.event = id;
                onChanged();
              },
            ),
            const SizedBox(height: Space.sm),
            _OpAndNumber(
              leaf: leaf,
              onChanged: onChanged,
              max: leaf.kind == LeafKind.minutesSince ? 1440 : 20,
            ),
            if (leaf.kind == LeafKind.minutesSince) ...[
              const SizedBox(height: Space.sm),
              _meaning(context,
                  context.t('Ein Ereignis, das nie eintrat, gilt als unendlich lange her. Für „läuft seit" braucht es zusätzlich eine Bedingung darauf, dass überhaupt etwas läuft.')),
            ],
          ],
      };

  Widget _meaning(BuildContext context, String text) => Text(
        text,
        style: monoStyle(context, size: 11.5, color: context.axiom.inkFaint),
      );
}

class _OpAndNumber extends StatelessWidget {
  final DraftLeaf leaf;
  final VoidCallback onChanged;
  final int max;

  const _OpAndNumber({
    required this.leaf,
    required this.onChanged,
    required this.max,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _Dropdown<CompareOp>(
              value: leaf.op,
              items: [
                for (final entry in RuleVocabulary.operatorLabels.entries)
                  (value: entry.key, label: context.t(entry.value)),
              ],
              onChanged: (op) {
                leaf.op = op;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: Space.md),
          _NumberField(
            value: leaf.number.toInt(),
            max: max,
            onChanged: (value) {
              leaf.number = value;
              onChanged();
            },
          ),
        ],
      );
}

// ── Bausteine ───────────────────────────────────────────────────────────

typedef _Item<T> = ({T value, String label});

class _Dropdown<T> extends StatelessWidget {
  final T value;
  final List<_Item<T>> items;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.md),
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.axiom.ink,
            ),
        items: [
          for (final item in items)
            DropdownMenuItem(value: item.value, child: Text(item.label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
}

class _NumberField extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: p.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(icon: Icons.remove, onTap: () => onChanged(_down())),
          SizedBox(
            width: 54,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: monoStyle(context,
                  size: 16, weight: FontWeight.w500, color: p.ink),
            ),
          ),
          _Step(icon: Icons.add, onTap: () => onChanged(_up())),
        ],
      ),
    );
  }

  /// Schrittweite passend zur Groessenordnung: Bei Minuten will niemand
  /// hundertmal tippen, bei einer Anzahl waeren Zehnerschritte unbrauchbar.
  int get _stepSize => max > 100
      ? 15
      : max > 20
          ? 5
          : 1;

  int _up() => (value + _stepSize).clamp(0, max);
  int _down() => (value - _stepSize).clamp(0, max);
}

class _Step extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Step({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 18, color: context.axiom.inkDim),
        ),
      );
}

class _Segmented<T> extends StatelessWidget {
  final List<_Item<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const _Segmented({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Wrap(
      spacing: Space.xs,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(option.value);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(
                color: option.value == value
                    ? p.signal.withValues(alpha: 0.85)
                    : p.panel,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(
                    color: option.value == value ? p.signal : p.rule),
              ),
              child: Text(
                option.label,
                style: monoStyle(context,
                    size: 12,
                    weight: FontWeight.w600,
                    color: option.value == value
                        ? Theme.of(context).colorScheme.onPrimary
                        : p.inkDim),
              ),
            ),
          ),
      ],
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ValueChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: selected ? p.signal.withValues(alpha: 0.85) : p.panel,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: selected ? p.signal : p.rule),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : p.inkDim,
              ),
        ),
      ),
    );
  }
}

class _NotToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _NotToggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!on);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 56),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: on ? p.caution.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: on ? p.caution : p.rule),
        ),
        child: Text(
          context.t('NICHT'),
          style: monoStyle(context,
              size: 11,
              weight: FontWeight.w600,
              color: on ? p.caution : p.inkFaint),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final text = '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: p.rule),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: monoStyle(context, size: 10.5, color: p.inkFaint)),
            Text(text,
                style: monoStyle(context,
                    size: 16, weight: FontWeight.w500, color: p.ink)),
          ],
        ),
      ),
    );
  }
}

class _HoldsBadge extends StatelessWidget {
  final bool? holds;
  const _HoldsBadge({required this.holds});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final (text, icon, color) = switch (holds) {
      true => (
          context.t('Trifft mit dem Zustand von jetzt zu.'),
          Icons.check_circle_outline,
          p.calm,
        ),
      false => (
          context.t('Trifft mit dem Zustand von jetzt nicht zu.'),
          Icons.circle_outlined,
          p.inkDim,
        ),
      null => (
          context.t('Noch unvollständig — unten steht, was fehlt.'),
          Icons.error_outline,
          p.caution,
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(text, style: monoStyle(context, size: 12, color: color)),
        ),
      ],
    );
  }
}

class _DeficitPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _DeficitPicker({required this.value, required this.onChanged});

  /// Die Kurzfassung. Die lange steht in docs/01 — hier zählt, dass die
  /// Zuordnung überhaupt getroffen wird: Eine Regel ohne Bezug ist verdächtig.
  static const _labels = {
    'D1': 'Kompensationskosten',
    'D2': 'Startbarriere',
    'D3': 'Meta-Work-Falle',
    'D4': 'Zeitwahrnehmung',
    'D5': 'Reizhunger',
    'D6': 'Hyperfokus',
    'D7': 'Körperwahrnehmung',
    'D8': 'Schlaf',
    'D9': 'Erfassungslücke',
    'D10': 'Emotionale Spitzen',
    'D11': 'Kontextwechsel',
    'D12': 'Langfristziele',
  };

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final entry in _labels.entries)
            _ValueChip(
              label: '${entry.key} · ${context.t(entry.value)}',
              selected: value == entry.key,
              onTap: () => onChanged(value == entry.key ? null : entry.key),
            ),
        ],
      );
}

class _ActionPicker extends StatelessWidget {
  final ActionType value;
  final ValueChanged<ActionType> onChanged;
  const _ActionPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final spec = RuleVocabulary.action(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Dropdown<ActionType>(
          value: value,
          items: [
            for (final action in RuleVocabulary.actions)
              (value: action.type, label: context.t(action.label)),
          ],
          onChanged: onChanged,
        ),
        if (spec != null) ...[
          const SizedBox(height: Space.sm),
          Text(context.t(spec.meaning),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _SeverityPicker extends StatelessWidget {
  final Severity value;
  final ValueChanged<Severity> onChanged;
  const _SeverityPicker({required this.value, required this.onChanged});

  static const _meaning = {
    Severity.info: 'Erscheint nur im Rückblick.',
    Severity.nudge: 'Still, wegwischbar.',
    Severity.intervene: 'Sichtbar, erwartet eine Antwort.',
    Severity.enforce: 'Verändert Systemverhalten. Nur für Regeln, die du im '
        'ruhigen Zustand selbst verbindlich gesetzt hast.',
  };

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Segmented<Severity>(
            options: [
              for (final severity in Severity.values)
                (value: severity, label: severity.name.toUpperCase()),
            ],
            value: value,
            onChanged: onChanged,
          ),
          const SizedBox(height: Space.sm),
          Text(context.t(_meaning[value]!),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final List<int> steps;
  final String meaning;
  final String? zeroLabel;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.unit,
    required this.steps,
    required this.meaning,
    required this.onChanged,
    this.zeroLabel,
  });

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final step in steps)
                  _ValueChip(
                    label: step == 0 && zeroLabel != null
                        ? zeroLabel!
                        : '$step $unit'.trim(),
                    selected: step == value,
                    onTap: () => onChanged(step),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(meaning, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
