/// Fokus — M4.
///
/// Der Governor ist bewusst asymmetrisch: Er **schützt** den Fokus und
/// unterbricht nur mit belegbarem Grund. Eine falsch getimte Unterbrechung
/// zerstört den wertvollsten kognitiven Zustand, den dieses Profil hat —
/// sie kostet mehr, als jede verpasste Unterbrechung einbringt (R5).
///
/// Beim Verlassen wird nach der Wiedereinstiegsnotiz gefragt. Das ist der
/// eigentliche Zweck des Ausstiegs: Ohne sie beginnt beim nächsten Mal das
/// Laden des Kontexts von vorn [D11].
library;

import 'package:axiom_core/axiom_core.dart';
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

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Fokus'))),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) => snap.focus == null
            ? _StartPane(snapshot: snap)
            : _RunningPane(snapshot: snap),
      ),
    );
  }
}

// ── Vor dem Start ───────────────────────────────────────────────────────

class _StartPane extends ConsumerStatefulWidget {
  final AxiomSnapshot snapshot;
  const _StartPane({required this.snapshot});

  @override
  ConsumerState<_StartPane> createState() => _StartPaneState();
}

class _StartPaneState extends ConsumerState<_StartPane> {
  Task? _target;
  int _minutes = 50;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final startable = widget.snapshot.startable;
    final cap = widget.snapshot.regime.maxFocusBlock;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.lg, Space.lg, Space.huge),
      children: [
        _BreadcrumbCard(),
        const SizedBox(height: Space.xl),

        SectionLabel(context.t('Worauf')),
        if (startable.isEmpty)
          Panel(
            child: Text(
              context.t('Nichts startbar gerade. Ein Fokusblock ohne Ziel lässt sich später nicht bewerten — dann lieber ohne.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final task in startable.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Panel(
                accent: _target?.id == task.id
                    ? p.signal.withValues(alpha: 0.55)
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _target = _target?.id == task.id ? null : task);
                },
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg, vertical: Space.md),
                child: Row(
                  children: [
                    Icon(
                      _target?.id == task.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: _target?.id == task.id ? p.signal : p.inkFaint,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(task.title,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                    Text('${task.activationEnergy}/10',
                        style: monoStyle(context, size: 11)),
                  ],
                ),
              ),
            ),

        const SizedBox(height: Space.xl),
        SectionLabel(context.t('Wie lange')),
        _MinutePicker(
          value: _minutes,
          max: cap?.inMinutes,
          onChanged: (v) => setState(() => _minutes = v),
        ),
        if (cap != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            context.t('{0}: Blöcke sind auf {1} min begrenzt.',
                [context.t(widget.snapshot.regime.headline), cap.inMinutes]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],

        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: () async {
            final runtime = await ref.read(runtimeProvider.future);
            await runtime.startFocus(
              taskId: _target?.id,
              taskTitle: _target?.title,
              planned: Duration(minutes: _minutes),
            );
            await AndroidBridge.focusStart();
            await HapticFeedback.mediumImpact();
            refreshAxiom(ref);
          },
          child: Text(context.t('Fokus starten')),
        ),
        const SizedBox(height: Space.md),
        Text(
          _target == null
              ? context.t('Ohne gesetztes Ziel fragt AXIOM nach 45 Minuten einmal leise nach, ob das noch das Richtige ist.')
              : context.t('Mit gesetztem Ziel bleibt es still, solange der Block läuft. Benachrichtigungen werden unterdrückt.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BreadcrumbCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crumb = ref.watch(breadcrumbProvider).value;
    if (crumb == null || crumb.isEmpty) return const SizedBox.shrink();
    final p = context.axiom;

    return Panel(
      accent: p.info.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('ZULETZT STEHENGEBLIEBEN'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(crumb, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Wo die laufende Sitzung außerhalb der App zu sehen ist.
///
/// Steht bewusst hier und nicht in den Einstellungen: Der Hinweis nützt nur
/// in dem Moment, in dem eine Sitzung läuft — und dann ersetzt er das
/// Nachsehen in der App, um das es eigentlich geht [D6].
class _LiveSlotHint extends StatelessWidget {
  const _LiveSlotHint();

  @override
  Widget build(BuildContext context) {
    if (!AndroidBridge.isSupported) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: AndroidBridge.liveSlotPromotable(),
      builder: (context, snapshot) {
        final promoted = snapshot.data ?? false;
        return Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Text(
            promoted
                ? context.t('Die Restzeit steht in der Statusleiste, auf dem Sperrbildschirm und in der Now Bar. Du musst hier nicht nachsehen.')
                : context.t('Die Restzeit steht als laufende Benachrichtigung im Benachrichtigungsbereich.'),
            style: monoStyle(context, size: 11, color: context.axiom.inkFaint),
          ),
        );
      },
    );
  }
}

class _MinutePicker extends StatelessWidget {
  final int value;
  final int? max;
  final ValueChanged<int> onChanged;

  const _MinutePicker({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  static const _options = [15, 25, 50, 75, 90];

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final allowed =
        _options.where((o) => max == null || o <= max!).toList();

    return Row(
      children: [
        for (final option in allowed)
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(option);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                margin: EdgeInsets.only(
                    right: option == allowed.last ? 0 : Space.sm),
                decoration: BoxDecoration(
                  color: value == option
                      ? p.signal.withValues(alpha: 0.9)
                      : p.panel,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border:
                      Border.all(color: value == option ? p.signal : p.rule),
                ),
                child: Text(
                  '$option',
                  style: monoStyle(context,
                      size: 14,
                      weight: FontWeight.w500,
                      color: value == option
                          ? Theme.of(context).colorScheme.onPrimary
                          : p.inkDim),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Während des Laufs ───────────────────────────────────────────────────

class _RunningPane extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _RunningPane({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final session = snapshot.focus!;
    final verdict = snapshot.focusVerdict;
    final now = ref.watch(nowProvider);
    final elapsed = session.elapsed(now);
    final ratio =
        (elapsed.inSeconds / session.planned.inSeconds).clamp(0.0, 1.5);

    final accent = switch (verdict?.action) {
      FocusAction.hardStop => p.caution,
      FocusAction.clearInterrupt => p.signal,
      _ => p.calm,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.lg, Space.lg, Space.huge),
      children: [
        Panel(
          accent: accent.withValues(alpha: 0.55),
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.hasAnchor ? context.t('LÄUFT AUF') : context.t('LÄUFT'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.md),
              Text(
                session.anchorTitle ?? context.t('Ohne gesetztes Ziel'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: Space.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${elapsed.inMinutes}',
                    style: TextStyle(
                      fontFamily: Fonts.mono,
                      fontSize: 44,
                      fontWeight: FontWeight.w300,
                      color: p.ink,
                    ),
                  ),
                  Text(context.t(' / {0} min', [session.planned.inMinutes]),
                      style: monoStyle(context, size: 14)),
                ],
              ),
              const SizedBox(height: Space.md),
              LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Container(height: 3, color: p.rule),
                    Container(
                      height: 3,
                      width: c.maxWidth * ratio.clamp(0.0, 1.0),
                      color: accent,
                    ),
                  ],
                ),
              ),
              if (ratio > 1.0) ...[
                const SizedBox(height: Space.sm),
                Text(
                  context.t('{0} min darüber', [session.overrun(now).inMinutes]),
                  style: monoStyle(context, size: 11, color: p.signal),
                ),
              ],
            ],
          ),
        ),

        const _LiveSlotHint(),

        if (verdict != null) ...[
          const SizedBox(height: Space.lg),
          _VerdictCard(verdict: verdict),
        ],

        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: () => _finish(context, ref, session),
          child: Text(context.t('Fokus beenden')),
        ),
        const SizedBox(height: Space.sm),
        Center(
          child: TextButton(
            onPressed: () async {
              final runtime = await ref.read(runtimeProvider.future);
              await runtime.endFocus(session, exit: 'interrupted');
              await AndroidBridge.focusEnd();
              refreshAxiom(ref);
              if (context.mounted) Navigator.of(context).maybePop();
            },
            child: Text(context.t('Abbrechen, ohne Notiz')),
          ),
        ),
      ],
    );
  }

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    FocusSession session,
  ) async {
    final breadcrumb = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BreadcrumbSheet(session: session),
    );

    final runtime = await ref.read(runtimeProvider.future);
    await runtime.endFocus(session, breadcrumb: breadcrumb);
    await AndroidBridge.focusEnd();
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

class _VerdictCard extends StatelessWidget {
  final FocusVerdict verdict;
  const _VerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final (label, color) = switch (verdict.action) {
      FocusAction.protect => (context.t('GESCHÜTZT'), p.calm),
      FocusAction.gentleNudge => ('HINWEIS', p.info),
      FocusAction.clearInterrupt => ('UNTERBRECHUNG', p.signal),
      FocusAction.hardStop => (context.t('JETZT BEENDEN'), p.caution),
    };

    return Panel(
      accent: verdict.action == FocusAction.protect
          ? null
          : color.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: monoStyle(context,
                  size: 10.5, weight: FontWeight.w600, spacing: 0.8,
                  color: color)),
          const SizedBox(height: Space.sm),
          Text(context.p(verdict.reason),
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Fragt die Wiedereinstiegsnotiz ab [D11].
class _BreadcrumbSheet extends StatefulWidget {
  final FocusSession session;
  const _BreadcrumbSheet({required this.session});

  @override
  State<_BreadcrumbSheet> createState() => _BreadcrumbSheetState();
}

class _BreadcrumbSheetState extends State<_BreadcrumbSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
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
              Text(context.t('WIEDEREINSTIEG'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.md),
              Text(FocusGovernor.breadcrumbPrompt(widget.session),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                context.t('Ein Satz reicht. Er spart dir beim nächsten Mal den halben Anlauf.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _controller,
                focusNode: _focus,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.t('Bei Anlage KAP, Zeile 7'),
                ),
              ),
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                child: Text(context.t('Notieren und beenden')),
              ),
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.t('Ohne Notiz beenden')),
                ),
              ),
            ],
          ),
        ),
      );
}
