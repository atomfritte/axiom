/// Impuls-Abfang — M6.
///
/// Kein Verbot, keine Sperre, keine Moral (G3). Nur **Latenz und
/// Sichtbarkeit** — und der Impulsdurchbruch überlebt beides meistens nicht.
///
/// Der Wirkmechanismus ist ein anderer als bei üblichen Blocker-Apps: Ein
/// Systemizer bricht ungern eine Regel, die er **selbst gesetzt** hat. Eine
/// fremde Sperre ist eine Herausforderung; eine eigene Regel ist ein Vertrag
/// mit dem Vergangenheits-Ich. Deshalb schreibt AXIOM die Prüffragen nicht
/// vor — der Nutzer formuliert sie im ruhigen Zustand selbst [D5, D10].
library;

import 'package:meta/meta.dart';

import 'phrase.dart';

/// Was abgefangen wird. Immer vom Nutzer definiert.
@immutable
final class InterceptTrigger {
  final String id;
  final String label;

  /// Wie lange gewartet wird, bevor die Handlung freigegeben ist.
  final Duration cooldown;

  /// Statt einer Dauer: Freigabe erst zu dieser Uhrzeit (z. B. „09:00").
  /// Für Nachtentscheidungen, die am Morgen anders aussehen.
  final String? releaseAt;

  /// Selbst geschriebene Prüffragen. Der Kern des Vertrags.
  final List<String> checklist;

  /// Hat der Nutzer diesen Trigger im ruhigen Zustand autorisiert?
  /// Ohne das darf er nicht als `enforce` laufen.
  final bool authorized;

  const InterceptTrigger({
    required this.id,
    required this.label,
    required this.cooldown,
    this.releaseAt,
    this.checklist = const [],
    this.authorized = false,
  });

  bool get isValid => checklist.isNotEmpty && label.trim().isNotEmpty;
}

/// Vorschläge für Prüffragen.
///
/// **Vorlagen, keine Vorgaben.** Der Nutzer formuliert um oder ersetzt sie —
/// eine fremde Frage wird weggeklickt, die eigene beantwortet.
const List<String> kChecklistSeeds = [
  'Kannte ich das vor heute?',
  'Was genau löst es, das ich gestern noch nicht lösen musste?',
  'Ist es die Sache oder das Gefühl?',
  'Wie sehe ich das in vier Wochen?',
  'Was würde ich jemandem raten, der mir das erzählt?',
];

enum InterceptOutcome {
  /// Cooldown lief ab, die Handlung wurde nicht ausgeführt.
  aborted,

  /// Trotzdem ausgeführt. Wird gezählt, nicht bewertet.
  proceeded,

  /// Cooldown läuft noch.
  pending,

  /// Abgelaufen, ohne dass es eine Rückmeldung gab.
  expired,
}

/// Ein laufender oder abgeschlossener Abfang.
@immutable
final class InterceptRun {
  final String id;
  final String triggerId;
  final String triggerLabel;
  final DateTime startedAt;
  final DateTime releasesAt;

  /// Beantwortete Prüffragen, in der Reihenfolge der Checkliste.
  final List<bool> answers;

  final InterceptOutcome outcome;

  /// Freitext, falls der Nutzer etwas festhalten wollte.
  final String? note;

  const InterceptRun({
    required this.id,
    required this.triggerId,
    required this.triggerLabel,
    required this.startedAt,
    required this.releasesAt,
    this.answers = const [],
    this.outcome = InterceptOutcome.pending,
    this.note,
  });

  bool isActive(DateTime now) =>
      outcome == InterceptOutcome.pending && now.isBefore(releasesAt);

  Duration remaining(DateTime now) {
    final left = releasesAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Anteil beantworteter Fragen — nur zur Anzeige, ohne Wertung.
  int get answered => answers.where((a) => a).length;
}

final class Interceptor {
  const Interceptor();

  /// Startet einen Abfang. Reine Funktion: Zeit kommt von außen.
  InterceptRun start({
    required InterceptTrigger trigger,
    required DateTime now,
    required String id,
  }) {
    final releasesAt = trigger.releaseAt == null
        ? now.add(trigger.cooldown)
        : _nextOccurrence(trigger.releaseAt!, now);
    return InterceptRun(
      id: id,
      triggerId: trigger.id,
      triggerLabel: trigger.label,
      startedAt: now,
      releasesAt: releasesAt,
    );
  }

  /// Nächstes Auftreten einer Uhrzeit „HH:MM", frühestens morgen früh,
  /// wenn sie heute schon vorbei ist.
  static DateTime _nextOccurrence(String hhmm, DateTime now) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  /// Text für die laufende Wartezeit. Beschreibt, urteilt nicht.
  String waitingText(InterceptRun run, DateTime now) =>
      waitingPhrase(run, now).text;

  /// Derselbe Text, aber mit getrennten Werten — uebersetzbar.
  Phrase waitingPhrase(InterceptRun run, DateTime now) {
    final left = run.remaining(now);
    if (left == Duration.zero) {
      return const Phrase('Wartezeit vorbei. Deine Entscheidung.');
    }
    if (left.inHours >= 2) {
      return Phrase(
        'Freigabe um {0}. Bis dahin steht die Sache still — '
        'sie läuft nicht weg.',
        [_hhmm(run.releasesAt)],
      );
    }
    return Phrase(
      'Noch {0} min. Die meisten Impulse überleben diese Zeit nicht.',
      [left.inMinutes],
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, "0")}:'
      '${t.minute.toString().padLeft(2, "0")}';
}

/// Wie oft der Trigger ausgelöst und wie oft er gehalten hat.
///
/// Zählt beides ohne Wertung. „Trotzdem gemacht" ist eine Information über
/// den Trigger, nicht über den Nutzer — ein Trigger, der nie hält, ist
/// falsch geschnitten und gehört ins Review, nicht ins Gewissen.
@immutable
final class InterceptStats {
  final String triggerId;
  final int started;
  final int aborted;
  final int proceeded;

  const InterceptStats({
    required this.triggerId,
    this.started = 0,
    this.aborted = 0,
    this.proceeded = 0,
  });

  int get decided => aborted + proceeded;
  double? get holdRate => decided == 0 ? null : aborted / decided;

  /// Ein Trigger, der fast nie hält, ist entweder zu breit geschnitten
  /// oder deckt keinen echten Impuls ab.
  bool get needsReview => decided >= 4 && (holdRate ?? 1) < 0.3;
}
