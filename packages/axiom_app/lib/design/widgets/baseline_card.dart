/// Stand der Baseline und der Weg zur Eichung.
///
/// Beantwortet drei Fragen an einer Stelle: Wie weit bin ich, was fehlt noch,
/// und was muss ich tun, wenn es soweit ist.
///
/// Zeigt bewusst **drei getrennte Bedingungen** statt eines Prozentbalkens.
/// „73 % Baseline" verrät nicht, ob Messpunkte oder Nächte fehlen — und
/// genau das entscheidet, was man ändern muss.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';
import 'instruments.dart';
import '../../i18n/i18n.dart';

class BaselineCard extends StatelessWidget {
  final BaselineProgress progress;

  /// Kompakt: nur Stand und Zusammenfassung, ohne Anleitung.
  final bool compact;

  const BaselineCard({
    super.key,
    required this.progress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    return switch (progress.status) {
      BaselineStatus.notStarted => Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('Baseline'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.sm),
              Text(
                context.t('Noch nicht gestartet. Sie beginnt, sobald das Onboarding abgeschlossen ist.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      BaselineStatus.calibrated => Panel(
          accent: p.calm.withValues(alpha: 0.45),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 20, color: p.calm),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('Geeicht'),
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: Space.xs),
                    Text(
                      context.t('Die Formelgewichte stammen aus deinen Daten.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      BaselineStatus.ready => _ReadyCard(compact: compact),
      BaselineStatus.collecting => _CollectingCard(
          progress: progress,
          compact: compact,
        ),
    };
  }
}

class _CollectingCard extends StatelessWidget {
  final BaselineProgress progress;
  final bool compact;

  const _CollectingCard({required this.progress, required this.compact});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('Baseline läuft'),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              // Bewusst ein Satz mit Platzhalter statt Marke plus Zahl:
              // „Tag" allein steht in der Woerterliste schon als
              // Haeufigkeitsangabe („Daily") und haette hier „Daily 7"
              // ergeben.
              Text(context.t('Tag {0}', [progress.day]),
                  style: readingStyle(context, size: 14, color: p.signal)),
            ],
          ),
          const SizedBox(height: Space.lg),

          for (final criterion in progress.criteria)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: _CriterionRow(criterion: criterion),
            ),

          const SizedBox(height: Space.sm),
          Text(progress.summary,
              style: Theme.of(context).textTheme.bodySmall),

          if (!compact) ...[
            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: p.well,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(
                context.t('Bis dahin laufen die Regeln auf geschätzten Gewichten. Sie können danebenliegen — betroffene Regeln sind unten mit UNGEEICHT markiert.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final BaselineCriterion criterion;
  const _CriterionRow({required this.criterion});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    // Hier lag beides in einer Farbe: `isMet ? calm : info` faerbte Haken,
    // Zaehler und Balken zugleich. Der Zaehler und der Balken sind aber
    // Messungen (wie weit von wie weit), und Messungen tragen ausnahmslos
    // `signal` — sonst liest sich eine halbvolle Baseline als „noch nicht
    // gut genug" (R7). Der Haken bleibt ein Zustand: erfuellt oder nicht,
    // und dafuer ist `calm` da.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              criterion.isMet
                  ? Icons.check_circle_outline
                  : Icons.circle_outlined,
              size: 15,
              color: criterion.isMet ? p.calm : p.inkFaint,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(criterion.label,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            Text(
              '${criterion.current} / ${criterion.required}',
              style: readingStyle(context, size: 13.5, color: p.signal),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: p.rule,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              Container(
                height: 3,
                width: c.maxWidth * criterion.progress,
                decoration: BoxDecoration(
                  color: p.signal,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Alle Bedingungen erfüllt — jetzt steht der konkrete Ablauf da.
class _ReadyCard extends StatelessWidget {
  final bool compact;
  const _ReadyCard({required this.compact});

  static const _command =
      'adb exec-out run-as de.atomfritte.axiom cat files/axiom.db > axiom.db\n'
      'dart run tools/bin/calibrate.dart axiom.db';

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    return Panel(
      accent: p.signal.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('Baseline vollständig'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(context.t('Genug Daten zum Eichen.'),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.md),
          Text(
            context.t('Ab jetzt können die Formelgewichte aus deinen Messungen kommen statt aus Schätzungen. Das ist der Punkt, ab dem die Empfehlungen belastbar werden.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),

          if (!compact) ...[
            const SizedBox(height: Space.xl),
            Text(context.t('Was zu tun ist'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),

            _Step(
              n: '1',
              text: context.t('Datenbank auf den Rechner holen und auswerten. Das Werkzeug schreibt nichts — es schlägt nur vor.'),
            ),
            const SizedBox(height: Space.sm),
            _CommandBlock(command: _command),
            const SizedBox(height: Space.lg),

            _Step(
              n: '2',
              text: context.t('Die Vorschläge im nächsten Wochen-Review durchgehen. Nicht blind übernehmen — jeder Wert soll erklärbar sein.'),
            ),
            const SizedBox(height: Space.lg),

            const _Step(
              n: '3',
              text: 'Werte in rules/core/weights.yaml eintragen und dort '
                  'calibration.status auf calibrated setzen.',
            ),
            const SizedBox(height: Space.lg),

            _Step(
              n: '4',
              text: context.t('Regelwerk spiegeln und neu bauen. Danach verschwinden die UNGEEICHT-Markierungen.'),
            ),
            const SizedBox(height: Space.sm),
            const _CommandBlock(
                command: 'dart run tools/bin/sync_rules.dart'),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(n,
              style: readingStyle(context, size: 15, color: p.signal)),
        ),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// Befehl zum Antippen und Kopieren — abtippen ist bei diesem Profil eine
/// echte Hürde, und eine Hürde kurz vor dem Ziel ist die teuerste.
class _CommandBlock extends StatelessWidget {
  final String command;
  const _CommandBlock({required this.command});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: command));
        await HapticFeedback.selectionClick();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('Befehl kopiert.')),
            duration: Duration(milliseconds: 1200),
          ),
        );
      },
      borderRadius: BorderRadius.circular(Radii.control),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: p.well,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // Bleibt Monospace, und zwar zu Recht: Das hier wird abgetippt
              // oder kopiert. Wo ein Bindestrich steht und wo ein
              // Unterstrich, ist hier die Information.
              child: Text(command,
                  style: monoStyle(context, size: 12.5, color: p.inkDim)),
            ),
            const SizedBox(width: Space.sm),
            Icon(Icons.copy, size: 14, color: p.inkFaint),
          ],
        ),
      ),
    );
  }
}
