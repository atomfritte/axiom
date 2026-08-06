/// Signal-Log — M10.
///
/// Emotionale Dysregulation ist bei Erwachsenen mit ADHS häufig der subjektiv
/// belastendste Anteil und zugleich der am seltensten adressierte. Die
/// Reaktion setzt sehr schnell ein, ist kurz, und die Nachwirkung ist lang:
/// Vermeidung, Rückzug, überstürzte Entscheidungen, Beziehungsschäden [D10].
///
/// Verschärfend bei diesem Profil: Ein Systemizer mit internalisiertem
/// Regelwerk erlebt eigenes Scheitern als **Regelbruch**, nicht als Ereignis.
/// Das koppelt es an den Selbstwert.
///
/// **Das Framing entscheidet über die Adhärenz.** Ein „Gefühlstagebuch" wird
/// nicht geführt. Ein Störungsbericht mit Ursachenanalyse schon — identischer
/// Inhalt, anderes Wort. Deshalb heißt es hier Vorfall und Nachbetrachtung.
///
/// Zweiter Punkt, genauso wichtig: **Die Nachbetrachtung kommt nicht sofort.**
/// Im Spike ist niemand analysefähig, und der Versuch macht es schlimmer. Sie
/// wird erst angeboten, wenn die Regulationsreserve wieder da ist.
library;

import 'package:meta/meta.dart';

/// Woran es hing. Bewusst grob — Feinunterscheidung im Spike ist unmöglich
/// und würde nur die Erfassung verhindern.
enum TriggerClass {
  criticism('Kritik', 'Etwas an mir wurde bemängelt'),
  rejection('Zurückweisung', 'Abgelehnt, übergangen, nicht gehört'),
  ownError('Eigener Fehler', 'Mir ist etwas misslungen'),
  misunderstanding('Missverständnis', 'Falsch verstanden worden'),
  overload('Überlastung', 'Zu viel auf einmal'),
  unclear('Unklar', 'Weiß ich nicht');

  const TriggerClass(this.label, this.description);
  final String label;
  final String description;
}

@immutable
final class SignalIncident {
  final String id;
  final DateTime at;

  /// 1..5 — wie stark es getroffen hat. Keine Bewertung, eine Ablesung.
  final int intensity;

  final TriggerClass triggerClass;

  /// Freitext, optional. Im Spike schreibt niemand viel.
  final String? note;

  const SignalIncident({
    required this.id,
    required this.at,
    required this.intensity,
    required this.triggerClass,
    this.note,
  });
}

/// Die Nachbetrachtung. Getrennt vom Vorfall, weil sie später kommt.
@immutable
final class PostMortem {
  final String incidentId;
  final DateTime at;

  /// Was der Auslöser tatsächlich war — oft ein anderer als der gefühlte.
  final String? rootCause;

  /// Was beim nächsten Mal anders laufen könnte. Konkret, nicht als Vorsatz.
  final String? countermeasure;

  /// Wie es sich im Rückblick darstellt, 1..5. Fast immer niedriger als
  /// im Moment — und genau das ist die nützlichste Erkenntnis.
  final int? intensityInHindsight;

  const PostMortem({
    required this.incidentId,
    required this.at,
    this.rootCause,
    this.countermeasure,
    this.intensityInHindsight,
  });

  bool get isComplete => rootCause != null && rootCause!.trim().isNotEmpty;
}

/// Wie lange nach einem Vorfall die Nachbetrachtung angeboten wird.
///
/// Nicht früher: Im Spike und in den Stunden danach ist die
/// Regulationsreserve zu niedrig, und ein erzwungener Analyseversuch
/// verlängert das Ereignis, statt es abzuschließen.
const Duration kPostMortemDelay = Duration(hours: 12);

/// Danach wird nicht mehr gefragt — die Erinnerung ist dann zu ungenau,
/// und Nachfragen zu alten Vorfällen ist selbst eine Belastung.
const Duration kPostMortemWindow = Duration(days: 4);

final class SignalLog {
  const SignalLog();

  /// Vorfälle, deren Nachbetrachtung jetzt sinnvoll ist.
  List<SignalIncident> awaitingPostMortem({
    required List<SignalIncident> incidents,
    required Set<String> reviewedIds,
    required DateTime now,
  }) {
    final due = incidents.where((i) {
      if (reviewedIds.contains(i.id)) return false;
      final age = now.difference(i.at);
      return age >= kPostMortemDelay && age <= kPostMortemWindow;
    }).toList()
      // Der stärkste zuerst — dort ist der Erkenntnisgewinn am größten.
      ..sort((a, b) {
        final byIntensity = b.intensity.compareTo(a.intensity);
        if (byIntensity != 0) return byIntensity;
        final byTime = a.at.compareTo(b.at);
        if (byTime != 0) return byTime;
        // Zuletzt die Kennung. Zwei Vorfälle derselben Minute sind keine
        // Seltenheit — ein Streit erzeugt selten genau einen Eintrag —, und
        // angeboten wird nur der erste. Ohne feste Ordnung wechselt er.
        return a.id.compareTo(b.id);
      });
    return due;
  }

  /// Wie stark die Regulationsreserve gerade belastet ist, 0..100.
  ///
  /// Klingt über 72 Stunden ab. Speist `regulation` im Zustandsvektor.
  double pressure({
    required List<SignalIncident> incidents,
    required DateTime now,
  }) {
    var total = 0.0;
    for (final incident in incidents) {
      final ageHours = now.difference(incident.at).inMinutes / 60;
      if (ageHours < 0 || ageHours > 72) continue;
      final decay = (1 - ageHours / 72).clamp(0.0, 1.0);
      total += incident.intensity * 8 * decay;
    }
    return total.clamp(0, 100);
  }

  /// Häufungen nach Auslöserklasse — für das Monats-Review.
  ///
  /// Zeigt Muster, die im Einzelfall unsichtbar bleiben: Wer viermal im
  /// Monat an derselben Klasse hängt, hat kein Einzelproblem.
  Map<TriggerClass, int> patterns(List<SignalIncident> incidents) {
    final counts = <TriggerClass, int>{};
    for (final incident in incidents) {
      counts.update(incident.triggerClass, (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(
      counts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.index.compareTo(b.key.index);
        }),
    );
  }

  /// Wie viel niedriger ein Vorfall im Rückblick bewertet wird.
  ///
  /// Die nützlichste Zahl des Moduls. Wer schwarz auf weiß sieht, dass ein
  /// Spike im Rückblick regelmäßig zwei Stufen niedriger ausfällt, kann das
  /// beim nächsten Mal einkalkulieren — nicht als Trost, als Erfahrungswert.
  double? hindsightDelta({
    required List<SignalIncident> incidents,
    required List<PostMortem> reviews,
  }) {
    final byId = {for (final i in incidents) i.id: i};
    final pairs = reviews
        .where((r) => r.intensityInHindsight != null)
        .map((r) => (byId[r.incidentId], r.intensityInHindsight!))
        .where((p) => p.$1 != null)
        .map((p) => p.$1!.intensity - p.$2)
        .toList();
    if (pairs.length < 3) return null;
    return pairs.reduce((a, b) => a + b) / pairs.length;
  }
}
