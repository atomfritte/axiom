/// Hält das Betriebssystem auf Stand: Widget, Alarme, Automation.
///
/// Läuft nach jedem Auswertungszyklus. Ohne diese Rückkopplung wäre die
/// nächste Handlung nur in der App sichtbar — und was nicht sichtbar ist,
/// existiert für dieses Profil nicht [D9].
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/foundation.dart';

import '../i18n/i18n.dart';
import '../state/runtime.dart';
import 'android_bridge.dart';

abstract final class SystemSync {
  /// Spiegelt den aktuellen Zustand auf Widget und Always-On-Anzeige.
  ///
  /// [language] wird durchgereicht, nicht aus einem Kontext geholt: Diese
  /// Texte landen im Widget und in Benachrichtigungen, und die entstehen
  /// ohne Widget-Baum.
  static Future<void> publish(
    AxiomSnapshot snapshot, {
    AppLanguage language = AppLanguage.de,
  }) async {
    if (!AndroidBridge.isSupported) return;

    // Zuerst die Texte, dann die Werte. Alles, was Android selbst zeichnet —
    // Kanalnamen, Knopfbeschriftungen, die Zeile unter dem Widget — kommt von
    // hier; die Systemseite erfindet keinen Text mehr. Der Aufruf ist billig:
    // Sie schreibt nur, wenn sich die Sprache geändert hat.
    await AndroidBridge.applySystemTexts(language);

    final (headline, detail) = describe(snapshot, language);
    await AndroidBridge.updateWidget(
      headline: headline,
      detail: detail,
      capacity: snapshot.state.capacity,
    );
    // Dieselbe Aussage in die dauerhafte Anzeige, falls eingeschaltet.
    // Widget und Benachrichtigung duerfen nie Verschiedenes behaupten.
    await AndroidBridge.updatePresence(headline: headline, detail: detail);

    await _syncLiveSlot(snapshot, language);

    // Erhaltungsmodus an die Geräteautomation melden, damit Samsung-Routinen
    // greifen können (Benachrichtigungen dämpfen, Bildschirmzeit begrenzen).
    if (snapshot.state.loadLevel == LoadLevel.l3) {
      await AndroidBridge.enterMaintenanceMode();
    }
  }

  /// Hält das Live Update mit der laufenden Sitzung im Gleichklang.
  ///
  /// Bewusst hier und nicht am Start- und Stopp-Knopf: Der Abgleich läuft
  /// nach jedem Auswertungszyklus, also auch nach einem Neustart der App
  /// oder nachdem das System den Dienst beendet hat. Eine Anzeige, die nach
  /// dem ersten Speicherdruck fehlt, wäre schlimmer als keine — man verlässt
  /// sich dann auf eine Restzeit, die niemand mehr zählt.
  static Future<void> _syncLiveSlot(
      AxiomSnapshot snapshot, AppLanguage language) async {
    final focus = snapshot.focus;
    if (focus == null) {
      if (await AndroidBridge.liveSlotRunning()) {
        await AndroidBridge.stopLiveSlot();
      }
      return;
    }
    await AndroidBridge.startLiveSlot(
      kind: 'focus',
      title: focus.anchorTitle ?? translate(language, 'Fokus'),
      detail: translate(
          language, focus.hasAnchor ? 'Fokus' : 'ohne Anker'),
      startedAt: focus.startedAt,
      planned: focus.planned,
    );
  }

  /// Die zwei Zeilen, die Widget und dauerhafte Anzeige tragen.
  ///
  /// Sichtbar für den Test, weil sonst nichts davon prüfbar ist: [publish]
  /// steigt ohne Android sofort aus, und ein Widget-Test kommt an diese
  /// Ebene nie heran — genau deshalb stand hier ein deutscher Regeltitel in
  /// einer englischen Anzeige, ohne dass ein Test rot wurde.
  @visibleForTesting
  static (String, String) describe(
      AxiomSnapshot snapshot, AppLanguage language) {
    // Ein anstehender Ankerschritt schlaegt alles andere: Er hat eine
    // Uhrzeit, und verpasste Uhrzeiten kosten am meisten [D4].
    final next = snapshot.nextStep;
    if (next != null) {
      final at = next.step.at;
      final minutes = at.difference(DateTime.now()).inMinutes;
      if (minutes <= 90) {
        return (
          next.step.label,
          '${at.hour.toString().padLeft(2, "0")}:'
              '${at.minute.toString().padLeft(2, "0")} · ${next.anchor.title}',
        );
      }
    }

    final rule = snapshot.decisionRule;
    if (rule != null) {
      // Vorher stand hier `rule.title` — der deutsche Titel aus dem YAML,
      // waehrend die Zeile darunter uebersetzt war. Widget und dauerhafte
      // Anzeige sprachen damit eine andere Sprache als derselbe Satz in der
      // App, die `context.ruleTitle` benutzt. Die Sprache liegt hier bereits
      // als Parameter vor; `titleFor` faellt ohne `title_en` auf Deutsch
      // zurueck, wie ueberall sonst.
      return (
        rule.titleFor(language.code),
        translate(language, 'Regel {0}', [rule.id]),
      );
    }
    final task = snapshot.startable.firstOrNull;
    if (task != null) {
      return (
        task.title,
        translate(language, 'Start {0}/10', [task.activationEnergy]),
      );
    }
    final blocked = snapshot.tasks
        .where((t) => t.state == TaskState.ready)
        .isNotEmpty;
    return blocked
        ? (
            translate(language, 'Nichts in Reichweite'),
            translate(language, 'Zerlegen hilft'),
          )
        : (
            translate(language, 'Nichts anliegend'),
            translate(language, 'Tippen zum Erfassen'),
          );
  }

  /// Richtet die Tagesanker ein. Einmal nach dem Onboarding.
  static Future<void> installDailyAnchors({
    AppLanguage language = AppLanguage.de,
  }) async {
    // Auch hier zuerst: Die Anker werden im Onboarding gesetzt, also
    // moeglicherweise bevor je ein Auswertungszyklus gelaufen ist.
    await AndroidBridge.applySystemTexts(language);
    await AndroidBridge.scheduleDailyCheckins(language: language);
  }

  // ── Zeitanker (M3) ────────────────────────────────────────────────────

  /// Alarm-IDs 1–3 gehören den Check-ins, ab 1000 die Ankerschritte.
  static const int _anchorIdBase = 1000;

  /// Eine Erinnerung je Schritt der Kette.
  ///
  /// Das ist der eigentliche Nutzen von M3: Nicht der Termin wird erinnert —
  /// den vergisst dieses Profil ohnehin nicht — sondern der Ausstieg aus dem
  /// Laufenden davor. Genau der geht im Kopfmodell verloren [D4].
  static Future<void> scheduleAnchorReminders(
    Anchor anchor, {
    AppLanguage language = AppLanguage.de,
  }) async {
    if (!AndroidBridge.isSupported) return;
    final now = DateTime.now();

    for (final (index, step) in anchor.chain.indexed) {
      final id = _alarmId(anchor, index);
      final fireAt = step.at.subtract(reminderLeadFor(step.kind));

      if (fireAt.isBefore(now) || step.kind == AnchorStepKind.arrive) {
        await AndroidBridge.cancelAlarm(id);
        continue;
      }

      await AndroidBridge.scheduleExact(
        id: id,
        at: fireAt,
        title: step.label,
        body: _bodyFor(anchor, step, language),
        // Ein Zeitanker darf sichtbar sein, aber nicht schreien.
        channel: step.kind == AnchorStepKind.leaveContext
            ? 'axiom_intervene'
            : 'axiom_nudge',
        // Auf die Kette, zu der der Schritt gehört — nicht auf die
        // Übersicht, von der aus man ihn erst wieder suchen müsste.
        route: AxiomRoute.anchors,
      );
    }
  }

  static Future<void> cancelAnchorReminders(Anchor anchor) async {
    if (!AndroidBridge.isSupported) return;
    for (var i = 0; i < 4; i++) {
      await AndroidBridge.cancelAlarm(_alarmId(anchor, i));
    }
  }

  /// Stabile ID je Anker und Schritt, damit ein erneutes Planen den alten
  /// Alarm ersetzt statt zu verdoppeln.
  static int _alarmId(Anchor anchor, int stepIndex) =>
      _anchorIdBase + (anchor.id.hashCode.abs() % 100000) * 4 + stepIndex;

  static String _bodyFor(
      Anchor anchor, AnchorStep step, AppLanguage language) {
    final at = '${anchor.arriveBy.hour.toString().padLeft(2, "0")}:'
        '${anchor.arriveBy.minute.toString().padLeft(2, "0")}';
    return switch (step.kind) {
      AnchorStepKind.leaveContext => translate(language,
          '{0} um {1}. Jetzt zu Ende bringen, was läuft.', [anchor.title, at]),
      AnchorStepKind.prepare => translate(
          language, '{0} um {1}. Fertigmachen.', [anchor.title, at]),
      AnchorStepKind.depart => anchor.location == null
          ? translate(language, '{0} um {1}. Losgehen.', [anchor.title, at])
          : translate(language, 'Los nach {0}. {1} um {2}.',
              [anchor.location, anchor.title, at]),
      AnchorStepKind.arrive => anchor.title,
    };
  }

  /// Prüft, ob die eigenen Alarme pünktlich gefeuert haben.
  ///
  /// Samsung beendet Hintergrundprozesse aggressiv. Weil Zeittrigger der
  /// wirksamste Interventionstyp dieses Profils sind, darf ein Ausfall nicht
  /// still bleiben (R4).
  @visibleForTesting
  static const Duration acceptableDrift = Duration(minutes: 2);

  static Future<Duration?> alarmDrift() async {
    final drift = await AndroidBridge.lastAlarmDrift();
    if (drift == null || drift <= acceptableDrift) return null;
    return drift;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
