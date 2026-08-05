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
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xl),

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
                  Text(context.t('AUS'),
                      style: Theme.of(context).textTheme.labelSmall),
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
class _Running extends StatelessWidget {
  final ExpertStatus status;
  const _Running({required this.status});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      accent: p.signal.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('LÄUFT'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(context.t('Im Browser öffnen'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Space.xs),
          SelectableText(
            status.address ?? '',
            style: monoStyle(context,
                size: 19, weight: FontWeight.w500, color: p.ink),
          ),
          if (status.fallbackAddress != null) ...[
            const SizedBox(height: Space.sm),
            Text(context.t('Falls der Name nicht aufgeht — in manchen Netzen ist Multicast gesperrt:'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.xs),
            SelectableText(
              status.fallbackAddress!,
              style: monoStyle(context, size: 15, color: p.inkDim),
            ),
          ],
          const SizedBox(height: Space.lg),
          Text(context.t('PIN — gilt nur für diesen Start'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Space.xs),
          SelectableText(
            _spaced(status.pin ?? ''),
            style: monoStyle(context,
                size: 30, weight: FontWeight.w600, color: p.signal, spacing: 4),
          ),
          const SizedBox(height: Space.lg),
          Text(context.t('Fingerabdruck des Zertifikats'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Space.xs),
          SelectableText(
            status.fingerprint ?? '',
            style: monoStyle(context, size: 12.5, color: p.calm),
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Muss mit dem übereinstimmen, den der Browser zeigt. Tut er das, ist die Verbindung geprüft — nicht bloß weggeklickt.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: Space.lg),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: p.inkFaint),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  context.t('Schaltet sich ohne Anfrage nach 30 Minuten ab.'),
                  style: monoStyle(context, size: 12, color: p.inkFaint),
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
      accent: p.signal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('FREIGABE ANGEFRAGT'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Center(
            child: Text(
              number,
              style: monoStyle(context,
                  size: 56, weight: FontWeight.w600, color: p.signal),
            ),
          ),
          const SizedBox(height: Space.md),
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
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  child: Text(context.t('Stimmt überein')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDeny,
                  child: Text(context.t('Stimmt nicht')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
