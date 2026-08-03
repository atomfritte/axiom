/// Hält das Betriebssystem auf Stand: Widget, Alarme, Automation.
///
/// Läuft nach jedem Auswertungszyklus. Ohne diese Rückkopplung wäre die
/// nächste Handlung nur in der App sichtbar — und was nicht sichtbar ist,
/// existiert für dieses Profil nicht [D9].
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/foundation.dart';

import '../state/runtime.dart';
import 'android_bridge.dart';

abstract final class SystemSync {
  /// Spiegelt den aktuellen Zustand auf Widget und Always-On-Anzeige.
  static Future<void> publish(AxiomSnapshot snapshot) async {
    if (!AndroidBridge.isSupported) return;

    final (headline, detail) = _describe(snapshot);
    await AndroidBridge.updateWidget(
      headline: headline,
      detail: detail,
      capacity: snapshot.state.capacity,
    );
    // Dieselbe Aussage in die dauerhafte Anzeige, falls eingeschaltet.
    // Widget und Benachrichtigung duerfen nie Verschiedenes behaupten.
    await AndroidBridge.updatePresence(headline: headline, detail: detail);

    await _syncLiveSlot(snapshot);

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
  static Future<void> _syncLiveSlot(AxiomSnapshot snapshot) async {
    final focus = snapshot.focus;
    if (focus == null) {
      if (await AndroidBridge.liveSlotRunning()) {
        await AndroidBridge.stopLiveSlot();
      }
      return;
    }
    await AndroidBridge.startLiveSlot(
      kind: 'focus',
      title: focus.anchorTitle ?? 'Fokus',
      detail: focus.hasAnchor ? 'Fokus' : 'ohne Anker',
      startedAt: focus.startedAt,
      planned: focus.planned,
    );
  }

  static (String, String) _describe(AxiomSnapshot snapshot) {
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
      return (rule.title, 'Regel ${rule.id}');
    }
    final task = snapshot.startable.firstOrNull;
    if (task != null) {
      return (task.title, 'Start ${task.activationEnergy}/10');
    }
    final blocked = snapshot.tasks
        .where((t) => t.state == TaskState.ready)
        .isNotEmpty;
    return blocked
        ? ('Nichts in Reichweite', 'Zerlegen hilft')
        : ('Nichts anliegend', 'Tippen zum Erfassen');
  }

  /// Richtet die Tagesanker ein. Einmal nach dem Onboarding.
  static Future<void> installDailyAnchors() =>
      AndroidBridge.scheduleDailyCheckins();

  // ── Zeitanker (M3) ────────────────────────────────────────────────────

  /// Alarm-IDs 1–3 gehören den Check-ins, ab 1000 die Ankerschritte.
  static const int _anchorIdBase = 1000;

  /// Eine Erinnerung je Schritt der Kette.
  ///
  /// Das ist der eigentliche Nutzen von M3: Nicht der Termin wird erinnert —
  /// den vergisst dieses Profil ohnehin nicht — sondern der Ausstieg aus dem
  /// Laufenden davor. Genau der geht im Kopfmodell verloren [D4].
  static Future<void> scheduleAnchorReminders(Anchor anchor) async {
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
        body: _bodyFor(anchor, step),
        // Ein Zeitanker darf sichtbar sein, aber nicht schreien.
        channel: step.kind == AnchorStepKind.leaveContext
            ? 'axiom_intervene'
            : 'axiom_nudge',
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

  static String _bodyFor(Anchor anchor, AnchorStep step) {
    final at = '${anchor.arriveBy.hour.toString().padLeft(2, "0")}:'
        '${anchor.arriveBy.minute.toString().padLeft(2, "0")}';
    return switch (step.kind) {
      AnchorStepKind.leaveContext =>
        '${anchor.title} um $at. Jetzt zu Ende bringen, was läuft.',
      AnchorStepKind.prepare => '${anchor.title} um $at. Fertigmachen.',
      AnchorStepKind.depart =>
        anchor.location == null
            ? '${anchor.title} um $at. Losgehen.'
            : 'Los nach ${anchor.location}. ${anchor.title} um $at.',
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
