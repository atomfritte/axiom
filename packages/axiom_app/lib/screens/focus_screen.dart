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
                    const SizedBox(width: Space.md),
                    // War Schreibmaschine in 11 px. Startenergie ist ein
                    // Messwert: Hausschrift mit Tabellenziffern, damit
                    // 2/10 und 10/10 untereinander fluchten.
                    Text('${task.activationEnergy}/10',
                        style: readingStyle(context,
                            size: 13.5, color: p.inkFaint)),
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

    // Hier stand ein blauer Rahmen. Auf einem Schirm mit vier Karten
    // untereinander zieht jeder Rahmen Aufmerksamkeit an eine Stelle, an der
    // nichts zu tun ist — die Notiz ist etwas zum Lesen, keine Handlung.
    // Erhoben ist unten der Knopf.
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hier stand `ZULETZT STEHENGEBLIEBEN` — dreiundzwanzig
          // Grossbuchstaben am Stueck. Die Marke gehoert zur Notiz, die man
          // beim Wiedereinstieg zuerst sucht, und gesperrte Versalien sind
          // genau dort am teuersten: Die Wortform faellt weg, man liest
          // Buchstabe fuer Buchstabe. `labelSmall` traegt die Auszeichnung
          // seit der Typografiereform selbst (13,5 px, w600, leicht
          // gesperrt); der Text muss nicht mehr schreien.
          Text(context.t('Zuletzt stehengeblieben'),
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
            // War Schreibmaschine — ein Satz zum Lesen, kein Messwert.
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.axiom.inkFaint),
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
                height: 56,
                alignment: Alignment.center,
                margin: EdgeInsets.only(
                    right: option == allowed.last ? 0 : Space.sm),
                decoration: BoxDecoration(
                  // Ungewaehlt lag hier `panel` mit Haarlinienrahmen — auf
                  // dem Seitengrund war das eine Karte, und fuenf Karten
                  // nebeneinander sehen alle gleich waehlbar aus. Jetzt
                  // liegen sie flach auf dem Grund und die gewaehlte kommt
                  // heraus.
                  color: value == option ? p.signal : p.panel,
                  borderRadius: BorderRadius.circular(Radii.control),
                  boxShadow: value == option ? null : Shadows.resting(p),
                  border: p.isDark ? Border.all(color: p.rim) : null,
                ),
                // War Schreibmaschine. Eine Minutenzahl ist ein Messwert.
                child: Text(
                  '$option',
                  style: readingStyle(context,
                      size: 16,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.lg, Space.lg, Space.huge),
      children: [
        // Hier lag ein farbiger Rahmen um die Karte, dessen Ton vom Urteil
        // des Governors abhing: gruen bei „geschuetzt", kupfern bei „jetzt
        // beenden". Das faerbte die laufende Sitzung selbst ein — als waere
        // die Arbeit gut oder schlecht, je nachdem wie lange sie schon
        // laeuft. Das Urteil steht eine Karte tiefer, mit seinem Namen und
        // seiner Begruendung; hier gehoert es nicht hin (R7).
        //
        // Was die Karte stattdessen traegt, ist Griffhoehe: Sie ist das
        // Einzige, was jetzt laeuft, und deshalb die einzige erhobene
        // Flaeche des Schirms (G1).
        Panel(
          reachable: true,
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // War `LÄUFT AUF` / `LÄUFT`. Dieselbe Umstellung wie ueberall:
              // normale Schreibweise, die Auszeichnung kommt aus der Rolle.
              Text(session.hasAnchor ? context.t('Läuft auf') : context.t('Läuft'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.md),
              Text(
                session.anchorTitle ?? context.t('Ohne gesetztes Ziel'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: Space.xl),
              // War Schreibmaschine in w300 — 44 px duenn und blass. Die
              // verstrichene Zeit ist der Messwert dieses Schirms und
              // laeuft jetzt wie jeder andere: Hausschrift, Tabellenziffern,
              // Signalfarbe.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    '${elapsed.inMinutes}',
                    style: readingStyle(context,
                        size: 46, height: 1.0, color: p.signal),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                        context.t(' / {0} min', [session.planned.inMinutes]),
                        style: readingStyle(context,
                            size: 15, color: p.inkFaint)),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    // Runde Enden wie bei jeder anderen Skala der App: Das
                    // ist eine Marke auf einer Strecke, kein Wettlauf gegen
                    // eine Ziellinie.
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      height: 4,
                      width: c.maxWidth * ratio.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: p.signal,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              if (ratio > 1.0) ...[
                const SizedBox(height: Space.md),
                Text(
                  context.t('{0} min darüber', [session.overrun(now).inMinutes]),
                  style: readingStyle(context, size: 13.5, color: p.inkDim),
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
    // Die vier Urteile standen in gesperrten Versalien: `GESCHÜTZT`,
    // `HINWEIS`, `UNTERBRECHUNG`, `JETZT BEENDEN`. Ausgerechnet hier war das
    // die falsche Lautstaerke — `JETZT BEENDEN` in Versalien liest sich als
    // Anweisung, und das Urteil des Governors ist eine Ablesung mit
    // Begruendung, kein Befehl (G3). Vier Zeilen, eine Regel: normale
    // Schreibweise, Farbe bleibt.
    final (label, color) = switch (verdict.action) {
      FocusAction.protect => (context.t('Geschützt'), p.calm),
      // Zwei der vier Zweige liefen frueher nicht durch die Uebersetzung:
      // Im Tupel eines `switch` steht das Literal nicht hinter `Text(`, und
      // genau daran hat der Waechter sie vorbeigelassen.
      FocusAction.gentleNudge => (context.t('Hinweis'), p.info),
      FocusAction.clearInterrupt => (context.t('Unterbrechung'), p.signal),
      FocusAction.hardStop => (context.t('Jetzt beenden'), p.caution),
    };

    return Panel(
      accent: verdict.action == FocusAction.protect
          ? null
          : color.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // War Schreibmaschine in 10,5 px. Die Farbe bleibt: Sie steht
          // hier nicht fuer einen Messwert, sondern fuer einen Zustand des
          // Governors — geschuetzt, Hinweis, Unterbrechung, beenden. Ein
          // Zustand darf eine Rolle haben, eine Ablesung nicht (R7).
          Text(label, style: sectionStyle(context, color: color)),
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
              // War `WIEDEREINSTIEG` — vierzehn Versalien ueber der Frage,
              // die man nach einem Fokusblock mit leerem Kopf beantwortet.
              Text(context.t('Wiedereinstieg'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.md),
              // Vorher stand hier `FocusGovernor.breadcrumbPrompt(...)`: ein
              // im Kern fertig zusammengesetzter deutscher Satz mit bereits
              // eingesetztem Ankertitel. So war er nicht uebersetzbar — als
              // Schluessel taugt er nicht, weil der Titel darin steckt — und
              // stand mitten zwischen englischen Zeilen. Jetzt traegt die
              // Oberflaeche den Satz und der Titel ist ein Platzhalter.
              Text(
                  widget.session.hasAnchor
                      ? context.t('Wo genau bist du bei „{0}" stehengeblieben?',
                          [widget.session.anchorTitle])
                      : context.t(
                          'Woran warst du dran, und was wäre der nächste Handgriff?'),
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
