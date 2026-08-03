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
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/baseline_card.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'channels_screen.dart';
import 'signal_screen.dart';
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
    final stats = ref.watch(ruleStatsProvider).value ?? const [];
    final p = context.axiom;

    return Scaffold(
      appBar: AppBar(title: const Text('System')),
      body: runtime.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rt) {
          final skipped = snapshot.value?.skipped ?? const <SkippedRule>[];
          final skipReasons = {
            for (final s in skipped) s.rule.id: s.reason,
          };
          final used = snapshot.value?.metaUsedToday ?? Duration.zero;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.huge),
            children: [
              _BudgetCard(used: used),
              const SizedBox(height: Space.xl),
              const SectionLabel('Eichung'),
              _BaselineSection(
                ungauged: rt.rules
                    .where((r) =>
                        !r.isShadow &&
                        r.when.referencedVariables
                            .intersection(_uncalibratedInputs)
                            .isNotEmpty)
                    .length,
              ),
              if (rt.ruleIssues.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                _IssuesCard(issues: rt.ruleIssues),
              ],
              const SizedBox(height: Space.xl),
              SectionLabel('Regelwerk · ${rt.rules.length}'),
              for (final rule in rt.rules)
                _RuleTile(
                  rule: rule,
                  calibrated: rt.weightsCalibrated,
                  skipReason: skipReasons[rule.id],
                  stats: stats.where((s) => s.ruleId == rule.id).firstOrNull,
                ),
              const SizedBox(height: Space.xl),
              const SectionLabel('Grenzen'),
              Panel(
                child: Column(
                  children: [
                    _Limit(
                        label: 'Interventionen pro Tag',
                        value: '${rt.limits.maxInterventionsPerDay}'),
                    _Limit(
                        label: 'Meldungen pro Stunde',
                        value: '${rt.limits.maxNotificationsPerHour}'),
                    _Limit(
                        label: 'Ruhezeit',
                        value: '${_hhmm(rt.limits.quietFromMinutes)}'
                            '–${_hhmm(rt.limits.quietToMinutes)}'),
                    _Limit(
                        label: 'Mindestkonfidenz',
                        value: rt.limits.minConfidence.toStringAsFixed(2)),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              const SectionLabel('Weiteres'),
              _LinkRow(
                icon: Icons.bolt_outlined,
                label: 'Erfassen',
                detail: 'Wege in die App: Widget, Benachrichtigung, Stift',
                target: const ChannelsScreen(),
              ),
              const SizedBox(height: Space.sm),
              _LinkRow(
                icon: Icons.history_toggle_off,
                label: 'Vorfälle',
                detail: 'Emotionale Spitzen festhalten und einordnen',
                target: const SignalScreen(),
              ),
              const SizedBox(height: Space.sm),
              _LinkRow(
                icon: Icons.lock_outline,
                label: 'Daten',
                detail: 'Verschlüsselter Export, Import, Wirkfenster',
                target: const VaultScreen(),
              ),

              const SizedBox(height: Space.xl),
              Text(
                'Regeln werden in YAML gepflegt und liegen unter Versionskontrolle. '
                'Neue Regeln laufen mindestens sieben Tage stumm mit '
                '(log_only), bevor sie etwas sagen dürfen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              Text('SCHEMA v$kSchemaVersion · ${rt.rules.length} REGELN',
                  style: monoStyle(context, size: 10.5, color: p.inkFaint)),
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
          Text('META-WORK-BUDGET',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${used.inMinutes}',
                  style: TextStyle(
                    fontFamily: Fonts.mono,
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: over ? p.caution : p.ink,
                  )),
              Text(' / ${kMetaBudget.inMinutes} min heute',
                  style: monoStyle(context, size: 13)),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            over
                ? 'Budget aufgebraucht. Änderungen am Regelwerk sind bis zum '
                    'nächsten Wochen-Review gesperrt. Das ist Absicht: '
                    'Das System zu optimieren fühlt sich an wie Arbeit, '
                    'ist aber keine.'
                : 'Zeit, die du im System verbringst statt im Leben. '
                    'Erfassen zählt nicht mit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
                  '$ungauged aktive '
                  '${ungauged == 1 ? "Regel läuft" : "Regeln laufen"} '
                  'auf geschätzten Gewichten — unten markiert.',
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
          Text('NICHT GELADEN · ${issues.length}',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Diese Regeln wurden abgelehnt und sind nicht aktiv. '
            'Eine stumm übersprungene Regel wäre schlimmer als ein Fehler: '
            'Man verlässt sich auf etwas, das es nicht gibt.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text('${issue.ruleId}: ${issue.message}',
                  style: monoStyle(context, size: 11, color: p.caution)),
            ),
        ],
      ),
    );
  }
}

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

  const _RuleTile({
    required this.rule,
    required this.calibrated,
    this.skipReason,
    this.stats,
  });

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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.panel),
            border: Border.all(color: p.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            // Farbe am Tile statt am Container — sonst verdeckt der
            // DecoratedBox die Ink-Effekte des ListTile.
            backgroundColor: p.panel,
            collapsedBackgroundColor: p.panel,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: Space.lg),
            childrenPadding: const EdgeInsets.fromLTRB(
                Space.lg, 0, Space.lg, Space.lg),
            title: Row(
              children: [
                Text(rule.id,
                    style: monoStyle(context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: shadow ? p.inkFaint : p.info)),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(rule.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: p.ink,
                          )),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _Tag(
                    text: shadow ? 'SHADOW' : rule.severity.name.toUpperCase(),
                    color: shadow ? p.inkFaint : p.signal,
                  ),
                  if (rule.deficit != null) ...[
                    const SizedBox(width: Space.sm),
                    _Tag(text: rule.deficit!, color: p.inkDim),
                  ],
                  if (_isUngauged) ...[
                    const SizedBox(width: Space.sm),
                    _Tag(text: 'UNGEEICHT', color: p.caution),
                  ],
                  if (followRate != null) ...[
                    const SizedBox(width: Space.sm),
                    _Tag(
                      text: '${(followRate * 100).round()}% befolgt',
                      color: followRate < 0.4 ? p.caution : p.calm,
                    ),
                  ],
                ],
              ),
            ),
            children: [
              if (_isUngauged)
                _Field(
                  label: 'Ungeeicht',
                  value: 'Diese Regel prüft auf Werte, deren Formelgewichte '
                      'noch geschätzt sind. Sie kann danebenliegen, bis '
                      'weights.yaml an echten Daten kalibriert ist.',
                ),
              _Field(label: 'Begründung', value: rule.rationale.trim()),
              _Field(label: 'Bedingung', value: _describe(rule.when), mono: true),
              _Field(label: 'Aktion', value: rule.then.type.token, mono: true),
              _Field(
                label: 'Grenzen',
                mono: true,
                value: 'Priorität ${rule.priority} · '
                    'Abstand ${rule.cooldown.minInterval.inMinutes} min'
                    '${rule.cooldown.maxPerDay == null ? "" : " · max ${rule.cooldown.maxPerDay}/Tag"}'
                    '${rule.cooldown.exponentialBackoff ? " · Backoff" : ""}',
              ),
              if (stats != null)
                _Field(
                  label: 'Letzte 7 Tage',
                  mono: true,
                  value: '${stats!.fires}× gefeuert · '
                      '${stats!.suppressed}× verdrängt · '
                      '${stats!.followed} befolgt / ${stats!.deferred} später / '
                      '${stats!.rejected} abgelehnt',
                ),
              if (skipReason != null)
                _Field(
                  label: 'Gerade inaktiv',
                  mono: true,
                  value: _skipText(skipReason!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _skipText(SkipReason reason) => switch (reason) {
        SkipReason.disabled => 'abgeschaltet',
        SkipReason.conditionFalse => 'Bedingung trifft nicht zu',
        SkipReason.cooldownActive => 'Cooldown läuft',
        SkipReason.dailyLimitReached => 'Tageslimit dieser Regel erreicht',
        SkipReason.globalLimitReached => 'globales Tageslimit erreicht',
        SkipReason.quietHours => 'Ruhezeit',
        SkipReason.lowConfidence => 'Datenlage zu dünn — lieber schweigen',
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
  final bool mono;
  const _Field({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text(
              value,
              style: mono
                  ? monoStyle(context, size: 11.5)
                  : Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
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
    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => target),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.inkDim),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyLarge),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(text,
            style: monoStyle(context,
                size: 9.5, weight: FontWeight.w600, color: color)),
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
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(value,
                style: monoStyle(context,
                    size: 12,
                    weight: FontWeight.w500,
                    color: context.axiom.ink)),
          ],
        ),
      );
}

