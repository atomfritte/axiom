/// Onboarding.
///
/// Fünf Schritte, jeder überspringbar. Grundsatz: Es wird nichts versprochen
/// und nichts beworben — es wird erklärt, wie das Ding funktioniert und was
/// es bewusst nicht tut. Wer hier abspringt, hätte auch später abgebrochen.
///
/// Der vierte Schritt ist der wichtigste: der erste Check-in. Ein Onboarding,
/// das nur erklärt und nichts tun lässt, hinterlässt eine leere App —
/// und eine leere App wird geschlossen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/axiom_mark.dart';
import '../design/widgets/capacity_line.dart';
import '../design/widgets/instruments.dart';
import '../platform/android_bridge.dart';
import '../state/providers.dart';
import 'checkin_sheet.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _checkinDone = false;

  static const _pageCount = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pageCount - 1) {
      _controller.nextPage(duration: Motion.settle, curve: Motion.instrument);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.markOnboardingDone();
    if (runtime.baselineStart == null) runtime.startBaseline();
    refreshAxiom(ref);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Fortschritt als Skala — passend zur Instrumentensprache.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.lg, Space.lg, Space.sm),
              child: Row(
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: Motion.quick,
                        height: 2,
                        margin: EdgeInsets.only(
                            right: i < _pageCount - 1 ? 4 : 0),
                        color: i <= _page ? p.signal : p.rule,
                      ),
                    ),
                  const SizedBox(width: Space.lg),
                  Text('${_page + 1}/$_pageCount',
                      style: monoStyle(context, size: 11)),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _PageWhat(),
                  const _PageHow(),
                  const _PageLine(),
                  _PageFirstCheckin(
                    done: _checkinDone,
                    onDone: () => setState(() => _checkinDone = true),
                  ),
                  const _PagePermissions(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Überspringen',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.md),
                      ),
                      child: Text(
                        _page == _pageCount - 1 ? 'Los geht’s' : 'Weiter',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Seiten ──────────────────────────────────────────────────────────────

class _Page extends StatelessWidget {
  final String eyebrow;
  final String title;
  final List<Widget> children;

  /// Optionaler Kopf ueber der Rubrik — nur auf der ersten Seite.
  final Widget? leading;

  const _Page({
    required this.eyebrow,
    required this.title,
    required this.children,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.lg),
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(height: Space.xxl),
          ],
          Text(eyebrow.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(title, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.xl),
          ...children,
        ],
      );
}

class _PageWhat extends StatelessWidget {
  const _PageWhat();

  @override
  Widget build(BuildContext context) => _Page(
        eyebrow: 'Was das hier ist',
        title: 'Ein Regelwerk,\nkeine To-do-App.',
        leading: const AxiomWordmark(markSize: 30),
        children: [
          const _Para(
            'AXIOM misst deinen Zustand, wendet Regeln darauf an, die du '
            'selbst setzt, und nennt dir eine nächste Handlung. Mit '
            'Begründung und der Regel, die sie erzeugt hat.',
          ),
          const SizedBox(height: Space.lg),
          const _Para(
            'Der Unterschied zu anderen Apps: Hier wird nicht gefragt, was du '
            'tun willst — sondern in welchem Zustand du bist. Was heute '
            'außerhalb deiner Reichweite liegt, wird gar nicht erst gezeigt.',
          ),
          const SizedBox(height: Space.xl),
          const _NotList([
            'Keine Streaks, die brechen können',
            'Keine Erinnerung, die dir Vorwürfe macht',
            'Keine Cloud, kein Konto, keine Auswertung durch andere',
            'Keine KI, die für dich entscheidet',
          ]),
        ],
      );
}

class _PageHow extends StatelessWidget {
  const _PageHow();

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return _Page(
      eyebrow: 'Wie es arbeitet',
      title: 'Zustand,\nRegel,\neine Handlung.',
      children: [
        Panel(
          child: Column(
            children: [
              _Step(
                n: '1',
                title: 'Messen',
                body: 'Drei kurze Check-ins am Tag, dazu Schlaf und Bewegung '
                    'vom Gerät. Zusammen ergibt das sechs Messwerte.',
              ),
              Divider(color: p.rule, height: Space.xl),
              _Step(
                n: '2',
                title: 'Regeln anwenden',
                body: 'Regeln sind Wenn-Dann-Sätze in Klartext. Du kannst '
                    'jede lesen, ändern und abschalten.',
              ),
              Divider(color: p.rule, height: Space.xl),
              _Step(
                n: '3',
                title: 'Eine Handlung',
                body: 'Nie eine Liste zum Auswählen. Genau eine Sache, plus '
                    'die Regel-Nummer, die dahintersteckt.',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        const _Para(
          'Gleicher Zustand, gleiche Regeln — immer dasselbe Ergebnis. '
          'Nichts davon ist geraten, und du kannst jederzeit nachsehen, '
          'wie ein Wert zustande kam.',
        ),
      ],
    );
  }
}

class _PageLine extends StatelessWidget {
  const _PageLine();

  @override
  Widget build(BuildContext context) {
    // Beispieldaten — zeigt das Prinzip, bevor es eigene Daten gibt.
    final demo = [
      for (final (i, ae) in [2, 3, 4, 6, 8, 9].indexed)
        Task(
          id: 'demo$i',
          title: 'Beispiel',
          activationEnergy: ae,
          salience: 5,
          stakes: 5,
          state: TaskState.ready,
        ),
    ];

    return _Page(
      eyebrow: 'Das zentrale Bild',
      title: 'Die\nKapazitätslinie.',
      children: [
        Panel(child: CapacityLine(capacity: 55, tasks: demo)),
        const SizedBox(height: Space.lg),
        const _Para(
          'Aufgaben sitzen auf einer Skala: Wie schwer fällt der Start? '
          'Der Strich zeigt, wie viel Anlauf du heute hast.',
        ),
        const SizedBox(height: Space.md),
        const _Para(
          'Was links davon liegt, ist in Reichweite. Was rechts davon liegt, '
          'ist heute zu schwer — und wird dir deshalb nicht vorgehalten. '
          'Das ist eine Messung, kein Urteil über dich.',
        ),
        const SizedBox(height: Space.md),
        const _Para(
          'Bleibt etwas Wichtiges rechts der Linie liegen, schlägt AXIOM vor, '
          'es in kleinere Schritte zu zerlegen, bis ein Teil links landet.',
        ),
      ],
    );
  }
}

class _PageFirstCheckin extends ConsumerWidget {
  final bool done;
  final VoidCallback onDone;
  const _PageFirstCheckin({required this.done, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return _Page(
      eyebrow: 'Erster Messpunkt',
      title: done ? 'Steht.' : 'Einmal\nkurz messen.',
      children: [
        _Para(
          done
              ? 'Der erste Wert ist drin. Ab jetzt sammelt AXIOM zwei Wochen '
                  'lang Daten, bevor es anfängt, Empfehlungen zu geben.'
              : 'Vier Regler, ungefähr reicht. Ohne einen Anfangswert kann '
                  'AXIOM nichts berechnen — und würde raten.',
        ),
        const SizedBox(height: Space.xl),
        if (done)
          Panel(
            accent: p.calm.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(Icons.check, color: p.calm, size: 20),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text('Check-in gespeichert.',
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: () async {
              final ok = await showCheckinSheet(context, slot: 'onboarding');
              if (ok) {
                await HapticFeedback.mediumImpact();
                onDone();
              }
            },
            child: const Text('Check-in machen'),
          ),
        const SizedBox(height: Space.xl),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DIE ERSTEN 14 TAGE',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.sm),
              Text(
                'In dieser Zeit gibt AXIOM absichtlich keine Empfehlungen. '
                'Es misst nur. Regeln, die auf geratenen Werten beruhen, '
                'liegen falsch — und eine App, die einmal offensichtlich '
                'danebenliegt, macht man nicht wieder auf.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PagePermissions extends ConsumerStatefulWidget {
  const _PagePermissions();

  @override
  ConsumerState<_PagePermissions> createState() => _PagePermissionsState();
}

class _PagePermissionsState extends ConsumerState<_PagePermissions> {
  final _granted = <String>{};

  @override
  Widget build(BuildContext context) {
    if (!AndroidBridge.isSupported) {
      return const _Page(
        eyebrow: 'Fertig',
        title: 'Bereit.',
        children: [
          _Para(
            'Auf dem Desktop läuft AXIOM ohne Systemrechte. '
            'Erfassen, Check-ins und der Regelinspektor funktionieren '
            'vollständig.',
          ),
        ],
      );
    }

    return _Page(
      eyebrow: 'Damit es zuverlässig läuft',
      title: 'Drei\nSystemrechte.',
      children: [
        const _Para(
          'AXIOM arbeitet mit exakten Uhrzeiten. Android schläfert Apps sonst '
          'ein — dann kommt die Erinnerung 40 Minuten zu spät oder gar nicht, '
          'und das ganze Konzept ist wertlos.',
        ),
        const SizedBox(height: Space.xl),
        _PermissionRow(
          title: 'Exakte Erinnerungen',
          body: 'Damit Erinnerungen auf die Minute kommen.',
          granted: _granted.contains('alarm'),
          onTap: () async {
            await AndroidBridge.requestExactAlarm();
            setState(() => _granted.add('alarm'));
          },
        ),
        _PermissionRow(
          title: 'Mitteilungen',
          body: 'Vier Kanäle, getrennt einstellbar. Du kannst leise Hinweise '
              'stummschalten und wichtige durchlassen.',
          granted: _granted.contains('notif'),
          onTap: () async {
            await AndroidBridge.requestNotifications();
            setState(() => _granted.add('notif'));
          },
        ),
        _PermissionRow(
          title: 'Akkuoptimierung aus',
          body: 'Samsung beendet Hintergrund-Apps aggressiv. Ohne diese '
              'Ausnahme feuern Erinnerungen unzuverlässig.',
          granted: _granted.contains('battery'),
          onTap: () async {
            await AndroidBridge.requestIgnoreBatteryOptimizations();
            setState(() => _granted.add('battery'));
          },
        ),
        const SizedBox(height: Space.lg),
        const _Para(
          'Standort und App-Nutzung werden nicht abgefragt — die brauchen '
          'erst spätere Module, und dann fragst du selbst danach.',
        ),
      ],
    );
  }
}

// ── Bausteine ───────────────────────────────────────────────────────────

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: context.axiom.inkDim, height: 1.55),
      );
}

class _NotList extends StatelessWidget {
  final List<String> items;
  const _NotList(this.items);

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(width: 10, height: 1, color: p.inkFaint),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(item,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  const _Step({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(n,
            style: TextStyle(
              fontFamily: Fonts.mono,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              color: p.signal,
            )),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Space.xs),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final String body;
  final bool granted;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.title,
    required this.body,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Panel(
        accent: granted ? p.calm.withValues(alpha: 0.45) : null,
        onTap: granted ? null : onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              granted ? Icons.check_circle_outline : Icons.circle_outlined,
              size: 20,
              color: granted ? p.calm : p.inkFaint,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: Space.xs),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (!granted)
              Text('ERLAUBEN',
                  style: monoStyle(context,
                      size: 10.5, weight: FontWeight.w600, color: p.signal)),
          ],
        ),
      ),
    );
  }
}
