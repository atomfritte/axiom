/// Erfassungskanäle — die Wege in die App hinein.
///
/// Zwischen „Gedanke entsteht" und „sicher notiert" liegen wenige Sekunden.
/// Jede Reibung in diesem Fenster führt zum Totalverlust [D9]. Deshalb gibt
/// es nicht einen Weg, sondern viele — und dieser Screen zeigt, welche
/// eingerichtet sind und wie man die übrigen einschaltet.
///
/// Die Anleitungen stehen hier, weil sie sonst nirgends stehen: Ein Kanal,
/// von dem man nicht weiß, ist kein Kanal.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../platform/android_bridge.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  bool _presence = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final on = await AndroidBridge.presenceEnabled();
      if (mounted) setState(() => _presence = on);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final snapshot = ref.watch(snapshotProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Erfassen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: [
          Text(
            context.t('Zwischen Einfall und Notiz liegen wenige Sekunden. Was in dieser Zeit nicht festgehalten ist, ist weg. Deshalb gibt es mehrere Wege — such dir den, der bei dir wirklich funktioniert.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xl),

          // ── Dauerhafte Anzeige ───────────────────────────────────────
          SectionLabel(context.t('Dauerhafte Anzeige')),
          Panel(
            accent: _presence ? p.calm.withValues(alpha: 0.45) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(context.t('Im Benachrichtigungsbereich bleiben'),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Switch(
                      value: _presence,
                      onChanged: AndroidBridge.isSupported
                          ? (value) => _togglePresence(value, snapshot)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  context.t('Zeigt die nächste Handlung dauerhaft — auch auf dem Sperrbildschirm. Mit einem Tipp auf „Erfassen" tippst du direkt in die Benachrichtigung, ohne zu entsperren und ohne die App zu öffnen.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Space.md),
                Text(
                  context.t('Der schnellste Weg, den das Gerät hergibt: zwei Sekunden statt zehn.'),
                  style: monoStyle(context, size: 11, color: p.signal),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Eingerichtet')),
          _ChannelCard(
            icon: Icons.add_circle_outline,
            title: context.t('Knopf in der App'),
            body: context.t('Unten rechts, immer sichtbar. Feld ist sofort aktiv, Tastatur offen.'),
            ready: true,
          ),
          _ChannelCard(
            icon: Icons.tune,
            title: context.t('Schnelleinstellung'),
            body: context.t('Herunterwischen, tippen, schreiben. Funktioniert aus jeder App heraus.'),
            ready: true,
            hint: context.t('Falls nicht sichtbar: Schnelleinstellungen aufziehen → Stift-Symbol → „AXIOM erfassen" nach oben ziehen.'),
          ),
          _ChannelCard(
            icon: Icons.widgets_outlined,
            title: context.t('Homescreen-Widget'),
            body: context.t('Zeigt die nächste Handlung und die Kapazität. Tippen auf „ERFASSEN" springt direkt ins Eingabefeld.'),
            ready: true,
            hint: context.t('Falls es in der Widget-Auswahl fehlt: Samsungs Startbildschirm merkt sich die Liste einer App und aktualisiert sie nach einem Update nicht zuverlässig. Der Knopf hier fragt das System direkt.'),
            action: context.t('Widget hinzufügen'),
            onAction: () async {
              final ok = await AndroidBridge.requestPinWidget();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? context.t('Anfrage gestellt — bestätige sie auf dem Startbildschirm.')
                    : context.t('Der Startbildschirm nimmt keine Anfrage entgegen. Dann über: lange auf den Homescreen tippen → Widgets → AXIOM.')),
              ));
            },
          ),
          _ChannelCard(
            icon: Icons.share_outlined,
            title: context.t('Aus anderen Apps teilen'),
            body: context.t('Text markieren, teilen, AXIOM wählen. AXIOM steht in der oberen Reihe des Teilen-Blatts, nicht in der App-Liste darunter — immer an derselben Stelle.'),
            ready: true,
          ),
          _ChannelCard(
            icon: Icons.touch_app_outlined,
            title: context.t('Langes Tippen auf das App-Symbol'),
            body: context.t('Erfassen, Check-in und Fokus direkt vom Startbildschirm.'),
            ready: true,
          ),

          const SizedBox(height: Space.xl),
          SectionLabel(context.t('Einmal einrichten')),
          _ChannelCard(
            icon: Icons.edit_outlined,
            title: context.t('S-Pen'),
            body: context.t('Der Stift-Doppeltipp fragt nicht nach dem Intent-Filter, sondern nach der Rolle „Notiz-App". Solange die woanders liegt, erscheint AXIOM dort nicht — eine einmalige Einstellung, kein Fehler.'),
            ready: false,
            hint: context.t('Zusätzlich in Samsung: Einstellungen → Erweiterte Funktionen → S Pen → Air Actions → Stiftknopf → AXIOM. Screen-off-Memos landen weiterhin in Samsung Notes — dafür gibt es keine offene Schnittstelle.'),
            action: context.t('AXIOM als Notiz-App setzen'),
            onAction: () => AndroidBridge.requestNotesRole(),
          ),
          _ChannelCard(
            icon: Icons.mic_none_outlined,
            title: context.t('Sprache'),
            body: context.t('Direkt beim Erfassen: Das Mikrofon im Eingabefeld diktiert, ohne dass etwas eingerichtet werden muss.'),
            ready: true,
            hint: context.t('„Hey Google, Notiz in AXIOM" setzt dagegen voraus, dass die App über Google Play verteilt wird — bei einer selbst installierten prüft Google die Anmeldung nicht. Was hier funktioniert: eine Bixby-Routine oder ein Link auf axiom://capture?text=…'),
          ),
          _ChannelCard(
            icon: Icons.route_outlined,
            title: context.t('Samsung Modi und Routinen'),
            body: context.t('AXIOM sendet Signale, auf die Routinen reagieren können: Fokus an und aus, Abendgrenze, Erhaltungsmodus.'),
            ready: false,
            hint: context.t('Routinen → Wenn → Anderes → Broadcast empfangen → axiom.FOCUS_START, axiom.FOCUS_END, axiom.WINDDOWN, axiom.L3_ENTER'),
          ),

          const SizedBox(height: Space.xl),
          Text(
            context.t('Kein Weg ist Pflicht. Der beste ist der, den du tatsächlich nutzt — welcher das ist, steht nach der Baseline in der Auswertung.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _togglePresence(bool value, dynamic snapshot) async {
    if (value) {
      final headline = snapshot?.decisionRule?.title ??
          snapshot?.startable.firstOrNull?.title ??
          'AXIOM';
      await AndroidBridge.startPresence(
        headline: headline,
        detail: context.t('Tippen zum Erfassen'),
      );
    } else {
      await AndroidBridge.stopPresence();
    }
    await HapticFeedback.selectionClick();
    if (mounted) setState(() => _presence = value);
  }
}

class _ChannelCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  /// Läuft ohne Zutun, oder muss einmal eingerichtet werden.
  final bool ready;

  /// Wie man es einrichtet oder wiederfindet.
  final String? hint;

  /// Wo es einen Knopf gibt, der die Einrichtung direkt erledigt.
  ///
  /// Eine Anleitung, die durch fünf Systemmenüs führt, wird nicht befolgt —
  /// jeder Schritt darin ist eine Gelegenheit auszusteigen [D2].
  final String? action;
  final Future<void> Function()? onAction;

  const _ChannelCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.ready,
    this.hint,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: ready ? p.calm : p.inkDim),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: Space.xs),
                      Text(body,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () async {
                    await HapticFeedback.selectionClick();
                    await onAction!();
                  },
                  child: Text(action!),
                ),
              ),
            ],
            if (hint != null) ...[
              const SizedBox(height: Space.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: p.base,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: p.rule),
                ),
                child: Text(hint!,
                    style: monoStyle(context, size: 11, color: p.inkDim)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
