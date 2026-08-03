/// Systemcheck — was das Gerät wirklich freigegeben hat.
///
/// **Warum es diesen Screen gibt.** „Geht nicht" ist keine Fehlermeldung.
/// Wenn eine Erinnerung ausbleibt, ein Widget sich nicht hinzufügen lässt
/// oder Health Connect nichts liefert, gibt es genau zwei Möglichkeiten:
/// Die App ist kaputt, oder das System hat etwas nicht freigegeben. Ohne
/// diese Seite ist beides von außen nicht zu unterscheiden — und man baut
/// an der falschen Stelle weiter.
///
/// Jede Zeile hier ist eine Aussage des Betriebssystems, keine Vermutung der
/// App. Wo etwas fehlt, steht daneben der Weg dorthin. Ein stiller Ausfall
/// ist schlimmer als ein lauter (R4).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../platform/android_bridge.dart';
import '../platform/health_sync.dart';

class CheckScreen extends ConsumerStatefulWidget {
  const CheckScreen({super.key});

  @override
  ConsumerState<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends ConsumerState<CheckScreen>
    with WidgetsBindingObserver {
  Map<String, Object?> _values = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Nach der Rückkehr aus einem Systemdialog neu lesen.
  ///
  /// Freigaben werden außerhalb der App erteilt. Ohne diesen Schritt zeigt
  /// die Seite nach dem Freigeben weiter „nicht freigegeben" — und man hält
  /// eine Funktion für kaputt, die gerade eingeschaltet wurde.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final values = await AndroidBridge.diagnostics();
    if (!mounted) return;
    setState(() {
      _values = values;
      _loading = false;
    });
  }

  bool _flag(String key) => _values[key] == true;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    if (!AndroidBridge.isSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(context.t('Systemcheck'))),
        body: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text(
            context.t('Auf dem Desktop gibt es keine Systemrechte zu prüfen. Erfassen, Check-ins und der Regelinspektor laufen trotzdem vollständig.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final health = (_values['healthSdkStatus'] as num?)?.toInt() ?? -1;
    final widgets = (_values['widgetCount'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Systemcheck')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.t('Neu prüfen'),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.lg, Space.lg, Space.huge),
              children: [
                Text(
                  context.t('Jede Zeile hier ist eine Aussage des Geräts, keine Vermutung der App. Was markiert ist, erklärt eine Funktion, die nicht tut, was sie soll — der Knopf daneben führt genau dorthin, wo es freigegeben wird.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.xl),

                SectionLabel(context.t('Gerät')),
                _Line(
                  label: context.t('System'),
                  value: 'Android ${_values['release']} '
                      '(API ${_values['sdkInt']})',
                ),
                _Line(
                  label: context.t('Modell'),
                  value: '${_values['manufacturer']} ${_values['model']}',
                ),

                const SizedBox(height: Space.xl),
                SectionLabel(context.t('Damit Erinnerungen ankommen')),
                _Check(
                  ok: _flag('postNotificationsGranted') &&
                      _flag('notifications'),
                  label: context.t('Benachrichtigungen'),
                  detail: _flag('postNotificationsGranted')
                      ? context.t('Freigegeben.')
                      : context.t('Nicht freigegeben. Ohne das bleibt jede Erinnerung stumm — und ein stiller Ausfall fällt erst auf, wenn etwas verpasst ist.'),
                  action: context.t('Freigeben'),
                  onAction: () async {
                    await AndroidBridge.requestNotifications();
                    await _reload();
                  },
                ),
                _Check(
                  ok: _flag('exactAlarm'),
                  label: context.t('Exakte Erinnerungen'),
                  detail: _flag('exactAlarm')
                      ? context.t('Auf die Minute genau.')
                      : context.t('Ohne diese Freigabe kommen Zeitanker ungefähr statt pünktlich — der wirksamste Interventionstyp wird damit wertlos.'),
                  action: context.t('Freigeben'),
                  onAction: () async {
                    await AndroidBridge.requestExactAlarm();
                    await _reload();
                  },
                ),
                _Check(
                  ok: _flag('batteryUnrestricted'),
                  label: context.t('Akkuoptimierung aus'),
                  detail: _flag('batteryUnrestricted')
                      ? context.t('AXIOM darf im Hintergrund aufwachen.')
                      : context.t('Samsung beendet Hintergrund-Apps aggressiv. Ohne Ausnahme feuern Erinnerungen unzuverlässig.'),
                  action: context.t('Freigeben'),
                  onAction: () async {
                    await AndroidBridge.requestIgnoreBatteryOptimizations();
                    await _reload();
                  },
                ),

                const SizedBox(height: Space.xl),
                SectionLabel(context.t('Wege in die App')),
                _Check(
                  ok: widgets > 0,
                  label: context.t('Homescreen-Widget'),
                  detail: widgets > 0
                      ? context.t('{0} Stück platziert.', [widgets])
                      : context.t('Noch keins platziert. Samsungs Startbildschirm merkt sich die Widget-Liste einer App und aktualisiert sie nach einem Update nicht zuverlässig — dieser Knopf geht daran vorbei.'),
                  action: context.t('Jetzt hinzufügen'),
                  onAction: () async {
                    final ok = await AndroidBridge.requestPinWidget();
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.t('Der Startbildschirm nimmt keine Anfrage entgegen. Dann über die Widget-Auswahl: lange auf den Homescreen tippen → Widgets → AXIOM.')),
                      ));
                    }
                    await _reload();
                  },
                ),
                _Check(
                  ok: _flag('notesRoleHeld'),
                  label: context.t('S-Pen und Notiz-Taste'),
                  detail: _flag('notesRoleHeld')
                      ? context.t('AXIOM ist die Notiz-App des Systems.')
                      : _flag('notesRoleAvailable')
                          ? context.t('Der Stift-Doppeltipp fragt nicht nach dem Intent-Filter, sondern nach der Rolle „Notiz-App". Solange die woanders liegt, erscheint AXIOM dort nicht.')
                          : context.t('Diese Rolle gibt es erst ab Android 14.'),
                  action: _flag('notesRoleAvailable')
                      ? context.t('AXIOM dafür setzen')
                      : null,
                  onAction: () async {
                    await AndroidBridge.requestNotesRole();
                    await _reload();
                  },
                ),
                _Check(
                  ok: _flag('presenceRunning'),
                  label: context.t('Dauerhafte Anzeige'),
                  detail: _flag('presenceRunning')
                      ? context.t('Läuft im Benachrichtigungsbereich.')
                      : context.t('Aus. Einschalten unter Erfassen — sie braucht die Benachrichtigungsfreigabe von oben.'),
                ),
                _Check(
                  ok: _flag('speechAvailable'),
                  label: context.t('Spracheingabe'),
                  detail: _flag('speechAvailable')
                      ? context.t('Diktieren steht im Erfassungsfeld bereit.')
                      : context.t('Auf diesem Gerät ist keine Spracherkennung installiert.'),
                ),

                const SizedBox(height: Space.xl),
                SectionLabel(context.t('Datenquellen')),
                _Check(
                  ok: _flag('healthGranted'),
                  label: context.t('Health Connect'),
                  detail: switch (health) {
                    3 when _flag('healthGranted') =>
                      context.t('Verbunden, liest Schlaf und Schritte.'),
                    3 => context.t('Vorhanden, aber noch nicht freigegeben.'),
                    2 => context.t('Die Systemkomponente ist zu alt und muss aktualisiert werden.'),
                    _ => context.t('Das System meldet Health Connect als nicht vorhanden (Status {0}).', [health]),
                  },
                  action: health == 3 && !_flag('healthGranted')
                      ? context.t('Freigeben')
                      : health == 3
                          ? context.t('Einstellungen öffnen')
                          : null,
                  onAction: () async {
                    if (_flag('healthGranted')) {
                      await HealthSync.openSettings();
                    } else {
                      await HealthSync.connect();
                    }
                    await _reload();
                  },
                ),

                const SizedBox(height: Space.xl),
                SectionLabel(context.t('Bekannte Grenzen')),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Limitation(
                        title: context.t('„Hey Google, Notiz in AXIOM"'),
                        body: context.t('Sprachbefehle über den Assistenten setzen voraus, dass die App über Google Play verteilt wird. Bei einer selbst installierten App prüft Google die Anmeldung nicht — der Befehl bleibt unbekannt. Was stattdessen funktioniert: die Notiz-Rolle oben, eine Bixby-Routine, oder ein Link auf axiom://capture?text=…'),
                      ),
                      Divider(color: p.rule, height: Space.xl),
                      _Limitation(
                        title: context.t('Lockscreen-Widget'),
                        body: context.t('Gibt es auf Android nicht — mit 5.0 entfernt. Die dauerhafte Benachrichtigung ist der verbliebene Weg zu ständiger Sichtbarkeit im gesperrten Zustand.'),
                      ),
                      Divider(color: p.rule, height: Space.xl),
                      _Limitation(
                        title: context.t('Screen-off-Memo mit dem Stift'),
                        body: context.t('Landet in Samsung Notes. Dafür gibt es keine öffentliche Schnittstelle, jeder Weg dorthin wäre Reverse Engineering und würde das nächste Systemupdate nicht überleben.'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Eine Prüfzeile: Zustand, Erklärung, und wo nötig der Weg dorthin.
class _Check extends StatelessWidget {
  final bool ok;
  final String label;
  final String detail;
  final String? action;
  final Future<void> Function()? onAction;

  const _Check({
    required this.ok,
    required this.label,
    required this.detail,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Panel(
        // Kupfer, nicht Rot: Ein fehlendes Systemrecht ist eine Aufgabe,
        // kein Fehler und schon gar kein Vorwurf (D10).
        accent: ok ? p.calm.withValues(alpha: 0.4) : p.caution.withValues(alpha: 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 19, color: ok ? p.calm : p.caution),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
            if (!ok && action != null && onAction != null) ...[
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
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(value, style: monoStyle(context, size: 12.5)),
          ],
        ),
      );
}

class _Limitation extends StatelessWidget {
  final String title;
  final String body;
  const _Limitation({required this.title, required this.body});

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
