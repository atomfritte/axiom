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
      appBar: AppBar(title: Text(context.t('System'))),
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
              SectionLabel(context.t('Eichung')),
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
              SectionLabel(context.t('Regelwerk · {0}', [rt.rules.length])),
              for (final rule in rt.rules)
                _RuleTile(
                  rule: rule,
                  calibrated: rt.weightsCalibrated,
                  skipReason: skipReasons[rule.id],
                  stats: stats.where((s) => s.ruleId == rule.id).firstOrNull,
                ),
              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Grenzen')),
              Panel(
                child: Column(
                  children: [
                    _Limit(
                        label: context.t('Interventionen pro Tag'),
                        value: '${rt.limits.maxInterventionsPerDay}'),
                    _Limit(
                        label: context.t('Meldungen pro Stunde'),
                        value: '${rt.limits.maxNotificationsPerHour}'),
                    _Limit(
                        label: context.t('Ruhezeit'),
                        value: '${_hhmm(rt.limits.quietFromMinutes)}'
                            '–${_hhmm(rt.limits.quietToMinutes)}'),
                    _Limit(
                        label: context.t('Mindestkonfidenz'),
                        value: rt.limits.minConfidence.toStringAsFixed(2)),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Anzeige')),
              const _LanguageRow(),

              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Datenquellen')),
              const _HealthCard(),

              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Weiteres')),
              _LinkRow(
                icon: Icons.bolt_outlined,
                label: context.t('Erfassen'),
                detail: context.t('Wege in die App: Widget, Benachrichtigung, Stift'),
                target: const ChannelsScreen(),
              ),
              const SizedBox(height: Space.sm),
              _LinkRow(
                icon: Icons.history_toggle_off,
                label: context.t('Vorfälle'),
                detail: context.t('Emotionale Spitzen festhalten und einordnen'),
                target: const SignalScreen(),
              ),
              const SizedBox(height: Space.sm),
              _LinkRow(
                icon: Icons.lock_outline,
                label: context.t('Daten'),
                detail: context.t('Verschlüsselter Export, Import, Wirkfenster'),
                target: const VaultScreen(),
              ),

              const SizedBox(height: Space.xl),
              Text(
                context.t('Regeln werden in YAML gepflegt und liegen unter Versionskontrolle. Neue Regeln laufen mindestens sieben Tage stumm mit (log_only), bevor sie etwas sagen dürfen.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              Text(context.t('SCHEMA v{0} · {1} REGELN', [kSchemaVersion, rt.rules.length]),
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
          Text(context.t('META-WORK-BUDGET'),
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
              Text(context.t(' / {0} min heute', [kMetaBudget.inMinutes]),
                  style: monoStyle(context, size: 13)),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            over
                ? context.t('Budget aufgebraucht. Änderungen am Regelwerk sind bis zum nächsten Wochen-Review gesperrt. Das ist Absicht: Das System zu optimieren fühlt sich an wie Arbeit, ist aber keine.')
                : context.t('Zeit, die du im System verbringst statt im Leben. Erfassen zählt nicht mit.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Anzeigesprache.
///
/// Deutsch ist die Quelle, Englisch die Uebersetzung. Regeltexte kommen aus
/// dem YAML — fehlt dort eine Uebersetzung, steht der deutsche Satz da.
/// Sichtbar unfertig ist besser als still falsch.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      child: Row(
        children: [
          Icon(Icons.translate, size: 18, color: context.axiom.inkDim),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(context.t('Sprache der Oberfläche'),
                style: Theme.of(context).textTheme.bodyLarge),
          ),
          for (final language in AppLanguage.values)
            Padding(
              padding: const EdgeInsets.only(left: Space.sm),
              child: _LanguageChip(
                language: language,
                selected: language == current,
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguageChip extends ConsumerWidget {
  final AppLanguage language;
  final bool selected;

  const _LanguageChip({required this.language, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return GestureDetector(
      onTap: selected
          ? null
          : () async {
              await HapticFeedback.selectionClick();
              await ref.read(languageProvider.notifier).set(language);
            },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.xs),
        decoration: BoxDecoration(
          color: selected ? p.signal.withValues(alpha: 0.9) : p.base,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: selected ? p.signal : p.rule),
        ),
        child: Text(
          language.code.toUpperCase(),
          style: monoStyle(context,
              size: 11,
              weight: FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : p.inkDim),
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
          context.t('Auf diesem Gerät gibt es kein Health Connect. Schlaf und Bewegung kommen weiterhin aus deiner Eingabe.'),
          null,
        ),
      HealthAvailability.needsUpdate => (
          context.t('Aktualisierung nötig'),
          context.t('Die Systemkomponente ist älter als das, was AXIOM liest. Sie lässt sich in den Systemeinstellungen aktualisieren.'),
          context.t('Einstellungen öffnen'),
        ),
      HealthAvailability.notGranted => (
          context.t('Nicht freigegeben'),
          context.t('AXIOM liest zwei Größen: Schlaffenster und Tagesschritte. Beide gehen in die Kapazität ein — heute nur, soweit du sie selbst einträgst.'),
          'Freigeben',
        ),
      HealthAvailability.ready => (
          'Verbunden',
          context.t('Schlaffenster und Tagesschritte werden beim Start nachgezogen. Nur lesend, nur diese beiden, jederzeit widerrufbar.'),
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
              Icon(Icons.monitor_heart_outlined,
                  size: 19,
                  color: availability == HealthAvailability.ready
                      ? p.calm
                      : p.inkDim),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(context.t('Health Connect · {0}', [label]),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          if (_lastResult != null) ...[
            const SizedBox(height: Space.md),
            Text(_lastResult!,
                style: monoStyle(context, size: 11, color: p.signal)),
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
          Text(
            context.t('Health Connect ist eine Schnittstelle des Geräts. Nichts davon verlässt das Telefon — AXIOM hat keine Netzwerkberechtigung.'),
            style: monoStyle(context, size: 10.5, color: p.inkFaint),
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
          : context.t('{0} Nächte · {1} Tage Schritte übernommen', [result.sleepNights, result.stepDays]);
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
                  context.t('{0} aktive {1} auf geschätzten Gewichten — unten markiert.', [ungauged, ungauged == 1 ? context.t('Regel läuft') : context.t('Regeln laufen')]),
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
          Text(context.t('NICHT GELADEN · {0}', [issues.length]),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Diese Regeln wurden abgelehnt und sind nicht aktiv. Eine stumm übersprungene Regel wäre schlimmer als ein Fehler: Man verlässt sich auf etwas, das es nicht gibt.'),
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
                  child: Text(context.ruleTitle(rule),
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
                      text: context.t('{0}% befolgt', [(followRate * 100).round()]),
                      color: followRate < 0.4 ? p.caution : p.calm,
                    ),
                  ],
                ],
              ),
            ),
            children: [
              if (_isUngauged)
                _Field(
                  label: context.t('Ungeeicht'),
                  value: context.t('Diese Regel prüft auf Werte, deren Formelgewichte noch geschätzt sind. Sie kann danebenliegen, bis weights.yaml an echten Daten kalibriert ist.'),
                ),
              _Field(
                  label: context.t('Begründung'),
                  value: context.ruleRationale(rule).trim()),
              _Field(label: context.t('Bedingung'), value: _describe(rule.when), mono: true),
              _Field(label: context.t('Aktion'), value: rule.then.type.token, mono: true),
              _Field(
                label: context.t('Grenzen'),
                mono: true,
                value: 'Priorität ${rule.priority} · '
                    'Abstand ${rule.cooldown.minInterval.inMinutes} min'
                    '${rule.cooldown.maxPerDay == null ? "" : " · max ${rule.cooldown.maxPerDay}/Tag"}'
                    '${rule.cooldown.exponentialBackoff ? " · Backoff" : ""}',
              ),
              if (stats != null)
                _Field(
                  label: context.t('Letzte 7 Tage'),
                  mono: true,
                  value: '${stats!.fires}× gefeuert · '
                      '${stats!.suppressed}× verdrängt · '
                      '${stats!.followed} befolgt / ${stats!.deferred} später / '
                      '${stats!.rejected} abgelehnt',
                ),
              if (skipReason != null)
                _Field(
                  label: context.t('Gerade inaktiv'),
                  mono: true,
                  value: _skipText(context, skipReason!),
                ),
            ],
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
        SkipReason.dailyLimitReached => context.t('Tageslimit dieser Regel erreicht'),
        SkipReason.globalLimitReached => context.t('globales Tageslimit erreicht'),
        SkipReason.quietHours => context.t('Ruhezeit'),
        SkipReason.lowConfidence => context.t('Datenlage zu dünn — lieber schweigen'),
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

